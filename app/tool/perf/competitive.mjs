#!/usr/bin/env node
// End-to-end DartPDF vs Chromium/PDFium user-journey benchmark.
//
// This is deliberately not another internal stopwatch comparison. It launches
// a clean copy of the same Chrome binary for each engine, serves the same PDF
// bytes, drives the same page jumps and zooms, and waits for the same Chrome
// compositor-settle criterion. The result is the user-visible latency that
// the PDFium-performance goal is about. Engine-specific timers are retained as
// diagnostics, but never substituted for the common parity metrics.
//
//   node competitive.mjs --scenario parity-plan --iterations 3
//   node competitive.mjs --scenario parity-scan --iterations 5 --gate

import { appendFile, mkdir, readFile, stat } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { execFileSync } from 'node:child_process';
import { cpus, platform, arch } from 'node:os';
import { dirname, extname, join, normalize, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import puppeteer from 'puppeteer-core';

import {
  aggregateRuns,
  cadenceDelay,
  digest,
  evaluateBudgets,
  framesInWindow,
  parityRatios,
  percentile,
  processTreeRssSnapshot,
  queryFlag,
  resolveHttpByteRange,
  resolveVisualCaptureMode,
  screenshotSampleAt,
  sleep,
  translateEpochTimestamp,
} from './competitive_common.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = normalize(join(HERE, '..', '..', '..'));
const WEB_DIR = resolve(
  process.env.PERF_WEB_DIR ??
    process.env.PERF_BUILD_OUTPUT ??
    join(REPO_ROOT, 'app', 'build', 'web'),
);
const REGISTRY = JSON.parse(
  readFileSync(join(HERE, 'competitive_scenarios.json'), 'utf8'),
);

const argv = process.argv.slice(2);
function opt(name, fallback) {
  const index = argv.indexOf(name);
  return index >= 0 && argv[index + 1] ? argv[index + 1] : fallback;
}
const has = (name) => argv.includes(name);

// Several visual-settle probes intentionally run in parallel with a separate
// engine-readiness wait. Attach a handler immediately so a fast rejection is
// not treated as an unhandled promise by newer Node releases before the probe
// is awaited a few lines later. Awaiting the original promise still surfaces
// the error through the normal benchmark try/catch.
function awaitLater(promise) {
  void promise.catch(() => {});
  return promise;
}

const scenarioName = opt('--scenario', REGISTRY.default);
const registeredScenario = REGISTRY.scenarios[scenarioName];
const parseNumberList = (value, label) => {
  if (value == null || value === '') return null;
  const result = String(value).split(',').map((part) => Number(part.trim()));
  if (result.length === 0 || result.some((number) => !Number.isFinite(number))) {
    fail(`${label} must be a comma-separated list of finite numbers`);
  }
  return result;
};
const pageOverride = parseNumberList(process.env.PERF_PAGES, 'PERF_PAGES');
const zoomOverride = parseNumberList(process.env.PERF_ZOOMS, 'PERF_ZOOMS');
const scenario = registeredScenario == null
  ? null
  : {
      ...registeredScenario,
      ...(pageOverride == null ? {} : {pages: pageOverride}),
      ...(zoomOverride == null ? {} : {zooms: zoomOverride}),
    };
const iterations = Number(opt('--iterations', '3'));
const timeoutMs = Number(opt('--timeout', '300000'));
const port = Number(opt('--port', process.env.PERF_PORT ?? '8100'));
const browserCooldownMs = Number(process.env.PERF_BROWSER_COOLDOWN_MS ?? 0);
const headless = !has('--headed') && process.env.PERF_HEADLESS !== 'false';
const gate = has('--gate');
const webBackend = process.env.PERF_WEB_BACKEND ??
  (process.env.WASM === '1' ? 'skwasm' : 'js-canvaskit');
const requestedVisualCaptureMode = process.env.PERF_VISUAL_CAPTURE;
const transport = scenario?.transport ?? 'full-file';
// Chrome returns Page.captureScreenshot only after JPEG encoding. The paired
// probe bounds pixel sampling at 32-34ms on the reference Chrome 151 runner;
// 36ms is the conservative default. Calibrate other controlled runners with
// screenshot_timing_probe.mjs and override this value when needed.
const screenshotSampleDelayMs = Number(
  process.env.PERF_SCREENSHOT_SAMPLE_DELAY_MS ?? 36,
);
// Optional Dart-only experiment switches (for example `syncRaster=1`) are
// recorded in the result and applied to the Dart harness URL. PDFium still
// receives the identical PDF bytes and common journey; this is an explicit
// A/B lever, never a hidden benchmark default.
const dartQueryParams = new URLSearchParams(
  String(process.env.PERF_DART_QUERY ?? '').replace(/^[?&]+/, ''),
);
if (transport === 'range') {
  dartQueryParams.set('source', 'range');
  dartQueryParams.set('deferStart', '1');
}
const dartQuery = dartQueryParams.toString();
const visualCaptureMode = resolveVisualCaptureMode(
  requestedVisualCaptureMode,
  webBackend,
  dartQuery,
);
const outPath = normalize(
  opt(
    '--out',
    process.env.PERF_RESULTS ??
      join(HERE, `results-competitive-${scenarioName}.ndjson`),
  ),
);
const diagnosticScreenshotDir = process.env.PERF_SCREENSHOT_DIR == null
  ? null
  : resolve(process.env.PERF_SCREENSHOT_DIR);

async function captureDiagnostic(
  page,
  engine,
  iteration,
  pageIndex,
  stage = `page-${pageIndex + 1}`,
) {
  if (diagnosticScreenshotDir == null) return;
  await mkdir(diagnosticScreenshotDir, {recursive: true});
  await page.screenshot({
    path: join(
      diagnosticScreenshotDir,
      `${engine}-run-${iteration}-${stage}.png`,
    ),
    type: 'png',
    fromSurface: true,
  });
}
const pdfPath = normalize(
  process.env.PERF_PDF ??
    (scenario ? join(REPO_ROOT, scenario.pdf) : ''),
);

const CHROME_CANDIDATES = [
  process.env.PERF_CHROME,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
].filter(Boolean);
const chromePath = CHROME_CANDIDATES.find(existsSync);

const VIEWPORT = { width: 1400, height: 1000 };
const SCREENCAST = {
  format: 'jpeg',
  quality: 20,
  maxWidth: 700,
  maxHeight: 500,
  everyNthFrame: 1,
};
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.pdf': 'application/pdf',
};

function fail(message) {
  console.error(`✗ ${message}`);
  process.exit(2);
}

if (!scenario) {
  fail(
    `unknown scenario "${scenarioName}"; known: ${Object.keys(REGISTRY.scenarios).join(', ')}`,
  );
}
if (!Number.isInteger(iterations) || iterations <= 0) {
  fail('--iterations must be a positive integer');
}
if (!Number.isFinite(browserCooldownMs) || browserCooldownMs < 0) {
  fail('PERF_BROWSER_COOLDOWN_MS must be a non-negative number');
}
if (!['screencast', 'screenshot', 'none'].includes(visualCaptureMode)) {
  fail(
    'PERF_VISUAL_CAPTURE must be screencast, screenshot, or none',
  );
}
if (!Number.isFinite(screenshotSampleDelayMs) ||
    screenshotSampleDelayMs < 0) {
  fail('PERF_SCREENSHOT_SAMPLE_DELAY_MS must be a non-negative number');
}
if (!['full-file', 'range'].includes(transport)) {
  fail(`unsupported transport "${transport}"; use full-file or range`);
}
if ((webBackend === 'skwasm' || queryFlag(dartQuery, 'domSurface')) &&
    visualCaptureMode === 'screencast') {
  fail(
    'SkWasm/worker-owned OffscreenCanvas pixels are absent from CDP ' +
      'screencasts; ' +
      'use PERF_VISUAL_CAPTURE=screenshot (or none for non-visual diagnostics)',
  );
}
if (!existsSync(pdfPath) && scenario.prepare) {
  const preparePath = resolve(REPO_ROOT, scenario.prepare);
  if (!existsSync(preparePath)) fail(`scenario prepare tool not found: ${preparePath}`);
  console.log(`==> preparing ${scenarioName} corpus via ${scenario.prepare}`);
  try {
    execFileSync(preparePath, [], { cwd: REPO_ROOT, stdio: 'inherit' });
  } catch (error) {
    fail(`scenario corpus preparation failed: ${error}`);
  }
}
if (!existsSync(pdfPath)) fail(`PDF not found: ${pdfPath}`);
if (!existsSync(join(WEB_DIR, 'index.html')) ||
    !existsSync(join(WEB_DIR, 'main.dart.js'))) {
  fail(`no DartPDF perf build in ${WEB_DIR}; run app/tool/perf/build.sh`);
}
if (!chromePath) fail('Chrome/Chromium not found; set PERF_CHROME');

function git(args) {
  try {
    return execFileSync('git', args, {
      cwd: REPO_ROOT,
      encoding: 'utf8',
    }).trim();
  } catch {
    return '';
  }
}

async function startServer() {
  const pdfBytes = await readFile(pdfPath);
  const emptyStats = () => ({
    requests: 0,
    bytes: 0,
    rangeRequests: 0,
    firstRequestAt: null,
    lastResponseAt: null,
  });
  let activeStats = emptyStats();

  const server = createServer(async (request, response) => {
    try {
      const requestPath = decodeURIComponent(
        new URL(request.url ?? '/', `http://${request.headers.host}`).pathname,
      );
      if (requestPath === '/perf.pdf') {
        activeStats.firstRequestAt ??= performance.now();
        activeStats.requests++;
        if (request.headers.range) activeStats.rangeRequests++;
        const range = transport === 'range'
          ? resolveHttpByteRange(request.headers.range, pdfBytes.length)
          : null;
        if (range != null && !range.satisfiable) {
          response.writeHead(416, {
            'content-range': `bytes */${pdfBytes.length}`,
            'accept-ranges': 'bytes',
            'cache-control': 'no-store',
          });
          response.end();
          return;
        }
        const ranged = range?.satisfiable === true;
        const body = ranged
          ? pdfBytes.subarray(range.start, range.endExclusive)
          : pdfBytes;
        activeStats.bytes += body.length;
        response.writeHead(ranged ? 206 : 200, {
          'content-type': 'application/pdf',
          'content-length': body.length,
          'cache-control': 'no-store',
          'accept-ranges': transport === 'range' ? 'bytes' : 'none',
          ...(ranged
            ? {
                'content-range':
                  `bytes ${range.start}-${range.endExclusive - 1}/` +
                  `${pdfBytes.length}`,
              }
            : {}),
        });
        response.once('finish', () => {
          activeStats.lastResponseAt = performance.now();
        });
        response.end(body);
        return;
      }

      let path = requestPath;
      if (path === '/') path = '/index.html';
      const file = normalize(join(WEB_DIR, path));
      if (!file.startsWith(WEB_DIR)) {
        response.writeHead(403).end();
        return;
      }
      const info = await stat(file).catch(() => null);
      if (!info?.isFile()) {
        response.writeHead(404).end('not found');
        return;
      }
      const bytes = await readFile(file);
      response.writeHead(200, {
        'content-type': MIME[extname(file).toLowerCase()] ??
          'application/octet-stream',
        'content-length': bytes.length,
        'cache-control': 'no-store',
        'cross-origin-opener-policy': 'same-origin',
        'cross-origin-embedder-policy': 'credentialless',
      });
      response.end(bytes);
    } catch (error) {
      response.writeHead(500).end(String(error));
    }
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', resolve);
  });
  return {
    server,
    resetStats() {
      activeStats = emptyStats();
    },
    stats() {
      return { ...activeStats };
    },
  };
}

