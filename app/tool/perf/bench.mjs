// One-command web A/B: build a baseline git ref and the working tree, run the
// same scenario against both in real headless Chrome, and print a per-metric
// delta table. The web counterpart of `tool/perf.sh diff` (which is VM-only) -
// the thing the VM diff's header said "stays manual, not worth automating yet."
//
//   node bench.mjs --scenario <name> [--baseline <ref>] [--iterations N]
//                  [--threshold R] [--keep] [--no-build-current]
//
// Defaults: scenario scroll-plan, baseline main, iterations 3, threshold 1.10.
//
// How it stays honest:
//   * Both sides run the SAME harness + driver + scenario + PDF bytes; only the
//     compiled library in the web bundle differs. The baseline ref is checked
//     out into a cached git worktree and the CURRENT tool/perf/* is copied in
//     before building, so an old ref measures its own lib code with today's
//     harness (same bootstrap trick as tool/perf/perf_diff.sh).
//   * Runs interleave ABAB so thermal/background drift cancels instead of
//     biasing one side.
//   * Per metric we compare the MEDIAN across iterations; regressions over the
//     threshold (lower-is-better metrics only) are flagged and set the exit
//     code so CI can gate on them.
import { execFileSync, execSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, mkdirSync, rmSync, cpSync } from 'node:fs';
import { join, dirname, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = normalize(join(HERE, '..', '..', '..'));
const APP_DIR = join(REPO_ROOT, 'app');

// ---- args ----
const argv = process.argv.slice(2);
function opt(name, def) {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : def;
}
const has = (name) => argv.includes(name);
const SCENARIO = opt('--scenario', 'scroll-plan');
const BASELINE = opt('--baseline', 'main');
const ITER = Number(opt('--iterations', '3'));
const THRESHOLD = Number(opt('--threshold', '1.10'));
const KEEP = has('--keep');
const BUILD_CURRENT = !has('--no-build-current');

// Structural/equality metrics: a change is informational, not a regression
// (they should stay ~constant across revisions). `frames` (total captured) is
// timing-dependent noise, so it's here too - but jankCount is a real quality
// metric and IS gated, not informational.
const INFORMATIONAL = new Set([
  'searchMatches', 'pagesVisited', 'editRevisions', 'frames',
]);

const reg = JSON.parse(readFileSync(join(HERE, 'scenarios.json'), 'utf8'));
const scenarioName = SCENARIO === 'default' ? reg.default : SCENARIO;
if (!reg.scenarios[scenarioName]) {
  console.error(`✗ unknown scenario "${scenarioName}". known: ${Object.keys(reg.scenarios).join(', ')}`);
  process.exit(2);
}
// Pin the served PDF to the CURRENT tree's file so both sides render identical
// bytes even if the corpus drifted between revisions.
const PDF = join(REPO_ROOT, reg.scenarios[scenarioName].pdf);

// execFileSync (no shell) so a ref name can't inject - BASELINE is external.
const git = (args, cwd = REPO_ROOT) =>
  execFileSync('git', args, { cwd, encoding: 'utf8' }).trim();

function build(treeRoot) {
  console.log(`\n▶ building web bundle in ${treeRoot}`);
  execFileSync('bash', [join(treeRoot, 'app', 'tool', 'perf', 'build.sh')], {
    cwd: join(treeRoot, 'app'),
    stdio: 'inherit',
  });
}

// Run the CURRENT driver against a prebuilt bundle, capturing its envelope.
function runDriver(webDir, resultsFile) {
  const env = {
    ...process.env,
    PERF_WEB_DIR: webDir,
    PERF_RESULTS: resultsFile,
    PERF_PDF: PDF,
  };
  try {
    execFileSync('node', [join(HERE, 'driver.mjs'), '--scenario', scenarioName], {
      env, stdio: 'inherit',
    });
  } catch {
    // driver exits non-zero on a FAIL verdict; the envelope is still appended.
  }
}

function readRuns(file) {
  if (!existsSync(file)) return [];
  return readFileSync(file, 'utf8').split('\n').filter(Boolean)
    .map((l) => { try { return JSON.parse(l); } catch { return null; } })
    .filter(Boolean)
    // A fatal/errored run carries no usable numbers - comparing it would skew
    // (or empty) the medians while the verdict still read "no regression".
    .filter((r) => !r.fatal && !r.harnessError && r.ok !== false);
}

const median = (xs) => {
  const s = xs.filter((x) => typeof x === 'number' && isFinite(x)).sort((a, b) => a - b);
  return s.length ? s[Math.floor((s.length - 1) / 2)] : null;
};

function medianMetrics(runs) {
  const keys = new Set();
  for (const r of runs) for (const k of Object.keys(r.metrics ?? {})) keys.add(k);
  const out = {};
  for (const k of keys) out[k] = median(runs.map((r) => r.metrics?.[k]));
  return out;
}

function main() {
  if (!existsSync(PDF)) { console.error(`✗ PDF not found: ${PDF}`); process.exit(2); }

  const sha = git(['rev-parse', '--short', BASELINE]);
  console.log(`\n══ web A/B: ${BASELINE} (${sha}) → working tree`);
  console.log(`   scenario ${scenarioName}  iterations ${ITER}  threshold ${THRESHOLD}×`);

  // ---- current tree ----
  if (BUILD_CURRENT) build(REPO_ROOT);
  else console.log('▶ skipping current build (--no-build-current); using app/build/web as-is');
  const curWeb = join(APP_DIR, 'build', 'web');

  // ---- baseline worktree (cached per sha, like perf_diff.sh) ----
  const wt = join(tmpdir(), 'dart-pdf-webperf-ab', sha);
  if (!existsSync(wt)) {
    console.log(`\n▶ creating worktree for ${BASELINE} (${sha}) at ${wt}`);
    mkdirSync(dirname(wt), { recursive: true });
    git(['worktree', 'add', '--detach', wt, BASELINE]);
    const dart = existsSync(join(REPO_ROOT, '.fvmrc')) ? 'fvm dart' : 'dart';
    execSync(`${dart} pub get`, { cwd: wt, stdio: 'inherit' });
  } else {
    console.log(`\n▶ reusing cached worktree ${wt}`);
  }
  // Bootstrap: copy today's harness tooling into the ref so it measures its own
  // lib with the current harness/scenario (additive, overwrites tool/perf).
  // Skip node_modules (big, unneeded for the build) and stray history files.
  cpSync(join(HERE), join(wt, 'app', 'tool', 'perf'), {
    recursive: true,
    filter: (src) => !/[/\\]node_modules([/\\]|$)|results.*\.ndjson$/.test(src),
  });
  build(wt);
  const refWeb = join(wt, 'app', 'build', 'web');

  // ---- interleaved runs ----
  const out = join(tmpdir(), 'dart-pdf-webperf-ab', `runs-${sha}-${process.pid}`);
  mkdirSync(out, { recursive: true });
  const curFile = join(out, 'current.ndjson');
  const refFile = join(out, 'ref.ndjson');
  writeFileSync(curFile, ''); writeFileSync(refFile, '');
  for (let i = 1; i <= ITER; i++) {
    console.log(`\n── iteration ${i}/${ITER}: working tree`);
    runDriver(curWeb, curFile);
    console.log(`── iteration ${i}/${ITER}: ${BASELINE}`);
    runDriver(refWeb, refFile);
  }

  // ---- compare ----
  const curRuns = readRuns(curFile);
  const refRuns = readRuns(refFile);
  if (!curRuns.length || !refRuns.length) {
    console.error(`\n✗ no successful runs on ${!refRuns.length ? BASELINE : 'the working tree'} `
      + `(${refRuns.length} ref / ${curRuns.length} current of ${ITER} each) - cannot compare`);
    if (!KEEP) rmSync(out, { recursive: true, force: true });
    process.exit(2);
  }
  const cur = medianMetrics(curRuns);
  const ref = medianMetrics(refRuns);
  const keys = [...new Set([...Object.keys(ref), ...Object.keys(cur)])].sort();

  console.log(`\n══ ${scenarioName}: ${BASELINE} (${sha}) → working tree, ${ITER} interleaved runs\n`);
  const pad = (s, n) => String(s).padEnd(n);
  console.log(pad('metric', 24) + pad('baseline', 12) + pad('current', 12) + pad('Δ', 10) + 'verdict');
  console.log('─'.repeat(72));
  let regressions = 0;
  const num = (v) => (v == null ? '—' : (Math.abs(v) >= 100 ? v.toFixed(0) : v.toFixed(2)));
  for (const k of keys) {
    const b = ref[k], c = cur[k];
    let delta = '—', verdict = '';
    if (typeof b === 'number' && typeof c === 'number' && b !== 0) {
      const ratio = c / b;
      const pct = (ratio - 1) * 100;
      delta = `${pct >= 0 ? '+' : ''}${pct.toFixed(1)}%`;
      if (INFORMATIONAL.has(k)) {
        verdict = c === b ? '≈' : 'ℹ';
      } else if (ratio >= THRESHOLD) {
        verdict = '✗ REGRESSION'; regressions++;
      } else if (ratio <= 1 / THRESHOLD) {
        verdict = '✓ faster';
      } else {
        verdict = '·';
      }
    }
    console.log(pad(k, 24) + pad(num(b), 12) + pad(num(c), 12) + pad(delta, 10) + verdict);
  }
  console.log('─'.repeat(72));
  console.log(regressions ? `\n✗ ${regressions} metric(s) regressed past ${THRESHOLD}×\n`
    : `\n✓ no metric regressed past ${THRESHOLD}×\n`);

  if (!KEEP) rmSync(out, { recursive: true, force: true });
  else console.log(`(kept run data in ${out}; worktree ${wt})`);
  process.exit(regressions ? 1 : 0);
}

main();
