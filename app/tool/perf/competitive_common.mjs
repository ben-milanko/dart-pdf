import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

export const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export function percentile(values, p) {
  const sorted = values
    .filter((value) => Number.isFinite(value))
    .toSorted((a, b) => a - b);
  if (!sorted.length) return null;
  const index = Math.min(
    sorted.length - 1,
    Math.max(0, Math.ceil((p / 100) * sorted.length) - 1),
  );
  return sorted[index];
}

export function summarize(values) {
  const finite = values.filter((value) => Number.isFinite(value));
  return {
    count: finite.length,
    p50: percentile(finite, 50),
    p95: percentile(finite, 95),
    max: finite.length ? Math.max(...finite) : null,
  };
}

export function framesInWindow(frames, startMs, endMs) {
  return frames.filter((frame) => frame.s >= startMs && frame.s <= endMs);
}

export function cadenceDelay(startAt, eventIndex, intervalMs, now) {
  return Math.max(0, startAt + eventIndex * intervalMs - now);
}

export function queryFlag(query, name) {
  const value = new URLSearchParams(String(query ?? '').replace(/^[?&]+/, ''))
    .get(name);
  return value === '1' || value === 'true';
}

export function resolveVisualCaptureMode(requested, webBackend, dartQuery) {
  if (requested) return requested;
  // Worker-owned OffscreenCanvas pixels are not represented reliably in CDP
  // screencasts, regardless of whether Flutter itself uses SkWasm or
  // CanvasKit. A screenshot is the only common pixel clock for that surface.
  return webBackend === 'skwasm' || queryFlag(dartQuery, 'domSurface')
    ? 'screenshot'
    : 'screencast';
}

// Page.captureScreenshot returns after its encoded payload, but the pixels are
// sampled earlier. Use a separately calibrated upper bound for that sampling
// instant so JPEG encoding is not charged to either rendering engine. The
// response time remains an absolute ceiling for unusually fast captures.
export function screenshotSampleAt(startAt, responseAt, sampleDelayMs) {
  if (!Number.isFinite(startAt) || !Number.isFinite(responseAt) ||
      responseAt < startAt) {
    throw new RangeError('invalid screenshot capture interval');
  }
  if (!Number.isFinite(sampleDelayMs) || sampleDelayMs < 0) {
    throw new RangeError('sampleDelayMs must be a non-negative number');
  }
  return Math.min(responseAt, startAt + sampleDelayMs);
}

// Translate `performance.timeOrigin + performance.now()` captured in another
// same-host process into this driver's performance.now() clock. Unlike a
// response-relative mapping, this does not inherit CDP queue/transport delay.
export function translateEpochTimestamp(remoteEpochAt, localTimeOrigin) {
  if (![remoteEpochAt, localTimeOrigin].every(Number.isFinite)) {
    throw new RangeError('invalid epoch timestamp sample');
  }
  return remoteEpochAt - localTimeOrigin;
}

// Resolves one RFC 7233 byte range against a known representation length.
// The benchmark server deliberately rejects multi-range requests: neither
// viewer needs multipart responses, and silently serving the first range would
// make its network accounting dishonest.
export function resolveHttpByteRange(header, length) {
  if (header == null || String(header).trim() === '') return null;
  if (!Number.isInteger(length) || length < 0) {
    throw new RangeError('length must be a non-negative integer');
  }
  const match = String(header).trim().match(/^bytes=(\d*)-(\d*)$/i);
  if (!match || (!match[1] && !match[2]) || length === 0) {
    return { satisfiable: false, start: null, endExclusive: null };
  }
  if (!match[1]) {
    const suffix = Number(match[2]);
    if (!Number.isSafeInteger(suffix) || suffix <= 0) {
      return { satisfiable: false, start: null, endExclusive: null };
    }
    return {
      satisfiable: true,
      start: Math.max(0, length - suffix),
      endExclusive: length,
    };
  }
  const start = Number(match[1]);
  const requestedEnd = match[2] ? Number(match[2]) : length - 1;
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(requestedEnd) ||
      start < 0 || start >= length || requestedEnd < start) {
    return { satisfiable: false, start: null, endExclusive: null };
  }
  return {
    satisfiable: true,
    start,
    endExclusive: Math.min(length, requestedEnd + 1),
  };
}

