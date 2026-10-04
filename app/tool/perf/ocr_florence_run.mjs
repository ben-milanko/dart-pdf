// Runs exported OCR tiles through the app's browser OCR bridge in headless
// Chromium - the middle step of the Florence-2 accuracy benchmark
// (app/test/ocr_web_accuracy_test.dart exports the tiles and scores the
// output). The bridge is lifted verbatim from app/web/index.html at run time,
// so this measures exactly what ships: same Transformers.js build, same model,
// same dtypes, same generation settings.
//
//   node ocr_florence_run.mjs <tile dir>
//
// Reads <tile dir>/manifest.json, writes <tile dir>/results.json. Env:
//   CHROME            browser binary (default: the Playwright Chromium)
//   OCR_PROFILE_DIR   persistent Chromium profile, so Transformers.js's model
//                     cache survives between runs (default: a fresh profile)
//   OCR_WEBGPU=1      expose WebGPU (the bridge then runs on it; headless
//                     Chromium's software adapter can crash on this model, so
//                     the default is the bridge's WASM path)
//   OCR_FETCH_VIA_NODE=1  fetch the page's https requests from Node instead of
//                     Chromium - for sandboxes whose TLS-intercepting proxy CA
//                     Node trusts (NODE_EXTRA_CA_CERTS + NODE_USE_ENV_PROXY=1)
//                     but Chromium's NSS store does not. Verification stays on.
//                     Each request is redirected to this script's localhost
//                     server, which streams it from Node through a disk cache
//                     (OCR_FETCH_CACHE, default <tile dir>/../fetch_cache) - a
//                     multi-hundred-MB model file can't cross the DevTools
//                     protocol as one interception response.
import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const here = dirname(fileURLToPath(import.meta.url));
const dir = process.argv[2];
if (!dir) throw new Error('usage: node ocr_florence_run.mjs <tile dir>');
const CHROME = process.env.CHROME ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';

// The bridge is the inline <script> in index.html that defines it.
const indexHtml = readFileSync(join(here, '../../web/index.html'), 'utf8');
const bridge = [...indexHtml.matchAll(/<script>([\s\S]*?)<\/script>/g)]
  .map((m) => m[1])
  .find((s) => s.includes('__dartPdfOcrRecognize'));
if (!bridge) throw new Error('no __dartPdfOcrRecognize bridge in web/index.html');

const cacheDir = process.env.OCR_FETCH_CACHE ?? join(dir, '..', 'fetch_cache');

// Streams [target] from Node (verified TLS through the env proxy), caching it
// on disk so repeat runs don't re-download the model.
async function relay(target, res) {
  const key = createHash('sha256').update(target).digest('hex');
  const body = join(cacheDir, key), meta = `${body}.json`;
  if (!existsSync(meta)) {
    mkdirSync(cacheDir, { recursive: true });
    const r = await fetch(target, { redirect: 'follow' });
    if (!r.ok) {
      res.writeHead(r.status, { 'access-control-allow-origin': '*' });
      return res.end();
    }
    const tmp = `${body}.part`;
    const out = createWriteStream(tmp);
    for await (const chunk of r.body) out.write(chunk);
    await new Promise((done) => out.end(done));
    renameSync(tmp, body);
    writeFileSync(meta, JSON.stringify({ type: r.headers.get('content-type') }));
    console.log(`fetched ${target}`);
  }
  const { type } = JSON.parse(readFileSync(meta, 'utf8'));
  res.writeHead(200, {
    'content-type': type ?? 'application/octet-stream',
    'access-control-allow-origin': '*',
  });
  createReadStream(body).pipe(res);
}

// A localhost origin, so the page is a secure context (Cache API, WebGPU).
const server = createServer((req, res) => {
  const u = new URL(req.url, 'http://127.0.0.1');
  if (u.pathname === '/fetch') {
    relay(u.searchParams.get('u'), res).catch((e) => {
      console.log(`fetch failed ${u.searchParams.get('u')}: ${e.cause ?? e}`);
      res.writeHead(502, { 'access-control-allow-origin': '*' });
      res.end();
    });
    return;
  }
  res.writeHead(200, { 'content-type': 'text/html' });
  res.end(`<!doctype html><meta charset="utf-8"><script>${bridge}</script>`);
}).listen(0, '127.0.0.1');
await new Promise((r) => server.once('listening', r));
const url = `http://127.0.0.1:${server.address().port}/`;

const viaNode = process.env.OCR_FETCH_VIA_NODE === '1';
const browser = await puppeteer.launch({
  executablePath: CHROME,
  headless: true,
  userDataDir: process.env.OCR_PROFILE_DIR,
  args: ['--no-sandbox', '--disable-dev-shm-usage',
    ...(process.env.OCR_WEBGPU === '1' ? ['--enable-unsafe-webgpu'] : [])],
  protocolTimeout: 0,
});
try {
  const page = await browser.newPage();
  if (process.env.OCR_WEBGPU !== '1') {
    // Headless Chromium still defines navigator.gpu with no adapter behind it.
    await page.evaluateOnNewDocument(() => {
      Object.defineProperty(Navigator.prototype, 'gpu', { get: () => undefined });
    });
  }
  if (viaNode) {
    await page.setRequestInterception(true);
    page.on('request', (req) => {
      if (!req.url().startsWith('https:')) return req.continue();
      return req.respond({
        status: 307,
        headers: {
          location: `${url}fetch?u=${encodeURIComponent(req.url())}`,
          'access-control-allow-origin': '*',
        },
      });
    });
  }
  page.on('error', (e) => console.log(`[page crashed] ${e.message}`));
  await page.goto(url);
  const gpu = await page.evaluate(async () => !!(navigator.gpu && await navigator.gpu.requestAdapter()));
  console.log(`WebGPU adapter: ${gpu}`);
  const manifest = JSON.parse(readFileSync(join(dir, 'manifest.json'), 'utf8'));
  const results = [];
  const started = Date.now();
  for (const tile of manifest) {
    const png = readFileSync(join(dir, tile.file));
    const t0 = Date.now();
    const out = await page.evaluate(async (dataUrl) => {
      const json = await window.__dartPdfOcrRecognize(dataUrl);
      const img = new Image();
      img.src = dataUrl;
      await img.decode();
      return { json, width: img.naturalWidth, height: img.naturalHeight };
    }, `data:image/png;base64,${png.toString('base64')}`);
    results.push({ tile, width: out.width, height: out.height, result: JSON.parse(out.json) });
    console.log(`${tile.file}: ${Date.now() - t0} ms`);
  }
  writeFileSync(join(dir, 'results.json'), JSON.stringify(results));
  console.log(`${manifest.length} tiles in ${((Date.now() - started) / 1000).toFixed(1)} s`);
} finally {
  await browser.close();
  server.close();
}
