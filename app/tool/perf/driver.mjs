// Headless-Chrome driver for the render-worker web perf harness.
//
// Serves build/web (the harness bundle) plus the big PDF at /perf.pdf, drives
// real Chrome through it via puppeteer-core (system Chrome, no download), waits
// for the harness auto-scroll to finish, then scrapes the captured perf trace
// and FrameTiming and prints a summary. Appends one JSON record per run to
// results.ndjson so a loop can chart trends.
//
// Prereqs:  npm install            (in this dir; pulls puppeteer-core only)
//           tool/perf/build.sh     (compiles the worker + harness into build/web)
//
// Run:      node driver.mjs
//
// Env:
//   PERF_PORT      http port                         (default 8099)
//   PERF_PDF       path to the PDF to serve          (default ~/Downloads/MW307...)
//   PERF_WEB_DIR   static dir to serve               (default ../../build/web)
//   PERF_HEADLESS  "false" for a visible window      (default true)
//   PERF_TIMEOUT   overall budget, seconds           (default 300)
//   PERF_VERBOSE   "true" to echo every console line  (default false)
//   PERF_RESULTS   ndjson output path                (default ./results.ndjson)
//   PERF_TRACE     optional Chrome trace output path (includes V8 CPU samples)
import { createServer } from 'node:http';
import { readFile, stat, appendFile } from 'node:fs/promises';
import { execSync } from 'node:child_process';
import { cpus } from 'node:os';
import { existsSync, readFileSync } from 'node:fs';
import { join, extname, normalize, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import puppeteer from 'puppeteer-core';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = normalize(join(HERE, '..', '..', '..'));
const PORT = Number(process.env.PERF_PORT ?? 8099);
const WEB_DIR = normalize(process.env.PERF_WEB_DIR ?? join(HERE, '..', '..', 'build', 'web'));

// --scenario <name> / PERF_SCENARIO selects a named workload from
// scenarios.json (kind + a portable repo-relative PDF + query params). Without
// one, keep the legacy default (a big local scroll PDF) so old invocations and
// the dashboard's chrome-scroll history are untouched.
function resolveScenario() {
  const argv = process.argv.slice(2);
  const flag = argv.indexOf('--scenario');
  let name = process.env.PERF_SCENARIO ?? (flag >= 0 ? argv[flag + 1] : null);
  if (!name) return null;
  const reg = JSON.parse(readFileSync(join(HERE, 'scenarios.json'), 'utf8'));
  if (name === 'default') name = reg.default;
  const s = reg.scenarios[name];
  if (!s) {
    console.error(`✗ unknown scenario "${name}". known: ${Object.keys(reg.scenarios).join(', ')}`);
    process.exit(2);
  }
  return { name, ...s };
}
const SCENARIO = resolveScenario();

// PDF precedence: explicit PERF_PDF wins; else the scenario's repo-relative
// PDF; else the legacy local default.
const PDF = process.env.PERF_PDF
  ?? (SCENARIO ? join(REPO_ROOT, SCENARIO.pdf) : join(homedir(), 'Downloads', 'MW307(TNT975)F-UPS-ZB.pdf'));
const HEADLESS = (process.env.PERF_HEADLESS ?? 'true') !== 'false';
const TIMEOUT_S = Number(process.env.PERF_TIMEOUT ?? 300);
const VERBOSE = (process.env.PERF_VERBOSE ?? 'false') === 'true';
const RESULTS = process.env.PERF_RESULTS ?? join(HERE, 'results.ndjson');
const TRACE = process.env.PERF_TRACE ?? null;
const CHROME = process.env.PERF_CHROME ??
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const ISOLATED = (process.env.PERF_CROSS_ORIGIN_ISOLATED ?? 'true') !== 'false';
// Negative control: serve a 404 for the worker script to force UI-thread
// fallback, so we can confirm the loop actually catches a regression.
const NO_WORKER = (process.env.PERF_NO_WORKER ?? 'false') === 'true';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream',
  '.pdf': 'application/pdf',
};

function headers(type, length) {
  const h = { 'content-type': type, 'content-length': length };
  if (ISOLATED) {
    h['cross-origin-opener-policy'] = 'same-origin';
    h['cross-origin-embedder-policy'] = 'credentialless';
  }
  return h;
}

