#!/usr/bin/env node
// Build the benchmark manifest from a corpus directory. Picks up to <count>
// PDFs (sorted, skipping obviously-broken fuzz fixtures) so the in-page harness
// has a deterministic, reproducible list to fetch and render.
//
//   node gen_manifest.cjs --corpus ../../test_corpora/pdfjs --count 20 \
//     --scale 2 --maxPages 5 --repeat 3 --out manifest.json
const fs = require('fs');
const path = require('path');

function arg(name, def) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : def;
}

const corpus = path.resolve(arg('corpus', '../../test_corpora/pdfjs'));
const count = parseInt(arg('count', '20'), 10);
const scale = parseFloat(arg('scale', '2'));
const maxPages = parseInt(arg('maxPages', '5'), 10);
const repeat = parseInt(arg('repeat', '3'), 10);
const out = path.resolve(arg('out', 'manifest.json'));

// Skip fuzzed/intentionally-corrupt fixtures: they exercise the parser's error
// paths, not the renderer, and add noise to a renderer-vs-renderer comparison.
const SKIP = /fuzz|ghostscript|pdfbox|bug\d|issue\d|corrupt|reduced|malform/i;

const files = fs
  .readdirSync(corpus)
  .filter((f) => f.toLowerCase().endsWith('.pdf'))
  .filter((f) => !SKIP.test(f))
  .sort()
  .slice(0, count);

if (files.length === 0) {
  console.error(`no PDFs selected from ${corpus}`);
  process.exit(1);
}

fs.writeFileSync(
  out,
  JSON.stringify({ scale, maxPages, repeat, warmup: true, files }, null, 2));
console.log(`manifest: ${files.length} files -> ${out}`);
files.forEach((f) => console.log('  ' + f));
