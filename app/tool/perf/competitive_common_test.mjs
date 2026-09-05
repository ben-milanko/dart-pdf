import assert from 'node:assert/strict';
import test from 'node:test';

import {
  aggregateRuns,
  cadenceDelay,
  evaluateBudgets,
  framesInWindow,
  parityRatios,
  percentile,
  queryFlag,
  resolveHttpByteRange,
  resolveVisualCaptureMode,
  screenshotSampleAt,
  summarize,
  translateEpochTimestamp,
} from './competitive_common.mjs';

test('percentiles use nearest-rank semantics', () => {
  assert.equal(percentile([5, 1, 4, 2, 3], 50), 3);
  assert.equal(percentile([5, 1, 4, 2, 3], 95), 5);
  assert.equal(percentile([], 50), null);
});

test('frame windows use render timestamps, not delayed callback order', () => {
  const frames = [
    {s: 90, b: 1, r: 2},
    {s: 150, b: 3, r: 4},
    {s: 210, b: 5, r: 6},
  ];
  assert.deepEqual(framesInWindow(frames, 100, 200), [frames[1]]);
  assert.deepEqual(framesInWindow(frames, 90, 150), [frames[0], frames[1]]);
});

test('input cadence targets event starts without adding command latency', () => {
  assert.equal(cadenceDelay(100, 0, 16, 100), 0);
  assert.equal(cadenceDelay(100, 3, 16, 130), 18);
  assert.equal(cadenceDelay(100, 3, 16, 160), 0);
});

test('worker-owned surfaces always select a pixel-valid capture mode', () => {
  assert.equal(queryFlag('foo=1&domSurface=true', 'domSurface'), true);
  assert.equal(queryFlag('?domSurface=0', 'domSurface'), false);
  assert.equal(resolveVisualCaptureMode(undefined, 'skwasm', ''), 'screenshot');
  assert.equal(
    resolveVisualCaptureMode(undefined, 'js-canvaskit', 'domSurface=1'),
    'screenshot',
  );
  assert.equal(
    resolveVisualCaptureMode(undefined, 'js-canvaskit', ''),
    'screencast',
  );
  assert.equal(
    resolveVisualCaptureMode('none', 'skwasm', 'domSurface=1'),
    'none',
  );
});

test('screenshot timestamps exclude post-sample encoding latency', () => {
  assert.equal(screenshotSampleAt(100, 160, 36), 136);
  assert.equal(screenshotSampleAt(100, 125, 36), 125);
  assert.throws(
    () => screenshotSampleAt(100, 99, 36),
    /invalid screenshot capture interval/,
  );
  assert.throws(
    () => screenshotSampleAt(100, 160, -1),
    /sampleDelayMs/,
  );
});

test('same-host epoch timestamps translate to the driver clock', () => {
  assert.equal(translateEpochTimestamp(1_000_450, 1_000_000), 450);
  assert.throws(
    () => translateEpochTimestamp(Number.NaN, 1_000_000),
    /invalid epoch timestamp sample/,
  );
});

test('HTTP byte ranges cover bounded, open, suffix, and rejected requests', () => {
  assert.deepEqual(resolveHttpByteRange(null, 100), null);
  assert.deepEqual(resolveHttpByteRange('bytes=10-19', 100), {
    satisfiable: true,
    start: 10,
    endExclusive: 20,
  });
  assert.deepEqual(resolveHttpByteRange('bytes=90-', 100), {
    satisfiable: true,
    start: 90,
    endExclusive: 100,
  });
  assert.deepEqual(resolveHttpByteRange('bytes=-15', 100), {
    satisfiable: true,
    start: 85,
    endExclusive: 100,
  });
  assert.equal(resolveHttpByteRange('bytes=100-120', 100).satisfiable, false);
  assert.equal(resolveHttpByteRange('bytes=0-1,4-5', 100).satisfiable, false);
});

