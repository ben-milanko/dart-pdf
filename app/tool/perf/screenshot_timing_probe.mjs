#!/usr/bin/env node
// Diagnostic for the timestamp semantics of Chrome's Page.captureScreenshot.
//
// The parity harness observes SkWasm through full compositor screenshots. CDP
// returns only after encoding, but does not expose the instant at which pixels
// were sampled. This probe changes a transferred OffscreenCanvas while a
// screenshot request is in flight and reports whether the result contains the
// old or new frame. It is intentionally separate from the benchmark metrics.

import { existsSync } from 'node:fs';
import { performance } from 'node:perf_hooks';

import puppeteer from 'puppeteer-core';

import { digest } from './competitive_common.mjs';

const chromeCandidates = [
  process.env.PERF_CHROME,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/usr/bin/google-chrome',
  '/usr/bin/google-chrome-stable',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
].filter(Boolean);
const chromePath = chromeCandidates.find(existsSync);
if (!chromePath) throw new Error('Chrome/Chromium not found; set PERF_CHROME');

const viewport = { width: 1400, height: 1000 };
const captureScale = Number(process.env.PERF_SCREENSHOT_PROBE_SCALE ?? 1);
const fromSurface = process.env.PERF_SCREENSHOT_PROBE_FROM_SURFACE !== 'false';
const screenshotOptions = {
  type: 'jpeg',
  quality: 20,
  optimizeForSpeed: true,
  fromSurface,
  clip: {
    x: 0,
    y: 0,
    width: viewport.width,
    height: viewport.height,
    scale: captureScale,
  },
};

const browser = await puppeteer.launch({
  executablePath: chromePath,
  headless: true,
  defaultViewport: viewport,
  args: [
    '--no-sandbox',
    '--disable-dev-shm-usage',
    '--disable-background-networking',
    '--disable-component-update',
    '--no-first-run',
    `--window-size=${viewport.width},${viewport.height}`,
  ],
});

try {
  const page = await browser.newPage();
  await page.setContent(`<!doctype html>
    <style>html,body,canvas{margin:0;width:100%;height:100%;display:block}</style>
    <canvas id="surface" width="1400" height="1000"></canvas>
    <script>
      const source = ` + '`' + `
        let context;
        function paint(phase) {
          for (let y = 0; y < 20; y++) {
            for (let x = 0; x < 28; x++) {
              const seed = (x * 41 + y * 67 + phase * 103) & 255;
              context.fillStyle = phase === 0
                ? 'rgb(' + seed + ',' + ((seed * 3) & 255) + ',32)'
                : 'rgb(24,' + ((seed * 5) & 255) + ',' + seed + ')';
              context.fillRect(x * 50, y * 50, 50, 50);
            }
          }
        }
        onmessage = ({data}) => {
          if (data.canvas) {
            context = data.canvas.getContext('2d');
            paint(0);
            postMessage({kind: 'painted', phase: 0, at: performance.now()});
          } else if (data.kind === 'paint') {
            setTimeout(() => {
              paint(data.phase);
              postMessage({kind: 'painted', phase: data.phase,
                at: performance.now(), token: data.token});
            }, data.delay);
          }
        };
      ` + '`' + `;
      const worker = new Worker(URL.createObjectURL(
        new Blob([source], {type: 'text/javascript'})));
      const canvas = document.querySelector('#surface');
      const offscreen = canvas.transferControlToOffscreen();
      const state = {events: [], waiters: new Map(), token: 0};
      worker.onmessage = ({data}) => {
        state.events.push(data);
        const waiter = state.waiters.get(data.token);
        if (waiter) {
          state.waiters.delete(data.token);
          waiter(data);
        }
      };
      worker.postMessage({canvas: offscreen}, [offscreen]);
      globalThis.probe = {
        state,
        paint(phase, delay = 0) {
          const token = ++state.token;
          const promise = new Promise(resolve => state.waiters.set(token, resolve));
          worker.postMessage({kind: 'paint', phase, delay, token});
          return promise;
        },
      };
    </script>`);

  const paint = async (phase, delay = 0) => {
    await page.evaluate(
      ([value, wait]) => globalThis.probe.paint(value, wait),
      [phase, delay],
    );
    await page.evaluate(() => new Promise((resolve) =>
      requestAnimationFrame(() => requestAnimationFrame(resolve))));
  };
  const capture = async () => {
    const start = performance.now();
    const bytes = await page.screenshot(screenshotOptions);
    const end = performance.now();
    return { hash: digest(bytes), durationMs: end - start };
  };

  await paint(0);
  const oldReference = await capture();
  await paint(1);
  const newReference = await capture();

  const delays = String(process.env.PERF_SCREENSHOT_PROBE_DELAYS ??
      '20,24,28,30,32,34,36,40,48')
    .split(',')
    .map(Number)
    .filter(Number.isFinite);
  const repeats = Number(process.env.PERF_SCREENSHOT_PROBE_REPEATS ?? 5);
  const trials = [];
  for (const delayMs of delays) {
    for (let repeat = 0; repeat < repeats; repeat++) {
      await paint(0);
      const pendingPaint = page.evaluate(
        (delay) => globalThis.probe.paint(1, delay),
        delayMs,
      );
      const captureStart = performance.now();
      const bytes = await page.screenshot(screenshotOptions);
      const captureEnd = performance.now();
      const paintEvent = await pendingPaint;
      const hash = digest(bytes);
      trials.push({
        delayMs,
        repeat,
        captureDurationMs: captureEnd - captureStart,
        result: hash === oldReference.hash
          ? 'old'
          : hash === newReference.hash
            ? 'new'
            : 'intermediate',
        workerPaintAtMs: paintEvent.at,
      });
    }
  }

  const delayResults = delays.map((delayMs) => {
    const results = trials
      .filter((trial) => trial.delayMs === delayMs)
      .map((trial) => trial.result);
    return {
      delayMs,
      results,
      consistentlyOld: results.length === repeats &&
        results.every((result) => result === 'old'),
    };
  });
  const recommendedSampleDelayMs = delayResults.find((entry, index) =>
    entry.consistentlyOld &&
      delayResults.slice(index).every((later) => later.consistentlyOld),
  )?.delayMs ?? null;

  console.log(JSON.stringify({
    chrome: await browser.version(),
    viewport,
    captureScale,
    fromSurface,
    oldReference,
    newReference,
    recommendedSampleDelayMs,
    delayResults,
    trials,
  }, null, 2));
} finally {
  await browser.close();
}