async function launchBrowser() {
  return puppeteer.launch({
    executablePath: chromePath,
    headless,
    defaultViewport: VIEWPORT,
    args: [
      '--no-sandbox',
      '--disable-dev-shm-usage',
      '--disable-background-networking',
      '--disable-component-update',
      '--no-first-run',
      `--window-size=${VIEWPORT.width},${VIEWPORT.height}`,
      '--lang=en-US',
      '--accept-lang=en-US',
    ],
  });
}

async function browserGraphicsInfo(browser) {
  let session;
  try {
    session = await browser.target().createCDPSession();
    const { gpu = {} } = await session.send('SystemInfo.getInfo');
    const device = gpu.devices?.[0] ?? {};
    const auxiliary = gpu.auxAttributes ?? {};
    return {
      vendorId: device.vendorId ?? null,
      deviceId: device.deviceId ?? null,
      vendor: device.vendorString ?? null,
      device: device.deviceString ?? null,
      driverVendor: device.driverVendor ?? null,
      driverVersion: device.driverVersion ?? null,
      displayType: auxiliary.displayType ?? null,
      skiaBackend: auxiliary.skiaBackendType ?? null,
      features: gpu.featureStatus ?? {},
    };
  } catch (error) {
    return { error: String(error) };
  } finally {
    await session?.detach().catch(() => {});
  }
}

class VisualTracker {
  constructor(page) {
    this.page = page;
    this.session = null;
    this.frames = [];
    this.sequence = 0;
    this.lastHash = null;
    this.lastChangedAt = null;
  }

  async start() {
    this.session = await this.page.createCDPSession();
    await this.session.send('Page.enable');
    this.session.on('Page.screencastFrame', (event) => {
      const at = performance.now();
      const hash = digest(event.data);
      const changed = hash !== this.lastHash;
      if (changed) {
        this.lastHash = hash;
        this.lastChangedAt = at;
      }
      this.frames.push({
        sequence: ++this.sequence,
        at,
        hash,
        changed,
        // Base64 length is 4/3 of the JPEG payload, ignoring at most 2 bytes
        // of padding. This is instrumentation cost, not an engine metric.
        bytes: Math.floor(event.data.length * 0.75),
      });
      void this.session
        .send('Page.screencastFrameAck', { sessionId: event.sessionId })
        .catch(() => {});
    });
    await this.session.send('Page.startScreencast', SCREENCAST);
    await waitUntil(() => this.sequence > 0, 'initial compositor frame', 10000);
  }

  mark() {
    return {
      at: performance.now(),
      sequence: this.sequence,
      hash: this.lastHash,
    };
  }

  async settle(
    mark,
    { timeout = 12000, quietMs = 500, ready = null, label = 'visual' } = {},
  ) {
    const deadline = performance.now() + timeout;
    let sawChange = false;
    let isReady = ready == null;
    let readyAt = ready == null ? mark.at : null;
    let readinessError = null;
    if (ready != null) {
      void Promise.resolve(ready).then(
        (reportedAt) => {
          readyAt = Number.isFinite(reportedAt)
            ? reportedAt
            : performance.now();
          isReady = true;
        },
        (error) => { readinessError = error; },
      );
    }
    while (performance.now() < deadline) {
      if (readinessError != null) throw readinessError;
      const after = this.frames.filter((frame) => frame.sequence > mark.sequence);
      if (after.some((frame) => frame.hash !== mark.hash)) sawChange = true;
      // The engine callback can follow the compositor frame it describes by a
      // few milliseconds. Accept that frame, but never attribute stable pixels
      // to an older shell/placeholder merely because lossy capture gave both
      // images the same hash.
      const hasReadyFrame = readyAt != null &&
        after.some((frame) => frame.at >= readyAt - 100);
      const presentationAt = readyAt == null
        ? this.lastChangedAt
        : Math.max(this.lastChangedAt, readyAt);
      if (isReady && sawChange && this.lastChangedAt >= mark.at &&
          hasReadyFrame && performance.now() - presentationAt >= quietMs) {
        const firstChanged = after.find((frame) => frame.hash !== mark.hash);
        // For cold open, the first changed frame may be browser/app chrome or
        // a blank page placeholder. The first occurrence of the eventual
        // settled hash is the earliest frame that actually shows the complete
        // stable page. Keeping this in the same pre-navigation screencast also
        // makes the metric immune to a fast renderer beating a readiness poll.
        const firstStable = after.find((frame) => frame.hash === this.lastHash);
        const stableAt = Math.max(firstStable.at, readyAt);
        return {
          firstVisualElapsedMs: firstChanged.at - mark.at,
          firstStableVisualElapsedMs: stableAt - mark.at,
          visualElapsedMs: presentationAt - mark.at,
          confirmationElapsedMs: performance.now() - mark.at,
          hash: this.lastHash,
          frameBytes: after.map((frame) => frame.bytes),
        };
      }
      await sleep(15);
    }
    throw new Error(
      `${label}: compositor output did not ` +
      `${sawChange ? 'settle' : 'change'} within ${timeout}ms`,
    );
  }

  async stop() {
    if (!this.session) return;
    await this.session.send('Page.stopScreencast').catch(() => {});
    await this.session.detach().catch(() => {});
    this.session = null;
  }
}

// SkWasm presents through an offscreen canvas that CDP's screencast can omit
// even though an ordinary browser screenshot contains it. This deliberately
// slower tracker is an opt-in validation mode, not the default benchmark: it
// polls full composited screenshots and applies the same hash/quiet-window
// semantics, symmetrically, to DartPDF and PDFium.
class ScreenshotVisualTracker {
  constructor(page) {
    this.page = page;
    this.frames = [];
    this.sequence = 0;
    this.lastHash = null;
    this.lastChangedAt = null;
    this.traceOrigin = performance.now();
  }

  async capture() {
    const startedAt = performance.now();
    const bytes = await this.page.screenshot({
      type: 'jpeg',
      quality: SCREENCAST.quality,
      optimizeForSpeed: true,
    });
    const responseAt = performance.now();
    const at = screenshotSampleAt(
      startedAt,
      responseAt,
      screenshotSampleDelayMs,
    );
    const hash = digest(bytes);
    const changed = hash !== this.lastHash;
    if (changed) {
      this.lastHash = hash;
      this.lastChangedAt = at;
    }
    this.frames.push({
      sequence: ++this.sequence,
      at,
      hash,
      changed,
      bytes: bytes.length,
      captureStartedAt: startedAt,
      captureResponseAt: responseAt,
      captureDurationMs: responseAt - startedAt,
    });
    const traceWindowMs = Number(process.env.PERF_CAPTURE_TRACE_MS ?? 3000);
    if (process.env.PERF_CAPTURE_TRACE === 'true' &&
        startedAt - this.traceOrigin < traceWindowMs) {
      console.error(
        `[capture] start=${(startedAt - this.traceOrigin).toFixed(1)} ` +
        `sample=${(at - this.traceOrigin).toFixed(1)} ` +
        `response=${(responseAt - this.traceOrigin).toFixed(1)} ` +
        `changed=${changed} hash=${hash.slice(0, 10)}`,
      );
    }
  }

  async start() {
    await this.capture();
  }

  async mark() {
    await this.capture();
    return {
      at: performance.now(),
      sequence: this.sequence,
      hash: this.lastHash,
    };
  }

  async settle(
    mark,
    { timeout = 12000, quietMs = 500, ready = null, label = 'visual' } = {},
  ) {
    const deadline = performance.now() + timeout;
    let sawChange = false;
    let isReady = ready == null;
    let readyAt = ready == null ? mark.at : null;
    let readinessError = null;
    if (ready != null) {
      void Promise.resolve(ready).then(
        (reportedAt) => {
          readyAt = Number.isFinite(reportedAt)
            ? reportedAt
            : performance.now();
          isReady = true;
        },
        (error) => { readinessError = error; },
      );
    }
    while (performance.now() < deadline) {
      if (readinessError != null) throw readinessError;
      await this.capture();
      const after = this.frames.filter((frame) => frame.sequence > mark.sequence);
      if (after.some((frame) => frame.hash !== mark.hash)) sawChange = true;
      const hasReadyFrame = readyAt != null &&
        after.some((frame) => frame.at >= readyAt - 100);
      const presentationAt = readyAt == null
        ? this.lastChangedAt
        : Math.max(this.lastChangedAt, readyAt);
      if (isReady && sawChange && this.lastChangedAt >= mark.at &&
          hasReadyFrame && performance.now() - presentationAt >= quietMs) {
        const firstChanged = after.find((frame) => frame.hash !== mark.hash);
        const firstStable = after.find((frame) => frame.hash === this.lastHash);
        const stableAt = Math.max(firstStable.at, readyAt);
        return {
          firstVisualElapsedMs: firstChanged.at - mark.at,
          firstStableVisualElapsedMs: stableAt - mark.at,
          visualElapsedMs: presentationAt - mark.at,
          confirmationElapsedMs: performance.now() - mark.at,
          hash: this.lastHash,
          frameBytes: after.map((frame) => frame.bytes),
        };
      }
      await sleep(15);
    }
    let surfaceState = null;
    try {
      surfaceState = await this.page.evaluate(() => ({
        currentPage: globalThis.__perfCurrentPage?.(),
        preloadActive: globalThis.__perfPreloadActive,
        preloadOverlay: document.querySelector(
          '#pdf-page-zero-preload-overlay',
        ) != null,
        surfaces: [...document.querySelectorAll(
          '[data-dartpdf-worker-surface]',
        )].map((element) => {
          const rect = element.getBoundingClientRect();
          return {
            page: element.getAttribute('data-dartpdf-worker-surface-page'),
            ready: element.getAttribute('data-dartpdf-worker-surface-ready'),
            visibility: getComputedStyle(element).visibility,
            rect: [rect.left, rect.top, rect.width, rect.height],
          };
        }),
      }));
    } catch (_) {
      // Best-effort timeout evidence only; preserve the original failure.
    }
    throw new Error(
      `${label}: screenshot output did not ` +
      `${sawChange ? 'settle' : 'change'} within ${timeout}ms` +
      (surfaceState == null ? '' : `; state=${JSON.stringify(surfaceState)}`),
    );
  }

  async stop() {}
}

// Diagnostics only: do not ask CDP to read or encode compositor output. This
// deliberately forfeits visual latency; it exists to tell whether capture is
// perturbing Flutter's own FrameTiming raster phase. Engine readiness still
// gates each action before the ordinary quiet window, so action-local frame
// attribution and rAF/RSS diagnostics remain comparable.
class NoCaptureVisualTracker {
  constructor() {
    this.lastHash = 'capture-disabled';
  }

