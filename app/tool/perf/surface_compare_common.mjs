// Pure pixel metrics shared by the real-Chrome surface correctness driver and
// its Node unit tests. Inputs are equally-sized RGBA byte arrays.

export function compareRgba(
  baseline,
  candidate,
  width,
  height,
  {
    channelTolerance = 8,
    backgroundTolerance = 24,
    foregroundRadius = 1,
    background = [255, 255, 255],
  } = {},
) {
  const pixels = width * height;
  if (!Number.isInteger(width) || width <= 0 ||
      !Number.isInteger(height) || height <= 0) {
    throw new RangeError('width and height must be positive integers');
  }
  if (baseline.length !== pixels * 4 || candidate.length !== pixels * 4) {
    throw new RangeError('RGBA input length does not match width × height');
  }

  const radius = Math.max(0, Math.trunc(foregroundRadius));
  const histogram = new Uint32Array(256);
  const baselineForeground = new Uint8Array(pixels);
  const candidateForeground = new Uint8Array(pixels);
  let differing = 0;
  let exactDiffering = 0;
  let absoluteError = 0;
  let squaredError = 0;
  let baselineForegroundCount = 0;
  let candidateForegroundCount = 0;

  for (let pixel = 0, offset = 0; pixel < pixels; pixel++, offset += 4) {
    let maxDifference = 0;
    let baselineBackgroundDistance = 0;
    let candidateBackgroundDistance = 0;
    for (let channel = 0; channel < 3; channel++) {
      const difference = Math.abs(
        baseline[offset + channel] - candidate[offset + channel],
      );
      maxDifference = Math.max(maxDifference, difference);
      absoluteError += difference;
      squaredError += difference * difference;
      baselineBackgroundDistance = Math.max(
        baselineBackgroundDistance,
        Math.abs(baseline[offset + channel] - background[channel]),
      );
      candidateBackgroundDistance = Math.max(
        candidateBackgroundDistance,
        Math.abs(candidate[offset + channel] - background[channel]),
      );
    }
    histogram[maxDifference]++;
    if (maxDifference > 0) exactDiffering++;
    if (maxDifference > channelTolerance) differing++;
    if (baselineBackgroundDistance > backgroundTolerance) {
      baselineForeground[pixel] = 1;
      baselineForegroundCount++;
    }
    if (candidateBackgroundDistance > backgroundTolerance) {
      candidateForeground[pixel] = 1;
      candidateForegroundCount++;
    }
  }

  const hasNeighbor = (mask, x, y) => {
    const x0 = Math.max(0, x - radius);
    const x1 = Math.min(width - 1, x + radius);
    const y0 = Math.max(0, y - radius);
    const y1 = Math.min(height - 1, y + radius);
    for (let yy = y0; yy <= y1; yy++) {
      const row = yy * width;
      for (let xx = x0; xx <= x1; xx++) {
        if (mask[row + xx]) return true;
      }
    }
    return false;
  };

  let baselineMatched = 0;
  let candidateMatched = 0;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const pixel = y * width + x;
      if (baselineForeground[pixel] &&
          hasNeighbor(candidateForeground, x, y)) {
        baselineMatched++;
      }
      if (candidateForeground[pixel] &&
          hasNeighbor(baselineForeground, x, y)) {
        candidateMatched++;
      }
    }
  }

  const percentile = (fraction) => {
    const target = Math.max(1, Math.ceil(pixels * fraction));
    let seen = 0;
    for (let value = 0; value < histogram.length; value++) {
      seen += histogram[value];
      if (seen >= target) return value;
    }
    return 255;
  };
  const ratio = (part, total) => total === 0 ? 1 : part / total;

  return {
    width,
    height,
    pixels,
    channelTolerance,
    backgroundTolerance,
    foregroundRadius: radius,
    exactDifferenceFraction: exactDiffering / pixels,
    differenceFraction: differing / pixels,
    meanAbsoluteChannelError: absoluteError / (pixels * 3),
    rootMeanSquareChannelError: Math.sqrt(squaredError / (pixels * 3)),
    maxChannelDifferenceP50: percentile(0.5),
    maxChannelDifferenceP95: percentile(0.95),
    maxChannelDifferenceP99: percentile(0.99),
    baselineForegroundPixels: baselineForegroundCount,
    candidateForegroundPixels: candidateForegroundCount,
    foregroundCoverageRatio: ratio(
      candidateForegroundCount,
      baselineForegroundCount,
    ),
    foregroundRecall: ratio(baselineMatched, baselineForegroundCount),
    foregroundPrecision: ratio(candidateMatched, candidateForegroundCount),
  };
}

export function evaluateSurfaceSample(metrics, budgets) {
  if (!budgets) return [];
  return [
    {
      metric: 'differenceFraction',
      value: metrics.differenceFraction,
      limit: budgets.maxDifferenceFraction,
      pass: metrics.differenceFraction <= budgets.maxDifferenceFraction,
    },
    {
      metric: 'meanAbsoluteChannelError',
      value: metrics.meanAbsoluteChannelError,
      limit: budgets.maxMeanAbsoluteChannelError,
      pass: metrics.meanAbsoluteChannelError <=
        budgets.maxMeanAbsoluteChannelError,
    },
    {
      metric: 'foregroundRecall',
      value: metrics.foregroundRecall,
      limit: budgets.minForegroundRecall,
      pass: metrics.foregroundRecall >= budgets.minForegroundRecall,
    },
    {
      metric: 'foregroundPrecision',
      value: metrics.foregroundPrecision,
      limit: budgets.minForegroundPrecision,
      pass: metrics.foregroundPrecision >= budgets.minForegroundPrecision,
    },
    {
      metric: 'foregroundCoverageRatioMin',
      value: metrics.foregroundCoverageRatio,
      limit: budgets.minForegroundCoverageRatio,
      pass: metrics.foregroundCoverageRatio >=
        budgets.minForegroundCoverageRatio,
    },
    {
      metric: 'foregroundCoverageRatioMax',
      value: metrics.foregroundCoverageRatio,
      limit: budgets.maxForegroundCoverageRatio,
      pass: metrics.foregroundCoverageRatio <=
        budgets.maxForegroundCoverageRatio,
    },
  ];
}
