#!/usr/bin/env node
// Builds the static perf trend dashboard from envelope history
// (tool/perf/SCHEMA.md): one self-contained index.html, inline SVG line
// charts per scenario x metric, latest-run table with targets.json
// PASS/MISS, per-point native tooltips carrying date + commit. Zero deps.
//
//   node tool/perf/report/build_report.mjs --history <dir> \
//     [--targets tool/perf/targets.json] [--out <file>] [--limit N]
//
// Colors/spec follow the repo's dataviz conventions: single-series charts
// (no legend needed), series color = categorical slot 1, text in ink
// tokens, recessive grid, both light and dark surfaces styled.
import { readFileSync, readdirSync, writeFileSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';

const args = process.argv.slice(2);
function flag(name, fallback) {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : fallback;
}
const historyDir = flag('--history', 'tool/perf/history');
const targetsPath = flag('--targets', 'tool/perf/targets.json');
const outPath = flag('--out', join(historyDir, 'index.html'));
const limit = Number(flag('--limit', '120'));

// Curated metric order; anything else numeric in `metrics` charts after these.
const preferred = [
  'p50OpenMs', 'p95OpenMs', 'p50FirstPageMs',
  'p50InterpretMsPerPage', 'p95InterpretMsPerPage',
  'p50ExtractMsPerPage', 'p50SaveMs', 'p95SaveMs',
  'maxPeakRssBytes', 'errors',
  'jankCount', 'buildP50', 'buildP95', 'buildOver50',
];

const targets = existsSync(targetsPath)
  ? JSON.parse(readFileSync(targetsPath, 'utf8'))
  : {};

// ---- Load history ----------------------------------------------------------
const runs = [];
if (existsSync(historyDir)) {
  for (const f of readdirSync(historyDir)) {
    if (!f.endsWith('.ndjson')) continue;
    for (const line of readFileSync(join(historyDir, f), 'utf8').split('\n')) {
      if (!line.trim()) continue;
      try { runs.push(JSON.parse(line)); } catch { /* skip corrupt line */ }
    }
  }
}
// Order the trend by COMMIT date (rev.date), not the day the sweep ran, so
// backfilled historical points land at their real position instead of stacking
// on the backfill job's run date. Fall back to the run timestamp for any point
// without a captured rev.
const whenOf = (r) => String(r.rev?.date ?? r.ts ?? '');
runs.sort((a, b) => whenOf(a).localeCompare(whenOf(b)));

const groups = new Map(); // "suite / scenario" -> runs
for (const r of runs) {
  const key = `${r.suite ?? r.tool ?? 'unknown'}${r.scenario ? ` · ${r.scenario}` : ''}`;
  if (!groups.has(key)) groups.set(key, []);
  groups.get(key).push(r);
}

// ---- Chart builder ---------------------------------------------------------
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;')
  .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const fmt = (v) => v >= 1e9 ? `${(v / 1e9).toFixed(2)}G`
  : v >= 1e6 ? `${(v / 1e6).toFixed(1)}M`
  : v >= 1000 ? `${(v / 1000).toFixed(1)}k`
  : Number.isInteger(v) ? String(v) : v.toFixed(2);

function chart(metric, series, budget) {
  const W = 320, H = 120, PL = 44, PR = 10, PT = 12, PB = 20;
  const values = series.map((p) => p.v);
  const hi = Math.max(...values, budget ?? -Infinity);
  const top = hi === 0 ? 1 : hi * 1.08;
  const x = (i) => series.length === 1
    ? (PL + (W - PL - PR) / 2)
    : PL + (i / (series.length - 1)) * (W - PL - PR);
  const y = (v) => PT + (1 - v / top) * (H - PT - PB);
  const pts = series.map((p, i) => `${x(i).toFixed(1)},${y(p.v).toFixed(1)}`);
  const last = series[series.length - 1];
  const miss = budget != null && last.v > budget;

  const gridLines = [0.5, 1].map((f) => {
    const v = top * f * 0.925;
    return `<line class="grid" x1="${PL}" y1="${y(v)}" x2="${W - PR}" y2="${y(v)}"/>
      <text class="axis" x="${PL - 4}" y="${y(v) + 3}" text-anchor="end">${fmt(v)}</text>`;
  }).join('');

  const budgetLine = budget == null ? '' :
    `<line class="budget" x1="${PL}" y1="${y(Math.min(budget, top))}" x2="${W - PR}" y2="${y(Math.min(budget, top))}"/>`;

  const hover = series.map((p, i) =>
    `<circle class="hit" cx="${x(i)}" cy="${y(p.v)}" r="8"><title>${esc(p.label)}</title></circle>`
  ).join('');

  return `<figure class="chart${miss ? ' miss' : ''}">
  <figcaption>${esc(metric)}
    <span class="last">${fmt(last.v)}${budget != null
      ? ` <span class="verdict">${miss ? '✕ over' : '✓ within'} ${fmt(budget)}</span>` : ''}</span>
  </figcaption>
  <svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(metric)} trend">
    ${gridLines}${budgetLine}
    <polyline class="line" points="${pts.join(' ')}"/>
    <circle class="dot" cx="${x(series.length - 1)}" cy="${y(last.v)}" r="3.5"/>
    ${hover}
    <text class="axis" x="${PL}" y="${H - 6}">${esc(series[0].date)}</text>
    <text class="axis" x="${W - PR}" y="${H - 6}" text-anchor="end">${esc(last.date)}</text>
  </svg>
</figure>`;
}

// ---- Headline tiles ---------------------------------------------------------
// Hero numbers from the latest envelope of each key group, with a delta vs
// the run before it (lower is better for every timing metric shown here).
function groupRuns(matcher) {
  const out = runs.filter(matcher).filter((r) => r.metrics);
  return out.length ? out : null;
}
function tile(label, note, value, unit, prev, { betterLow = true, digits = 2 } = {}) {
  if (value == null) return null;
  let delta = '';
  let cls = 'flat';
  if (prev != null && prev > 0) {
    const pct = ((value - prev) / prev) * 100;
    // Under 3% is measurement jitter, not a signal - match the counter
    // gate's tolerance rather than painting noise red/green.
    if (Math.abs(pct) >= 3) {
      const improved = betterLow ? pct < 0 : pct > 0;
      cls = improved ? 'good' : 'bad';
      delta = `${improved ? '▼' : '▲'} ${Math.abs(pct).toFixed(0)}% vs prev run`;
    } else {
      delta = '≈ prev run';
    }
  }
  const shown = value >= 100 ? fmt(value) : value.toFixed(digits);
  return `<div class="tile">
    <div class="tile-label">${esc(label)}</div>
    <div class="tile-value">${shown}<span class="tile-unit">${esc(unit)}</span></div>
    <div class="tile-delta ${cls}">${esc(delta || note)}</div>
    ${delta ? `<div class="tile-note">${esc(note)}</div>` : ''}
  </div>`;
}

const tiles = [];
{
  const corpus = groupRuns((r) => r.suite === 'vm-sweep' && r.scenario === 'dartpdf-corpus')
    ?? groupRuns((r) => r.suite === 'vm-sweep');
  if (corpus) {
    const last = corpus[corpus.length - 1].metrics;
    const prev = corpus.length > 1 ? corpus[corpus.length - 2].metrics : {};
    const scen = corpus[corpus.length - 1].scenario ?? 'vm-sweep';
    tiles.push(tile('Open p50', scen, last.p50OpenMs, 'ms', prev.p50OpenMs));
    tiles.push(tile('Interpret p50', `${scen}, per page`,
      last.p50InterpretMsPerPage, 'ms/pg', prev.p50InterpretMsPerPage));
    tiles.push(tile('Peak RSS', `${scen}, worst file`,
      last.maxPeakRssBytes == null ? null : last.maxPeakRssBytes / 1e6, 'MB',
      prev.maxPeakRssBytes == null ? null : prev.maxPeakRssBytes / 1e6,
      { digits: 0 }));
  }
  const save = groupRuns((r) => r.scenario === 'save-incremental');
  if (save) {
    const last = save[save.length - 1].metrics;
    const prev = save.length > 1 ? save[save.length - 2].metrics : {};
    tiles.push(tile('Save p50', 'incremental, ghent', last.p50SaveMs, 'ms', prev.p50SaveMs));
  }
  // Competitive: dart-pdf vs PDFium document open over the same corpus.
  const ghent = groupRuns((r) => r.scenario === 'ghent-suite-open');
  const pdfium = groupRuns((r) => r.suite === 'pdfium');
  const dartOpen = ghent?.[ghent.length - 1].metrics.p50OpenMs;
  const pdfiumOpen = pdfium?.[pdfium.length - 1].metrics.p50OpenMs;
  if (dartOpen > 0 && pdfiumOpen > 0) {
    const ratio = pdfiumOpen / dartOpen;
    tiles.push(tile('Open vs PDFium', 'ghent, p50, higher is better',
      ratio, 'x faster', null, { betterLow: false, digits: 1 }));
  }
  // Perf budgets: pass count across every scenario with targets + data.
  let pass = 0, total = 0;
  for (const [scenario, budgets] of Object.entries(targets)) {
    if (scenario.startsWith('_')) continue;
    const g = groupRuns((r) => r.scenario === scenario);
    if (!g) continue;
    const m = g[g.length - 1].metrics;
    for (const [key, budget] of Object.entries(budgets)) {
      if (typeof m[key] !== 'number' || budget.max == null) continue;
      total++;
      if (m[key] <= budget.max) pass++;
    }
  }
  if (total > 0) {
    tiles.push(`<div class="tile">
      <div class="tile-label">Perf budgets</div>
      <div class="tile-value ${pass === total ? 'all-pass' : ''}">${pass}<span class="tile-unit">/ ${total} green</span></div>
      <div class="tile-note">targets.json, aspirational</div>
    </div>`);
  }
}
const tilesHtml = tiles.filter(Boolean).length
  ? `<div class="tiles">${tiles.filter(Boolean).join('\n')}</div>`
  : '';

// ---- Sections --------------------------------------------------------------
let sections = '';
for (const [key, groupRuns] of groups) {
  const recent = groupRuns.slice(-limit);
  const scenario = recent[recent.length - 1]?.scenario;
  const scenarioTargets = (scenario && targets[scenario]) || {};

  const metricKeys = new Set();
  for (const r of recent) {
    for (const [k, v] of Object.entries(r.metrics ?? {})) {
      if (typeof v === 'number') metricKeys.add(k);
    }
  }
  const ordered = [
    ...preferred.filter((k) => metricKeys.has(k)),
    ...[...metricKeys].filter((k) => !preferred.includes(k) && k !== 'files').sort(),
  ];
  if (ordered.length === 0) continue;

  const charts = ordered.map((metric) => {
    const series = recent
      .filter((r) => typeof r.metrics?.[metric] === 'number')
      .map((r) => ({
        v: r.metrics[metric],
        date: whenOf(r).slice(0, 10),
        label: `${whenOf(r).slice(0, 16).replace('T', ' ')}  ${metric}=${fmt(r.metrics[metric])}  @${String(r.rev?.sha ?? '').slice(0, 8)}${r.rev?.dirty ? '+dirty' : ''}`,
      }));
    if (series.length === 0) return '';
    return chart(metric, series, scenarioTargets[metric]?.max);
  }).join('\n');

  const tableRows = ordered.map((metric) => {
    const lastRun = [...recent].reverse().find((r) => typeof r.metrics?.[metric] === 'number');
    if (!lastRun) return '';
    const v = lastRun.metrics[metric];
    const budget = scenarioTargets[metric]?.max;
    const verdict = budget == null ? '—' : v <= budget ? '✓ PASS' : '✕ MISS';
    const cls = budget == null ? '' : v <= budget ? 'pass' : 'fail';
    return `<tr><td>${esc(metric)}</td><td>${fmt(v)}</td><td>${budget == null ? '—' : fmt(budget)}</td><td class="${cls}">${verdict}</td></tr>`;
  }).join('');

  const last = recent[recent.length - 1];
  sections += `<section>
  <h2>${esc(key)}</h2>
  <p class="meta">${recent.length} runs · latest ${esc(String(last.ts ?? '').slice(0, 16).replace('T', ' '))}
    @ <code>${esc(String(last.rev?.sha ?? '').slice(0, 8))}</code> on ${esc(last.env?.os ?? '?')}
    (${esc(last.env?.runner ?? '?')})</p>
  <div class="charts">${charts}</div>
  <details><summary>Latest run vs targets</summary>
    <table><thead><tr><th>metric</th><th>latest</th><th>budget</th><th>verdict</th></tr></thead>
    <tbody>${tableRows}</tbody></table>
  </details>
</section>`;
}

if (!sections) {
  sections = runs.length === 0
    ? '<p class="meta">No history yet. Run <code>tool/perf.sh sweep &lt;scenario&gt;</code> to record the first envelope.</p>'
    : `<p class="meta">${runs.length} run(s) on record, but none carry a chartable <code>metrics</code> block - check the producing tool emits envelope metrics (tool/perf/SCHEMA.md).</p>`;
}

// ---- Page ------------------------------------------------------------------
const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>dart-pdf perf trends</title>
<style>
  .viz-root {
    color-scheme: light;
    --surface-1: #fcfcfb; --text-primary: #0b0b0b; --text-secondary: #52514e;
    --series-1: #2a78d6; --grid: #52514e33; --budget: #e34948;
    --pass: #008300; --fail: #e34948; --card: #f2f1ef;
  }
  @media (prefers-color-scheme: dark) {
    :root:where(:not([data-theme="light"])) .viz-root {
      color-scheme: dark;
      --surface-1: #1a1a19; --text-primary: #ffffff; --text-secondary: #c3c2b7;
      --series-1: #3987e5; --grid: #c3c2b733; --budget: #e66767;
      --pass: #7fbf7f; --fail: #e66767; --card: #242423;
    }
  }
  :root[data-theme="dark"] .viz-root {
    color-scheme: dark;
    --surface-1: #1a1a19; --text-primary: #ffffff; --text-secondary: #c3c2b7;
    --series-1: #3987e5; --grid: #c3c2b733; --budget: #e66767;
    --pass: #7fbf7f; --fail: #e66767; --card: #242423;
  }
  body { margin: 0; }
  .viz-root { background: var(--surface-1); color: var(--text-primary);
    font: 14px/1.5 system-ui, sans-serif; padding: 24px; min-height: 100vh; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  h2 { font-size: 16px; margin: 28px 0 2px; }
  .meta { color: var(--text-secondary); margin: 0 0 10px; font-size: 12.5px; }
  .charts { display: flex; flex-wrap: wrap; gap: 12px; }
  .chart { margin: 0; background: var(--card); border-radius: 8px;
    padding: 10px 12px; width: 320px; }
  .chart figcaption { font-size: 12.5px; color: var(--text-secondary);
    display: flex; justify-content: space-between; gap: 8px; }
  .chart .last { color: var(--text-primary); font-weight: 600;
    font-variant-numeric: tabular-nums; }
  .chart .verdict { font-weight: 400; font-size: 11.5px; }
  .chart.miss .verdict { color: var(--fail); }
  .chart:not(.miss) .verdict { color: var(--pass); }
  svg { display: block; width: 100%; height: auto; }
  .line { fill: none; stroke: var(--series-1); stroke-width: 2;
    stroke-linejoin: round; stroke-linecap: round; }
  .dot { fill: var(--series-1); }
  .grid { stroke: var(--grid); stroke-width: 1; }
  .budget { stroke: var(--budget); stroke-width: 1; stroke-dasharray: 4 3; }
  .axis { fill: var(--text-secondary); font-size: 9px; }
  .hit { fill: transparent; }
  .hit:hover { fill: var(--series-1); fill-opacity: 0.25; }
  details { margin: 10px 0 0; }
  summary { cursor: pointer; color: var(--text-secondary); font-size: 12.5px; }
  table { border-collapse: collapse; margin-top: 8px; font-size: 12.5px; }
  th, td { text-align: left; padding: 3px 14px 3px 0;
    border-bottom: 1px solid var(--grid); font-variant-numeric: tabular-nums; }
  th { color: var(--text-secondary); font-weight: 500; }
  td.pass { color: var(--pass); } td.fail { color: var(--fail); }
  code { font-size: 12px; }
  .tiles { display: flex; flex-wrap: wrap; gap: 12px; margin: 18px 0 6px; }
  .tile { background: var(--card); border-radius: 8px; padding: 12px 16px;
    min-width: 150px; }
  .tile-label { font-size: 12px; color: var(--text-secondary); }
  .tile-value { font-size: 26px; font-weight: 650; line-height: 1.25;
    font-variant-numeric: tabular-nums; }
  .tile-value.all-pass { color: var(--pass); }
  .tile-unit { font-size: 12px; font-weight: 400;
    color: var(--text-secondary); margin-left: 4px; }
  .tile-delta { font-size: 11.5px; color: var(--text-secondary); }
  .tile-delta.good { color: var(--pass); }
  .tile-delta.bad { color: var(--fail); }
  .tile-note { font-size: 11px; color: var(--text-secondary); }
</style>
</head>
<body>
<div class="viz-root">
  <h1>dart-pdf perf trends</h1>
  <p class="meta">Generated ${new Date().toISOString().slice(0, 16).replace('T', ' ')} UTC ·
    ${runs.length} runs on record · budgets from tool/perf/targets.json
    (aspirational targets, never PR gates)</p>
  ${tilesHtml}
  ${sections}
</div>
</body>
</html>`;

writeFileSync(outPath, html);
console.log(`wrote ${resolve(outPath)} (${groups.size} sections, ${runs.length} runs)`);
