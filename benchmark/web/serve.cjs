#!/usr/bin/env node
// Static file server for the web render benchmark.
//
// Serves a `flutter build web` output directory at `/`, the benchmark manifest
// at `/bench/manifest.json`, and the corpus PDFs at `/bench/pdfs/<name>`.
//
// Every response carries cross-origin-isolation headers (COOP/COEP) because the
// multithreaded Wasm/skwasm renderer needs SharedArrayBuffer. The headers are
// harmless for the CanvasKit build, so both builds are served identically for a
// fair comparison.
//
//   node serve.cjs --root build/web --corpus ../corpus --manifest manifest.json --port 8099
const http = require('http');
const fs = require('fs');
const path = require('path');

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : def;
}

const root = path.resolve(arg('root', 'build/web'));
const corpus = path.resolve(arg('corpus', '../corpus'));
const manifestPath = path.resolve(arg('manifest', 'manifest.json'));
const port = parseInt(arg('port', '8099'), 10);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.pdf': 'application/pdf',
  '.map': 'application/json; charset=utf-8',
  '.symbols': 'text/plain; charset=utf-8',
};

function setIsolation(res) {
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
  res.setHeader('Cache-Control', 'no-store');
}

function send(res, status, body, type) {
  setIsolation(res);
  if (type) res.setHeader('Content-Type', type);
  res.statusCode = status;
  res.end(body);
}

function sendFile(res, file) {
  fs.readFile(file, (err, data) => {
    if (err) return send(res, 404, 'not found: ' + file, 'text/plain');
    send(res, 200, data, MIME[path.extname(file).toLowerCase()] ||
        'application/octet-stream');
  });
}

// Block path traversal, then resolve a request path inside a base dir.
function safeJoin(base, rel) {
  const p = path.normalize(path.join(base, rel));
  return p.startsWith(base) ? p : null;
}

const server = http.createServer((req, res) => {
  let urlPath = decodeURIComponent((req.url || '/').split('?')[0]);

  if (urlPath === '/bench/manifest.json') return sendFile(res, manifestPath);

  if (urlPath.startsWith('/bench/pdfs/')) {
    const file = safeJoin(corpus, urlPath.slice('/bench/pdfs/'.length));
    if (!file) return send(res, 403, 'forbidden', 'text/plain');
    return sendFile(res, file);
  }

  if (urlPath === '/') urlPath = '/index.html';
  const file = safeJoin(root, urlPath.slice(1));
  if (!file) return send(res, 403, 'forbidden', 'text/plain');
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) return sendFile(res, path.join(root, 'index.html'));
    sendFile(res, file);
  });
});

server.listen(port, () => {
  console.log(`serving ${root} on http://localhost:${port}`);
  console.log(`  corpus:   ${corpus}`);
  console.log(`  manifest: ${manifestPath}`);
});
