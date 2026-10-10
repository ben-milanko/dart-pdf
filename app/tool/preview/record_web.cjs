// Records the preview tour from the web build, for drafting the App Store
// preview without a Mac. The store upload itself comes from the iOS simulator
// (record_ios.sh); this exists so the tour and the composition can be iterated
// anywhere Chromium runs.
//
//   fvm flutter build web -t tool/preview_main.dart --no-tree-shake-icons
//   npx http-server build/web -p 8765 &
//   NODE_PATH=$(npm root -g) node tool/preview/record_web.cjs \
//       --url http://localhost:8765/ --out build/preview-web
//
// Writes <out>/raw.mp4 (the screen, 1320x2868 like a 6.9" iPhone) and
// <out>/tour.log (the tour's markers) for compose_preview.py. A software-GL
// headless browser draws far slower than a device, which costs only time: the
// tour runs on frame time and the composer places every frame by the number
// it carries, so every frame the page sends is kept as it came.
const { chromium } = require('playwright');
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => {
    if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1]]);
    return acc;
  }, []),
);
const url = args.url || 'http://localhost:8765/';
const out = path.resolve(args.out || 'build/preview-web');
const frames = path.join(out, 'frames');
fs.rmSync(frames, { recursive: true, force: true });
fs.mkdirSync(frames, { recursive: true });

(async () => {
  const browser = await chromium.launch({
    args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'],
  });
  const context = await browser.newContext({
    viewport: { width: 440, height: 956 },
    deviceScaleFactor: 3,
    isMobile: true,
    hasTouch: true,
    locale: 'en-US',
  });
  const page = await context.newPage();
  const cdp = await context.newCDPSession(page);
  const shots = [];
  let t0 = null;
  const log = [];
  let done;
  const finished = new Promise((resolve) => (done = resolve));

  cdp.on('Page.screencastFrame', async ({ data, metadata, sessionId }) => {
    const t = metadata.timestamp;
    if (t0 === null) t0 = t;
    const file = path.join(frames, `${String(shots.length).padStart(6, '0')}.jpg`);
    fs.writeFileSync(file, Buffer.from(data, 'base64'));
    shots.push({ file, t: t - t0 });
    await cdp.send('Page.screencastFrameAck', { sessionId }).catch(() => {});
  });
  page.on('console', (m) => {
    const text = m.text();
    if (!text.includes('@@PREVIEW')) return;
    const now = Date.now() / 1000;
    log.push({ now, text });
    if (text.includes('@@PREVIEW_DONE@@')) done();
  });
  page.on('pageerror', (e) => console.error('page error:', e.message));

  await page.goto(url);
  await cdp.send('Page.startScreencast', {
    format: 'jpeg',
    quality: 92,
    maxWidth: 1320,
    maxHeight: 2868,
    everyNthFrame: 1,
  });
  await Promise.race([finished, new Promise((r) => setTimeout(r, 240000))]);
  await page.waitForTimeout(500);
  await cdp.send('Page.stopScreencast');
  // The screencast only sends a frame when the page changes, so a static end
  // would otherwise be missing: hold the last frame until recording stopped.
  const stopped = Date.now() / 1000 - (t0 ?? 0);
  await browser.close();

  // Screencast timestamps are wall-clock seconds, like the console times, so
  // the first frame anchors both (video time 0).
  const lines = log.map(({ now, text }) => `${(now - t0).toFixed(3)} ${text}`);
  fs.writeFileSync(path.join(out, 'tour.log'), lines.join('\n') + '\n');

  // Every frame, in order, at its own duration (the composer places frames by
  // their stamps, so none may be dropped or merged).
  const list = shots
    .map((s, i) => {
      const next = shots[i + 1] ? shots[i + 1].t : Math.max(stopped, s.t + 1 / 30);
      return `file '${s.file}'\nduration ${(next - s.t).toFixed(4)}`;
    })
    .join('\n');
  fs.writeFileSync(path.join(out, 'frames.txt'), list + `\nfile '${shots.at(-1).file}'\n`);
  execFileSync('ffmpeg', [
    '-y', '-v', 'error', '-f', 'concat', '-safe', '0', '-i', path.join(out, 'frames.txt'),
    '-fps_mode', 'passthrough', '-vf', 'scale=1320:2868:flags=lanczos,format=yuv420p',
    '-video_track_timescale', '90000', '-c:v', 'libx264', '-crf', '14', '-preset', 'fast',
    path.join(out, 'raw.mp4'),
  ]);
  console.log(`wrote ${out}/raw.mp4 (${shots.length} frames) and tour.log`);
})();