test('run aggregation keeps actions pooled and opens per-run', () => {
  const result = aggregateRuns([
    {
      openLogicalReadyMs: 10,
      openFirstVisualMs: 20,
      openVisualStableMs: 30,
      documentFirstVisualMs: 12,
      documentVisualStableMs: 22,
      documentRequestOffsetMs: 8,
      navigationFullyLoadedMs: 48,
      fullyLoadedMs: 40,
      openNetwork: {bytes: 30, requests: 2},
      network: {bytes: 80, requests: 4},
      warmOpenFirstVisualMs: 14,
      warmOpenVisualStableMs: 18,
      navigationSamplesMs: [5, 7],
      navigationFirstVisualSamplesMs: [3, 4],
      zoomSamplesMs: [9],
      zoomFirstVisualSamplesMs: [6],
      scrollSamplesMs: [21, 23],
      scrollRafIntervalsMs: [16, 18],
      scrubSamplesMs: [31, 33],
      scrubFirstVisualSamplesMs: [25, 27],
      scrubRafIntervalsMs: [16, 17],
      searchColdMs: 70,
      searchWarmMs: 12,
      screencastFrameBytes: [2000, 3000],
      rafIntervalsMs: [16, 17],
      browserRssBytes: 100,
      browserOpenRssBytes: 70,
      browserPeakRssBytes: 100,
      browserSettledRssBytes: 80,
    },
    {
      openLogicalReadyMs: 20,
      openFirstVisualMs: 40,
      openVisualStableMs: 50,
      documentFirstVisualMs: 28,
      documentVisualStableMs: 38,
      documentRequestOffsetMs: 12,
      navigationFullyLoadedMs: 72,
      fullyLoadedMs: 60,
      openNetwork: {bytes: 40, requests: 3},
      network: {bytes: 90, requests: 5},
      warmOpenFirstVisualMs: 16,
      warmOpenVisualStableMs: 20,
      navigationSamplesMs: [6, 8],
      navigationFirstVisualSamplesMs: [2, 5],
      zoomSamplesMs: [11],
      zoomFirstVisualSamplesMs: [7],
      scrollSamplesMs: [22, 24],
      scrollRafIntervalsMs: [17, 19],
      scrubSamplesMs: [32, 34],
      scrubFirstVisualSamplesMs: [26, 28],
      scrubRafIntervalsMs: [17, 18],
      searchColdMs: 80,
      searchWarmMs: 14,
      screencastFrameBytes: [4000],
      rafIntervalsMs: [18],
      browserRssBytes: 120,
      browserOpenRssBytes: 75,
      browserPeakRssBytes: 120,
      browserSettledRssBytes: 90,
    },
  ]);
  assert.deepEqual(result.openVisualStableMs, {
    count: 2,
    p50: 30,
    p95: 50,
    max: 50,
  });
  assert.deepEqual(result.openFirstVisualMs, {
    count: 2,
    p50: 20,
    p95: 40,
    max: 40,
  });
  assert.deepEqual(result.documentVisualStableMs, {
    count: 2,
    p50: 22,
    p95: 38,
    max: 38,
  });
  assert.deepEqual(result.fullyLoadedMs, {
    count: 2,
    p50: 40,
    p95: 60,
    max: 60,
  });
  assert.deepEqual(result.navigationFullyLoadedMs, {
    count: 2,
    p50: 48,
    p95: 72,
    max: 72,
  });
  assert.deepEqual(result.openNetworkBytes, {
    count: 2,
    p50: 30,
    p95: 40,
    max: 40,
  });
  assert.deepEqual(result.openNetworkRequests, {
    count: 2,
    p50: 2,
    p95: 3,
    max: 3,
  });
  assert.deepEqual(result.navigationFirstVisualMs, {
    count: 4,
    p50: 3,
    p95: 5,
    max: 5,
  });
  assert.deepEqual(result.navigationMs, {
    count: 4,
    p50: 6,
    p95: 8,
    max: 8,
  });
  assert.deepEqual(result.scrollMs, {
    count: 4,
    p50: 22,
    p95: 24,
    max: 24,
  });
  assert.deepEqual(result.searchColdMs, {
    count: 2,
    p50: 70,
    p95: 80,
    max: 80,
  });
  assert.deepEqual(result.warmOpenVisualStableMs, {
    count: 2,
    p50: 18,
    p95: 20,
    max: 20,
  });
  assert.deepEqual(result.scrubMs, {
    count: 4,
    p50: 32,
    p95: 34,
    max: 34,
  });
  assert.deepEqual(result.browserSettledRssBytes, {
    count: 2,
    p50: 80,
    p95: 90,
    max: 90,
  });
});

