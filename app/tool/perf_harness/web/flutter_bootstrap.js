{{flutter_js}}
{{flutter_build_config}}

// The worker-owned PDF surface does not use SkWasm for page pixels. Keep the
// production-like multithreaded engine as the default, but expose Flutter's
// smaller single-threaded Wimp runtime for a controlled cold-bootstrap A/B:
// `?wimp=1`. One bundle can therefore compare startup tail and UI frame pacing
// without a rebuild or a hidden benchmark-only default.
const perfQuery = new URLSearchParams(window.location.search);
const preloadPageZero = perfQuery.get('scenario') === 'external' &&
  ['1', 'true'].includes(perfQuery.get('domSurface')) &&
  perfQuery.get('source') !== 'range' &&
  typeof Worker !== 'undefined' &&
  typeof HTMLCanvasElement.prototype.transferControlToOffscreen === 'function';

if (preloadPageZero) {
  const pdfBytes = fetch('/perf.pdf', {cache: 'no-store'}).then((response) => {
    if (!response.ok) throw new Error(`GET /perf.pdf -> ${response.status}`);
    return response.arrayBuffer();
  });
  // Dart consumes this original buffer, while the worker receives a clone.
  // The competitive full-file tier therefore still performs one PDF request.
  globalThis.__perfPdfBytesPromise = pdfBytes;
  globalThis.__perfPreloadReadyAt = -1;
  globalThis.__perfPreloadActive = false;

  void (async () => {
    let worker;
    let canvas;
    let overlay;
    const release = () => {
      overlay?.remove();
      worker?.terminate();
      globalThis.__perfPreloadActive = false;
    };
    globalThis.__perfPreloadRelease = release;
    try {
      const bytes = await pdfBytes;
      worker = new Worker('pdf_render_worker.dart.js');
      const nextMessage = (kind) => new Promise((resolve, reject) => {
        const onMessage = (event) => {
          if (event.data?.kind !== kind) return;
          worker.removeEventListener('message', onMessage);
          resolve(event.data);
        };
        worker.addEventListener('message', onMessage);
        worker.addEventListener('error', reject, {once: true});
      });
      const readyPromise = nextMessage('ready');
      const workerBytes = bytes.slice(0);
      worker.postMessage({
        kind: 'init',
        bytes: workerBytes,
        shared: false,
        timings: true,
        reuseTranscripts: true,
      }, [workerBytes]);
      const ready = await readyPromise;
      if (!(ready.pageWidth > 0) || !(ready.pageHeight > 0)) {
        throw new Error('render worker did not provide page-zero geometry');
      }

      const rotation = Number(ready.pageRotation ?? 0);
      const swapsAxes = rotation === 90 || rotation === 270;
      const pageWidth = swapsAxes ? ready.pageHeight : ready.pageWidth;
      const pageHeight = swapsAxes ? ready.pageWidth : ready.pageHeight;
      const fit = Math.min(
        window.innerWidth / pageWidth,
        window.innerHeight / pageHeight,
      );
      const cssWidth = Math.max(1, Math.round(pageWidth * fit));
      const cssHeight = Math.max(1, Math.round(pageHeight * fit));
      const pixelRatio = window.devicePixelRatio || 1;

      overlay = document.createElement('div');
      overlay.id = 'pdf-page-zero-preload-overlay';
      Object.assign(overlay.style, {
        position: 'fixed',
        inset: '0',
        overflow: 'hidden',
        visibility: 'hidden',
        pointerEvents: 'none',
        background: '#404347',
        zIndex: '2147483647',
      });
      canvas = document.createElement('canvas');
      canvas.id = 'pdf-page-zero-preload';
      canvas.width = Math.max(1, Math.round(cssWidth * pixelRatio));
      canvas.height = Math.max(1, Math.round(cssHeight * pixelRatio));
      Object.assign(canvas.style, {
        position: 'fixed',
        left: `${Math.round((window.innerWidth - cssWidth) / 2)}px`,
        top: `${Math.round((window.innerHeight - cssHeight) / 2)}px`,
        width: `${cssWidth}px`,
        height: `${cssHeight}px`,
        visibility: 'hidden',
        pointerEvents: 'none',
      });
      document.body.style.margin = '0';
      document.body.style.background = '#404347';
      overlay.append(canvas);
      document.body.append(overlay);
      const surface = canvas.transferControlToOffscreen();
      const resultPromise = nextMessage('result');
      worker.postMessage({
        kind: 'surface',
        id: 1,
        page: 0,
        annotations: true,
        surfaceId: 1,
        deviceWidth: canvas.width,
        deviceHeight: canvas.height,
        pageColor: 0xffffffff,
        rotation,
        surface,
      }, [surface]);
      const result = await resultPromise;
      const painted = result.buffer && new Uint8Array(result.buffer)[0] === 1;
      if (!painted) throw new Error(result.error || 'page-zero surface declined');
      canvas.style.visibility = 'visible';
      overlay.style.visibility = 'visible';
      globalThis.__perfPreloadActive = true;
      // Keep the worker alive until handoff. Terminating immediately after its
      // postMessage can leave transferred-canvas presentation pending behind
      // the concurrent SkWasm bootstrap. Two animation frames prove that the
      // visible DOM surface has crossed the browser presentation boundary.
      await new Promise((resolve) => requestAnimationFrame(
        () => requestAnimationFrame(resolve),
      ));
      globalThis.__perfPreloadReadyAt = performance.timeOrigin + performance.now();
      console.log(
        `[perf.preload] page-zero surface ready ` +
        `at=${globalThis.__perfPreloadReadyAt}`,
      );
    } catch (error) {
      globalThis.__perfPreloadError = String(error?.stack || error);
      release();
      console.warn('[perf.preload] declined', error);
    }
  })();
}
const hasSkwasm = _flutter.buildConfig.builds.some(
  (build) => build.renderer === 'skwasm',
);
_flutter.loader.load({
  config: {
    renderer: hasSkwasm ? 'skwasm' : 'canvaskit',
    enableWimp: perfQuery.get('wimp') === '1',
  },
});
