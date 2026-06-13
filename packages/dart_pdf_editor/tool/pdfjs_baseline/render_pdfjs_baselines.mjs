#!/usr/bin/env node
import { readdir, readFile, writeFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  createCanvas,
  DOMMatrix,
  GlobalFonts,
  ImageData,
  Path2D,
} from '@napi-rs/canvas';

globalThis.DOMMatrix ??= DOMMatrix;
globalThis.ImageData ??= ImageData;
globalThis.Path2D ??= Path2D;

const pdfjsLib = await import('pdfjs-dist/legacy/build/pdf.mjs');

const passwords = new Map([
  ['issue6010_1.pdf', 'abc'],
  ['issue6010_2.pdf', 'æøå'],
  ['issue15893_reduced.pdf', 'test'],
  ['bug1782186.pdf', 'Hello'],
  ['issue3371.pdf', 'ELXRTQWS'],
  ['encrypted-attachment.pdf', '000000'],
]);

const skipped = new Set([
  'GHOSTSCRIPT-698804-1-fuzzed.pdf',
  'Pages-tree-refs.pdf',
  'REDHAT-1531897-0.pdf',
  'poppler-395-0-fuzzed.pdf',
  'poppler-742-0-fuzzed.pdf',
  'poppler-85140-0.pdf',
  'poppler-937-0-fuzzed.pdf',
  'print_protection.pdf',
]);

// Non-embedded CJK fonts must be substituted with a real system font, and the
// substitute must cover the document's language: a Chinese font has no Japanese
// kana, so Japanese text (e.g. あいうえお) would still render as .notdef boxes.
// Each language lists macOS faces first, then Linux Noto/arphic for CI. The
// Noto pan-CJK .ttc files cover every language, so they double as a fallback.
const cjkFontsByLang = {
  ja: {
    serif: [
      '/System/Library/Fonts/ヒラギノ明朝 ProN.ttc',
      '/System/Library/Fonts/Hiragino Mincho ProN.ttc',
      '/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc',
      '/usr/share/fonts/opentype/noto/NotoSerifCJKjp-Regular.otf',
    ],
    sans: [
      '/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc',
      '/System/Library/Fonts/Hiragino Sans GB.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJKjp-Regular.otf',
    ],
  },
  ko: {
    serif: [
      '/System/Library/Fonts/Supplemental/AppleMyungjo.ttf',
      '/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc',
      '/usr/share/fonts/opentype/noto/NotoSerifCJKkr-Regular.otf',
    ],
    sans: [
      '/System/Library/Fonts/Supplemental/AppleGothic.ttf',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJKkr-Regular.otf',
    ],
  },
  // Simplified and Traditional Chinese share the macOS Songti/STHeiti faces
  // (both cover GB and Big5); Noto splits sc/tc for CI.
  'zh-Hans': {
    serif: [
      '/System/Library/Fonts/Supplemental/Songti.ttc',
      '/System/Library/Fonts/Songti.ttc',
      '/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc',
      '/usr/share/fonts/opentype/noto/NotoSerifCJKsc-Regular.otf',
      '/usr/share/fonts/truetype/arphic/uming.ttc',
    ],
    sans: [
      '/System/Library/Fonts/STHeiti Medium.ttc',
      '/System/Library/Fonts/STHeiti Light.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJKsc-Regular.otf',
      '/usr/share/fonts/truetype/arphic/ukai.ttc',
    ],
  },
  'zh-Hant': {
    serif: [
      '/System/Library/Fonts/Supplemental/Songti.ttc',
      '/System/Library/Fonts/Songti.ttc',
      '/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc',
      '/usr/share/fonts/opentype/noto/NotoSerifCJKtc-Regular.otf',
      '/usr/share/fonts/truetype/arphic/uming.ttc',
    ],
    sans: [
      '/System/Library/Fonts/STHeiti Medium.ttc',
      '/System/Library/Fonts/STHeiti Light.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJKtc-Regular.otf',
      '/usr/share/fonts/truetype/arphic/ukai.ttc',
    ],
  },
};

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const packageDir = path.resolve(scriptDir, '../..');
const pdfjsDistDir = path.join(scriptDir, 'node_modules/pdfjs-dist');
const resourcePath = (name) => `${path.join(pdfjsDistDir, name)}${path.sep}`;