function startServer() {
  return new Promise((resolve, reject) => {
    const server = createServer(async (req, res) => {
      try {
        let path = decodeURIComponent(req.url.split('?')[0]);
        if (path === '/perf.pdf') {
          const buf = await readFile(PDF);
          res.writeHead(200, headers('application/pdf', buf.length));
          res.end(buf);
          return;
        }
        // Negative control: 404 the worker script so the app degrades to
        // UI-thread render - the loop must then flag the regression.
        if (NO_WORKER && path === '/pdf_render_worker.dart.js') {
          res.writeHead(404); res.end('worker disabled'); return;
        }
        if (path === '/') path = '/index.html';
        // Resolve inside WEB_DIR only (no traversal).
        const file = normalize(join(WEB_DIR, path));
        if (!file.startsWith(WEB_DIR)) { res.writeHead(403); res.end(); return; }
        const info = await stat(file).catch(() => null);
        if (!info || !info.isFile()) { res.writeHead(404); res.end('not found'); return; }
        const buf = await readFile(file);
        const type = MIME[extname(file).toLowerCase()] ?? 'application/octet-stream';
        res.writeHead(200, headers(type, buf.length));
        res.end(buf);
      } catch (e) {
        res.writeHead(500);
        res.end(String(e));
      }
    });
    server.on('error', reject);
    server.listen(PORT, '127.0.0.1', () => resolve(server));
  });
}

// ---------------------------------------------------------------------------
// Trace parsing
// ---------------------------------------------------------------------------
function pctile(sorted, p) {
  if (sorted.length === 0) return 0;
  const i = Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length));
  return sorted[i];
}

