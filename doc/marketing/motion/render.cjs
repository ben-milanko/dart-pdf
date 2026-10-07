#!/usr/bin/env node
// Renders dartpdf-sting.html frame-exactly in headless Chromium.
//
//   node render.cjs --out build/sting.mp4 [--audio build/soundtrack.wav] [--fps 60]
//   node render.cjs --stills 3.5,8.6,18.9 --outdir build/stills
//   node render.cjs --cues build/cues.json      (cue sheet for soundtrack.py)
//   add --variant app to any of these for the end-user cut
//
// Needs playwright (global install is fine: NODE_PATH=$(npm root -g)) and
// ffmpeg on PATH for video output.
'use strict';
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
const { chromium } = require('playwright');

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => {
    if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : true]);
    return acc;
  }, []),
);
const html = 'file://' + path.resolve(__dirname, 'dartpdf-sting.html') + '?play=0' +
  (args.variant ? '&variant=' + args.variant : '');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
  await page.goto(html);
  await page.waitForFunction(() => window.ready === true);
  const { duration, offset, fps, cues, music } = await page.evaluate(() => ({
    duration: window.DURATION, offset: window.OFFSET, fps: window.FPS, cues: window.CUES, music: window.MUSIC,
  }));
  const clip = { x: 0, y: 0, width: 1920, height: 1080 };

  if (args.cues) {
    fs.mkdirSync(path.dirname(path.resolve(args.cues)), { recursive: true });
    fs.writeFileSync(args.cues, JSON.stringify({ duration, offset, cues, music }, null, 2));
    console.log('wrote', args.cues);
  }

  if (args.stills) {
    const dir = args.outdir || 'stills';
    fs.mkdirSync(dir, { recursive: true });
    for (const t of String(args.stills).split(',').map(Number)) {
      await page.evaluate(t => window.renderAt(t), t);
      await page.screenshot({ path: path.join(dir, `t${t.toFixed(2)}.png`), clip });
    }
    console.log('stills in', dir);
  }

  if (args.out) {
    const rate = Number(args.fps || fps);
    const frames = Math.round(duration * rate);
    const ff = [
      '-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(rate), '-i', '-',
    ];
    if (args.audio) ff.push('-i', args.audio);
    ff.push('-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p',
      '-profile:v', 'high', '-movflags', '+faststart');
    if (args.audio) ff.push('-c:a', 'aac', '-b:a', '256k', '-shortest');
    ff.push(args.out);
    fs.mkdirSync(path.dirname(path.resolve(args.out)), { recursive: true });
    const enc = spawn('ffmpeg', ff, { stdio: ['pipe', 'inherit', 'inherit'] });
    const started = Date.now();
    for (let i = 0; i < frames; i++) {
      await page.evaluate(t => window.renderAt(t), i / rate);
      const png = await page.screenshot({ clip, type: 'png' });
      if (!enc.stdin.write(png)) await new Promise(r => enc.stdin.once('drain', r));
      if (i % 120 === 0) console.log(`frame ${i}/${frames} (${((Date.now() - started) / 1000).toFixed(0)}s)`);
    }
    enc.stdin.end();
    await new Promise((res, rej) => enc.on('close', c => (c === 0 ? res() : rej(new Error('ffmpeg exit ' + c)))));
    console.log('wrote', args.out);
  }
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
