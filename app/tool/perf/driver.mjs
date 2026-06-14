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
import { createServer } from 'node:http';
import { readFile, stat, appendFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join, extname, normalize, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import puppeteer from 'puppeteer-core';

const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PERF_PORT ?? 8099);
const WEB_DIR = normalize(process.env.PERF_WEB_DIR ?? join(HERE, '..', '..', 'build', 'web'));
const PDF = process.env.PERF_PDF ?? join(homedir(), 'Downloads', 'MW307(TNT975)F-UPS-ZB.pdf');
const HEADLESS = (process.env.PERF_HEADLESS ?? 'true') !== 'false';
const TIMEOUT_S = Number(process.env.PERF_TIMEOUT ?? 300);
const VERBOSE = (process.env.PERF_VERBOSE ?? 'false') === 'true';
const RESULTS = process.env.PERF_RESULTS ?? join(HERE, 'results.ndjson');
const CHROME = process.env.PERF_CHROME ??
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
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

function startServer() {
  return new Promise((resolve, reject) => {
    const server = createServer(async (req, res) => {
      try {
        let path = decodeURIComponent(req.url.split('?')[0]);
        if (path === '/perf.pdf') {
          const buf = await readFile(PDF);
          res.writeHead(200, { 'content-type': 'application/pdf', 'content-length': buf.length });
          res.end(buf);
          return;
        }
        // Negative control: 404 the worker script so the app degrades to
        // UI-thread render — the loop must then flag the regression.
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
        // The render worker is a same-origin classic worker; no COOP/COEP needed.
        res.writeHead(200, { 'content-type': type, 'content-length': buf.length });
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
    jankCount: 0,
    errorLines: [],
    declines: 0,
    harness: {},
  };
  for (const line of lines) {
    const m = line.match(/interpret page=(\d+) path=(\w+)/);
    if (m) {
      r.pages.add(Number(m[1]));
      const path = m[2];
      if (path in r.interpret) r.interpret[path]++; else r.interpret.other++;
    }
    const wr = line.match(/webworker result page=\d+ (\d+)B/);
    if (wr) {
      const b = Number(wr[1]);
      r.workerResultBytes += b;
      r.workerResultMax = Math.max(r.workerResultMax, b);
    }
    const warm = line.match(/worker warm=([\d.]+)ms/);
    if (warm) r.workerWarmMax = Math.max(r.workerWarmMax, Number(warm[1]));
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

async function main() {
  if (!existsSync(WEB_DIR) || !existsSync(join(WEB_DIR, 'index.html'))) {
    console.error(`✗ no harness build at ${WEB_DIR} — run tool/perf/build.sh first`);
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
  // Scroll tunables ride the URL so the prebuilt harness needs no rebuild.
  const qp = new URLSearchParams();
  if (process.env.PERF_MAX_PAGES) qp.set('maxPages', process.env.PERF_MAX_PAGES);
  if (process.env.PERF_DWELL_MS) qp.set('dwell', process.env.PERF_DWELL_MS);
  if (process.env.PERF_PASSES) qp.set('passes', process.env.PERF_PASSES);
  if (process.env.PERF_FAST_PASS) qp.set('fast', process.env.PERF_FAST_PASS);
  const qs = qp.toString();
  const url = `http://127.0.0.1:${PORT}/${qs ? '?' + qs : ''}`;
  console.log(`▶ serving ${WEB_DIR} + /perf.pdf at ${url} (headless=${HEADLESS})`);

  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: HEADLESS ? 'shell' : false,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--window-size=1400,1000'],
    defaultViewport: { width: 1400, height: 1000 },
  });

  let result = null;
  let fatal = null;
  try {
    const pageErrors = [];
    const page = await browser.newPage();
    page.on('console', (msg) => { if (VERBOSE) console.log('  ‹console›', msg.text()); });
    page.on('pageerror', (e) => { pageErrors.push(String(e)); console.error('  ‹pageerror›', String(e)); });

    await page.goto(url, { waitUntil: 'load', timeout: 60_000 });

    // Poll for the harness to finish (or its own error path), up to the budget.
    // Bail fast on a startup crash: a pageerror with no harness output after a
    // short grace means the app never came up — don't burn the whole budget.
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

    const harnessError = await page.evaluate('window.__perfError ?? null').catch(() => null);
    const dump = await page.evaluate('window.__perfDump ? window.__perfDump() : ""').catch(() => '');
    const framesJson = await page.evaluate('window.__perfFrames ? window.__perfFrames() : "[]"').catch(() => '[]');
    const lines = dump ? dump.split('\n') : [];
    let frames = [];
    try { frames = JSON.parse(framesJson); } catch { /* ignore */ }

    result = { ...(result ?? {}), harnessError, lines: lines.length, ...parse(lines, frames) };
    result.rawLineSample = lines.filter((l) => /interpret|webworker|HARNESS|JANK|error/i.test(l)).slice(0, 40);
  } catch (e) {
    fatal = String(e?.stack ?? e);
  } finally {
    await browser.close().catch(() => {});
    server.close();
  }

  const elapsed = (Date.now() - t0) / 1000;
  const record = {
    ts: new Date().toISOString(),
    elapsedS: Number(elapsed.toFixed(1)),
    headless: HEADLESS,
    fatal,
    ...(result ?? {}),
  };
  // pages is a Set — make it serialisable / summarisable.
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
    console.log(`  frames             ${f.count}  buildP50=${fmt(f.buildP50)}ms p95=${fmt(f.buildP95)}ms max=${fmt(f.buildMax)}ms`);
    console.log(`  build over budget  >16ms=${f.buildOver16}  >32ms=${f.buildOver32}  >50ms=${f.buildOver50}   (PdfPerfLog JANK lines=${result.jankCount})`);
    if (result.errorLines?.length) {
      console.log(`  ⚠ error lines (${result.errorLines.length}):`);
      for (const e of result.errorLines.slice(0, 5)) console.log(`      ${e}`);
    }
  }
  console.log(`  elapsed            ${elapsed.toFixed(1)}s`);

  // ---- Verdict ----
  const ok = !fatal && !result?.harnessError && !(result?.errorLines?.length) &&
    !(result?.pageErrors?.length) && pagesVisited > 0;
  // A regression signal worth flagging (not a hard fail): any UI-thread plain
  // interpret on a doc that should fully offload.
  const regressed = result && (result.interpret.plain > 0 || result.interpret.recorded > 0);
  record.ok = ok;
  record.regressed = !!regressed;
  console.log(ok ? (regressed ? '◐ PASS (with UI-thread interpret — see plain/recorded)' : '✓ PASS') : '✗ FAIL');
  console.log('──────────────────────────────────\n');

  await appendFile(RESULTS, JSON.stringify(record) + '\n').catch(() => {});
  process.exit(ok ? 0 : 1);
}

main().catch((e) => { console.error(e); process.exit(1); });
