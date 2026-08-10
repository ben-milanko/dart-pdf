#!/usr/bin/env node
// Correctness gate for the default-off worker-owned browser page surface.
//
// It renders representative page/zoom states twice through the same SkWasm
// harness: once with the established Flutter compositor and once with
// `domSurface=1`. Chrome captures the exact visible worker canvas rectangle in
// both tabs. Pixel error plus one-pixel-tolerant foreground precision/recall
// catch missing or extra geometry without treating antialiasing edges as whole
// missing paths.
//
//   node surface_compare.mjs --scenario parity-plan
//   node surface_compare.mjs --scenario parity-plan --pages 0,8,15 --gate

import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { dirname, extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import puppeteer from 'puppeteer-core';

import {
  compareRgba,
  evaluateSurfaceSample,
} from './surface_compare_common.mjs';

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
const VIEWPORT = { width: 1400, height: 1000 };
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
};
const CHROME_CANDIDATES = [
  process.env.PERF_CHROME,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
].filter(Boolean);

const argv = process.argv.slice(2);
function opt(name, fallback) {
  const index = argv.indexOf(name);
  return index >= 0 && argv[index + 1] ? argv[index + 1] : fallback;
}
const has = (name) => argv.includes(name);
const list = (value) => String(value)
  .split(',')
  .map(Number)
  .filter(Number.isFinite);
const unique = (values) => [...new Set(values)];

const scenarioName = opt('--scenario', REGISTRY.default);
const scenario = REGISTRY.scenarios[scenarioName];
const timeoutMs = Number(opt('--timeout', '300000'));
const port = Number(opt('--port', process.env.PERF_PORT ?? '8110'));
const headless = !has('--headed') && process.env.PERF_HEADLESS !== 'false';
const gate = has('--gate');
const chromePath = CHROME_CANDIDATES.find(existsSync);
const pdfPath = normalize(
  process.env.PERF_PDF ??
    (scenario ? join(REPO_ROOT, scenario.pdf) : ''),
);
const baseQuery = new URLSearchParams(
  String(process.env.PERF_DART_QUERY ?? '').replace(/^[?&]+/, ''),
);
baseQuery.delete('domSurface');
const defaultPages = unique((scenario?.pages ?? [0]).map(Number)).slice(0, 3);
// Preserve one repeated zoom leg from the competitive journey. The worker
// surface keeps a bounded exact-size bitmap for repeated zoom-out states; a
// unique-only matrix would verify cache misses while never checking the pixels
// produced by the cache hit that contributes to the latency gate.
const defaultZooms = (scenario?.zooms ?? [1]).map(Number).slice(0, 4);
const pages = unique(list(opt('--pages', defaultPages.join(','))))
  .filter((page) => Number.isInteger(page) && page >= 0);
const zooms = list(opt('--zooms', defaultZooms.join(',')))
  .filter((zoom) => zoom > 0);
const scenarioComparison = scenario?.surfaceComparison ?? {};
const comparisonOptions = {
  channelTolerance: Number(opt(
    '--channel-tolerance',
    String(scenarioComparison.channelTolerance ?? 8),
  )),
  backgroundTolerance: Number(opt(
    '--background-tolerance',
    String(scenarioComparison.backgroundTolerance ?? 24),
  )),
  foregroundRadius: Number(opt(
    '--foreground-radius',
    String(scenarioComparison.foregroundRadius ?? 1),
  )),
  background: [255, 255, 255],
};
const artifactRoot = resolve(
  opt(
    '--artifacts',
    join(
      '/tmp',
      `dartpdf-surface-${scenarioName}-${new Date().toISOString()}`
        .replaceAll(':', '-'),
    ),
  ),
);
const reportPath = resolve(opt('--out', join(artifactRoot, 'report.json')));

function fail(message) {
  console.error(`✗ ${message}`);
  process.exit(2);
}

if (!scenario) {
  fail(
    `unknown scenario "${scenarioName}"; known: ` +
      Object.keys(REGISTRY.scenarios).join(', '),
  );
}
if (!pages.length) fail('--pages must contain at least one page index');
if (!zooms.length) fail('--zooms must contain at least one positive scale');
if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
  fail('--timeout must be positive');
}
if (!existsSync(pdfPath)) fail(`PDF not found: ${pdfPath}`);
if (!existsSync(join(WEB_DIR, 'index.html')) ||
    !existsSync(join(WEB_DIR, 'main.dart.js'))) {
  fail(`no DartPDF perf build in ${WEB_DIR}; run app/tool/perf/build.sh`);
}
if (!chromePath) fail('Chrome/Chromium not found; set PERF_CHROME');