  async start() {}

  mark() {
    return { at: performance.now(), sequence: 0, hash: this.lastHash };
  }

  async settle(mark, { quietMs = 500, ready = null } = {}) {
    if (ready != null) await ready;
    await sleep(quietMs);
    return {
      firstVisualElapsedMs: 0,
      firstStableVisualElapsedMs: 0,
      visualElapsedMs: 0,
      confirmationElapsedMs: performance.now() - mark.at,
      hash: this.lastHash,
      frameBytes: [],
    };
  }

  async stop() {}
}

function createVisualTracker(page) {
  if (visualCaptureMode === 'none') return new NoCaptureVisualTracker();
  if (visualCaptureMode === 'screenshot') {
    return new ScreenshotVisualTracker(page);
  }
  return new VisualTracker(page);
}

function captureDurationSummary(tracker) {
  const values = (tracker.frames ?? [])
    .map((frame) => frame.captureDurationMs)
    .filter(Number.isFinite);
  return {
    count: values.length,
    p50: percentile(values, 50),
    p95: percentile(values, 95),
    max: values.length ? Math.max(...values) : null,
  };
}

async function installRafProbe(target) {
  await target.evaluate(() => {
    const state = { active: true, previous: null, intervals: [] };
    globalThis.__dartPdfParityRaf = state;
    const tick = (stamp) => {
      if (!state.active) return;
      if (state.previous != null) state.intervals.push(stamp - state.previous);
      state.previous = stamp;
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  });
}

async function resetRafProbe(target) {
  await target.evaluate(() => {
    const state = globalThis.__dartPdfParityRaf;
    if (state) {
      state.previous = null;
      state.intervals.length = 0;
    }
  });
}

async function readRafProbe(target) {
  return target.evaluate(
    () => globalThis.__dartPdfParityRaf?.intervals.slice() ?? [],
  );
}

async function markFlutterFrames(page) {
  return page.evaluate(() => performance.now());
}

async function waitUntil(probe, description, timeout = timeoutMs) {
  const deadline = performance.now() + timeout;
  let lastError = null;
  while (performance.now() < deadline) {
    try {
      const value = await probe();
      if (value) return value;
    } catch (error) {
      lastError = error;
    }
    await sleep(20);
  }
  throw new Error(
    `timeout waiting for ${description}${lastError ? `: ${lastError}` : ''}`,
  );
}

function pageTimestampOnDriverClock(sample) {
  return translateEpochTimestamp(Number(sample.at), performance.timeOrigin);
}

async function pdfiumFrame(page) {
  return page.frames().find((frame) =>
    frame.url().startsWith(
      'chrome-extension://mhjfbmdgcfjbbpaeojofohoefgiehjai/',
    ));
}

async function pdfiumState(page) {
  const frame = await pdfiumFrame(page);
  if (!frame) return null;
  const state = await frame.evaluate(() => {
    const viewer = document.querySelector('pdf-viewer');
    const viewport = viewer?.viewport_;
    const shell = Boolean(
      viewer?.shadowRoot?.querySelector('#main') && viewport,
    );
    return {
      shell,
      logicalReady: shell &&
        Number.isInteger(viewer.docLength_) && viewer.docLength_ > 0 &&
        Boolean(viewer.documentDimensions),
      initialLoadComplete: viewer?.initialLoadComplete_ === true,
      fullyLoaded: viewer?.loadState_ === 'success' &&
        viewer?.loadProgress_ >= 100,
      pageCount: viewer?.docLength_ ?? 0,
      currentPage: shell ? viewport.getMostVisiblePage() : -1,
      zoom: shell ? viewport.getZoom() : null,
      scrollFraction: shell && viewport.contentSize && viewport.size
        ? viewport.position.y /
          Math.max(1, viewport.contentSize.height - viewport.size.height)
        : null,
      apiReady: shell &&
        typeof viewport.goToPage === 'function' &&
        typeof viewport.setZoom === 'function' &&
        typeof viewport.scrollTo === 'function',
    };
  });
  return { frame, state };
}

async function waitPdfium(page, predicate, description) {
  return waitUntil(async () => {
    const snapshot = await pdfiumState(page);
    return snapshot && predicate(snapshot.state) ? snapshot : null;
  }, `PDFium ${description}`);
}

function validTargets(configured, pageCount) {
  return configured
    .map(Number)
    .filter((page) => Number.isInteger(page) && page >= 0 && page < pageCount);
}

async function driveScrollJourney(
  page,
  rafTarget,
  visualTracker,
  actions,
  flutterWindows = null,
) {
  const samplesMs = [];
  const rafIntervalsMs = [];
  const frameBytes = [];
  if (!Array.isArray(actions) || !actions.length) {
    return { samplesMs, rafIntervalsMs, frameBytes };
  }
  await page.mouse.move(VIEWPORT.width / 2, VIEWPORT.height / 2);
  for (const action of actions) {
    const deltaY = Number(action.deltaY);
    const steps = Math.max(1, Math.trunc(Number(action.steps ?? 18)));
    const intervalMs = Math.max(0, Number(action.intervalMs ?? 16));
    if (!Number.isFinite(deltaY) || deltaY === 0) continue;
    const flutterStart = flutterWindows == null
      ? null
      : await markFlutterFrames(page);
    await resetRafProbe(rafTarget);
    const mark = await visualTracker.mark();
    const gestureStartedAt = performance.now();
    const dispatches = [];
    for (let step = 0; step < steps; step++) {
      // A physical wheel emits at a wall-clock cadence independent of how long
      // the previous event took the page to acknowledge. Sleeping a full
      // interval *after* every CDP round trip made a busier engine receive a
      // slower synthetic gesture and charged that changed input duration as
      // rendering latency. Target event-start times instead, catching up when
      // an acknowledgement consumes the interval.
      const delay = cadenceDelay(
        gestureStartedAt,
        step,
        intervalMs,
        performance.now(),
      );
      if (delay > 0) await sleep(delay);
      // Queue the next hardware-like event without waiting for the previous
      // CDP acknowledgement. Attach the rejection handler immediately (rather
      // than only at the final Promise.all) so Node never sees a transient
      // unhandled rejection while the cadence timer is still emitting.
      dispatches.push(
        page.mouse.wheel({ deltaY: deltaY / steps }).then(
          () => null,
          (error) => error,
        ),
      );
    }
    const dispatchResults = await Promise.all(dispatches);
    const dispatchError = dispatchResults.find((result) => result instanceof Error);
    if (dispatchError) {
      throw dispatchError;
    }
    // Read the rAF probe before the 500ms quiet confirmation window can dilute
    // a stalled gesture with thirty idle 16ms frames. The visual duration still
    // runs to the last changed compositor frame, so it captures any render tail.
    rafIntervalsMs.push(...await readRafProbe(rafTarget));
    const settled = await visualTracker.settle(mark, {
      label: `scroll deltaY=${deltaY}`,
    });
    samplesMs.push(settled.visualElapsedMs);
    frameBytes.push(...settled.frameBytes);
    if (flutterStart != null) {
      flutterWindows.push({
        deltaY,
        startMs: flutterStart,
        endMs: await markFlutterFrames(page),
      });
    }
  }
  return { samplesMs, rafIntervalsMs, frameBytes };
}

async function runDartTextQuery(page, query) {
  return page.evaluate(async (needle) => {
    const started = performance.now();
    globalThis.__perfSearch(needle);
    const deadline = performance.now() + 30000;
    while (performance.now() < deadline) {
      if (globalThis.__perfSearchQuery() === needle &&
          !globalThis.__perfSearchBusy()) {
        return {
          elapsedMs: performance.now() - started,
          count: globalThis.__perfSearchCount(),
        };
      }
      await new Promise((resolve) => setTimeout(resolve, 0));
    }
    throw new Error(`DartPDF search timed out: ${needle}`);
  }, query);
}

async function runPdfiumTextQuery(frame, query) {
  return frame.evaluate(async (needle) => {
    const viewer = document.querySelector('pdf-viewer');
    const controller = viewer?.pluginController_;
    if (!controller || typeof controller.selectAll !== 'function' ||
        typeof controller.getSelectedText !== 'function') {
      throw new Error('PDFium text extraction API unavailable');
    }
    const started = performance.now();
    controller.selectAll();
    const reply = await controller.getSelectedText();
    const text = String(reply?.selectedText ?? '');
    const haystack = text.toLocaleLowerCase('en-US');
    const target = needle.toLocaleLowerCase('en-US');
    let count = 0;
    let from = 0;
    if (target.length) {
      while ((from = haystack.indexOf(target, from)) >= 0) {
        count++;
        from += target.length;
      }
    }
    return {
      elapsedMs: performance.now() - started,
      count,
      textLength: text.length,
    };
  }, query);
}

async function commonPage(browser) {
  const page = await browser.newPage();
  await page.setCacheEnabled(false);
  page.setDefaultTimeout(timeoutMs);
  return page;
}

// Reopen in a fresh tab of the SAME browser process/profile after the measured
// journey's tab has closed. This keeps Chrome/PDFium and Flutter/SkWasm code
// caches warm without retaining two live documents or relying on HTTP cache
// (the common full-file transport remains `no-store` for both engines).
async function measureDartWarmOpen(browser, iteration) {
  const page = await commonPage(browser);
  const visualTracker = createVisualTracker(page);
  let resolvePreload;
  const preloadSignal = new Promise((resolve) => {
    resolvePreload = resolve;
  });
  page.on('console', (message) => {
    const match = message.text().match(
      /^\[perf\.preload\] page-zero surface ready at=([0-9.]+)$/,
    );
    if (match) resolvePreload(Number(match[1]));
  });
  try {
    await visualTracker.start();
    const mark = await visualTracker.mark();
    await page.goto(
      `http://127.0.0.1:${port}/?scenario=external&run=warm-${iteration}` +
        (dartQuery ? `&${dartQuery}` : ''),
      { waitUntil: 'domcontentloaded', timeout: timeoutMs },
    );
    const logicalPromise = waitUntil(
      () => page.evaluate(() => {
        const at = Number(globalThis.__perfExternalReadyAt);
        if (globalThis.__perfExternalReady !== true ||
            !Number.isFinite(at)) return null;
        return {
          at,
          pageCount: globalThis.__perfPageCount(),
          preloadReadyAt: Number(globalThis.__perfPreloadReadyAt),
          preloadActive: globalThis.__perfPreloadActive === true,
        };
      }),
      'DartPDF warm-reopen readiness',
    );
    const earlyPreloadEpoch = await Promise.race([
      preloadSignal,
      logicalPromise.then(() => null),
    ]);
    let preloadReadyAt = Number.isFinite(earlyPreloadEpoch)
      ? translateEpochTimestamp(earlyPreloadEpoch, performance.timeOrigin)
      : null;
    let visualPromise = preloadReadyAt == null
      ? null
      : awaitLater(visualTracker.settle(mark, {
          ready: Promise.resolve(preloadReadyAt),
          label: 'DartPDF warm reopen',
        }));
    const logical = await logicalPromise;
    const flutterReadyPromise = waitUntil(
      () => page.evaluate(() => {
        const at = Number(globalThis.__perfPageReadyAt?.(0));
        if (!globalThis.__perfPageReady(0) ||
            !Number.isFinite(at) || at < 0) return null;
        return { at };
      }),
      'DartPDF warm-reopen first page raster',
    ).then(pageTimestampOnDriverClock);
    preloadReadyAt ??= logical.preloadActive &&
        Number.isFinite(logical.preloadReadyAt) &&
        logical.preloadReadyAt >= 0
      ? translateEpochTimestamp(logical.preloadReadyAt, performance.timeOrigin)
      : null;
    const readyPromise = preloadReadyAt == null
      ? flutterReadyPromise
      : Promise.resolve(preloadReadyAt);
    visualPromise ??= awaitLater(visualTracker.settle(mark, {
      ready: readyPromise,
      label: 'DartPDF warm reopen',
    }));
    await Promise.race([readyPromise, visualPromise]);
    await readyPromise;
    const visual = await visualPromise;
    await flutterReadyPromise;
    await page.evaluate(() => globalThis.__perfPreloadRelease?.());
    await page.evaluate(() => globalThis.__perfFinish());
    await waitUntil(
      () => page.evaluate(() => globalThis.__perfDone === true),
      'DartPDF warm-reopen completion',
    );
    const error = await page.evaluate(() => globalThis.__perfError);
    if (error) throw new Error(`DartPDF warm reopen: ${error}`);
    return {
      page,
      visualTracker,
      pageCount: logical.pageCount,
      firstVisualMs: visual.firstStableVisualElapsedMs,
      stableVisualMs: visual.visualElapsedMs,
      frameBytes: visual.frameBytes,
    };
  } catch (error) {
    await visualTracker.stop().catch(() => {});
    await page.close().catch(() => {});
    throw error;
  }
}

async function measurePdfiumWarmOpen(browser, iteration) {
  const page = await commonPage(browser);
  const visualTracker = createVisualTracker(page);
  try {
    await visualTracker.start();
    const mark = await visualTracker.mark();
    await page.goto(
      `http://127.0.0.1:${port}/perf.pdf?engine=pdfium&warm=${iteration}`,
      { waitUntil: 'domcontentloaded', timeout: timeoutMs },
    );
    const logical = await waitPdfium(
      page,
      (state) => state.logicalReady,
      'warm-reopen document dimensions',
    );
    if (!logical.state.apiReady) {
      throw new Error('Chrome PDF viewer warm-reopen API unavailable');
    }
    await logical.frame.evaluate(() => {
      const viewer = document.querySelector('pdf-viewer');
      if (!viewer.sidenavCollapsed_) viewer.onSidenavToggleClick_();
    });
    const readyPromise = waitPdfium(
      page,
      (state) => state.initialLoadComplete,
      'warm-reopen initial page load',
    );
    const visualPromise = awaitLater(visualTracker.settle(mark, {
      ready: readyPromise,
      label: 'PDFium warm reopen',
    }));
    const visual = await visualPromise;
    const full = await waitPdfium(
      page,
      (state) => state.fullyLoaded,
      'warm-reopen full document load',
    );
    return {
      page,
      visualTracker,
      pageCount: full.state.pageCount,
      firstVisualMs: visual.firstStableVisualElapsedMs,
      stableVisualMs: visual.visualElapsedMs,
      frameBytes: visual.frameBytes,
    };
  } catch (error) {
    await visualTracker.stop().catch(() => {});
    await page.close().catch(() => {});
    throw error;
  }
}

async function runDartPdf(serverStats, iteration) {
  const browser = await launchBrowser();
  const browserVersion = await browser.version();
  const graphics = await browserGraphicsInfo(browser);
  const browserPid = browser.process()?.pid ?? null;
  const rssSamples = [];
  const rssStages = [];
  const rssStartedAt = performance.now();
  const sampleRss = (stage) => {
    const snapshot = processTreeRssSnapshot(browserPid);
    const bytes = snapshot?.totalBytes ?? null;
    rssSamples.push(bytes);
    rssStages.push({
      stage,
      atMs: performance.now() - rssStartedAt,
      bytes,
      byTypeBytes: snapshot?.byTypeBytes ?? {},
      topProcesses: snapshot?.processes?.slice(0, 12) ?? [],
    });
    return bytes;
  };
  const rssIntervalMs = Number(scenario.memorySampleIntervalMs ?? 0);
  const rssTimer = Number.isFinite(rssIntervalMs) && rssIntervalMs > 0
    ? setInterval(() => sampleRss('periodic'), rssIntervalMs)
    : null;
  rssTimer?.unref();
  const screencastFrameBytes = [];
  const navigationSamplesMs = [];
  const navigationFirstVisualSamplesMs = [];
  const navigationReadySamplesMs = [];
  const zoomSamplesMs = [];
  const zoomFirstVisualSamplesMs = [];
  const zoomReadySamplesMs = [];
  const scrollSamplesMs = [];
  const scrollRafIntervalsMs = [];
  const scrubSamplesMs = [];
  const scrubFirstVisualSamplesMs = [];
  const scrubReadySamplesMs = [];
  const scrubRafIntervalsMs = [];
  const navigationFlutterWindows = [];
  const zoomFlutterWindows = [];
  const scrollFlutterWindows = [];
  const scrubFlutterWindows = [];
  const searchResults = [];
  const rafIntervalsMs = [];
  const consoleLines = [];
  let page;
  let visualTracker;
  let openRssBytes = null;
  let settledRssBytes = null;
  try {
    page = await commonPage(browser);
    let resolvePreloadSignal;
    const preloadSignal = new Promise((resolve) => {
      resolvePreloadSignal = resolve;
    });
    page.on('console', (message) => {
      const line = message.text();
      consoleLines.push(line);
      const match = line.match(
        /^\[perf\.preload\] page-zero surface ready at=([0-9.]+)$/,
      );
      if (match) resolvePreloadSignal(Number(match[1]));
    });
    visualTracker = createVisualTracker(page);
    await visualTracker.start();
    // Start the visual boundary before navigation. A small/simple page can
    // finish its first raster before Puppeteer's readiness poll observes the
    // Dart harness; retaining the whole screencast lets us find that frame
    // retrospectively without counting the loading surface as page content.
    // Screenshot mode must finish this blank-tab baseline before the cold-open
    // clock starts; its capture/encoding cost is instrumentation, not loading.
    const openRenderMark = await visualTracker.mark();
    const started = openRenderMark.at;
    await page.goto(
      `http://127.0.0.1:${port}/?scenario=external&run=${iteration}` +
        (dartQuery ? `&${dartQuery}` : ''),
      { waitUntil: 'domcontentloaded', timeout: timeoutMs },
    );
    if (transport === 'range') {
      await waitUntil(
        () => page.evaluate(() =>
          typeof globalThis.__perfStartDocument === 'function' || null),
        'DartPDF initialized shell trigger',
      );
      // A full composited capture is the reliable SkWasm presentation fence
      // in headless Chrome (Flutter's firstFrameRasterized future is not
      // signalled there). Keep this warm-up outside the first-request clock.
      await page.screenshot({
        type: 'jpeg',
        quality: SCREENCAST.quality,
        optimizeForSpeed: true,
      });
      await page.evaluate(() => globalThis.__perfStartDocument());
    }
    // Full screenshots contend with SkWasm compilation during bootstrap. Wait
    // only for the common logical boundary (real page count) before polling
    // pixels, then race first-page readiness and visual capture. This still
    // starts before either engine's first-page-ready boundary while avoiding a
    // measurement tool that manufactures cold-start tail latency. Continuous
    // screencast has already been collecting frames and is unaffected.
    let openLogicalReadyMs;
    let openEngineReadyMs;
    const logicalPromise = waitUntil(
      () => page.evaluate(() => {
        const at = Number(globalThis.__perfExternalReadyAt);
        if (globalThis.__perfExternalReady !== true ||
            !Number.isFinite(at)) return null;
        return {
          at,
          pageCount: globalThis.__perfPageCount(),
          preloadReadyAt: Number(globalThis.__perfPreloadReadyAt),
          preloadActive: globalThis.__perfPreloadActive === true,
          preloadError: globalThis.__perfPreloadError ?? null,
        };
      }),
      'DartPDF external harness readiness',
    );
    // The bootstrap worker can present page zero before Flutter exposes its
    // control API. Begin pixel observation at that browser-side presentation
    // boundary instead of waiting for a later page-count poll. Logical and
    // Flutter-raster clocks are still collected below and remain visible.
    const earlyPreloadEpoch = await Promise.race([
      preloadSignal,
      logicalPromise.then(() => null),
    ]);
    let preloadReadyAt = Number.isFinite(earlyPreloadEpoch)
      ? translateEpochTimestamp(earlyPreloadEpoch, performance.timeOrigin)
      : null;
    let openVisualPromise = preloadReadyAt == null
      ? null
      : awaitLater(visualTracker.settle(openRenderMark, {
          ready: Promise.resolve(preloadReadyAt),
        }));
    const logical = await logicalPromise;
    const logicalAt = pageTimestampOnDriverClock(logical);
    openLogicalReadyMs = logicalAt - started;
    let pageCount = logical.pageCount;
    const flutterReadyPromise = (async () => {
      const raster = await waitUntil(
        () => page.evaluate(() => {
          const at = Number(globalThis.__perfPageReadyAt?.(0));
          if (!globalThis.__perfPageReady(0) ||
              !Number.isFinite(at) || at < 0) return null;
          return { at };
        }),
        'DartPDF first page raster',
      );
      const rasterAt = pageTimestampOnDriverClock(raster);
      openEngineReadyMs = rasterAt - started;
      return rasterAt;
    })();
    preloadReadyAt ??= logical.preloadActive &&
        Number.isFinite(logical.preloadReadyAt) &&
        logical.preloadReadyAt >= 0
      ? translateEpochTimestamp(logical.preloadReadyAt, performance.timeOrigin)
      : null;
    const openReadyPromise = preloadReadyAt == null
      ? flutterReadyPromise
      : Promise.resolve(preloadReadyAt);
    // In a fast sparse-range open, the page-count API can become available
    // before SkWasm starts its first raster. A full composited CDP screenshot
    // taken in that narrow interval contends with SkWasm initialization and,
    // on the controlled harness, delayed raster scheduling by ~1.3 seconds.
    // That is measurement work, not engine work. Let the timestamped raster
    // boundary land first, then use screenshots to verify presentation and
    // stability. The original navigation mark still anchors elapsed time.
    if (openVisualPromise == null && transport === 'range') {
      await flutterReadyPromise;
    }
    openVisualPromise ??= awaitLater(visualTracker.settle(openRenderMark, {
      ready: openReadyPromise,
      label: 'DartPDF cold open',
    }));
    await openReadyPromise;
    await installRafProbe(page);
    const initial = await openVisualPromise;
    await flutterReadyPromise;
    await page.evaluate(() => globalThis.__perfPreloadRelease?.());
    screencastFrameBytes.push(...initial.frameBytes);
    const openVisualStableMs =
      initial.visualElapsedMs + (openRenderMark.at - started);
    const openFirstVisualMs =
      initial.firstStableVisualElapsedMs + (openRenderMark.at - started);
    const openFlutterEnd = await markFlutterFrames(page);
    openRssBytes = sampleRss('open');
    const openNetwork = {...serverStats()};
    const loaded = await waitUntil(
      () => page.evaluate(() => {
        if (typeof globalThis.__perfFullyLoaded !== 'function' ||
            globalThis.__perfFullyLoaded() !== true) return null;
        const at = Number(globalThis.__perfFullyLoadedAt?.());
        return Number.isFinite(at) && at >= 0 ? {at} : null;
      }),
      'DartPDF complete source load',
    );
    const fullyLoadedMs = pageTimestampOnDriverClock(loaded) - started;
    // A sparse preview may intentionally expose only its covered first pages
    // to avoid one Range request per leaf. Actions and correctness checks must
    // use the authoritative page count after the complete buffer swaps in.
    pageCount = await page.evaluate(() => globalThis.__perfPageCount());

    let currentPage = await page.evaluate(() => globalThis.__perfCurrentPage());
    for (const target of validTargets(scenario.pages, pageCount)) {
      if (target === currentPage) continue;
      const flutterStart = await markFlutterFrames(page);
      await resetRafProbe(page);
      const actionMark = await visualTracker.mark();
      await page.evaluate((pageIndex) => {
        console.log(
          `[driver] page=${pageIndex} browserMs=${performance.now().toFixed(1)}`,
        );
        globalThis.__perfGoToPage(pageIndex);
      }, target);
      const readyPromise = waitUntil(
        () => page.evaluate((pageIndex) => {
          const at = Number(globalThis.__perfPageReadyAt?.(pageIndex));
          // A panoramic page can occupy less than half the viewport at
          // fit-width. Jumping to it correctly places it at the leading edge,
          // while the viewport centre (and therefore `currentPage`) belongs
          // to the following page. Readiness is the requested page being
          // visible and fully rastered, not an unrelated centre-page label.
          if (!globalThis.__perfPageVisible(pageIndex) ||
              !globalThis.__perfPageReady(pageIndex) ||
              !Number.isFinite(at) || at < 0) return null;
          return { at };
        }, target),
        `DartPDF page ${target + 1}`,
      ).then(pageTimestampOnDriverClock);
      const visualPromise = awaitLater(visualTracker.settle(actionMark, {
        ready: readyPromise,
        label: `DartPDF page ${target + 1}`,
      }));
      await Promise.race([readyPromise, visualPromise]);
      const readyAt = await readyPromise;
      navigationReadySamplesMs.push(readyAt - actionMark.at);
      const settled = await visualPromise;
      await captureDiagnostic(page, 'dartpdf', iteration, target);
      navigationFirstVisualSamplesMs.push(settled.firstVisualElapsedMs);
      navigationSamplesMs.push(settled.visualElapsedMs);
      screencastFrameBytes.push(...settled.frameBytes);
      rafIntervalsMs.push(...await readRafProbe(page));
      navigationFlutterWindows.push({
        page: target,
        startMs: flutterStart,
        endMs: await markFlutterFrames(page),
      });
      sampleRss(`page:${target + 1}`);
      // Navigation readiness is intentionally based on the requested page
      // being visible and raster-ready. A short panoramic page can satisfy
      // that contract while the viewport centre (the viewer's currentPage)
      // belongs to a following page. Carry the viewer's authoritative centre
      // page into zoom readiness; retaining `target` here makes a later zoom
      // wait forever for a page that the zoom correctly moved off-screen.
      currentPage = await page.evaluate(
        () => globalThis.__perfCurrentPage(),
      );
    }

    for (const zoom of scenario.zooms.map(Number)) {
      const flutterStart = await markFlutterFrames(page);
      await resetRafProbe(page);
      const actionMark = await visualTracker.mark();
      await page.evaluate((scale) => {
        console.log(
          `[driver] zoom=${scale} browserMs=${performance.now().toFixed(1)}`,
        );
        globalThis.__perfSetZoom(scale);
      }, zoom);
      const readyPromise = waitUntil(
        () => page.evaluate(
          ({ pageIndex, scale }) =>
            Math.abs(globalThis.__perfZoom() - scale) < 0.02 &&
            globalThis.__perfPageVisible(pageIndex) &&
            !globalThis.__perfBusy(),
          { pageIndex: currentPage, scale: zoom },
        ),
        `DartPDF zoom ${zoom}`,
      );
      const visualPromise = awaitLater(visualTracker.settle(actionMark, {
        ready: readyPromise,
        label: `DartPDF zoom ${zoom}`,
      }));
      await Promise.race([readyPromise, visualPromise]);
      await readyPromise;
      zoomReadySamplesMs.push(performance.now() - actionMark.at);
      const settled = await visualPromise;
      await captureDiagnostic(
        page,
        'dartpdf',
        iteration,
        currentPage,
        `zoom-${zoom}-page-${currentPage + 1}`,
      );
      zoomFirstVisualSamplesMs.push(settled.firstVisualElapsedMs);
      zoomSamplesMs.push(settled.visualElapsedMs);
      screencastFrameBytes.push(...settled.frameBytes);
      rafIntervalsMs.push(...await readRafProbe(page));
      zoomFlutterWindows.push({
        zoom,
        startMs: flutterStart,
        endMs: await markFlutterFrames(page),
      });
      sampleRss(`zoom:${zoom}`);
      currentPage = await page.evaluate(
        () => globalThis.__perfCurrentPage(),
      );
    }

    const scroll = await driveScrollJourney(
      page,
      page,
      visualTracker,
      scenario.scrolls,
      scrollFlutterWindows,
    );
    scrollSamplesMs.push(...scroll.samplesMs);
    scrollRafIntervalsMs.push(...scroll.rafIntervalsMs);
    screencastFrameBytes.push(...scroll.frameBytes);
    if (scroll.samplesMs.length) sampleRss('scroll');

    for (const configured of scenario.scrubs ?? []) {
      const fraction = Number(configured);
      if (!Number.isFinite(fraction) || fraction < 0 || fraction > 1) continue;
      const flutterStart = await markFlutterFrames(page);
      await resetRafProbe(page);
      const actionMark = await visualTracker.mark();
      await page.evaluate((position) => {
        console.log(
          `[driver] scrub=${position} browserMs=${performance.now().toFixed(1)}`,
        );
        globalThis.__perfScrollToNormalized(position);
      }, fraction);
      const readyPromise = waitUntil(
        () => page.evaluate((position) => {
          const actual = Number(globalThis.__perfScrollPosition?.());
          const pageIndex = globalThis.__perfCurrentPage();
          const at = Number(globalThis.__perfPageReadyAt?.(pageIndex));
          if (!Number.isFinite(actual) || Math.abs(actual - position) > 0.005 ||
              !globalThis.__perfPageVisible(pageIndex) ||
              !globalThis.__perfPageReady(pageIndex) ||
              !Number.isFinite(at) || at < 0) return null;
          return { at, pageIndex, actual };
        }, fraction),
        `DartPDF scrub ${(fraction * 100).toFixed(0)}%`,
      ).then((sample) => ({
        ...sample,
        at: pageTimestampOnDriverClock(sample),
      }));
      const visualPromise = awaitLater(visualTracker.settle(actionMark, {
        ready: readyPromise.then((sample) => sample.at),
        label: `DartPDF scrub ${(fraction * 100).toFixed(0)}%`,
      }));
      await Promise.race([readyPromise, visualPromise]);
      const ready = await readyPromise;
      scrubReadySamplesMs.push(ready.at - actionMark.at);
      const settled = await visualPromise;
      scrubFirstVisualSamplesMs.push(settled.firstVisualElapsedMs);
      scrubSamplesMs.push(settled.visualElapsedMs);
      screencastFrameBytes.push(...settled.frameBytes);
      const raf = await readRafProbe(page);
      scrubRafIntervalsMs.push(...raf);
      rafIntervalsMs.push(...raf);
      scrubFlutterWindows.push({
        fraction,
        page: ready.pageIndex,
        startMs: flutterStart,
        endMs: await markFlutterFrames(page),
      });
      sampleRss(`scrub:${fraction}`);
      currentPage = ready.pageIndex;
    }

    for (const query of scenario.searches ?? []) {
      searchResults.push(await runDartTextQuery(page, String(query)));
    }
    if (searchResults.length) sampleRss('search');

    await page.evaluate(() => globalThis.__perfFinish());
    await waitUntil(
      () => page.evaluate(() => globalThis.__perfDone === true),
      'DartPDF harness completion',
    );
    const harnessError = await page.evaluate(() => globalThis.__perfError);
    if (harnessError) throw new Error(`DartPDF harness: ${harnessError}`);
    const internalMetrics = JSON.parse(
      await page.evaluate(() => globalThis.__perfMetrics()),
    );
    const frameTimings = JSON.parse(
      await page.evaluate(() => globalThis.__perfFrames()),
    );
    const flutterFramesByAction = {
      open: framesInWindow(frameTimings, 0, openFlutterEnd),
      navigation: navigationFlutterWindows.map(
        ({page: pageIndex, startMs, endMs}) => ({
          page: pageIndex,
          frames: framesInWindow(frameTimings, startMs, endMs),
        }),
      ),
      zoom: zoomFlutterWindows.map(({zoom, startMs, endMs}) => ({
        zoom,
        frames: framesInWindow(frameTimings, startMs, endMs),
      })),
      scroll: scrollFlutterWindows.map(({deltaY, startMs, endMs}) => ({
        deltaY,
        frames: framesInWindow(frameTimings, startMs, endMs),
      })),
      scrub: scrubFlutterWindows.map(
        ({fraction, page: pageIndex, startMs, endMs}) => ({
          fraction,
          page: pageIndex,
          frames: framesInWindow(frameTimings, startMs, endMs),
        }),
      ),
    };
    const traceLines = [
      ...(await page.evaluate(() => globalThis.__perfDump())).split('\n'),
      ...consoleLines,
    ];
    const primaryCaptureSummary = captureDurationSummary(visualTracker);
    let warmCaptureSummary = null;
    let warmOpenFirstVisualMs = null;
    let warmOpenVisualStableMs = null;
    if (scenario.warmReopen === true) {
      await visualTracker.stop();
      await page.close();
      sampleRss('warm:between-tabs');
      const warm = await measureDartWarmOpen(browser, iteration);
      page = warm.page;
      visualTracker = warm.visualTracker;
      if (warm.pageCount !== pageCount) {
        throw new Error(
          `DartPDF warm reopen page count changed: ${pageCount} -> ` +
            `${warm.pageCount}`,
        );
      }
      warmOpenFirstVisualMs = warm.firstVisualMs;
      warmOpenVisualStableMs = warm.stableVisualMs;
      screencastFrameBytes.push(...warm.frameBytes);
      warmCaptureSummary = captureDurationSummary(visualTracker);
      sampleRss('warm:open');
    }
    const memorySettleMs = Number(scenario.memorySettleMs ?? 0);
    if (Number.isFinite(memorySettleMs) && memorySettleMs > 0) {
      await sleep(memorySettleMs);
    }
    settledRssBytes = sampleRss('final-settled');
    const network = serverStats();
    const documentRequestOffsetMs = Number.isFinite(network.firstRequestAt)
      ? network.firstRequestAt - started
      : null;
    return {
      engine: 'dart-pdf',
      pageCount,
      openLogicalReadyMs,
      openEngineReadyMs,
      openPreloadReadyMs: preloadReadyAt == null
        ? null
        : preloadReadyAt - started,
      openFirstVisualMs,
      openVisualStableMs,
      documentFirstVisualMs: Number.isFinite(documentRequestOffsetMs)
        ? openFirstVisualMs - documentRequestOffsetMs
        : null,
      documentVisualStableMs: Number.isFinite(documentRequestOffsetMs)
        ? openVisualStableMs - documentRequestOffsetMs
        : null,
      documentRequestOffsetMs,
      navigationFullyLoadedMs: fullyLoadedMs,
      fullyLoadedMs: Number.isFinite(documentRequestOffsetMs)
        ? fullyLoadedMs - documentRequestOffsetMs
        : fullyLoadedMs,
      warmOpenFirstVisualMs,
      warmOpenVisualStableMs,
      navigationSamplesMs,
      navigationFirstVisualSamplesMs,
      navigationReadySamplesMs,
      zoomSamplesMs,
      zoomFirstVisualSamplesMs,
      zoomReadySamplesMs,
      scrollSamplesMs,
      scrollRafIntervalsMs,
      scrubSamplesMs,
      scrubFirstVisualSamplesMs,
      scrubReadySamplesMs,
      scrubRafIntervalsMs,
      searchColdMs: searchResults[0]?.elapsedMs ?? null,
      searchWarmMs: searchResults[1]?.elapsedMs ?? null,
      searchResults,
      screencastFrameBytes,
      rafIntervalsMs,
      browserRssBytes: rssSamples.some(Number.isFinite)
        ? Math.max(...rssSamples.filter(Number.isFinite))
        : null,
      browserOpenRssBytes: openRssBytes,
      browserPeakRssBytes: rssSamples.some(Number.isFinite)
        ? Math.max(...rssSamples.filter(Number.isFinite))
        : null,
      browserSettledRssBytes: settledRssBytes,
      openNetwork,
      network,
      finalVisualHash: visualTracker.lastHash,
      diagnostics: {
        browserVersion,
        graphics,
        internalMetrics,
        preloadError: logical.preloadError,
        flutterBuildMsP95: percentile(
          frameTimings.map((frame) => frame.b),
          95,
        ),
        flutterRasterMsP95: percentile(
          frameTimings.map((frame) => frame.r),
          95,
        ),
        flutterFramesByAction,
        traceSample: traceLines
          .filter((line) =>
            /interpret|webworker|scheduler|renderhold|raster|replay|decode|flate|image|jpeg|softmask|preview|page-raster|page-ready|jump-focus|command-warm|record-cache|detail|region-index|tile|vector|surface|\[driver\]/i
              .test(line),
          )
          // Keep enough context to preserve the explicit action markers on a
          // multi-page journey; a 200-line tail was swallowed by scroll and
          // search diagnostics before the earlier navigation markers.
          .slice(-1000),
        rssStages,
        screenshotCaptureDurationMs: primaryCaptureSummary,
        warmScreenshotCaptureDurationMs: warmCaptureSummary,
      },
    };
  } catch (error) {
    if (process.env.PERF_DUMP_ON_ERROR === 'true' && page != null) {
      let dumpLines = [];
      try {
        const dump = await Promise.race([
          page.evaluate(() => globalThis.__perfDump?.() ?? '')
            .catch(() => null),
          sleep(1000).then(() => null),
        ]);
        if (dump != null) dumpLines = String(dump).split('\n');
      } catch (_) {
        // The page may already have crashed or navigated away. Console output
        // collected by Puppeteer is still useful in that case.
      }
      const failureTrace = [...dumpLines, ...consoleLines]
        .filter((line) =>
          /interpret|webworker|scheduler|renderhold|raster|replay|decode|flate|image|jpeg|softmask|preview|page-raster|page-ready|jump-focus|command-warm|detail|region-index|tile|vector|surface|\[driver\]/i
            .test(line),
        )
        .slice(-1000);
      if (failureTrace.length > 0) {
        console.error('\n── DartPDF failure trace ──');
        console.error(failureTrace.join('\n'));
      }
    }
    throw error;
  } finally {
    if (rssTimer != null) clearInterval(rssTimer);
    await visualTracker?.stop().catch(() => {});
    await browser.close().catch(() => {});
  }
}

async function runPdfium(serverStats, iteration) {
  const browser = await launchBrowser();
  const browserVersion = await browser.version();
  const graphics = await browserGraphicsInfo(browser);
  const browserPid = browser.process()?.pid ?? null;
  const rssSamples = [];
  const rssStages = [];
  const rssStartedAt = performance.now();
  const sampleRss = (stage) => {
    const snapshot = processTreeRssSnapshot(browserPid);
    const bytes = snapshot?.totalBytes ?? null;
    rssSamples.push(bytes);
    rssStages.push({
      stage,
      atMs: performance.now() - rssStartedAt,
      bytes,
      byTypeBytes: snapshot?.byTypeBytes ?? {},
      topProcesses: snapshot?.processes?.slice(0, 12) ?? [],
    });
    return bytes;
  };
  const rssIntervalMs = Number(scenario.memorySampleIntervalMs ?? 0);
  const rssTimer = Number.isFinite(rssIntervalMs) && rssIntervalMs > 0
    ? setInterval(() => sampleRss('periodic'), rssIntervalMs)
    : null;
  rssTimer?.unref();
  const screencastFrameBytes = [];
  const navigationSamplesMs = [];
  const navigationFirstVisualSamplesMs = [];
  const navigationReadySamplesMs = [];
  const zoomSamplesMs = [];
  const zoomFirstVisualSamplesMs = [];
  const zoomReadySamplesMs = [];
  const scrollSamplesMs = [];
  const scrollRafIntervalsMs = [];
  const scrubSamplesMs = [];
  const scrubFirstVisualSamplesMs = [];
  const scrubReadySamplesMs = [];
  const scrubRafIntervalsMs = [];
  const searchResults = [];
  const rafIntervalsMs = [];
  let page;
  let visualTracker;
  let openRssBytes = null;
  let settledRssBytes = null;
  try {
    page = await commonPage(browser);
    visualTracker = createVisualTracker(page);
    await visualTracker.start();
    // Use the same pre-navigation boundary as DartPDF. Extension bootstrap,
    // the thumbnail rail, and blank placeholders remain in the frame history,
    // but the cold-open metric selects the first occurrence of the eventual
    // settled page pixels rather than the first arbitrary visual change. The
    // baseline screenshot itself is outside the cold-open clock for both.
    const openRenderMark = await visualTracker.mark();
    const started = openRenderMark.at;
    await page.goto(
      `http://127.0.0.1:${port}/perf.pdf?engine=pdfium&run=${iteration}`,
      { waitUntil: 'domcontentloaded', timeout: timeoutMs },
    );
    let openLogicalReadyMs;
    let openEngineReadyMs;
    const logical = await waitPdfium(
      page,
      (state) => state.logicalReady,
      'document dimensions',
    );
    openLogicalReadyMs = performance.now() - started;
    if (!logical.state.apiReady) {
      throw new Error(
        'Chrome PDF viewer API changed: missing viewport.goToPage/setZoom',
      );
    }
    // A clean Chrome profile opens its thumbnail rail. The Dart engine harness
    // intentionally contains only the viewer canvas, so leave both engines the
    // same page viewport before visual polling begins.
    await logical.frame.evaluate(() => {
      const viewer = document.querySelector('pdf-viewer');
      if (!viewer.sidenavCollapsed_) viewer.onSidenavToggleClick_();
    });
    const openReadyPromise = (async () => {
      const initial = await waitPdfium(
        page,
        (state) => state.initialLoadComplete,
        'initial page load',
      );
      openEngineReadyMs = performance.now() - started;
      return initial;
    })();
    const openVisualPromise = awaitLater(visualTracker.settle(openRenderMark, {
      ready: openReadyPromise,
      label: 'PDFium cold open',
    }));
    const initial = await openReadyPromise;
    await installRafProbe(initial.frame);
    const visual = await openVisualPromise;
    screencastFrameBytes.push(...visual.frameBytes);
    const openVisualStableMs =
      visual.visualElapsedMs + (openRenderMark.at - started);
    const openFirstVisualMs =
      visual.firstStableVisualElapsedMs + (openRenderMark.at - started);
    openRssBytes = sampleRss('open');
    const openNetwork = {...serverStats()};

    const full = await waitPdfium(
      page,
      (state) => state.fullyLoaded,
      'full document load',
    );
    const fullyLoadedMs = performance.now() - started;
    const pageCount = full.state.pageCount;
    let currentPage = full.state.currentPage;

    for (const target of validTargets(scenario.pages, pageCount)) {
      if (target === currentPage) continue;
      const frame = (await waitPdfium(page, () => true, 'frame')).frame;
      await resetRafProbe(frame);
      const actionMark = await visualTracker.mark();
      await frame.evaluate((pageIndex) => {
        document.querySelector('pdf-viewer').viewport_.goToPage(pageIndex);
      }, target);
      const readyPromise = waitPdfium(
        page,
        (state) => state.currentPage === target,
        `page ${target + 1}`,
      );
      const visualPromise = awaitLater(visualTracker.settle(actionMark, {
        ready: readyPromise,
        label: `PDFium page ${target + 1}`,
      }));
      const arrived = await readyPromise;
      navigationReadySamplesMs.push(performance.now() - actionMark.at);
      const settled = await visualPromise;
      await captureDiagnostic(page, 'pdfium', iteration, target);
      navigationFirstVisualSamplesMs.push(settled.firstVisualElapsedMs);
      navigationSamplesMs.push(settled.visualElapsedMs);
      screencastFrameBytes.push(...settled.frameBytes);
      rafIntervalsMs.push(...await readRafProbe(arrived.frame));
      sampleRss(`page:${target + 1}`);
      currentPage = target;
    }

    for (const zoom of scenario.zooms.map(Number)) {
      const frame = (await waitPdfium(page, () => true, 'frame')).frame;
      await resetRafProbe(frame);
      const actionMark = await visualTracker.mark();
      await frame.evaluate((scale) => {
        document.querySelector('pdf-viewer').viewport_.setZoom(scale);
      }, zoom);
      const readyPromise = waitPdfium(
        page,
        (state) => Math.abs(state.zoom - zoom) < 0.02,
        `zoom ${zoom}`,
      );
      const visualPromise = awaitLater(visualTracker.settle(actionMark, {
        ready: readyPromise,
        label: `PDFium zoom ${zoom}`,
      }));
      const zoomed = await readyPromise;
      zoomReadySamplesMs.push(performance.now() - actionMark.at);
      const settled = await visualPromise;
      await captureDiagnostic(
        page,
        'pdfium',
        iteration,
        currentPage,
        `zoom-${zoom}-page-${currentPage + 1}`,
      );
      zoomFirstVisualSamplesMs.push(settled.firstVisualElapsedMs);
      zoomSamplesMs.push(settled.visualElapsedMs);
      screencastFrameBytes.push(...settled.frameBytes);
      rafIntervalsMs.push(...await readRafProbe(zoomed.frame));
      sampleRss(`zoom:${zoom}`);
    }

    const journeyFrame = (await waitPdfium(page, () => true, 'frame')).frame;
    const scroll = await driveScrollJourney(
      page,
      journeyFrame,
      visualTracker,
      scenario.scrolls,
    );
    scrollSamplesMs.push(...scroll.samplesMs);
    scrollRafIntervalsMs.push(...scroll.rafIntervalsMs);
    screencastFrameBytes.push(...scroll.frameBytes);
    if (scroll.samplesMs.length) sampleRss('scroll');

    for (const configured of scenario.scrubs ?? []) {
      const fraction = Number(configured);
      if (!Number.isFinite(fraction) || fraction < 0 || fraction > 1) continue;
      const frame = (await waitPdfium(page, () => true, 'frame')).frame;
      await resetRafProbe(frame);
      const actionMark = await visualTracker.mark();
      await frame.evaluate((position) => {
        const viewport = document.querySelector('pdf-viewer').viewport_;
        const extent = Math.max(
          0,
          viewport.contentSize.height - viewport.size.height,
        );
        viewport.scrollTo({ x: viewport.position.x, y: extent * position });
      }, fraction);
      const readyPromise = waitPdfium(
        page,
        (state) => Number.isFinite(state.scrollFraction) &&
          Math.abs(state.scrollFraction - fraction) <= 0.005,
        `scrub ${(fraction * 100).toFixed(0)}%`,
      );
      const visualPromise = awaitLater(visualTracker.settle(actionMark, {
        ready: readyPromise,
        label: `PDFium scrub ${(fraction * 100).toFixed(0)}%`,
      }));
      const arrived = await readyPromise;
      scrubReadySamplesMs.push(performance.now() - actionMark.at);
      const settled = await visualPromise;
      scrubFirstVisualSamplesMs.push(settled.firstVisualElapsedMs);
      scrubSamplesMs.push(settled.visualElapsedMs);
      screencastFrameBytes.push(...settled.frameBytes);
      const raf = await readRafProbe(arrived.frame);
      scrubRafIntervalsMs.push(...raf);
      rafIntervalsMs.push(...raf);
      sampleRss(`scrub:${fraction}`);
      currentPage = arrived.state.currentPage;
    }

    for (const query of scenario.searches ?? []) {
      searchResults.push(await runPdfiumTextQuery(journeyFrame, String(query)));
    }
    if (searchResults.length) sampleRss('search');

    const primaryCaptureSummary = captureDurationSummary(visualTracker);
    let warmCaptureSummary = null;
    let warmOpenFirstVisualMs = null;
    let warmOpenVisualStableMs = null;
    if (scenario.warmReopen === true) {
      await visualTracker.stop();
      await page.close();
      sampleRss('warm:between-tabs');
      const warm = await measurePdfiumWarmOpen(browser, iteration);
      page = warm.page;
      visualTracker = warm.visualTracker;
      if (warm.pageCount !== pageCount) {
        throw new Error(
          `PDFium warm reopen page count changed: ${pageCount} -> ` +
            `${warm.pageCount}`,
        );
      }
      warmOpenFirstVisualMs = warm.firstVisualMs;
      warmOpenVisualStableMs = warm.stableVisualMs;
      screencastFrameBytes.push(...warm.frameBytes);
      warmCaptureSummary = captureDurationSummary(visualTracker);
      sampleRss('warm:open');
    }
    const memorySettleMs = Number(scenario.memorySettleMs ?? 0);
    if (Number.isFinite(memorySettleMs) && memorySettleMs > 0) {
      await sleep(memorySettleMs);
    }
    settledRssBytes = sampleRss('final-settled');

    const network = serverStats();
    const documentRequestOffsetMs = Number.isFinite(network.firstRequestAt)
      ? network.firstRequestAt - started
      : null;
    return {
      engine: 'pdfium',
      pageCount,
      openLogicalReadyMs,
      openEngineReadyMs,
      openFirstVisualMs,
      openVisualStableMs,
      documentFirstVisualMs: Number.isFinite(documentRequestOffsetMs)
        ? openFirstVisualMs - documentRequestOffsetMs
        : null,
      documentVisualStableMs: Number.isFinite(documentRequestOffsetMs)
        ? openVisualStableMs - documentRequestOffsetMs
        : null,
      documentRequestOffsetMs,
      navigationFullyLoadedMs: fullyLoadedMs,
      fullyLoadedMs: Number.isFinite(documentRequestOffsetMs)
        ? fullyLoadedMs - documentRequestOffsetMs
        : fullyLoadedMs,
      warmOpenFirstVisualMs,
      warmOpenVisualStableMs,
      navigationSamplesMs,
      navigationFirstVisualSamplesMs,
      navigationReadySamplesMs,
      zoomSamplesMs,
      zoomFirstVisualSamplesMs,
      zoomReadySamplesMs,
      scrollSamplesMs,
      scrollRafIntervalsMs,
      scrubSamplesMs,
      scrubFirstVisualSamplesMs,
      scrubReadySamplesMs,
      scrubRafIntervalsMs,
      searchColdMs: searchResults[0]?.elapsedMs ?? null,
      searchWarmMs: searchResults[1]?.elapsedMs ?? null,
      searchResults,
      screencastFrameBytes,
      rafIntervalsMs,
      browserRssBytes: rssSamples.some(Number.isFinite)
        ? Math.max(...rssSamples.filter(Number.isFinite))
        : null,
      browserOpenRssBytes: openRssBytes,
      browserPeakRssBytes: rssSamples.some(Number.isFinite)
        ? Math.max(...rssSamples.filter(Number.isFinite))
        : null,
      browserSettledRssBytes: settledRssBytes,
      openNetwork,
      network,
      finalVisualHash: visualTracker.lastHash,
      diagnostics: {
        browserVersion,
        graphics,
        loadProgress: full.state.fullyLoaded ? 100 : null,
        rssStages,
        screenshotCaptureDurationMs: primaryCaptureSummary,
        warmScreenshotCaptureDurationMs: warmCaptureSummary,
      },
    };
  } finally {
    if (rssTimer != null) clearInterval(rssTimer);
    await visualTracker?.stop().catch(() => {});
    await browser.close().catch(() => {});
  }
}

function formatMs(value) {
  return Number.isFinite(value) ? value.toFixed(1) : '—';
}

function formatRatio(value) {
  return Number.isFinite(value) ? `${value.toFixed(2)}×` : '—';
}

function printReport(dart, pdfium, ratios, budgetResults) {
  const rows = [
    ['open first visual p50', dart.openFirstVisualMs.p50, pdfium.openFirstVisualMs.p50, ratios.openFirstP50, 'openFirstP50'],
    ['open first visual p95', dart.openFirstVisualMs.p95, pdfium.openFirstVisualMs.p95, ratios.openFirstP95, 'openFirstP95'],
    ['open visual p50', dart.openVisualStableMs.p50, pdfium.openVisualStableMs.p50, ratios.openP50, 'openP50'],
    ['open visual p95', dart.openVisualStableMs.p95, pdfium.openVisualStableMs.p95, ratios.openP95, 'openP95'],
    ['document first visual p50', dart.documentFirstVisualMs.p50, pdfium.documentFirstVisualMs.p50, ratios.documentFirstP50, 'documentFirstP50'],
    ['document first visual p95', dart.documentFirstVisualMs.p95, pdfium.documentFirstVisualMs.p95, ratios.documentFirstP95, 'documentFirstP95'],
    ['document open p50', dart.documentVisualStableMs.p50, pdfium.documentVisualStableMs.p50, ratios.documentOpenP50, 'documentOpenP50'],
    ['document open p95', dart.documentVisualStableMs.p95, pdfium.documentVisualStableMs.p95, ratios.documentOpenP95, 'documentOpenP95'],
    ['fully loaded p50', dart.fullyLoadedMs.p50, pdfium.fullyLoadedMs.p50, ratios.fullyLoadedP50, 'fullyLoadedP50'],
    ['fully loaded p95', dart.fullyLoadedMs.p95, pdfium.fullyLoadedMs.p95, ratios.fullyLoadedP95, 'fullyLoadedP95'],
    ['bytes at open p50', dart.openNetworkBytes.p50, pdfium.openNetworkBytes.p50, ratios.openTransferP50, 'openTransferP50'],
    ['bytes at open p95', dart.openNetworkBytes.p95, pdfium.openNetworkBytes.p95, ratios.openTransferP95, 'openTransferP95'],
    ['total PDF bytes p50', dart.totalNetworkBytes.p50, pdfium.totalNetworkBytes.p50, ratios.totalTransferP50, 'totalTransferP50'],
    ['total PDF bytes p95', dart.totalNetworkBytes.p95, pdfium.totalNetworkBytes.p95, ratios.totalTransferP95, 'totalTransferP95'],
    ['requests at open p50', dart.openNetworkRequests.p50, pdfium.openNetworkRequests.p50, ratios.openRequestP50, 'openRequestP50'],
    ['requests at open p95', dart.openNetworkRequests.p95, pdfium.openNetworkRequests.p95, ratios.openRequestP95, 'openRequestP95'],
    ['total PDF requests p50', dart.totalNetworkRequests.p50, pdfium.totalNetworkRequests.p50, ratios.totalRequestP50, 'totalRequestP50'],
    ['total PDF requests p95', dart.totalNetworkRequests.p95, pdfium.totalNetworkRequests.p95, ratios.totalRequestP95, 'totalRequestP95'],
    ['warm open first p50', dart.warmOpenFirstVisualMs.p50, pdfium.warmOpenFirstVisualMs.p50, ratios.warmOpenFirstP50, 'warmOpenFirstP50'],
    ['warm open first p95', dart.warmOpenFirstVisualMs.p95, pdfium.warmOpenFirstVisualMs.p95, ratios.warmOpenFirstP95, 'warmOpenFirstP95'],
    ['warm open p50', dart.warmOpenVisualStableMs.p50, pdfium.warmOpenVisualStableMs.p50, ratios.warmOpenP50, 'warmOpenP50'],
    ['warm open p95', dart.warmOpenVisualStableMs.p95, pdfium.warmOpenVisualStableMs.p95, ratios.warmOpenP95, 'warmOpenP95'],
    ['page first visual p50', dart.navigationFirstVisualMs.p50, pdfium.navigationFirstVisualMs.p50, ratios.navigationFirstP50, 'navigationFirstP50'],
    ['page first visual p95', dart.navigationFirstVisualMs.p95, pdfium.navigationFirstVisualMs.p95, ratios.navigationFirstP95, 'navigationFirstP95'],
    ['page jump p50', dart.navigationMs.p50, pdfium.navigationMs.p50, ratios.navigationP50, 'navigationP50'],
    ['page jump p95', dart.navigationMs.p95, pdfium.navigationMs.p95, ratios.navigationP95, 'navigationP95'],
    ['zoom first visual p50', dart.zoomFirstVisualMs.p50, pdfium.zoomFirstVisualMs.p50, ratios.zoomFirstP50, 'zoomFirstP50'],
    ['zoom first visual p95', dart.zoomFirstVisualMs.p95, pdfium.zoomFirstVisualMs.p95, ratios.zoomFirstP95, 'zoomFirstP95'],
    ['zoom p50', dart.zoomMs.p50, pdfium.zoomMs.p50, ratios.zoomP50, 'zoomP50'],
    ['zoom p95', dart.zoomMs.p95, pdfium.zoomMs.p95, ratios.zoomP95, 'zoomP95'],
    ['scroll journey p50', dart.scrollMs.p50, pdfium.scrollMs.p50, ratios.scrollP50, 'scrollP50'],
    ['scroll journey p95', dart.scrollMs.p95, pdfium.scrollMs.p95, ratios.scrollP95, 'scrollP95'],
    ['scroll rAF p95', dart.scrollRafIntervalMs.p95, pdfium.scrollRafIntervalMs.p95, ratios.scrollRafP95, 'scrollRafP95'],
    ['scrub first visual p50', dart.scrubFirstVisualMs.p50, pdfium.scrubFirstVisualMs.p50, ratios.scrubFirstP50, 'scrubFirstP50'],
    ['scrub first visual p95', dart.scrubFirstVisualMs.p95, pdfium.scrubFirstVisualMs.p95, ratios.scrubFirstP95, 'scrubFirstP95'],
    ['scrub p50', dart.scrubMs.p50, pdfium.scrubMs.p50, ratios.scrubP50, 'scrubP50'],
    ['scrub p95', dart.scrubMs.p95, pdfium.scrubMs.p95, ratios.scrubP95, 'scrubP95'],
    ['scrub rAF p95', dart.scrubRafIntervalMs.p95, pdfium.scrubRafIntervalMs.p95, ratios.scrubRafP95, 'scrubRafP95'],
    ['search cold p50', dart.searchColdMs.p50, pdfium.searchColdMs.p50, ratios.searchColdP50, 'searchColdP50'],
    ['search cold p95', dart.searchColdMs.p95, pdfium.searchColdMs.p95, ratios.searchColdP95, 'searchColdP95'],
    ['search warm p50', dart.searchWarmMs.p50, pdfium.searchWarmMs.p50, ratios.searchWarmP50, 'searchWarmP50'],
    ['search warm p95', dart.searchWarmMs.p95, pdfium.searchWarmMs.p95, ratios.searchWarmP95, 'searchWarmP95'],
    ['browser peak RSS p50 MiB', dart.browserRssBytes.p50 / 1048576, pdfium.browserRssBytes.p50 / 1048576, ratios.rssP50, 'rssP50'],
    ['browser settled RSS MiB', dart.browserSettledRssBytes.p50 / 1048576, pdfium.browserSettledRssBytes.p50 / 1048576, ratios.settledRssP50, 'settledRssP50'],
  ].filter(([, dartValue, pdfiumValue]) =>
    Number.isFinite(dartValue) || Number.isFinite(pdfiumValue));
  const budgetByMetric = new Map(
    budgetResults.map((result) => [result.metric, result]),
  );
  console.log('\nmetric                    dart-pdf    PDFium      ratio     target');
  console.log('─'.repeat(75));
  for (const [name, d, p, ratio, key] of rows) {
    const budget = budgetByMetric.get(key);
    const verdict = budget?.pass ? '✓' : '✗';
    console.log(
      name.padEnd(26) +
      formatMs(d).padEnd(12) +
      formatMs(p).padEnd(12) +
      formatRatio(ratio).padEnd(10) +
      `${budget ? `≤${budget.limit.toFixed(2)}× ${verdict}` : '—'}`,
    );
  }
  console.log('─'.repeat(75));
  const misses = budgetResults.filter((result) => !result.pass);
  console.log(
    misses.length
      ? `PDFium parity not yet reached: ${misses.map((m) => m.metric).join(', ')}`
      : 'PDFium parity budgets met for this run.',
  );
}

async function main() {
  if (gate && visualCaptureMode === 'none') {
    throw new Error(
      '--gate cannot be used with PERF_VISUAL_CAPTURE=none: visual parity ' +
      'metrics are deliberately invalid in diagnostics-only mode',
    );
  }
  const server = await startServer();
  const dartRuns = [];
  const pdfiumRuns = [];
  let chromeVersion = null;
  console.log(`\n══ DartPDF ↔ Chromium/PDFium: ${scenarioName}`);
  console.log(`   ${scenario.note}`);
  console.log(`   pdf=${pdfPath} iterations=${iterations} headless=${headless}`);
  try {
    // Alternate order each iteration to distribute temperature/background
    // drift rather than always handing one engine the cold machine.
    for (let index = 0; index < iterations; index++) {
      const order = index % 2 === 0
        ? ['dart-pdf', 'pdfium']
        : ['pdfium', 'dart-pdf'];
      for (const engine of order) {
        console.log(`\n── iteration ${index + 1}/${iterations}: ${engine}`);
        server.resetStats();
        const run = engine === 'dart-pdf'
          ? await runDartPdf(server.stats, index)
          : await runPdfium(server.stats, index);
        (engine === 'dart-pdf' ? dartRuns : pdfiumRuns).push(run);
        console.log(
          `   open=${run.openVisualStableMs.toFixed(1)}ms ` +
          `jump-p50=${formatMs(percentile(run.navigationSamplesMs, 50))}ms ` +
          `zoom-p50=${formatMs(percentile(run.zoomSamplesMs, 50))}ms ` +
          (run.scrubSamplesMs?.length
            ? `scrub-p50=${formatMs(percentile(run.scrubSamplesMs, 50))}ms `
            : '') +
          (run.warmOpenVisualStableMs == null
            ? ''
            : `warm=${formatMs(run.warmOpenVisualStableMs)}ms `) +
          `scroll-p95=${formatMs(percentile(run.scrollRafIntervalsMs, 95))}ms ` +
          (run.searchColdMs == null
            ? ''
            : `search=${formatMs(run.searchColdMs)}/${formatMs(run.searchWarmMs)}ms `) +
          `rss=${formatMs(run.browserRssBytes / 1048576)}MiB`,
        );
        if (browserCooldownMs > 0) await sleep(browserCooldownMs);
      }
    }
    chromeVersion =
      dartRuns[0]?.diagnostics?.browserVersion ??
      pdfiumRuns[0]?.diagnostics?.browserVersion ??
      chromePath;
  } finally {
    server.server.close();
  }

  for (let run = 0; run < dartRuns.length; run++) {
    for (let query = 0; query < (scenario.searches?.length ?? 0); query++) {
      const dartCount = dartRuns[run]?.searchResults?.[query]?.count;
      const pdfiumCount = pdfiumRuns[run]?.searchResults?.[query]?.count;
      if (dartCount !== pdfiumCount) {
        throw new Error(
          `search result mismatch for "${scenario.searches[query]}" ` +
          `(iteration ${run + 1}): DartPDF=${dartCount}, PDFium=${pdfiumCount}`,
        );
      }
    }
  }

  const dart = aggregateRuns(dartRuns);
  const pdfium = aggregateRuns(pdfiumRuns);
  const ratios = parityRatios(dart, pdfium);
  const budgets = scenario.inheritBudgets === false
    ? {...(scenario.budgets ?? {})}
    : {...REGISTRY.budgets, ...(scenario.budgets ?? {})};
  const visualMetricsValid = visualCaptureMode !== 'none';
  const budgetResults = visualMetricsValid
    ? evaluateBudgets(ratios, budgets)
    : [];
  if (visualMetricsValid) {
    printReport(dart, pdfium, ratios, budgetResults);
  } else {
    console.log(
      '\nvisual capture disabled: parity table suppressed; ' +
      'only frame, search, and RSS diagnostics are valid',
    );
  }

  const record = {
    schema: 1,
    suite: 'chrome-pdfium-parity',
    scenario: scenarioName,
    params: {
      iterations,
      pdfPath,
      registeredPdfPath: scenario.pdf,
      viewport: VIEWPORT,
      webDirectory: WEB_DIR,
      visualCaptureMode,
      webBackend,
      screencast: SCREENCAST,
      screenshotSampleDelayMs: visualCaptureMode === 'screenshot'
        ? screenshotSampleDelayMs
        : null,
      pages: scenario.pages,
      zooms: scenario.zooms,
      scrolls: scenario.scrolls ?? [],
      scrubs: scenario.scrubs ?? [],
      warmReopen: scenario.warmReopen === true,
      memorySampleIntervalMs: scenario.memorySampleIntervalMs ?? 0,
      memorySettleMs: scenario.memorySettleMs ?? 0,
      searches: scenario.searches ?? [],
      transport,
      dartQuery,
      browserCooldownMs,
      visualStability: visualCaptureMode === 'none'
        ? 'disabled (diagnostic quiet window only; visual metrics invalid)'
        : visualCaptureMode === 'screenshot'
          ? 'last changed full composited screenshot followed by 500ms quiet'
          : 'last changed Chrome compositor frame followed by 500ms quiet',
      budgets,
    },
    rev: {
      sha: git(['rev-parse', 'HEAD']),
      branch: git(['rev-parse', '--abbrev-ref', 'HEAD']),
      dirty: Boolean(git(['status', '--porcelain'])),
      date: git(['show', '-s', '--format=%cI', 'HEAD']),
    },
    env: {
      os: `${platform()}-${arch()}`,
      cpus: cpus().length,
      node: process.version,
      chrome: chromeVersion,
      graphics:
        dartRuns[0]?.diagnostics?.graphics ??
        pdfiumRuns[0]?.diagnostics?.graphics ??
        null,
      headless,
      ci: process.env.CI === 'true',
    },
    ts: new Date().toISOString(),
    metrics: visualMetricsValid
      ? {
          ...Object.fromEntries(
            Object.entries(ratios).map(
              ([key, value]) => [`${key}Ratio`, value],
            ),
          ),
          parityMisses: budgetResults.filter((result) => !result.pass).length,
        }
      : { parityMisses: null },
    aggregates: { dartPdf: dart, pdfium },
    parity: budgetResults,
    runs: { dartPdf: dartRuns, pdfium: pdfiumRuns },
  };
  await appendFile(outPath, `${JSON.stringify(record)}\n`);
  console.log(`\n▸ result: ${outPath}`);

  if (gate && budgetResults.some((result) => !result.pass)) process.exit(1);
}

main().catch((error) => {
  console.error(error?.stack ?? error);
  process.exit(1);
});
