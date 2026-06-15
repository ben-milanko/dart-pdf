// Summarises results.ndjson: one line per run plus an aggregate, so a loop of
// driver.mjs runs shows trend + variance and flags any regression.
//   node report.mjs            # all runs
//   node report.mjs 20         # last 20 runs
import { readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const FILE = process.env.PERF_RESULTS ?? join(HERE, 'results.ndjson');
const last = Number(process.argv[2] ?? 0);

const text = await readFile(FILE, 'utf8').catch(() => '');
let runs = text.split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
if (last > 0) runs = runs.slice(-last);
if (!runs.length) { console.log('no runs in', FILE); process.exit(0); }

const num = (v) => (typeof v === 'number' ? v : 0);
const agg = (xs) => {
  const s = xs.filter((x) => typeof x === 'number').sort((a, b) => a - b);
  if (!s.length) return { min: 0, med: 0, max: 0 };
  return { min: s[0], med: s[Math.floor(s.length / 2)], max: s[s.length - 1] };
};

console.log(`\n${runs.length} run(s) from ${FILE}\n`);
const hdr = ['#', 'when', 'secs', 'pages', 'wkr', 'plain', 'p95', 'bMax', '>16', '>50', 'warmMax', 'verdict'];
console.log(hdr.map((h, i) => h.padEnd([3, 20, 6, 6, 5, 6, 7, 7, 5, 5, 8, 12][i])).join(' '));
runs.forEach((r, i) => {
  const f = r.frames ?? {};
  const verdict = r.fatal || r.harnessError || (r.errorLines?.length) || (r.pageErrors?.length)
    ? 'FAIL' : (r.regressed ? 'PASS(ui-interp)' : 'PASS');
  const cells = [
    String(i + 1),
    (r.ts ?? '').replace('T', ' ').slice(5, 19),
    String(num(r.elapsedS)),
    String(num(r.pages)),
    String(r.interpret?.worker ?? 0),
    String(r.interpret?.plain ?? 0),
    num(f.buildP95).toFixed(1),
    num(f.buildMax).toFixed(0),
    String(num(f.buildOver16)),
    String(num(f.buildOver50)),
    num(r.workerWarmMax).toFixed(0),
    verdict,
  ];
  console.log(cells.map((c, j) => c.padEnd([3, 20, 6, 6, 5, 6, 7, 7, 5, 5, 8, 12][j])).join(' '));
});

const fails = runs.filter((r) => r.fatal || r.harnessError || r.errorLines?.length || r.pageErrors?.length);
const regr = runs.filter((r) => r.regressed);
const p95 = agg(runs.map((r) => r.frames?.buildP95));
const bmax = agg(runs.map((r) => r.frames?.buildMax));
const warm = agg(runs.map((r) => r.workerWarmMax));
const over50 = agg(runs.map((r) => r.frames?.buildOver50));

console.log('\n──────── aggregate ────────');
console.log(`  runs            ${runs.length}   FAIL=${fails.length}   regressed(ui-interp)=${regr.length}`);
console.log(`  build p95 ms    min=${p95.min.toFixed(1)} med=${p95.med.toFixed(1)} max=${p95.max.toFixed(1)}`);
console.log(`  build max ms    min=${bmax.min.toFixed(0)} med=${bmax.med.toFixed(0)} max=${bmax.max.toFixed(0)}`);
console.log(`  frames >50ms    min=${over50.min} med=${over50.med} max=${over50.max}`);
console.log(`  worker warmMax  min=${warm.min.toFixed(0)} med=${warm.med.toFixed(0)} max=${warm.max.toFixed(0)} ms`);
if (fails.length) {
  console.log('\n  ⚠ failing runs:');
  for (const r of fails) console.log(`     ${r.ts}  ${r.fatal ?? r.harnessError ?? (r.errorLines?.[0]) ?? r.pageErrors?.[0]}`);
}
console.log('───────────────────────────\n');
