#!/usr/bin/env node
// Playwright driver for the web render benchmark.
//
// Loads a served `web_benchmark.dart` build in headless Chromium, waits for the
// in-page harness to publish `window.__benchResults`, and writes a JSON payload
// in the same schema as benchmark/compare.py (tool/scale/maxPages/engine/
// results[]) plus web-specific fields (renderer actually used, boot time, and
// approximate transfer size).
//
//   NODE_PATH=$(npm root -g) node drive.cjs \
//     --url http://localhost:8099/ --tool canvaskit \
//     --out out/web-canvaskit.json --timeout 900000
//
// WebGL in headless Chromium falls back to SwiftShader (software). That makes
// the ABSOLUTE numbers software-rasterized rather than GPU; the CanvasKit-vs-
// skwasm RATIO is still the portable signal. Pass --headed (with a display) for
// GPU numbers.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : def;
}
const has = (name) => process.argv.includes(`--${name}`);

const url = arg('url', 'http://localhost:8099/');
const tool = arg('tool', 'web');
const out = arg('out', `out/${tool}.json`);
const timeout = parseInt(arg('timeout', '900000'), 10);
const headed = has('headed');

(async () => {
  const browser = await chromium.launch({
    headless: !headed,
    args: [
      '--enable-unsafe-swiftshader',
      '--ignore-gpu-blocklist',
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--enable-features=SharedArrayBuffer',
      '--lang=en-US',
    ],
  });
  // An explicit locale is required: headless Chromium otherwise reports an empty
  // locale that Flutter's Locale parser rejects with "Incorrect locale
  // information provided", which kills boot before the harness can run.
  const context = await browser.newContext({ locale: 'en-US' });
  // Block the CDN font fallback (CanvasKit/skwasm fetch Noto faces from
  // fonts.gstatic.com for glyphs missing from embedded fonts). The sandbox
  // can't reach it anyway; aborting makes the run offline + deterministic and
  // applies the same handicap to both renderers.
  await context.route('**://fonts.gstatic.com/**', (r) => r.abort());
  const page = await context.newPage();

  // Detect which renderer actually ran + tally app transfer size.
  let sawSkwasm = false;
  let sawCanvaskit = false;
  let sawWasmApp = false;
  let appBytes = 0;
  page.on('response', (resp) => {
    const u = resp.url();
    if (/skwasm/i.test(u)) sawSkwasm = true;
    if (/canvaskit/i.test(u)) sawCanvaskit = true;
    if (/main\.dart\.wasm/i.test(u)) sawWasmApp = true;
    if (!/\/bench\/pdfs\//.test(u)) {
      const len = parseInt(resp.headers()['content-length'] || '0', 10);
      if (Number.isFinite(len)) appBytes += len;
    }
  });
  page.on('console', (m) => {
    const t = m.text();
    // Skip the expected blocked-font-fallback noise; surface real errors.
    if (/gstatic|Failed to load font|ERR_FAILED/i.test(t)) return;
    if (/error|exception|fail/i.test(t)) console.log(`  [page] ${t}`);
  });
  page.on('pageerror', (e) => console.log(`  [pageerror] ${e.message}`));

  const navStart = Date.now();
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout });

  await page.waitForFunction('window.__benchReady === true', { timeout });
  const loadMs = Date.now() - navStart;
  console.log(`  [${tool}] booted in ${loadMs} ms`);

  // Surface progress while the long render loop runs.
  let last = '';
  const ticker = setInterval(async () => {
    try {
      const p = await page.evaluate('window.__benchProgress || ""');
      if (p && p !== last) {
        last = p;
        console.log(`  [${tool}] ${p}`);
      }
    } catch (_) {}
  }, 3000);

  await page.waitForFunction(
    'window.__benchResults != null || window.__benchError != null',
    { timeout });
  clearInterval(ticker);

  const errStr = await page.evaluate('window.__benchError || null');
  if (errStr) {
    console.error(`  [${tool}] harness error: ${errStr}`);
    await browser.close();
    process.exit(1);
  }

  const resStr = await page.evaluate('window.__benchResults');
  const inner = JSON.parse(resStr);
  await browser.close();

  const renderer = sawSkwasm
    ? 'skwasm'
    : sawCanvaskit
    ? 'canvaskit'
    : 'unknown';
  const engine = sawSkwasm
    ? `Flutter Wasm/skwasm renderer${sawWasmApp ? ' (dart2wasm app)' : ''}`
    : 'Flutter CanvasKit renderer (dart2js app)';

  const payload = {
    tool,
    engine,
    renderer,
    scale: inner.scale,
    maxPages: inner.maxPages,
    repeat: inner.repeat,
    loadMs,
    appBytes,
    results: inner.results,
  };

  fs.mkdirSync(path.dirname(path.resolve(out)), { recursive: true });
  fs.writeFileSync(out, JSON.stringify(payload, null, 2));

  const ok = inner.results.filter((r) => r && !r.error);
  const pages = ok.reduce((a, r) => a + (r.pagesRendered || 0), 0);
  const ms = ok.reduce((a, r) => a + (r.renderMs || 0), 0);
  console.log(
    `  [${tool}] renderer=${renderer} app≈${(appBytes / 1e6).toFixed(1)}MB ` +
      `boot=${loadMs}ms — ${pages} pages in ${ms.toFixed(0)}ms ` +
      `(${pages && ms ? (1000 * pages / ms).toFixed(1) : '0'} pages/s)`);
  console.log(`  wrote ${out}`);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