const args = parseArgs(process.argv.slice(2));
const corpusDir = path.resolve(
  process.cwd(),
  args.corpus ?? path.join(packageDir, '../../test_corpora/pdfjs'),
);
const outDir = path.resolve(
  process.cwd(),
  args.out ?? path.join(packageDir, '../../test_corpora/pdfjs/_baselines'),
);
const scale = positiveNumber(args.scale, 1);
const maxPages = positiveInteger(args['max-pages'], 5);
const only = args.only == null ? null : new RegExp(args.only);

if (!existsSync(corpusDir)) {
  throw new Error(`PDF.js corpus not found: ${corpusDir}`);
}
await mkdir(outDir, { recursive: true });

const files = (await readdir(corpusDir, { withFileTypes: true }))
  .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith('.pdf'))
  .map((entry) => entry.name)
  .filter((name) => !skipped.has(name))
  .filter((name) => only == null || only.test(name))
  .sort();

const selfPath = fileURLToPath(import.meta.url);

if (args.worker != null) {
  // Child mode: render exactly one file in a fresh process. pdf.js caches its
  // generic font substitution (the `serif`/`sans-serif` family) in
  // module-global state on first use and never re-resolves it, so within one
  // process the first CJK file to register a CJK face under those aliases
  // poisons every later non-embedded Latin serif/sans substitution into
  // .notdef boxes (see non-embedded-NuptialScript). GlobalFonts.remove() can't
  // undo it — the leak is inside pdf.js, not the canvas — so the only reliable
  // isolation is a clean process per file.
  const result = await renderOne(args.worker);
  if (!result.ok) {
    console.warn(`FAILED ${args.worker}: ${result.error}`);
    process.exitCode = 1;
  } else {
    const n = result.pages;
    console.log(`rendered ${args.worker} (${n} page${n === 1 ? '' : 's'})`);
  }
} else {
  // Parent mode: spawn one isolated child per file.
  let rendered = 0;
  const failures = [];
  for (const name of files) {
    const child = spawnSync(
      process.execPath,
      [
        '--expose-gc', selfPath,
        '--worker', name,
        '--corpus', corpusDir,
        '--out', outDir,
        '--scale', String(scale),
        '--max-pages', String(maxPages),
      ],
      { stdio: 'inherit' },
    );
    if (child.status === 0) rendered++;
    else failures.push(name);
  }
  console.log(`rendered ${rendered}/${files.length} files into ${outDir}`);
  if (failures.length > 0) {
    console.warn(`failed to render ${failures.length} file(s):`);
    for (const failure of failures) console.warn(`  ${failure}`);
    process.exitCode = 1;
  }
}

async function renderOne(name) {
  const fontKeys = [];
  try {
    const bytes = await readFile(path.join(corpusDir, name));
    const cjkLang = cjkLanguage(bytes);
    if (cjkLang) {
      const keys = registerCjkFallbacks(cjkLang);
      if (keys.length === 0) {
        console.warn(
          `Warning: no local ${cjkLang} CJK fonts found; ${name} may render missing glyph boxes.`,
        );
      } else {
        fontKeys.push(...keys);
      }
    }
    const loadingTask = pdfjsLib.getDocument({
      data: new Uint8Array(bytes),
      password: passwords.get(name) ?? '',
      useSystemFonts: true,
      // In Node, @napi-rs/canvas does not load PDF.js-created FontFace
      // instances like a browser does. Force PDF.js to draw embedded glyph
      // outlines itself so CID subset fonts and CIDToGIDMap entries are used.
      disableFontFace: true,
      cMapUrl: resourcePath('cmaps'),
      cMapPacked: true,
      iccUrl: resourcePath('iccs'),
      standardFontDataUrl: resourcePath('standard_fonts'),
      wasmUrl: resourcePath('wasm'),
    });
    const pdf = await loadingTask.promise;
    const pages = Math.min(pdf.numPages, maxPages);
    for (let pageIndex = 0; pageIndex < pages; pageIndex++) {
      const page = await pdf.getPage(pageIndex + 1);
      const viewport = page.getViewport({ scale });
      const canvas = createCanvas(
        Math.ceil(viewport.width),
        Math.ceil(viewport.height),
      );
      const canvasContext = canvas.getContext('2d');
      canvasContext.fillStyle = 'white';
      canvasContext.fillRect(0, 0, canvas.width, canvas.height);
      await page.render({ canvasContext, viewport }).promise;
      const outName = `${safeName(name)}.p${pageIndex}.png`;
      await writeFile(path.join(outDir, outName), canvas.toBuffer('image/png'));
      // Release PDF.js's retained render/image state for this page now,
      // rather than holding every page's intent state until pdf.cleanup().
      page.cleanup();
      // Drop our references to the native-backed canvas so it can be
      // finalized; @napi-rs/canvas surfaces live in native memory that V8's
      // GC does not see, so nothing pressures it to collect on its own.
      canvas.width = 0;
      canvas.height = 0;
    }
    await pdf.cleanup();
    await loadingTask.destroy();
    return { ok: true, pages };
  } catch (error) {
    return { ok: false, error: error?.message ?? String(error) };
  } finally {
    for (const key of fontKeys) {
      GlobalFonts.remove(key);
    }
    // V8 sizes its GC heuristics off the (tiny) JS heap and never sees the
    // megabytes of native Skia/canvas + decoded-image memory each file
    // leaves behind, so without a nudge RSS climbs into tens of GB. The child
    // renders one file, but multi-page files still benefit; degrade gracefully
    // when --expose-gc is absent.
    globalThis.gc?.();
  }
}

