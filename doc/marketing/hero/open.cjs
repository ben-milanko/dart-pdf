const { chromium, devices } = require('playwright');
(async () => {
  const [,, out, w, h, dpr, mobile, ...actions] = process.argv;
  const b = await chromium.launch({args:['--use-gl=swiftshader','--enable-unsafe-swiftshader']});
  const ctx = await b.newContext({ viewport: { width: +w, height: +h }, deviceScaleFactor: +dpr,
     isMobile: mobile==='1', hasTouch: mobile==='1' });
  const p = await ctx.newPage();
  await p.goto('http://localhost:8765/');
  await p.waitForTimeout(+(process.env.BOOT||8000));
  const fc = p.waitForEvent('filechooser', {timeout: 15000});
  // click "Open a PDF" - centered button left of center
  const [ox, oy] = (process.env.OPEN||'').split(',').map(Number);
  await p.mouse.click(ox, oy);
  (await fc).setFiles(process.env.PDF);
  await p.waitForTimeout(7000);
  for (const a of actions) {
    const [k, x, y] = a.split(':');
    if (k==='click') { await p.mouse.click(+x, +y); await p.waitForTimeout(1500); }
    if (k==='wait') await p.waitForTimeout(+x);
    if (k==='shot') await p.screenshot({ path: x });
    if (k==='key') { await p.keyboard.press(x); await p.waitForTimeout(800); }
  }
  await p.screenshot({ path: out });
  await b.close();
})();