function parse(lines, frames) {
  const r = {
    interpret: { worker: 0, recorded: 0, plain: 0, other: 0 },
    pages: new Set(),
    workerResultBytes: 0,
    workerResultMax: 0,
    workerWarmMax: 0,
    prerender: { vector: 0, full: 0 },
    target: {},
    jankCount: 0,
    errorLines: [],
    declines: 0,
    harness: {},
  };
  for (const line of lines) {
    const stamp = line.match(/^\[perf ([\d.]+)\]/);
    const atMs = stamp ? Number(stamp[1]) : null;
    const targetStart = line.match(/HARNESS TARGET start page=(\d+)/);
    if (targetStart && atMs != null) {
      r.target.page = Number(targetStart[1]);
      r.target.startMs = atMs;
    }
    const targetFirst = line.match(/HARNESS TARGET firstContent page=(\d+)/);
    if (targetFirst && atMs != null && r.target.startMs != null) {
      r.target.detectedMs = atMs - r.target.startMs;
    }
    const m = line.match(/interpret page=(\d+) path=(\w+)/);
    if (m) {
      r.pages.add(Number(m[1]));
      const path = m[2];
      if (path in r.interpret) r.interpret[path]++; else r.interpret.other++;
      if (atMs != null &&
        r.target.startMs != null &&
        r.target.firstContentMs == null &&
        Number(m[1]) === r.target.page) {
        r.target.firstContentMs = atMs - r.target.startMs;
        r.target.kind = `interpret/${path}`;
      }
    }
    const wr = line.match(/webworker result page=\d+ (\d+)B/);
    if (wr) {
      const b = Number(wr[1]);
      r.workerResultBytes += b;
      r.workerResultMax = Math.max(r.workerResultMax, b);
    }
    const warm = line.match(/worker warm=([\d.]+)ms/);
    if (warm) r.workerWarmMax = Math.max(r.workerWarmMax, Number(warm[1]));
    // `prerender page=N lod=<rung> [worker ][shared ]<vector|full> warm=…`.
    // The lod token arrived with the preview ladder and `shared` with #699's
    // one-record-per-ladder build; both are optional so an older bundle's
    // lines still count.
    const pre = line.match(
      /prerender page=\d+ (?:lod=\S+ )?(?:worker )?(?:shared )?(vector|full) /);
    if (pre) r.prerender[pre[1]]++;
    // The #527 bounded early prefix is real ink on the target page too, so it
    // counts as first content for the baseline (progressive off) - otherwise the
    // A/B would credit the reveal for a win the bounded prefix already delivers.
    const early = line.match(/early-prefix page=(\d+)/);
    if (early &&
      atMs != null &&
      r.target.startMs != null &&
      r.target.firstContentMs == null &&
      Number(early[1]) === r.target.page) {
      r.target.firstContentMs = atMs - r.target.startMs;
      r.target.kind = 'early-prefix';
    }
    // A #564 progressive partial is real ink on the target page - the top-down
    // reveal - so it counts as first content, earlier than the vector-first
    // full raster it precedes.
    const partial = line.match(/progressive-partial page=(\d+)/);
    if (partial &&
      atMs != null &&
      r.target.startMs != null &&
      r.target.firstContentMs == null &&
      Number(partial[1]) === r.target.page) {
      r.target.firstContentMs = atMs - r.target.startMs;
      r.target.kind = 'progressive-partial';
    }
    const vector = line.match(/vector-first page=(\d+)/);
    if (vector &&
      atMs != null &&
      r.target.startMs != null &&
      r.target.firstContentMs == null &&
      Number(vector[1]) === r.target.page) {
      r.target.firstContentMs = atMs - r.target.startMs;
      r.target.kind = 'vector-first';
    }
    const preview = line.match(/preview-paint page=(\d+)/);
    if (preview &&
      atMs != null &&
      r.target.startMs != null &&
      r.target.firstContentMs == null &&
      Number(preview[1]) === r.target.page) {
      r.target.firstContentMs = atMs - r.target.startMs;
      r.target.kind = 'preview';
    }
    if (/JANK /.test(line)) r.jankCount++;
    if (/declin/i.test(line)) r.declines++;
    if (/error|exception|unsupported|cannot|failed/i.test(line) && /\[perf|webworker/.test(line)) {
      r.errorLines.push(line.trim());
    }
    const hp = line.match(/HARNESS (pageCount|DONE|loaded|PASS) ?(.*)/);
    if (hp) r.harness[hp[1]] = (hp[2] || '').trim() || true;
  }
  const builds = frames.map((f) => f.b).sort((a, b) => a - b);
  const rasters = frames.map((f) => f.r).sort((a, b) => a - b);
  r.frames = {
    count: frames.length,
    buildP50: pctile(builds, 50),
    buildP95: pctile(builds, 95),
    buildMax: builds.length ? builds[builds.length - 1] : 0,
    rasterP95: pctile(rasters, 95),
    buildOver16: builds.filter((b) => b > 16).length,
    buildOver32: builds.filter((b) => b > 32).length,
    buildOver50: builds.filter((b) => b > 50).length,
  };
  return r;
}

function fmt(n, d = 1) { return Number(n).toFixed(d); }

// What the tab actually holds. performance.memory only sees the JS heap, and
// decoded PDF images live in CanvasKit's wasm heap - so the number that matters
// comes from measureUserAgentSpecificMemory(), which counts WASM and is why the
// server sends COOP/COEP (it needs cross-origin isolation). Returns the agent
// total plus the ceilings a tab is judged against.
const MEMORY_PROBE = `(async () => {
  const out = { deviceMemoryGb: navigator.deviceMemory ?? null };
  // Chrome is launched with --expose-gc so the numbers below are retained
  // memory, not whatever V8 had not got round to collecting.
  if (window.gc) { window.gc(); await new Promise((r) => setTimeout(r, 500)); window.gc(); out.gc = true; }
  const m = performance.memory;
  if (m) {
    out.jsHeapUsed = m.usedJSHeapSize;
    out.jsHeapLimit = m.jsHeapSizeLimit;
  }
  if (window.__perfImageCacheBytes) out.imageCacheBytes = window.__perfImageCacheBytes();
  if (performance.measureUserAgentSpecificMemory) {
    try {
      const r = await performance.measureUserAgentSpecificMemory();
      out.agentBytes = r.bytes;
      out.breakdown = r.breakdown
        .filter((b) => b.bytes > 0)
        .map((b) => ({ bytes: b.bytes, types: b.types }))
        .sort((a, b) => b.bytes - a.bytes)
        .slice(0, 6);
    } catch (e) { out.measureError = String(e); }
  } else {
    out.measureError = 'measureUserAgentSpecificMemory unavailable '
      + '(not cross-origin isolated, or an old-headless / headless_shell binary '
      + 'without the PerformanceManager - use a full-browser binary + new headless)';
  }
  return out;
})()`;

function mb(bytes) { return bytes == null ? '?' : `${(bytes / 1048576).toFixed(0)}MB`; }

async function main() {
  if (!existsSync(WEB_DIR) || !existsSync(join(WEB_DIR, 'index.html'))) {
    console.error(`✗ no harness build at ${WEB_DIR} - run tool/perf/build.sh first`);
    process.exit(2);
  }
  // A failed `flutter build web` still leaves index.html but no compiled entry,
  // so main() never runs and the page just times out. Catch that up front.
  if (!existsSync(join(WEB_DIR, 'main.dart.js'))) {
    console.error(`✗ ${WEB_DIR} has no main.dart.js - the last build failed; re-run tool/perf/build.sh`);
    process.exit(2);
  }
  if (!existsSync(PDF)) {
    console.error(`✗ PDF not found: ${PDF} (set PERF_PDF)`);
    process.exit(2);
  }
  if (!existsSync(CHROME)) {
    console.error(`✗ Chrome not found: ${CHROME} (set PERF_CHROME)`);
    process.exit(2);
  }

  const t0 = Date.now();
  const server = await startServer();
  // Tunables ride the URL so the prebuilt harness needs no rebuild. Order of
  // precedence: scenario params (from scenarios.json) < explicit PERF_* env
  // (so a power user can still override any single knob on the command line).
  const qp = new URLSearchParams();
  if (SCENARIO) {
    qp.set('scenario', SCENARIO.kind);
    for (const [k, v] of Object.entries(SCENARIO.params ?? {})) qp.set(k, String(v));
  }
  if (process.env.PERF_MAX_PAGES) qp.set('maxPages', process.env.PERF_MAX_PAGES);
  if (process.env.PERF_DWELL_MS) qp.set('dwell', process.env.PERF_DWELL_MS);
  if (process.env.PERF_PASSES) qp.set('passes', process.env.PERF_PASSES);
  if (process.env.PERF_FAST_PASS) qp.set('fast', process.env.PERF_FAST_PASS);
  if (process.env.PERF_TARGET_PAGE) qp.set('targetPage', process.env.PERF_TARGET_PAGE);
  if (process.env.PERF_IMAGE_CACHE_MB) qp.set('imageCacheMb', process.env.PERF_IMAGE_CACHE_MB);
  if (process.env.PERF_QUERY) qp.set('query', process.env.PERF_QUERY);
  if (process.env.PERF_REPEAT) qp.set('repeat', process.env.PERF_REPEAT);
  if (process.env.PERF_OPS) qp.set('ops', process.env.PERF_OPS);
  if (process.env.PERF_PER_GLYPH) qp.set('perGlyph', process.env.PERF_PER_GLYPH);
  if (process.env.PERF_WORKERS) qp.set('worker', process.env.PERF_WORKERS);
  const qs = qp.toString();
  const url = `http://127.0.0.1:${PORT}/${qs ? '?' + qs : ''}`;
  if (SCENARIO) console.log(`▶ scenario ${SCENARIO.name} (${SCENARIO.kind}) pdf=${SCENARIO.pdf}`);
  console.log(`▶ serving ${WEB_DIR} + /perf.pdf at ${url} (headless=${HEADLESS}, isolated=${ISOLATED})`);

  const browser = await puppeteer.launch({
    executablePath: CHROME,
    // New headless, NOT the old `chrome --headless=old` / headless_shell:
    // performance.measureUserAgentSpecificMemory() - the whole point of the
    // memory probe below - is backed by the browser-process PerformanceManager,
    // which the headless shell doesn't run, so there the call throws
    // "not available" even when the page is cross-origin isolated. New headless
    // (a full Chrome/Chromium binary) has it. Point PERF_CHROME at a full
    // browser binary, not a *_headless_shell one, for the memory numbers.
    headless: HEADLESS,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--window-size=1400,1000',
      '--js-flags=--expose-gc',
      // A locale-less headless host makes Flutter's intl throw "Incorrect
      // locale information provided" at startup; pin one so the app boots.
      '--lang=en-US', '--accept-lang=en-US'],
    defaultViewport: { width: 1400, height: 1000 },
  });

  let result = null;
  let fatal = null;
  try {
    const pageErrors = [];
    const consoleLines = [];
    const page = await browser.newPage();
    if (TRACE) {
      await page.tracing.start({
        path: TRACE,
        categories: [
          'devtools.timeline',
          'disabled-by-default-devtools.timeline',
          'disabled-by-default-v8.cpu_profiler',
          'disabled-by-default-v8.cpu_profiler.hires',
        ],
      });
    }
    page.on('console', (msg) => {
      const text = msg.text();
      consoleLines.push(text);
      if (VERBOSE) console.log('  ‹console›', text);
    });
    page.on('pageerror', (e) => { pageErrors.push(String(e)); console.error('  ‹pageerror›', String(e)); });

    await page.goto(url, { waitUntil: 'load', timeout: 60_000 });

    // Poll for the harness to finish (or its own error path), up to the budget.
    // Bail fast on a startup crash: a pageerror with no harness output after a
    // short grace means the app never came up - don't burn the whole budget.
    const deadline = t0 + TIMEOUT_S * 1000;
    let done = false;
    while (Date.now() < deadline) {
      done = await page.evaluate('window.__perfDone === true').catch(() => false);
      if (done) break;
      if (pageErrors.length) {
        const progressed = await page.evaluate('(window.__perfDump && window.__perfDump().length) || 0').catch(() => 0);
        if (!progressed && Date.now() - t0 > 12_000) { fatal = `startup crash: ${pageErrors[0]}`; break; }
      }
      await new Promise((r) => setTimeout(r, 500));
    }
    if (!done && !fatal) fatal = `timeout after ${TIMEOUT_S}s waiting for __perfDone`;
    if (pageErrors.length) (result ??= {}).pageErrors = pageErrors;
    if (TRACE) await page.tracing.stop();

    // Sample memory before scraping the trace, while the run's peak is still
    // resident (the wasm heap never shrinks, so this is a high-water mark).
    const memory = await page.evaluate(MEMORY_PROBE).catch((e) => ({ measureError: String(e) }));

    const harnessError = await page.evaluate('window.__perfError ?? null').catch(() => null);
    const dump = await page.evaluate('window.__perfDump ? window.__perfDump() : ""').catch(() => '');
    const framesJson = await page.evaluate('window.__perfFrames ? window.__perfFrames() : "[]"').catch(() => '[]');
    const metricsJson = await page.evaluate('window.__perfMetrics ? window.__perfMetrics() : "{}"').catch(() => '{}');
    const lines = dump ? dump.split('\n') : [];
    lines.push(...consoleLines.filter((line) => line.startsWith('[perf ')));
    let frames = [];
    try { frames = JSON.parse(framesJson); } catch { /* ignore */ }
    // The scenario's own headline numbers - whatever the harness chose to emit.
    // Parsed generically so a new scenario needs no driver change.
    let scenarioMetrics = {};
    try { scenarioMetrics = JSON.parse(metricsJson); } catch { /* ignore */ }

    result = { ...(result ?? {}), harnessError, memory, scenarioMetrics, lines: lines.length, ...parse(lines, frames) };
    // The `open` scenario's first-content time is logged in the render-worker
    // isolate, so only the driver's [perf <ms>] target machinery (not the
    // harness) can see it. Fold it into the scenario metrics so it prints and
    // rides into history/A-B exactly like a harness-emitted one.
    if (result.target?.firstContentMs != null) {
      result.scenarioMetrics.openFirstContentMs = Math.round(result.target.firstContentMs * 10) / 10;
    }
    result.rawLineSample = lines.filter((l) => /interpret|webworker|vector-first|preview-paint|HARNESS|JANK|error/i.test(l)).slice(0, 60);
  } catch (e) {
    fatal = String(e?.stack ?? e);
  } finally {
    await browser.close().catch(() => { });
    server.close();
  }

  const elapsed = (Date.now() - t0) / 1000;
  // Envelope fields (tool/perf/SCHEMA.md) wrap the legacy flat record; every
  // pre-existing field keeps its place so report.mjs reads both vintages.
  const git = (args) => {
    try { return execSync(`git ${args}`, { encoding: 'utf8' }).trim(); }
    catch { return ''; }
  };
  const record = {
    schema: 1,
    // Keep the legacy suite name for scroll (the dashboard's chrome-scroll
    // history), and a per-kind suite for the new workloads.
    suite: SCENARIO ? `chrome-${SCENARIO.kind}` : 'chrome-scroll',
    scenario: SCENARIO?.name ?? process.env.PERF_SCENARIO ?? null,
    rev: {
      sha: git('rev-parse HEAD'),
      branch: git('rev-parse --abbrev-ref HEAD'),
      dirty: git('status --porcelain').length > 0,
      date: git('show -s --format=%cI HEAD'),
    },
    env: {
      os: `${process.platform}-${process.arch}`,
      cpus: cpus().length,
      node: process.version,
      ci: process.env.CI === 'true',
      runner: process.env.RUNNER_OS ? 'github-actions' : 'local',
    },
    ts: new Date().toISOString(),
    elapsedS: Number(elapsed.toFixed(1)),
    headless: HEADLESS,
    fatal,
    ...(result ?? {}),
  };
  // pages is a Set - make it serialisable / summarisable.
  const pagesVisited = result?.pages ? result.pages.size : 0;
  if (record.pages) record.pages = pagesVisited;

  // ---- Console summary ----
  console.log('\n──────── perf run summary ────────');
  if (fatal) console.log(`✗ FATAL: ${fatal}`);
  if (result?.harnessError) console.log(`✗ harness error: ${String(result.harnessError).split('\n')[0]}`);
  if (result) {
    const i = result.interpret;
    const f = result.frames;
    console.log(`  pages visited      ${pagesVisited}`);
    console.log(`  interpret paths    worker=${i.worker} recorded=${i.recorded} plain=${i.plain} other=${i.other} declines=${result.declines}`);
    console.log(`  worker decode      max=${(result.workerResultMax / 1e6).toFixed(2)}MB total=${(result.workerResultBytes / 1e6).toFixed(1)}MB warmMax=${fmt(result.workerWarmMax)}ms`);
    console.log(`  prerender warms    vector=${result.prerender.vector} full=${result.prerender.full}`);
    if (result.target?.firstContentMs != null) {
      console.log(`  target first paint page=${result.target.page} ${fmt(result.target.firstContentMs)}ms via ${result.target.kind}`);
    }
    const mem = result.memory;
    if (mem && !mem.measureError) {
      console.log(`  tab memory         agent=${mb(mem.agentBytes)} imageCache=${mb(mem.imageCacheBytes)} jsHeap=${mb(mem.jsHeapUsed)}/${mb(mem.jsHeapLimit)} deviceMemory=${mem.deviceMemoryGb ?? '?'}GB`);
      for (const b of mem.breakdown ?? []) {
        console.log(`      ${mb(b.bytes).padStart(7)}  ${b.types.join(', ')}`);
      }
    } else if (mem?.measureError) {
      console.log(`  tab memory         unavailable: ${mem.measureError}`);
    }
    console.log(`  frames             ${f.count}  buildP50=${fmt(f.buildP50)}ms p95=${fmt(f.buildP95)}ms max=${fmt(f.buildMax)}ms`);
    console.log(`  build over budget  >16ms=${f.buildOver16}  >32ms=${f.buildOver32}  >50ms=${f.buildOver50}   (PdfPerfLog JANK lines=${result.jankCount})`);
    if (result.errorLines?.length) {
      console.log(`  ⚠ error lines (${result.errorLines.length}):`);
      for (const e of result.errorLines.slice(0, 5)) console.log(`      ${e}`);
    }
    const sm = result.scenarioMetrics ?? {};
    const smKeys = Object.keys(sm);
    if (smKeys.length) {
      console.log(`  scenario metrics   ${smKeys.map((k) => `${k}=${fmt(sm[k])}`).join('  ')}`);
    }
  }
  console.log(`  elapsed            ${elapsed.toFixed(1)}s`);

  // ---- Verdict ----
  const scenarioMetrics = result?.scenarioMetrics ?? {};
  const hasScenarioMetrics = Object.keys(scenarioMetrics).length > 0;
  const ok = !fatal && !result?.harnessError && !(result?.errorLines?.length) &&
    !(result?.pageErrors?.length) && (pagesVisited > 0 || hasScenarioMetrics);
  // The worker-offload regression signal only means something for the scroll
  // suite; open/search/edit intentionally may render on the UI thread.
  const isScroll = !SCENARIO || SCENARIO.kind === 'scroll';
  const regressed = isScroll && result && (result.interpret.plain > 0 || result.interpret.recorded > 0);
  record.ok = ok;
  record.regressed = !!regressed;
  // Run-level aggregates for the dashboard (which reads only `metrics`). The
  // scenario's own headline numbers ride alongside the frame aggregates, so a
  // new scenario's metrics land in history and the A/B diff automatically.
  record.metrics = {
    ...scenarioMetrics,
    ...(result?.frames
      ? {
          pagesVisited,
          jankCount: result.jankCount ?? 0,
          buildP50: result.frames.buildP50,
          buildP95: result.frames.buildP95,
          buildMax: result.frames.buildMax,
          buildOver50: result.frames.buildOver50,
          workerWarmMaxMs: result.workerWarmMax ?? null,
          agentMemoryBytes: result.memory?.agentBytes ?? null,
        }
      : {}),
  };
  console.log(ok ? (regressed ? '◐ PASS (with UI-thread interpret - see plain/recorded)' : '✓ PASS') : '✗ FAIL');
  console.log('──────────────────────────────────\n');

  await appendFile(RESULTS, JSON.stringify(record) + '\n').catch(() => { });
  process.exit(ok ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
