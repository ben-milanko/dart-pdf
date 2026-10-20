// Hosts the app's browser OCR bridge (the __dartPdfOcrLoad/__dartPdfOcrRun
// script lifted verbatim from app/web/index.html) in headless Chromium and
// exposes it over localhost HTTP, so the Dart PP-OCR accuracy benchmark
// (packages/pdf_ocr_ondevice/test/accuracy, PDF_OCR_WEB_BRIDGE=<url>) can run
// its pipeline against onnxruntime-web exactly as the web app does.
//
//   node ocr_web_bridge.mjs <web root>       # holds ocr/pp-ocrv5-mobile/*
//
// Prints `bridge listening on <url>` and serves until killed:
//   POST /api/load            -> the recognizer dictionary (text)
//   POST /api/run/<det|rec>?dims=1,3,H,W  body: float32 LE tensor
//                             -> float32 LE output, `x-dims` header
// The page is served cross-origin isolated (COOP same-origin + COEP
// credentialless, like firebase.json), so onnxruntime-web runs threaded.
//
// Env: CHROME (browser binary; default the Playwright Chromium), PORT (default
// ephemeral), OCR_BRIDGE_VERBOSE=1 (log every request with its time), OCR_WEBGPU=1 (expose WebGPU; off by default since headless
// Chromium's software adapter is not representative), OCR_PROFILE_DIR
// (persistent profile), OCR_FETCH_VIA_NODE=1 (fetch the page's https requests
// from Node - for sandboxes whose TLS-intercepting proxy CA Node trusts via
// NODE_EXTRA_CA_CERTS + NODE_USE_ENV_PROXY=1 but Chromium does not; each is
// 307'd to this server, which streams it through a disk cache,
// OCR_FETCH_CACHE, default <web root>/../fetch_cache).
import { createHash } from 'node:crypto';
import {
  createReadStream, createWriteStream, existsSync, mkdirSync, readFileSync,
  renameSync, statSync, writeFileSync,
} from 'node:fs';
import { createServer } from 'node:http';
import { dirname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';

const here = dirname(fileURLToPath(import.meta.url));
const root = process.argv[2];
if (!root) throw new Error('usage: node ocr_web_bridge.mjs <web root>');
const CHROME = process.env.CHROME ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome';
const cacheDir = process.env.OCR_FETCH_CACHE ?? join(root, '..', 'fetch_cache');

// The bridge is the inline <script> in index.html that defines it.
const indexHtml = readFileSync(join(here, '../../web/index.html'), 'utf8');
const bridge = [...indexHtml.matchAll(/<script>([\s\S]*?)<\/script>/g)]
  .map((m) => m[1])
  .find((s) => s.includes('__dartPdfOcrRun'));
if (!bridge) throw new Error('no __dartPdfOcrRun bridge in web/index.html');

const isolation = {
  'cross-origin-opener-policy': 'same-origin',
  'cross-origin-embedder-policy': 'credentialless',
};

// Tensors in flight between the Dart client and the page, by id.
const inputs = new Map();
const outputs = new Map();
let nextId = 0;
let page = null;

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
  }
  const { type } = JSON.parse(readFileSync(meta, 'utf8'));
  res.writeHead(200, {
    'content-type': type ?? 'application/octet-stream',
    'content-length': statSync(body).size,
    'access-control-allow-origin': '*',
    'cross-origin-resource-policy': 'cross-origin',
  });
  createReadStream(body).pipe(res);
}

async function readBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  return Buffer.concat(chunks);
}

const verbose = process.env.OCR_BRIDGE_VERBOSE === '1';