const sleep = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));
const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');

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

async function startServer() {
  const pdfBytes = await readFile(pdfPath);
  const rootPrefix = WEB_DIR.endsWith(sep) ? WEB_DIR : `${WEB_DIR}${sep}`;
  const server = createServer(async (request, response) => {
    try {
      const requestPath = decodeURIComponent(
        new URL(request.url ?? '/', `http://${request.headers.host}`).pathname,
      );
      if (requestPath === '/perf.pdf') {
        response.writeHead(200, {
          'content-type': 'application/pdf',
          'content-length': pdfBytes.length,
          'cache-control': 'no-store',
          'accept-ranges': 'none',
        });
        response.end(pdfBytes);
        return;
      }
      const requestFile = requestPath === '/' ? '/index.html' : requestPath;
      const file = resolve(WEB_DIR, `.${requestFile}`);
      if (file !== WEB_DIR && !file.startsWith(rootPrefix)) {
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
  return { server, pdfBytes };
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

function harnessUrl(surface) {
  const query = new URLSearchParams(baseQuery);
  query.set('scenario', 'external');
  query.set('run', surface ? 'surface' : 'baseline');
  // Idle preview interpretation is unrelated to this same-page correctness
  // check and can make a background comparison tab consume the worker pool
  // while Chrome is encoding its screenshot.
  if (!query.has('previews')) query.set('previews', '0');
  if (!query.has('previewIdleMs')) query.set('previewIdleMs', '-1');
  if (surface) query.set('domSurface', '1');
  return `http://127.0.0.1:${port}/?${query}`;
}

async function openHarness(browser, surface) {
  const page = await browser.newPage();
  const consoleLines = [];
  page.on('console', (message) => {
    consoleLines.push(message.text());
    if (process.env.PERF_VERBOSE === 'true') {
      console.log(`   [${surface ? 'surface' : 'baseline'}] ${message.text()}`);
    }
  });
  await page.setCacheEnabled(false);
  page.setDefaultTimeout(timeoutMs);
  await page.goto(harnessUrl(surface), {
    waitUntil: 'domcontentloaded',
    timeout: timeoutMs,
  });
  await waitUntil(
    () => page.evaluate(() => globalThis.__perfExternalReady === true),
    `${surface ? 'surface' : 'baseline'} harness readiness`,
  );
  let preload = null;
  if (surface) {
    const clip = await page.evaluate(() => {
      if (globalThis.__perfPreloadActive !== true) return null;
      const canvas = document.querySelector('#pdf-page-zero-preload');
      if (!canvas) return null;
      const rect = canvas.getBoundingClientRect();
      const x = Math.max(0, Math.floor(rect.left));
      const y = Math.max(0, Math.floor(rect.top));
      const rawRight = Math.min(innerWidth, Math.ceil(rect.right));
      const rawBottom = Math.min(innerHeight, Math.ceil(rect.bottom));
      const right = rect.right >= innerWidth - 0.5
        ? Math.max(x + 1, rawRight - 16)
        : rawRight;
      const bottom = rect.bottom >= innerHeight - 0.5
        ? Math.max(y + 1, rawBottom - 16)
        : rawBottom;
      return {
        x,
        y,
        width: right - x,
        height: bottom - y,
        cssRect: {
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
        },
        backingWidth: canvas.width,
        backingHeight: canvas.height,
      };
    });
    if (clip?.width > 0 && clip?.height > 0) {
      preload = {
        clip,
        shot: await stableScreenshot(page, clip, 'pre-Flutter page zero'),
      };
    }
  }
  // The competitive harness may have shown its pre-Flutter page-zero canvas.
  // This gate compares the real viewer surfaces across arbitrary pages/zooms,
  // so release that cold-start overlay before taking either arm's snapshots.
  await page.evaluate(() => globalThis.__perfPreloadRelease?.());
  let handoff = null;
  if (surface && preload != null) {
    await waitUntil(
      () => page.evaluate(() =>
        globalThis.__perfPageReady(0) && !globalThis.__perfBusy(),
      ),
      'hydrated worker page zero',
    );
    const clip = await surfaceClip(page, 0);
    handoff = {
      clip,
      shot: await stableScreenshot(page, clip, 'hydrated page zero'),
    };
  }
  return { page, consoleLines, preload, handoff };
}

async function settleHarness(page, pageIndex, zoom) {
  // Headless Chrome throttles background tabs. The comparison keeps baseline,
  // candidate, and decode pages in one clean browser, so explicitly foreground
  // the renderer being settled before waiting on its frame callbacks.
  await page.bringToFront();
  // Center the full destination crop first. showRect lands at 100% for this
  // large rectangle; applying the requested zoom afterwards keeps that center
  // fixed in both independently-timed tabs.
  await page.evaluate(
    (target) => globalThis.__perfCenterPage(target),
    pageIndex,
  );
  await waitUntil(
    () => page.evaluate(
      (target) =>
        globalThis.__perfCurrentPage() === target &&
        globalThis.__perfPageVisible(target),
      pageIndex,
    ),
    `centered page ${pageIndex + 1}`,
  );
  await sleep(800);
  await page.evaluate((scale) => globalThis.__perfSetZoom(scale), zoom);
  await waitUntil(
    () => page.evaluate(
      ({ target, scale }) =>
        globalThis.__perfCurrentPage() === target &&
        globalThis.__perfPageVisible(target) &&
        Math.abs(globalThis.__perfZoom() - scale) < 0.02 &&
        globalThis.__perfPageReady(target) &&
        !globalThis.__perfBusy(),
      { target: pageIndex, scale: zoom },
    ),
    `page ${pageIndex + 1} at ${zoom}×`,
  );
  // Far jumps can report their cached/base raster before the sharp destination
  // layer has painted. This is a correctness probe, not a latency metric: give
  // that presentation tail a deterministic quiet window, then re-check all
  // state before capturing.
  await sleep(800);
  await waitUntil(
    () => page.evaluate(
      ({ target, scale }) =>
        globalThis.__perfCurrentPage() === target &&
        globalThis.__perfPageVisible(target) &&
        Math.abs(globalThis.__perfZoom() - scale) < 0.02 &&
        globalThis.__perfPageReady(target) &&
        !globalThis.__perfBusy(),
      { target: pageIndex, scale: zoom },
    ),
    `settled page ${pageIndex + 1} at ${zoom}×`,
  );
  await page.evaluate(() => new Promise((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(resolve));
  }));
}

async function mirrorHarnessView(source, destination, pageIndex, zoom) {
  const sync = await source.evaluate(() => globalThis.__perfViewSync());
  if (!sync) throw new Error('source harness did not expose a view snapshot');
  await destination.bringToFront();
  await destination.evaluate(
    (snapshot) => globalThis.__perfApplyViewSync(snapshot),
    sync,
  );
  await waitUntil(
    () => destination.evaluate(
      ({ target, scale }) =>
        globalThis.__perfCurrentPage() === target &&
        globalThis.__perfPageVisible(target) &&
        Math.abs(globalThis.__perfZoom() - scale) < 0.02 &&
        globalThis.__perfPageReady(target) &&
        !globalThis.__perfBusy(),
      { target: pageIndex, scale: zoom },
    ),
    `mirrored page ${pageIndex + 1} at ${zoom}×`,
  );
  // applyViewSync may relay pages out on the next frame when layout zoom
  // changes. Give the destination the same correctness-only quiet window as
  // the canonical surface view, then re-apply the exact snapshot after layout
  // metrics exist so neither tab independently rounds its destination.
  await sleep(800);
  await destination.evaluate(
    (snapshot) => globalThis.__perfApplyViewSync(snapshot),
    sync,
  );
  await waitUntil(
    () => destination.evaluate(
      ({ target, scale }) =>
        globalThis.__perfCurrentPage() === target &&
        globalThis.__perfPageVisible(target) &&
        Math.abs(globalThis.__perfZoom() - scale) < 0.02 &&
        globalThis.__perfPageReady(target) &&
        !globalThis.__perfBusy(),
      { target: pageIndex, scale: zoom },
    ),
    `settled mirrored page ${pageIndex + 1} at ${zoom}×`,
  );
  await destination.evaluate(() => new Promise((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(resolve));
  }));
  return sync;
}

async function surfaceClip(page, pageIndex) {
  return waitUntil(
    () => page.evaluate((target) => {
      const selector =
        `canvas[data-dartpdf-worker-surface-page="${target}"]`;
      const elements = [];
      const visit = (root) => {
        elements.push(...root.querySelectorAll(selector));
        for (const element of root.querySelectorAll('*')) {
          if (element.shadowRoot) visit(element.shadowRoot);
        }
      };
      // Flutter embeds HtmlElementView content under platform-view shadow
      // roots. document.querySelectorAll alone therefore sees no canvas even
      // though Chrome composites it; walk every open shadow tree.
      visit(document);
      const candidates = elements
        .map((element) => ({
          element,
          rect: element.getBoundingClientRect(),
          visible: getComputedStyle(element).visibility !== 'hidden',
        }))
        .filter(({ element, rect, visible }) =>
          visible &&
          element.getAttribute('data-dartpdf-worker-surface-ready') ===
            'true' &&
          rect.width > 0 && rect.height > 0 &&
          rect.right > 0 && rect.bottom > 0 &&
          rect.left < innerWidth && rect.top < innerHeight,
        )
        .sort((a, b) => b.rect.width * b.rect.height -
          a.rect.width * a.rect.height);
      if (!candidates.length) return null;
      const { element, rect } = candidates[0];
      const x = Math.max(0, Math.floor(rect.left));
      const y = Math.max(0, Math.floor(rect.top));
      const rawRight = Math.min(innerWidth, Math.ceil(rect.right));
      const rawBottom = Math.min(innerHeight, Math.ceil(rect.bottom));
      // The viewer's fading scrollbars paint above the page at viewport edges.
      // Exclude their 14px hit zone plus two pixels of outline so screenshot
      // stability and pixel metrics describe PDF content only.
      const right = rect.right >= innerWidth - 0.5
        ? Math.max(x + 1, rawRight - 16)
        : rawRight;
      const bottom = rect.bottom >= innerHeight - 0.5
        ? Math.max(y + 1, rawBottom - 16)
        : rawBottom;
      return {
        x,
        y,
        width: right - x,
        height: bottom - y,
        cssRect: {
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
        },
        backingWidth: element.width,
        backingHeight: element.height,
        visibility: getComputedStyle(element).visibility,
      };
    }, pageIndex),
    `visible worker surface for page ${pageIndex + 1}`,
  );
}

async function stableScreenshot(page, clip, label) {
  await page.bringToFront();
  await page.evaluate(() => new Promise((resolve) => {
    requestAnimationFrame(() => requestAnimationFrame(resolve));
  }));
  let previousHash = null;
  let previousBytes = null;
  for (let attempt = 0; attempt < 30; attempt++) {
    const bytes = await page.screenshot({
      type: 'png',
      // The worker canvas can be several times larger than the viewport at
      // zoom. Puppeteer's default captureBeyondViewport=true temporarily
      // expands Chrome's surface around that element; Flutter observes the
      // resize, relays out the document, and invalidates the very frame being
      // measured. The clip above is already intersected with innerWidth/
      // innerHeight, so a viewport-only capture is both sufficient and inert.
      captureBeyondViewport: false,
      clip: {
        x: clip.x,
        y: clip.y,
        width: clip.width,
        height: clip.height,
      },
      optimizeForSpeed: true,
    });
    const hash = digest(bytes);
    if (hash === previousHash) return { bytes, hash, attempts: attempt + 1 };
    previousHash = hash;
    previousBytes = bytes;
    await sleep(80);
  }
  throw new Error(
    `${label} screenshot did not stabilize ` +
      `(last=${digest(previousBytes)})`,
  );
}

async function comparePngs(comparePage, baselineBytes, candidateBytes) {
  const baseline = Buffer.from(baselineBytes).toString('base64');
  const candidate = Buffer.from(candidateBytes).toString('base64');
  const comparatorSource = compareRgba.toString();
  return comparePage.evaluate(
    async ({ baseline, candidate, comparatorSource, options }) => {
      const decode = async (base64) => {
        const binary = atob(base64);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) {
          bytes[i] = binary.charCodeAt(i);
        }
        const bitmap = await createImageBitmap(
          new Blob([bytes], { type: 'image/png' }),
        );
        const canvas = document.createElement('canvas');
        canvas.width = bitmap.width;
        canvas.height = bitmap.height;
        const context = canvas.getContext('2d', { willReadFrequently: true });
        context.drawImage(bitmap, 0, 0);
        bitmap.close();
        return {
          width: canvas.width,
          height: canvas.height,
          pixels: context.getImageData(0, 0, canvas.width, canvas.height).data,
        };
      };
      const [left, right] = await Promise.all([
        decode(baseline),
        decode(candidate),
      ]);
      if (left.width !== right.width || left.height !== right.height) {
        throw new Error(
          `image sizes differ: ${left.width}x${left.height} vs ` +
            `${right.width}x${right.height}`,
        );
      }
      // The comparator is pure and unit-tested in Node. Evaluating its source
      // here avoids serializing two multi-megabyte RGBA arrays back over CDP.
      const comparator = (0, eval)(`(${comparatorSource})`);
      const metrics = comparator(
        left.pixels,
        right.pixels,
        left.width,
        left.height,
        options,
      );

      const diffCanvas = document.createElement('canvas');
      diffCanvas.width = left.width;
      diffCanvas.height = left.height;
      const diffContext = diffCanvas.getContext('2d');
      const diff = diffContext.createImageData(left.width, left.height);
      for (let offset = 0; offset < left.pixels.length; offset += 4) {
        const maximum = Math.max(
          Math.abs(left.pixels[offset] - right.pixels[offset]),
          Math.abs(left.pixels[offset + 1] - right.pixels[offset + 1]),
          Math.abs(left.pixels[offset + 2] - right.pixels[offset + 2]),
        );
        if (maximum > options.channelTolerance) {
          diff.data[offset] = 255;
          diff.data[offset + 1] = 0;
          diff.data[offset + 2] = 0;
        } else {
          const luma = (left.pixels[offset] * 54 +
            left.pixels[offset + 1] * 183 +
            left.pixels[offset + 2] * 19) / 256;
          const faint = Math.round(224 + luma * 31 / 255);
          diff.data[offset] = faint;
          diff.data[offset + 1] = faint;
          diff.data[offset + 2] = faint;
        }
        diff.data[offset + 3] = 255;
      }
      diffContext.putImageData(diff, 0, 0);
      return {
        metrics,
        diffBase64: diffCanvas.toDataURL('image/png').split(',')[1],
      };
    },
    { baseline, candidate, comparatorSource, options: comparisonOptions },
  );
}

function percent(value, digits = 3) {
  return `${(value * 100).toFixed(digits)}%`;
}

async function main() {
  const { server, pdfBytes } = await startServer();
  let browser;
  try {
    await mkdir(artifactRoot, { recursive: true });
    browser = await launchBrowser();
    const browserVersion = await browser.version();
    const baselineHarness = await openHarness(browser, false);
    const surfaceHarness = await openHarness(browser, true);
    const comparePage = await browser.newPage();
    const pageCount = await surfaceHarness.page.evaluate(
      () => globalThis.__perfPageCount(),
    );
    const targets = pages.filter((page) => page < pageCount);
    if (!targets.length) {
      throw new Error(`none of pages ${pages.join(',')} exist (${pageCount})`);
    }
    const samples = [];
    const budgets = scenario.surfaceBudgets ?? REGISTRY.surfaceBudgets ?? null;
    if (gate && !budgets) {
      throw new Error(
        `--gate requested but ${scenarioName} has no surfaceBudgets`,
      );
    }

    let preloadSample = null;
    let preloadHandoffSample = null;
    if (surfaceHarness.preload != null) {
      await waitUntil(
        () => baselineHarness.page.evaluate(() =>
          globalThis.__perfPageReady(0) && !globalThis.__perfBusy(),
        ),
        'baseline page zero for pre-Flutter comparison',
      );
      const baselineShot = await stableScreenshot(
        baselineHarness.page,
        surfaceHarness.preload.clip,
        'baseline initial page zero',
      );
      const comparison = await comparePngs(
        comparePage,
        baselineShot.bytes,
        surfaceHarness.preload.shot.bytes,
      );
      const checks = evaluateSurfaceSample(comparison.metrics, budgets);
      const pass = checks.length ? checks.every((check) => check.pass) : null;
      await Promise.all([
        writeFile(join(artifactRoot, 'preload-baseline.png'), baselineShot.bytes),
        writeFile(
          join(artifactRoot, 'preload-surface.png'),
          surfaceHarness.preload.shot.bytes,
        ),
        writeFile(
          join(artifactRoot, 'preload-diff.png'),
          Buffer.from(comparison.diffBase64, 'base64'),
        ),
      ]);
      preloadSample = {
        clip: surfaceHarness.preload.clip,
        baselineHash: baselineShot.hash,
        surfaceHash: surfaceHarness.preload.shot.hash,
        metrics: comparison.metrics,
        checks,
        pass,
        gated: false,
        artifacts: {
          baseline: 'preload-baseline.png',
          surface: 'preload-surface.png',
          diff: 'preload-diff.png',
        },
      };
      console.log(
        `   preload vs Flutter p1 (diagnostic)  ` +
        `diff>${comparisonOptions.channelTolerance} ` +
        `${percent(comparison.metrics.differenceFraction)}  ` +
        `fg recall ${percent(comparison.metrics.foregroundRecall, 2)}  ` +
        `precision ${percent(comparison.metrics.foregroundPrecision, 2)}` +
        (pass == null ? '' : pass ? '  ✓' : '  ✗'),
      );
      if (surfaceHarness.handoff != null &&
          surfaceHarness.handoff.clip.width ===
            surfaceHarness.preload.clip.width &&
          surfaceHarness.handoff.clip.height ===
            surfaceHarness.preload.clip.height) {
        const handoffComparison = await comparePngs(
          comparePage,
          surfaceHarness.handoff.shot.bytes,
          surfaceHarness.preload.shot.bytes,
        );
        const handoffChecks = evaluateSurfaceSample(
          handoffComparison.metrics,
          budgets,
        );
        const handoffPass = handoffChecks.length
          ? handoffChecks.every((check) => check.pass)
          : null;
        preloadHandoffSample = {
          clip: surfaceHarness.preload.clip,
          handoffClip: surfaceHarness.handoff.clip,
          metrics: handoffComparison.metrics,
          checks: handoffChecks,
          pass: handoffPass,
        };
        await Promise.all([
          writeFile(
            join(artifactRoot, 'preload-handoff.png'),
            surfaceHarness.handoff.shot.bytes,
          ),
          writeFile(
            join(artifactRoot, 'preload-handoff-diff.png'),
            Buffer.from(handoffComparison.diffBase64, 'base64'),
          ),
        ]);
        console.log(
          `   preload handoff  diff>${comparisonOptions.channelTolerance} ` +
          `${percent(handoffComparison.metrics.differenceFraction)}  ` +
          `fg recall ` +
          `${percent(handoffComparison.metrics.foregroundRecall, 2)}  ` +
          `precision ` +
          `${percent(handoffComparison.metrics.foregroundPrecision, 2)}` +
          (handoffPass == null ? '' : handoffPass ? '  ✓' : '  ✗'),
        );
      }
    }

    console.log(
      `══ worker surface correctness: ${scenarioName} ` +
        `(${targets.map((page) => page + 1).join(', ')})`,
    );
    console.log(`   build: ${WEB_DIR}`);
    console.log(`   artifacts: ${artifactRoot}`);

    for (const pageIndex of targets) {
      for (const zoom of zooms) {
        console.log(`   preparing canonical p${pageIndex + 1} @ ${zoom}× surface`);
        await settleHarness(surfaceHarness.page, pageIndex, zoom);
        console.log(`   mirroring p${pageIndex + 1} @ ${zoom}× into baseline`);
        const viewSync = await mirrorHarnessView(
          surfaceHarness.page,
          baselineHarness.page,
          pageIndex,
          zoom,
        );
        console.log(`   locating p${pageIndex + 1} worker canvas`);
        const clip = await surfaceClip(surfaceHarness.page, pageIndex);
        console.log(
          `   capturing ${clip.width}×${clip.height} visible page pixels`,
        );
        const baselineShot = await stableScreenshot(
          baselineHarness.page,
          clip,
          `baseline p${pageIndex + 1} @ ${zoom}×`,
        );
        const surfaceShot = await stableScreenshot(
          surfaceHarness.page,
          clip,
          `surface p${pageIndex + 1} @ ${zoom}×`,
        );
        const comparison = await comparePngs(
          comparePage,
          baselineShot.bytes,
          surfaceShot.bytes,
        );
        const checks = evaluateSurfaceSample(comparison.metrics, budgets);
        const pass = checks.length ? checks.every((check) => check.pass) : null;
        const stem = `page-${String(pageIndex + 1).padStart(3, '0')}` +
          `-zoom-${String(zoom).replace('.', '_')}`;
        await Promise.all([
          writeFile(join(artifactRoot, `${stem}-baseline.png`), baselineShot.bytes),
          writeFile(join(artifactRoot, `${stem}-surface.png`), surfaceShot.bytes),
          writeFile(
            join(artifactRoot, `${stem}-diff.png`),
            Buffer.from(comparison.diffBase64, 'base64'),
          ),
        ]);
        samples.push({
          pageIndex,
          zoom,
          clip,
          viewSync: JSON.parse(viewSync),
          baselineHash: baselineShot.hash,
          surfaceHash: surfaceShot.hash,
          baselineStabilityCaptures: baselineShot.attempts,
          surfaceStabilityCaptures: surfaceShot.attempts,
          metrics: comparison.metrics,
          checks,
          pass,
          artifacts: {
            baseline: `${stem}-baseline.png`,
            surface: `${stem}-surface.png`,
            diff: `${stem}-diff.png`,
          },
        });
        console.log(
          `   p${pageIndex + 1} @ ${zoom}×  ` +
            `diff>${comparisonOptions.channelTolerance} ` +
            `${percent(comparison.metrics.differenceFraction)}  ` +
            `MAE ${comparison.metrics.meanAbsoluteChannelError.toFixed(2)}  ` +
            `fg recall ${percent(comparison.metrics.foregroundRecall, 2)}  ` +
            `precision ${percent(comparison.metrics.foregroundPrecision, 2)}` +
            (pass == null ? '' : pass ? '  ✓' : '  ✗'),
        );
      }
    }

    const allChecks = [
      // Preload-vs-hydrated-surface is the handoff invariant. The separate
      // preload-vs-Flutter sample remains diagnostic because the established
      // surface gate below already compares those renderers across every
      // selected page/zoom, with scenario-calibrated scales.
      ...(preloadHandoffSample?.checks ?? []),
      ...samples.flatMap((sample) => sample.checks),
    ];
    const passed = allChecks.length ? allChecks.every((check) => check.pass) : null;
    const report = {
      schema: 1,
      generatedAt: new Date().toISOString(),
      scenario: scenarioName,
      scenarioNote: scenario.note,
      pdf: scenario.pdf,
      pdfBytes: pdfBytes.length,
      pdfSha256: digest(pdfBytes),
      buildDirectory: WEB_DIR,
      browserVersion,
      chromePath,
      viewport: VIEWPORT,
      pagesRequested: pages,
      pagesTested: targets,
      zooms,
      baseQuery: baseQuery.toString(),
      comparisonOptions,
      budgets,
      passed,
      preloadSample,
      preloadHandoffSample,
      samples,
      console: {
        baseline: baselineHarness.consoleLines,
        surface: surfaceHarness.consoleLines,
      },
    };
    await mkdir(dirname(reportPath), { recursive: true });
    await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`);
    await Promise.all([
      baselineHarness.page.evaluate(() => globalThis.__perfFinish?.()),
      surfaceHarness.page.evaluate(() => globalThis.__perfFinish?.()),
    ]).catch(() => {});
    console.log(`   report: ${reportPath}`);
    if (gate) {
      console.log(passed ? '✓ surface correctness gate passed' :
        '✗ surface correctness gate failed');
      if (!passed) process.exitCode = 1;
    } else {
      console.log('· diagnostic run (add --gate after budgets are calibrated)');
    }
  } finally {
    await browser?.close().catch(() => {});
    await new Promise((resolve) => server.close(resolve));
  }
}

main().catch((error) => {
  console.error(error?.stack ?? String(error));
  process.exitCode = 2;
});