function parseArgs(values) {
  const result = {};
  for (let i = 0; i < values.length; i++) {
    const value = values[i];
    if (!value.startsWith('--')) {
      throw new Error(`unexpected argument: ${value}`);
    }
    const eq = value.indexOf('=');
    if (eq === -1) {
      result[value.slice(2)] = values[++i];
    } else {
      result[value.slice(2, eq)] = value.slice(eq + 1);
    }
  }
  return result;
}

function positiveInteger(value, fallback) {
  const parsed = Number.parseInt(value ?? '', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function positiveNumber(value, fallback) {
  const parsed = Number.parseFloat(value ?? '');
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

// Returns the CJK language whose system font should substitute for this file's
// non-embedded fonts, or null when none is needed. Detected from CIDSystemInfo
// /Ordering and predefined CJK CMap /Encoding names; a hex-encoded BaseFont/
// FontName (simple non-CID fonts, the legacy heuristic) is treated as
// Simplified Chinese, which is what those corpus files are.
function cjkLanguage(bytes) {
  const text = Buffer.from(bytes).toString('latin1');
  if (
    /\/Ordering\s*\(\s*Japan1\s*\)/.test(text) ||
    /\/Encoding\s*\/(?:90ms|90msp|90pv|78|78ms|83pv|Add|Ext|Hankaku|Hiragana|Katakana|Roman|WP|EUC|RKSJ|UniJIS)[A-Za-z0-9-]*/.test(
      text,
    )
  ) {
    return 'ja';
  }
  if (
    /\/Ordering\s*\(\s*Korea1\s*\)/.test(text) ||
    /\/Encoding\s*\/(?:KSC|KSCms|KSCpc|UniKS)[A-Za-z0-9-]*/.test(text)
  ) {
    return 'ko';
  }
  if (
    /\/Ordering\s*\(\s*CNS1\s*\)/.test(text) ||
    /\/Encoding\s*\/(?:B5|B5pc|ETen|ETenms|CNS|HKscs|UniCNS)[A-Za-z0-9-]*/.test(
      text,
    )
  ) {
    return 'zh-Hant';
  }
  if (
    /\/Ordering\s*\(\s*GB1\s*\)/.test(text) ||
    /\/Encoding\s*\/(?:GB|GBK|GBpc|GBT|GBKp|GBK2K|UniGB)[A-Za-z0-9-]*/.test(text)
  ) {
    return 'zh-Hans';
  }
  if (
    /\/BaseFont \/(?:#[0-9A-Fa-f]{2}){2,}(?:[_-]GB2312)?/.test(text) ||
    /\/FontName <(?:[0-9A-Fa-f]{4}){2,}>/.test(text)
  ) {
    return 'zh-Hans';
  }
  return null;
}

function registerCjkFallbacks(lang) {
  const set = cjkFontsByLang[lang] ?? cjkFontsByLang['zh-Hans'];
  return [
    registerFirstAvailableFont(set.serif, 'serif'),
    registerFirstAvailableFont(set.sans, 'sans-serif'),
  ].filter((key) => key != null);
}

function registerFirstAvailableFont(fontPaths, alias) {
  for (const fontPath of fontPaths) {
    if (!existsSync(fontPath)) continue;
    const key = GlobalFonts.registerFromPath(fontPath, alias);
    if (key != null) return key;
  }
  return null;
}

function safeName(name) {
  return name.replaceAll(/[^A-Za-z0-9._-]+/g, '_');
}