async function handle(req, res) {
  const u = new URL(req.url, 'http://127.0.0.1');
  if (verbose && !u.pathname.startsWith('/fetch')) {
    const t0 = Date.now();
    res.on('finish', () => console.log(
      `${req.method} ${u.pathname}${u.search} ${res.statusCode} ${Date.now() - t0} ms`));
  }
  if (u.pathname === '/fetch') return relay(u.searchParams.get('u'), res);
  if (u.pathname === '/') {
    res.writeHead(200, { 'content-type': 'text/html', ...isolation });
    return res.end(`<!doctype html><meta charset="utf-8"><script>${bridge}</script>`);
  }
  if (u.pathname.startsWith('/ocr/')) {
    const file = normalize(join(root, u.pathname));
    if (!file.startsWith(normalize(root)) || !existsSync(file)) {
      res.writeHead(404);
      return res.end();
    }
    res.writeHead(200, { 'content-length': statSync(file).size, ...isolation });
    return createReadStream(file).pipe(res);
  }
  // The page pulls its input and pushes its output here.
  let m = u.pathname.match(/^\/tensor\/(\d+)$/);
  if (m) {
    const buf = inputs.get(Number(m[1]));
    inputs.delete(Number(m[1]));
    res.writeHead(200, { 'content-type': 'application/octet-stream' });
    return res.end(buf);
  }
  m = u.pathname.match(/^\/result\/(\d+)$/);
  if (m) {
    outputs.set(Number(m[1]), await readBody(req));
    res.writeHead(204);
    return res.end();
  }
  // The Dart client's API.
  if (u.pathname === '/api/load') {
    const dictionary = await page.evaluate(() => window.__dartPdfOcrLoad());
    res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
    return res.end(dictionary);
  }
  m = u.pathname.match(/^\/api\/run\/(det|rec)$/);
  if (m) {
    const dims = u.searchParams.get('dims').split(',').map(Number);
    const id = nextId++;
    inputs.set(id, await readBody(req));
    const outDims = await page.evaluate(async (name, id, dims) => {
      const input = await (await fetch(`/tensor/${id}`)).arrayBuffer();
      const r = await window.__dartPdfOcrRun(name, new Float32Array(input), dims);
      await fetch(`/result/${id}`, { method: 'POST', body: r.data });
      return r.dims;
    }, m[1], id, dims);
    const out = outputs.get(id);
    outputs.delete(id);
    res.writeHead(200, {
      'content-type': 'application/octet-stream',
      'x-dims': outDims.join(','),
    });
    return res.end(out);
  }
  res.writeHead(404);
  res.end();
}

const server = createServer((req, res) => {
  handle(req, res).catch((e) => {
    console.log(`error ${req.url}: ${e.stack ?? e}`);
    if (!res.headersSent) res.writeHead(500);
    res.end(String(e));
  });
}).listen(Number(process.env.PORT ?? 0), '127.0.0.1');
await new Promise((r) => server.once('listening', r));
const url = `http://127.0.0.1:${server.address().port}/`;

const browser = await puppeteer.launch({
  executablePath: CHROME,
  headless: true,
  userDataDir: process.env.OCR_PROFILE_DIR,
  args: ['--no-sandbox', '--disable-dev-shm-usage',
    ...(process.env.OCR_WEBGPU === '1' ? ['--enable-unsafe-webgpu'] : [])],
  protocolTimeout: 0,
});
page = await browser.newPage();
if (process.env.OCR_WEBGPU !== '1') {
  // Headless Chromium still defines navigator.gpu with no adapter behind it;
  // hide it so the bridge takes its WASM path deterministically.
  await page.evaluateOnNewDocument(() => {
    Object.defineProperty(Navigator.prototype, 'gpu', { get: () => undefined });
  });
}
if (process.env.OCR_FETCH_VIA_NODE === '1') {
  // Pause only https:// requests (the CDN fetches), through the DevTools Fetch
  // domain. puppeteer's setRequestInterception pauses *every* request, and an
  // intercepted multi-MB POST (the tensors this server trades with the page)
  // can stall indefinitely.
  const cdp = await page.createCDPSession();
  await cdp.send('Fetch.enable', { patterns: [{ urlPattern: 'https://*' }] });
  cdp.on('Fetch.requestPaused', ({ requestId, request }) => {
    cdp.send('Fetch.fulfillRequest', {
      requestId,
      responseCode: 307,
      responseHeaders: [
        { name: 'location', value: `${url}fetch?u=${encodeURIComponent(request.url)}` },
        { name: 'access-control-allow-origin', value: '*' },
      ],
    }).catch((e) => console.log(`relay ${request.url}: ${e.message}`));
  });
}
page.on('console', (m) => console.log(`[page] ${m.text()}`));
page.on('pageerror', (e) => console.log(`[page error] ${e.message}`));
page.on('error', (e) => console.log(`[page crashed] ${e.message}`));
await page.goto(url);
console.log(`isolated: ${await page.evaluate(() => self.crossOriginIsolated)}`);
console.log(`bridge listening on ${url}`);

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, async () => {
    await browser.close();
    server.close();
    process.exit(0);
  });
}
