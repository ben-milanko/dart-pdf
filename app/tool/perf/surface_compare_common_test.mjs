import assert from 'node:assert/strict';
import test from 'node:test';

import {
  compareRgba,
  evaluateSurfaceSample,
} from './surface_compare_common.mjs';

function image(width, height, foreground = []) {
  const bytes = new Uint8Array(width * height * 4).fill(255);
  for (const [x, y, color = [0, 0, 0]] of foreground) {
    const offset = (y * width + x) * 4;
    bytes.set([...color, 255], offset);
  }
  return bytes;
}

test('identical pages have perfect pixel and foreground metrics', () => {
  const page = image(3, 2, [[1, 1]]);
  const result = compareRgba(page, page, 3, 2);
  assert.equal(result.differenceFraction, 0);
  assert.equal(result.meanAbsoluteChannelError, 0);
  assert.equal(result.foregroundRecall, 1);
  assert.equal(result.foregroundPrecision, 1);
  assert.equal(result.foregroundCoverageRatio, 1);
});

test('foreground matching tolerates a one-pixel raster edge shift', () => {
  const baseline = image(4, 1, [[1, 0]]);
  const candidate = image(4, 1, [[2, 0]]);
  const tolerant = compareRgba(baseline, candidate, 4, 1);
  const exact = compareRgba(baseline, candidate, 4, 1, {
    foregroundRadius: 0,
  });
  assert.equal(tolerant.foregroundRecall, 1);
  assert.equal(tolerant.foregroundPrecision, 1);
  assert.equal(exact.foregroundRecall, 0);
  assert.equal(exact.foregroundPrecision, 0);
});

test('missing and extra geometry lower recall and precision independently', () => {
  const baseline = image(5, 1, [[0, 0], [4, 0]]);
  const missing = image(5, 1, [[0, 0]]);
  const extra = image(5, 1, [[0, 0], [2, 0], [4, 0]]);
  const missingResult = compareRgba(baseline, missing, 5, 1, {
    foregroundRadius: 0,
  });
  const extraResult = compareRgba(baseline, extra, 5, 1, {
    foregroundRadius: 0,
  });
  assert.equal(missingResult.foregroundRecall, 0.5);
  assert.equal(missingResult.foregroundPrecision, 1);
  assert.equal(extraResult.foregroundRecall, 1);
  assert.equal(extraResult.foregroundPrecision, 2 / 3);
});

test('channel tolerance and percentile metrics use max RGB difference', () => {
  const baseline = image(2, 1);
  const candidate = image(2, 1, [
    [0, 0, [250, 255, 255]],
    [1, 0, [245, 255, 255]],
  ]);
  const result = compareRgba(baseline, candidate, 2, 1, {
    channelTolerance: 8,
  });
  assert.equal(result.exactDifferenceFraction, 1);
  assert.equal(result.differenceFraction, 0.5);
  assert.equal(result.maxChannelDifferenceP50, 5);
  assert.equal(result.maxChannelDifferenceP95, 10);
});

test('invalid RGBA dimensions fail loudly', () => {
  assert.throws(
    () => compareRgba(new Uint8Array(3), new Uint8Array(3), 1, 1),
    /RGBA input length/,
  );
});

test('surface budgets reject foreground coverage outside both bounds', () => {
  const checks = evaluateSurfaceSample({
    differenceFraction: 0.01,
    meanAbsoluteChannelError: 1,
    foregroundRecall: 0.99,
    foregroundPrecision: 0.99,
    foregroundCoverageRatio: 1.4,
  }, {
    maxDifferenceFraction: 0.1,
    maxMeanAbsoluteChannelError: 5,
    minForegroundRecall: 0.9,
    minForegroundPrecision: 0.9,
    minForegroundCoverageRatio: 0.8,
    maxForegroundCoverageRatio: 1.2,
  });
  assert.equal(checks.length, 6);
  assert.equal(
    checks.find((check) => check.metric === 'foregroundCoverageRatioMin').pass,
    true,
  );
  assert.equal(
    checks.find((check) => check.metric === 'foregroundCoverageRatioMax').pass,
    false,
  );
});