test('parity ratios and budgets are lower-is-better', () => {
  const base = {
    openFirstVisualMs: summarize([70, 90]),
    openVisualStableMs: summarize([100, 120]),
    documentFirstVisualMs: summarize([50, 60]),
    documentVisualStableMs: summarize([80, 100]),
    fullyLoadedMs: summarize([100, 120]),
    openNetworkBytes: summarize([1000, 1200]),
    totalNetworkBytes: summarize([2000, 2200]),
    openNetworkRequests: summarize([1, 2]),
    totalNetworkRequests: summarize([2, 3]),
    warmOpenFirstVisualMs: summarize([40, 50]),
    warmOpenVisualStableMs: summarize([60, 70]),
    navigationFirstVisualMs: summarize([10, 15]),
    navigationMs: summarize([20, 30]),
    zoomFirstVisualMs: summarize([20, 25]),
    zoomMs: summarize([40, 50]),
    scrollMs: summarize([300, 350]),
    scrollRafIntervalMs: summarize([16, 18]),
    scrubFirstVisualMs: summarize([15, 20]),
    scrubMs: summarize([25, 30]),
    scrubRafIntervalMs: summarize([16, 18]),
    searchColdMs: summarize([80, 100]),
    searchWarmMs: summarize([10, 12]),
    browserRssBytes: summarize([200]),
    browserPeakRssBytes: summarize([200]),
    browserSettledRssBytes: summarize([180]),
  };
  const dart = {
    openFirstVisualMs: summarize([77, 99]),
    openVisualStableMs: summarize([110, 130]),
    documentFirstVisualMs: summarize([55, 66]),
    documentVisualStableMs: summarize([88, 110]),
    fullyLoadedMs: summarize([110, 132]),
    openNetworkBytes: summarize([1100, 1320]),
    totalNetworkBytes: summarize([2200, 2420]),
    openNetworkRequests: summarize([1.1, 2.2]),
    totalNetworkRequests: summarize([2.2, 3.3]),
    warmOpenFirstVisualMs: summarize([44, 55]),
    warmOpenVisualStableMs: summarize([66, 77]),
    navigationFirstVisualMs: summarize([11, 16.5]),
    navigationMs: summarize([22, 33]),
    zoomFirstVisualMs: summarize([22, 27.5]),
    zoomMs: summarize([44, 55]),
    scrollMs: summarize([330, 385]),
    scrollRafIntervalMs: summarize([17.6, 19.8]),
    scrubFirstVisualMs: summarize([16.5, 22]),
    scrubMs: summarize([27.5, 33]),
    scrubRafIntervalMs: summarize([17.6, 19.8]),
    searchColdMs: summarize([88, 110]),
    searchWarmMs: summarize([11, 13.2]),
    browserRssBytes: summarize([250]),
    browserPeakRssBytes: summarize([250]),
    browserSettledRssBytes: summarize([225]),
  };
  const ratios = parityRatios(dart, base);
  assert.equal(ratios.openP50, 1.1);
  assert.equal(ratios.documentOpenP95, 1.1);
  assert.equal(ratios.fullyLoadedP95, 1.1);
  assert.equal(ratios.openTransferP50, 1.1);
  assert.equal(ratios.totalTransferP95, 1.1);
  assert.equal(ratios.openRequestP95, 1.1);
  assert.equal(ratios.totalRequestP50, 1.1);
  assert.equal(ratios.navigationP95, 1.1);
  assert.equal(ratios.scrollRafP95, 1.1);
  assert.equal(ratios.warmOpenP95, 1.1);
  assert.equal(ratios.scrubP95, 1.1);
  assert.equal(ratios.scrubRafP95, 1.1);
  assert.equal(ratios.searchColdP50, 1.1);
  assert.equal(ratios.rssP50, 1.25);
  assert.equal(ratios.peakRssP50, 1.25);
  assert.equal(ratios.settledRssP50, 1.25);
  assert.deepEqual(evaluateBudgets(ratios, { openP50: 1.15, rssP50: 1.2 }), [
    { metric: 'openP50', value: 1.1, limit: 1.15, pass: true },
    { metric: 'rssP50', value: 1.25, limit: 1.2, pass: false },
  ]);
});