export function digest(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

export function aggregateRuns(runs) {
  const all = (name) => runs.flatMap((run) => run[name] ?? []);
  const scalar = (name) => summarize(runs.map((run) => run[name]));
  return {
    runs: runs.length,
    openLogicalReadyMs: scalar('openLogicalReadyMs'),
    openFirstVisualMs: scalar('openFirstVisualMs'),
    openVisualStableMs: scalar('openVisualStableMs'),
    documentFirstVisualMs: scalar('documentFirstVisualMs'),
    documentVisualStableMs: scalar('documentVisualStableMs'),
    documentRequestOffsetMs: scalar('documentRequestOffsetMs'),
    navigationFullyLoadedMs: scalar('navigationFullyLoadedMs'),
    fullyLoadedMs: scalar('fullyLoadedMs'),
    openNetworkBytes: summarize(
      runs.map((run) => run.openNetwork?.bytes),
    ),
    totalNetworkBytes: summarize(
      runs.map((run) => run.network?.bytes),
    ),
    openNetworkRequests: summarize(
      runs.map((run) => run.openNetwork?.requests),
    ),
    totalNetworkRequests: summarize(
      runs.map((run) => run.network?.requests),
    ),
    warmOpenFirstVisualMs: scalar('warmOpenFirstVisualMs'),
    warmOpenVisualStableMs: scalar('warmOpenVisualStableMs'),
    navigationFirstVisualMs: summarize(all('navigationFirstVisualSamplesMs')),
    navigationMs: summarize(all('navigationSamplesMs')),
    zoomFirstVisualMs: summarize(all('zoomFirstVisualSamplesMs')),
    zoomMs: summarize(all('zoomSamplesMs')),
    scrollMs: summarize(all('scrollSamplesMs')),
    scrollRafIntervalMs: summarize(all('scrollRafIntervalsMs')),
    scrubFirstVisualMs: summarize(all('scrubFirstVisualSamplesMs')),
    scrubMs: summarize(all('scrubSamplesMs')),
    scrubRafIntervalMs: summarize(all('scrubRafIntervalsMs')),
    searchColdMs: scalar('searchColdMs'),
    searchWarmMs: scalar('searchWarmMs'),
    screencastFrameBytes: summarize(all('screencastFrameBytes')),
    rafIntervalMs: summarize(all('rafIntervalsMs')),
    browserRssBytes: scalar('browserRssBytes'),
    browserOpenRssBytes: scalar('browserOpenRssBytes'),
    browserPeakRssBytes: scalar('browserPeakRssBytes'),
    browserSettledRssBytes: scalar('browserSettledRssBytes'),
  };
}

export function parityRatios(dart, pdfium) {
  const ratio = (a, b) =>
    Number.isFinite(a) && Number.isFinite(b) && b > 0 ? a / b : null;
  return {
    openFirstP50: ratio(
      dart.openFirstVisualMs.p50,
      pdfium.openFirstVisualMs.p50,
    ),
    openFirstP95: ratio(
      dart.openFirstVisualMs.p95,
      pdfium.openFirstVisualMs.p95,
    ),
    openP50: ratio(
      dart.openVisualStableMs.p50,
      pdfium.openVisualStableMs.p50,
    ),
    openP95: ratio(
      dart.openVisualStableMs.p95,
      pdfium.openVisualStableMs.p95,
    ),
    documentFirstP50: ratio(
      dart.documentFirstVisualMs.p50,
      pdfium.documentFirstVisualMs.p50,
    ),
    documentFirstP95: ratio(
      dart.documentFirstVisualMs.p95,
      pdfium.documentFirstVisualMs.p95,
    ),
    documentOpenP50: ratio(
      dart.documentVisualStableMs.p50,
      pdfium.documentVisualStableMs.p50,
    ),
    documentOpenP95: ratio(
      dart.documentVisualStableMs.p95,
      pdfium.documentVisualStableMs.p95,
    ),
    fullyLoadedP50: ratio(
      dart.fullyLoadedMs.p50,
      pdfium.fullyLoadedMs.p50,
    ),
    fullyLoadedP95: ratio(
      dart.fullyLoadedMs.p95,
      pdfium.fullyLoadedMs.p95,
    ),
    openTransferP50: ratio(
      dart.openNetworkBytes.p50,
      pdfium.openNetworkBytes.p50,
    ),
    openTransferP95: ratio(
      dart.openNetworkBytes.p95,
      pdfium.openNetworkBytes.p95,
    ),
    totalTransferP50: ratio(
      dart.totalNetworkBytes.p50,
      pdfium.totalNetworkBytes.p50,
    ),
    totalTransferP95: ratio(
      dart.totalNetworkBytes.p95,
      pdfium.totalNetworkBytes.p95,
    ),
    openRequestP50: ratio(
      dart.openNetworkRequests.p50,
      pdfium.openNetworkRequests.p50,
    ),
    openRequestP95: ratio(
      dart.openNetworkRequests.p95,
      pdfium.openNetworkRequests.p95,
    ),
    totalRequestP50: ratio(
      dart.totalNetworkRequests.p50,
      pdfium.totalNetworkRequests.p50,
    ),
    totalRequestP95: ratio(
      dart.totalNetworkRequests.p95,
      pdfium.totalNetworkRequests.p95,
    ),
    warmOpenFirstP50: ratio(
      dart.warmOpenFirstVisualMs.p50,
      pdfium.warmOpenFirstVisualMs.p50,
    ),
    warmOpenFirstP95: ratio(
      dart.warmOpenFirstVisualMs.p95,
      pdfium.warmOpenFirstVisualMs.p95,
    ),
    warmOpenP50: ratio(
      dart.warmOpenVisualStableMs.p50,
      pdfium.warmOpenVisualStableMs.p50,
    ),
    warmOpenP95: ratio(
      dart.warmOpenVisualStableMs.p95,
      pdfium.warmOpenVisualStableMs.p95,
    ),
    navigationP50: ratio(dart.navigationMs.p50, pdfium.navigationMs.p50),
    navigationP95: ratio(dart.navigationMs.p95, pdfium.navigationMs.p95),
    navigationFirstP50: ratio(
      dart.navigationFirstVisualMs.p50,
      pdfium.navigationFirstVisualMs.p50,
    ),
    navigationFirstP95: ratio(
      dart.navigationFirstVisualMs.p95,
      pdfium.navigationFirstVisualMs.p95,
    ),
    zoomP50: ratio(dart.zoomMs.p50, pdfium.zoomMs.p50),
    zoomP95: ratio(dart.zoomMs.p95, pdfium.zoomMs.p95),
    zoomFirstP50: ratio(
      dart.zoomFirstVisualMs.p50,
      pdfium.zoomFirstVisualMs.p50,
    ),
    zoomFirstP95: ratio(
      dart.zoomFirstVisualMs.p95,
      pdfium.zoomFirstVisualMs.p95,
    ),
    scrollP50: ratio(dart.scrollMs.p50, pdfium.scrollMs.p50),
    scrollP95: ratio(dart.scrollMs.p95, pdfium.scrollMs.p95),
    scrollRafP95: ratio(
      dart.scrollRafIntervalMs.p95,
      pdfium.scrollRafIntervalMs.p95,
    ),
    scrubP50: ratio(dart.scrubMs.p50, pdfium.scrubMs.p50),
    scrubP95: ratio(dart.scrubMs.p95, pdfium.scrubMs.p95),
    scrubFirstP50: ratio(
      dart.scrubFirstVisualMs.p50,
      pdfium.scrubFirstVisualMs.p50,
    ),
    scrubFirstP95: ratio(
      dart.scrubFirstVisualMs.p95,
      pdfium.scrubFirstVisualMs.p95,
    ),
    scrubRafP95: ratio(
      dart.scrubRafIntervalMs.p95,
      pdfium.scrubRafIntervalMs.p95,
    ),
    searchColdP50: ratio(dart.searchColdMs.p50, pdfium.searchColdMs.p50),
    searchColdP95: ratio(dart.searchColdMs.p95, pdfium.searchColdMs.p95),
    searchWarmP50: ratio(dart.searchWarmMs.p50, pdfium.searchWarmMs.p50),
    searchWarmP95: ratio(dart.searchWarmMs.p95, pdfium.searchWarmMs.p95),
    rssP50: ratio(dart.browserRssBytes.p50, pdfium.browserRssBytes.p50),
    peakRssP50: ratio(
      dart.browserPeakRssBytes.p50,
      pdfium.browserPeakRssBytes.p50,
    ),
    settledRssP50: ratio(
      dart.browserSettledRssBytes.p50,
      pdfium.browserSettledRssBytes.p50,
    ),
  };
}

// Sum the resident set of Chrome's root process and every descendant. This is
// intentionally browser-process RSS, not JS heap: DartPDF retains decoded
// pixels in CanvasKit/Wasm while PDFium retains them in native/plugin
// processes, so either engine-specific heap would omit the competitor's main
// cost. `ps` is present on the macOS/Linux hosts used by this benchmark.
export function processTreeRssSnapshot(rootPid) {
  if (!Number.isInteger(rootPid) || rootPid <= 0) return null;
  let text;
  try {
    text = execFileSync('ps', ['-axo', 'pid=,ppid=,rss=,command='], {
      encoding: 'utf8',
    });
  } catch {
    return null;
  }
  const rows = text
    .trim()
    .split('\n')
    .map((line) =>
      line.match(/^\s*(\d+)\s+(\d+)\s+(\d+)\s+(.*)$/),
    )
    .filter(Boolean)
    .map((match) => ({
      pid: Number(match[1]),
      ppid: Number(match[2]),
      rssKb: Number(match[3]),
      command: match[4],
    }))
    .filter((row) =>
      Number.isFinite(row.pid) &&
      Number.isFinite(row.ppid) &&
      Number.isFinite(row.rssKb),
    );
  const children = new Map();
  const byPid = new Map();
  for (const row of rows) {
    byPid.set(row.pid, row);
    const list = children.get(row.ppid) ?? [];
    list.push(row.pid);
    children.set(row.ppid, list);
  }
  const pending = [rootPid];
  const seen = new Set();
  let totalKb = 0;
  const byTypeKb = {};
  while (pending.length) {
    const pid = pending.pop();
    if (seen.has(pid)) continue;
    seen.add(pid);
    const row = byPid.get(pid);
    const rssKb = row?.rssKb ?? 0;
    totalKb += rssKb;
    const command = row?.command ?? '';
    const type = pid === rootPid
      ? 'browser'
      : command.includes('--type=renderer')
        ? 'renderer'
        : command.includes('--type=gpu-process')
          ? 'gpu'
          : command.includes('--type=utility')
            ? 'utility'
            : command.includes('--type=zygote')
              ? 'zygote'
              : 'other';
    byTypeKb[type] = (byTypeKb[type] ?? 0) + rssKb;
    pending.push(...(children.get(pid) ?? []));
  }
  if (totalKb <= 0) return null;
  return {
    totalBytes: totalKb * 1024,
    byTypeBytes: Object.fromEntries(
      Object.entries(byTypeKb).map(([type, kb]) => [type, kb * 1024]),
    ),
  };
}

export function processTreeRssBytes(rootPid) {
  return processTreeRssSnapshot(rootPid)?.totalBytes ?? null;
}

export function evaluateBudgets(ratios, budgets) {
  return Object.entries(budgets).map(([metric, limit]) => {
    const value = ratios[metric] ?? null;
    return {
      metric,
      value,
      limit,
      pass: Number.isFinite(value) && value <= limit,
    };
  });
}
