import 'dart:convert';
import 'dart:collection';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_cos/perf.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
import 'package:web/web.dart' as web;

import 'region_replay_index.dart';
import 'render_worker_transcript_cache.dart';
import 'web_canvas_device.dart';
import 'web_surface_profile.dart';

// Cached smaller backings per live surface. Eight megapixels in total bounds
// each surface to 32 MiB RGBA; A1 2x canvases (~16 MP / 64 MiB) deliberately
// repaint instead. The LRU targets repeated zoom legs, where a direct-size
// render is needed for Canvas2D hairline correctness but replaying 270k
// diagram commands or decoding a scanned page again would miss the PDFium
// tail-latency budget.
const _pageSurfaceBitmapMaxPixels = 8 * 1024 * 1024;

class _PageSurfaceBitmapKey {
  const _PageSurfaceBitmapKey(
    this.pageIndex,
    this.annotations,
    this.width,
    this.height,
    this.pageColor,
    this.rotation,
  );

  final int pageIndex;
  final bool annotations;
  final int width;
  final int height;
  final int pageColor;
  final int? rotation;

  @override
  bool operator ==(Object other) =>
      other is _PageSurfaceBitmapKey &&
      other.pageIndex == pageIndex &&
      other.annotations == annotations &&
      other.width == width &&
      other.height == height &&
      other.pageColor == pageColor &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(
        pageIndex,
        annotations,
        width,
        height,
        pageColor,
        rotation,
      );
}

class _PageSurfaceBitmapCache {
  final _entries = <_PageSurfaceBitmapKey, web.ImageBitmap>{};
  var _pixels = 0;

  web.ImageBitmap? lookup(_PageSurfaceBitmapKey key) {
    final bitmap = _entries.remove(key);
    if (bitmap == null) return null;
    // Reinsert so the map's iteration order remains least-recently-used first.
    _entries[key] = bitmap;
    return bitmap;
  }

  void store(_PageSurfaceBitmapKey key, web.ImageBitmap bitmap) {
    final replaced = _entries.remove(key);
    if (replaced != null) {
      _pixels -= key.width * key.height;
      replaced.close();
    }
    _entries[key] = bitmap;
    _pixels += key.width * key.height;
    while (_pixels > _pageSurfaceBitmapMaxPixels && _entries.length > 1) {
      final oldestKey = _entries.keys.first;
      final oldest = _entries.remove(oldestKey)!;
      _pixels -= oldestKey.width * oldestKey.height;
      oldest.close();
    }
  }

  void dispose() {
    for (final bitmap in _entries.values) {
      bitmap.close();
    }
    _entries.clear();
    _pixels = 0;
  }
}

bool _presentPageSurfaceBitmap(
  web.OffscreenCanvas surface,
  web.ImageBitmap bitmap,
  int width,
  int height,
) {
  surface
    ..width = width
    ..height = height;
  final context =
      surface.getContext('2d') as web.OffscreenCanvasRenderingContext2D?;
  if (context == null) return false;
  context
    ..resetTransform()
    ..globalAlpha = 1
    ..globalCompositeOperation = 'copy'
    ..drawImage(bitmap, 0, 0)
    ..globalCompositeOperation = 'source-over';
  return true;
}

/// Runs the render worker inside a dedicated Web Worker.
///
/// dart_pdf_editor ships a prebuilt worker as a Flutter package asset, so most
/// consuming apps do not call this directly. Apps that want to self-host a
/// custom worker can still compile a tiny worker script that calls this:
///
/// ```dart
/// // web/pdf_render_worker.dart
/// import 'package:dart_pdf_editor/render_worker_web.dart';
/// void main() => runPdfRenderWorker();
/// ```
///
/// compiled with `dart compile js web/pdf_render_worker.dart -o
/// web/pdf_render_worker.dart.js` and served alongside the app; set
/// `pdfRenderWorkerScriptUrl = 'pdf_render_worker.dart.js'` before opening a
/// viewer to use that custom script. See `doc/render_worker_web.md` for the
/// full wiring.
///
/// Protocol (mirrors the native isolate backend):
/// - `{kind:'init', bytes:ArrayBuffer|SharedArrayBuffer, shared}` → opens the
///   document, replies `{kind:'ready', shared}`.
/// - `{kind:'record', id, page, annotations}` → replies `{kind:'result', id,
///   buffer:ArrayBuffer|null}` (null = the page can't be offloaded; the main
///   thread renders it locally).
/// - `{kind:'cancel', id}` → cancels only the matching active request, so a
///   late message cannot abort its successor; a match abandons the interpreter
///   walk early and replies with `buffer:null`.
/// - `{kind:'bin', id, page, annotations, m0..m5, deviceWidth, deviceHeight,
///   pixelRatio, slugGlyphs}` → replies with an encoded `StripPlan` in the same result
///   shape (null = bin locally).
/// - `{kind:'detail', id, page, annotations, m0..m5, deviceWidth, deviceHeight,
///   pixelRatio, regionLeft..regionTop}` → replies with transferable command
///   and plan buffers produced by one cancellable worker job.
void runPdfRenderWorker() {
  final scope = globalContext as web.DedicatedWorkerGlobalScope;
  PdfDocument? document;
  // One decoded-image cache per open document. A worker records the same page
  // several times in a scroll (vector-first, full, prerender warm, thumbnail)
  // and each record re-decoded every image; #451's device trace showed one page
  // paying ~900ms of pure-Dart CMYK decode three times. Reuse is exact-match on
  // (stream, target size), so it cannot change what a record renders.
  var imageCache = PdfImageDecodeCache();
  var flateSampleCache = _BrowserFlateSampleCache();
  var reuseTranscripts = true;
  var collectTimings = false;
  PdfCancellationToken? activeToken;
  int? activeRequestId;
  final transcriptCache = PdfWorkerTranscriptCache();
  final pageSurfaces = <int, web.OffscreenCanvas>{};
  final pageSurfaceBitmaps = <int, _PageSurfaceBitmapCache>{};

  // The handler MUST stay synchronous (return void): `.toJS` cannot convert a
  // Future-returning function, so an `async` handler fails `dart compile js`
  // ("invalid types in its function signature: Future<Null> Function(...)").
  // The cancellable record below therefore runs in a fire-and-forget inner
  // async closure instead of making the handler itself async.
  scope.onmessage = ((web.MessageEvent event) {
    final data = event.data as JSObject?;
    if (data == null) return;
    final kind = (data.getProperty('kind'.toJS) as JSString?)?.toDart;

    if (kind == 'init') {
      // Extract AND open inside the try: a malformed transfer (the cast or the
      // ArrayBuffer view can throw on some hosts) must NOT skip the 'ready'
      // reply below, or the main thread waits on it forever. A null document
      // simply declines every page to a local render.
      var shared = false;
      Stopwatch? openClock;
      try {
        shared =
            (data.getProperty('shared'.toJS) as JSBoolean?)?.toDart ?? false;
        reuseTranscripts =
            (data.getProperty('reuseTranscripts'.toJS) as JSBoolean?)?.toDart ??
                true;
        collectTimings =
            (data.getProperty('timings'.toJS) as JSBoolean?)?.toDart ?? false;
        // Light up the COS-layer facade alongside the trace timings; each
        // result attaches (and resets) its per-job snapshot.
        PdfPerf.enabled = collectTimings;
        if (collectTimings) openClock = Stopwatch()..start();
        final buffer = data.getProperty('bytes'.toJS) as JSObject;
        final bytes = shared
            ? _jsUint8View(buffer).toDart
            : (buffer as JSArrayBuffer).toDart.asUint8List();
        document = PdfDocument.open(bytes);
        imageCache = PdfImageDecodeCache(); // new document, new streams
        flateSampleCache = _BrowserFlateSampleCache();
        for (final cached in pageSurfaceBitmaps.values) {
          cached.dispose();
        }
        pageSurfaceBitmaps.clear();
      } catch (_) {
        document = null; // bad transfer / broken document → local renders
      }
      // ALWAYS reply ready, even on failure, so the client never hangs.
      openClock?.stop();
      final ready = JSObject()
        ..setProperty('kind'.toJS, 'ready'.toJS)
        ..setProperty('shared'.toJS, shared.toJS);
      // A bootstrap client can paint page zero before Flutter starts only if
      // it can size the DOM canvas without opening the PDF a second time on
      // the main thread. Keep this optional metadata on the existing ready
      // envelope; established clients ignore unknown fields.
      final readyDocument = document;
      if (readyDocument != null) {
        try {
          final pageCount = readyDocument.pageCount;
          ready.setProperty('pageCount'.toJS, pageCount.toJS);
          if (pageCount > 0) {
            final page = readyDocument.page(0);
            ready
              ..setProperty('pageWidth'.toJS, page.cropBox.width.toJS)
              ..setProperty('pageHeight'.toJS, page.cropBox.height.toJS)
              ..setProperty('pageRotation'.toJS, page.rotation.toJS);
          }
        } catch (_) {
          // Metadata is an optimization only. A malformed page tree still
          // reaches the normal ready/fallback path rather than wedging init.
        }
      }
      // Report the browser-codec capability so a worker that will decline every
      // image (no OffscreenCanvas, etc.) is visible up front rather than
      // discovered as an unexplained main-thread decode cost. See #458.
      final missing = _browserImageDecodeMissing();
      ready.setProperty('browserImageDecode'.toJS, missing.isEmpty.toJS);
      // The worker ships as its own `dart compile js` bundle, separate from
      // the app's main.dart.js, so the app being current is no evidence that
      // the worker is. Report the decode-reuse capability (#451): a worker
      // built before it simply omits the field, which is the only way a trace
      // can distinguish "reuse found nothing" from "this worker cannot reuse".
      ready.setProperty('imageDecodeCache'.toJS, true.toJS);
      if (missing.isNotEmpty) {
        ready.setProperty(
          'browserImageDecodeMissing'.toJS,
          missing.join('+').toJS,
        );
      }
      if (openClock != null) {
        ready.setProperty('openUs'.toJS, openClock.elapsedMicroseconds.toJS);
      }
      scope.postMessage(ready);
      return;
    }

    if (kind == 'cancel') {
      final id = (data.getProperty('id'.toJS) as JSNumber?)?.toDartInt;
      if (id != null && id == activeRequestId) {
        activeToken?.cancelled = true;
      } else if (id != null) {
        final ignored = JSObject()
          ..setProperty('kind'.toJS, 'cancelIgnored'.toJS)
          ..setProperty('targetId'.toJS, id.toJS);
        final active = activeRequestId;
        if (active != null) {
          ignored.setProperty('activeId'.toJS, active.toJS);
        }
        scope.postMessage(ignored);
      }
      return;
    }

    if (kind == 'releaseSurface') {
      final surfaceId =
          (data.getProperty('surfaceId'.toJS) as JSNumber?)?.toDartInt;
      if (surfaceId != null) {
        pageSurfaces.remove(surfaceId);
        pageSurfaceBitmaps.remove(surfaceId)?.dispose();
      }
      return;
    }

    if (kind == 'surface') {
      final id = (data.getProperty('id'.toJS) as JSNumber).toDartInt;
      final pageIndex = (data.getProperty('page'.toJS) as JSNumber).toDartInt;
      final annotations =
          (data.getProperty('annotations'.toJS) as JSBoolean).toDart;
      final surfaceId =
          (data.getProperty('surfaceId'.toJS) as JSNumber).toDartInt;
      final width =
          (data.getProperty('deviceWidth'.toJS) as JSNumber).toDartInt;
      final height =
          (data.getProperty('deviceHeight'.toJS) as JSNumber).toDartInt;
      final pageColor =
          (data.getProperty('pageColor'.toJS) as JSNumber).toDartInt;
      final regionLeft =
          (data.getProperty('regionLeft'.toJS) as JSNumber?)?.toDartDouble;
      final regionTop =
          (data.getProperty('regionTop'.toJS) as JSNumber?)?.toDartDouble;
      final regionRight =
          (data.getProperty('regionRight'.toJS) as JSNumber?)?.toDartDouble;
      final regionBottom =
          (data.getProperty('regionBottom'.toJS) as JSNumber?)?.toDartDouble;
      final surfacePixelRatio =
          (data.getProperty('pixelRatio'.toJS) as JSNumber?)?.toDartDouble;
      final surfaceRegion = regionLeft != null &&
              regionTop != null &&
              regionRight != null &&
              regionBottom != null &&
              surfacePixelRatio != null
          ? (
              left: regionLeft,
              top: regionTop,
              right: regionRight,
              bottom: regionBottom,
              pixelRatio: surfacePixelRatio,
            )
          : null;
      final rotation =
          (data.getProperty('rotation'.toJS) as JSNumber?)?.toDartInt;
      final supplied = data.getProperty('surface'.toJS);
      if (supplied != null) {
        pageSurfaces[surfaceId] = supplied as web.OffscreenCanvas;
      }

      final token = PdfCancellationToken();
      activeToken = token;
      activeRequestId = id;
      () async {
        final timings = collectTimings ? PdfWorkerPhaseTimings() : null;
        final workerClock = collectTimings ? (Stopwatch()..start()) : null;
        var painted = false;
        String? error;
        try {
          final doc = document;
          final surface = pageSurfaces[surfaceId];
          if (doc != null &&
              surface != null &&
              pageIndex >= 0 &&
              pageIndex < doc.pageCount) {
            final cacheKey = _PageSurfaceBitmapKey(
              pageIndex,
              annotations,
              width,
              height,
              pageColor,
              rotation,
            );
            final cached = surfaceRegion == null
                ? pageSurfaceBitmaps[surfaceId]?.lookup(cacheKey)
                : null;
            if (cached != null) {
              painted = _presentPageSurfaceBitmap(
                surface,
                cached,
                width,
                height,
              );
            }
            if (!painted) {
              final transcript = await transcriptCache.transcriptFor(
                doc,
                pageIndex,
                annotations,
                token,
                yieldInterval: 4096,
                timings: timings,
              );
              if (transcript != null && !token.cancelled) {
                var commands = transcript.sourceCommands;
                final profile = pdfBrowserPageSurfaceProfile(
                  commands,
                  allowUndecodedImages: true,
                );
                if (profile != null) {
                  Map<Object, web.CanvasImageSource> browserImages = const {};
                  var browserFrames = const <web.VideoFrame>[];
                  if (profile.needsImageDecode) {
                    final decodeClock =
                        timings == null ? null : (Stopwatch()..start());
                    final tally =
                        timings == null ? null : _BrowserDecodeTally();
                    final page = doc.page(pageIndex);
                    final swap = (rotation ?? page.rotation) == 90 ||
                        (rotation ?? page.rotation) == 270;
                    final pageWidth =
                        swap ? page.cropBox.height : page.cropBox.width;
                    final pageHeight =
                        swap ? page.cropBox.width : page.cropBox.height;
                    final ratio = surfaceRegion?.pixelRatio ??
                        (pageWidth > 0 && pageHeight > 0
                            ? (width / pageWidth + height / pageHeight) / 2
                            : null);
                    final grayFrames = await _browserGrayFlateFrames(
                      doc.cos,
                      commands,
                      token,
                      flateSampleCache,
                      tally,
                      // Full-page VideoFrame presentation past ~2x caused a
                      // deferred compositor tail because the destination
                      // canvas itself was enormous. A region surface is
                      // viewport-sized, so it keeps the zero-copy browser
                      // frame at deep zoom.
                      maxPixelRatio: surfaceRegion == null ? ratio : 2,
                    );
                    if (grayFrames == null) {
                      commands = await _withBrowserDecodedImages(
                        doc.cos,
                        imageCache,
                        commands,
                        token,
                        tally,
                        maxImagePixelRatio: ratio,
                        flateSampleCache: flateSampleCache,
                      );
                    } else {
                      browserImages = grayFrames.images;
                      browserFrames = grayFrames.frames;
                    }
                    if (decodeClock != null) {
                      decodeClock.stop();
                      timings!.decodeUs += decodeClock.elapsedMicroseconds;
                      timings.imageDecodeSummary = grayFrames == null
                          ? tally!.format()
                          : 'videoGray=${grayFrames.frames.length}';
                    }
                  }
                  final cacheable = surfaceRegion == null &&
                      width * height <= _pageSurfaceBitmapMaxPixels;
                  final paintCanvas =
                      cacheable ? web.OffscreenCanvas(width, height) : surface;
                  try {
                    painted = paintPdfBrowserPageSurface(
                      canvas: paintCanvas,
                      page: doc.page(pageIndex),
                      commands: commands,
                      width: width,
                      height: height,
                      pageColor: pageColor,
                      rotation: rotation,
                      region: surfaceRegion,
                      commandsAreValidated:
                          browserImages.isNotEmpty || !profile.needsImageDecode,
                      browserImages: browserImages,
                    );
                    if (painted && cacheable) {
                      final bitmap = paintCanvas.transferToImageBitmap();
                      pageSurfaceBitmaps
                          .putIfAbsent(
                            surfaceId,
                            _PageSurfaceBitmapCache.new,
                          )
                          .store(cacheKey, bitmap);
                      painted = _presentPageSurfaceBitmap(
                        surface,
                        bitmap,
                        width,
                        height,
                      );
                    }
                  } finally {
                    for (final frame in browserFrames) {
                      frame.close();
                    }
                  }
                }
              }
            }
          }
        } on PdfCancelledException {
          painted = false;
        } catch (e, st) {
          painted = false;
          error = '$e\n$st';
        }
        if (identical(activeToken, token)) {
          activeToken = null;
          activeRequestId = null;
        }
        workerClock?.stop();
        _postResult(
          scope,
          id,
          token.cancelled ? null : Uint8List.fromList([painted ? 1 : 0]),
          error,
          timings,
          workerClock?.elapsedMicroseconds,
        );
      }();
      return;
    }

    if (kind == 'bin' || kind == 'detail') {
      final id = (data.getProperty('id'.toJS) as JSNumber).toDartInt;
      final page = (data.getProperty('page'.toJS) as JSNumber).toDartInt;
      final annotations =
          (data.getProperty('annotations'.toJS) as JSBoolean).toDart;
      final matrix = <double>[
        for (var i = 0; i < 6; i++)
          (data.getProperty('m$i'.toJS) as JSNumber).toDartDouble,
      ];
      final deviceWidth =
          (data.getProperty('deviceWidth'.toJS) as JSNumber).toDartInt;
      final deviceHeight =
          (data.getProperty('deviceHeight'.toJS) as JSNumber).toDartInt;
      final pixelRatio =
          (data.getProperty('pixelRatio'.toJS) as JSNumber).toDartDouble;
      final slugGlyphs =
          (data.getProperty('slugGlyphs'.toJS) as JSBoolean?)?.toDart ?? false;
      final token = PdfCancellationToken();
      activeToken = token;
      activeRequestId = id;
      () async {
        final timings = collectTimings ? PdfWorkerPhaseTimings() : null;
        final workerClock = collectTimings ? (Stopwatch()..start()) : null;
        Uint8List? out;
        Uint8List? detailPlan;
        String? error;
        final doc = document;
        try {
          if (doc != null) {
            if (kind == 'detail') {
              final region = PdfRect(
                (data.getProperty('regionLeft'.toJS) as JSNumber).toDartDouble,
                (data.getProperty('regionBottom'.toJS) as JSNumber)
                    .toDartDouble,
                (data.getProperty('regionRight'.toJS) as JSNumber).toDartDouble,
                (data.getProperty('regionTop'.toJS) as JSNumber).toDartDouble,
              );
              final detail = await _recordStripDetailAsync(
                doc,
                imageCache,
                transcriptCache,
                page,
                annotations,
                matrix,
                deviceWidth,
                deviceHeight,
                pixelRatio,
                region,
                token,
                timings: timings,
              );
              out = detail?.$1;
              detailPlan = detail?.$2;
            } else {
              out = await _binStripsAsync(
                doc,
                transcriptCache,
                page,
                annotations,
                matrix,
                deviceWidth,
                deviceHeight,
                pixelRatio,
                slugGlyphs,
                token,
                timings: timings,
              );
            }
          }
        } on PdfCancelledException {
          out = null;
        } catch (e, st) {
          out = null;
          error = '$e\n$st';
        }
        if (identical(activeToken, token)) {
          activeToken = null;
          activeRequestId = null;
        }
        workerClock?.stop();
        if (detailPlan == null) {
          _postResult(
            scope,
            id,
            out,
            error,
            timings,
            workerClock?.elapsedMicroseconds,
          );
        } else {
          _postDetailResult(
            scope,
            id,
            out!,
            detailPlan,
            timings,
            workerClock?.elapsedMicroseconds,
          );
        }
      }();
      return;
    }

    if (kind == 'regionIndex') {
      final id = (data.getProperty('id'.toJS) as JSNumber).toDartInt;
      final page = (data.getProperty('page'.toJS) as JSNumber).toDartInt;
      final annotations =
          (data.getProperty('annotations'.toJS) as JSBoolean).toDart;
      final maxCommands =
          (data.getProperty('maxCommands'.toJS) as JSNumber).toDartInt;
      final buildGrid =
          (data.getProperty('buildGrid'.toJS) as JSBoolean?)?.toDart ?? false;
      final token = PdfCancellationToken();
      activeToken = token;
      activeRequestId = id;
      () async {
        final timings = collectTimings ? PdfWorkerPhaseTimings() : null;
        final workerClock = collectTimings ? (Stopwatch()..start()) : null;
        Uint8List? out;
        String? error;
        final doc = document;
        try {
          if (doc != null) {
            out = await _buildRegionIndexAsync(
              doc,
              transcriptCache,
              page,
              annotations,
              maxCommands,
              buildGrid,
              token,
              timings: timings,
            );
          }
        } on PdfCancelledException {
          out = null;
        } catch (e, st) {
          out = null;
          error = '$e\n$st';
        }
        if (identical(activeToken, token)) {
          activeToken = null;
          activeRequestId = null;
        }
        workerClock?.stop();
        _postResult(
          scope,
          id,
          out,
          error,
          timings,
          workerClock?.elapsedMicroseconds,
        );
      }();
      return;
    }

    if (kind == 'extractText') {
      final id = (data.getProperty('id'.toJS) as JSNumber).toDartInt;
      final page = (data.getProperty('page'.toJS) as JSNumber).toDartInt;
      // Text extraction has no cancellation seam and runs synchronously; it
      // still lands off the UI thread here, which is the point (#396).
      activeToken = null;
      activeRequestId = id;
      () async {
        final timings = collectTimings ? PdfWorkerPhaseTimings() : null;
        final workerClock = collectTimings ? (Stopwatch()..start()) : null;
        Uint8List? out;
        String? error;
        final doc = document;
        try {
          if (doc != null && page >= 0 && page < doc.pageCount) {
            out = serializePageText(PdfTextExtractor.extract(doc, page));
          }
        } catch (e, st) {
          out = null;
          error = '$e\n$st';
        }
        if (activeRequestId == id) {
          activeToken = null;
          activeRequestId = null;
        }
        workerClock?.stop();
        _postResult(
          scope,
          id,
          out,
          error,
          timings,
          workerClock?.elapsedMicroseconds,
        );
      }();
      return;
    }

    if (kind != 'record') return;
    final id = (data.getProperty('id'.toJS) as JSNumber).toDartInt;
    final page = (data.getProperty('page'.toJS) as JSNumber).toDartInt;
    final annotations =
        (data.getProperty('annotations'.toJS) as JSBoolean).toDart;
    final imagePixelRatio =
        (data.getProperty('imageRatio'.toJS) as JSNumber?)?.toDartDouble;
    // Default true so an older client that doesn't send the flag still decodes.
    final decodeImages =
        (data.getProperty('decodeImages'.toJS) as JSBoolean?)?.toDart ?? true;
    final commandLimit =
        (data.getProperty('commandLimit'.toJS) as JSNumber?)?.toDartInt;
    final regionLeft =
        (data.getProperty('regionLeft'.toJS) as JSNumber?)?.toDartDouble;
    final regionBottom =
        (data.getProperty('regionBottom'.toJS) as JSNumber?)?.toDartDouble;
    final regionRight =
        (data.getProperty('regionRight'.toJS) as JSNumber?)?.toDartDouble;
    final regionTop =
        (data.getProperty('regionTop'.toJS) as JSNumber?)?.toDartDouble;
    final imageDecodeRegion = regionLeft != null &&
            regionBottom != null &&
            regionRight != null &&
            regionTop != null
        ? PdfRect(regionLeft, regionBottom, regionRight, regionTop)
        : null;
    final wantsPartials =
        (data.getProperty('wantsPartials'.toJS) as JSBoolean?)?.toDart ?? false;

    final token = PdfCancellationToken();
    activeToken = token;
    activeRequestId = id;
    // Progressive partials (#564): stream each interim linework prefix only while
    // this record still owns the slot and has not been cancelled, so a preempted
    // record stops immediately (the main thread drops any partial whose id no
    // longer matches its in-flight request anyway).
    void emitPartial(Uint8List bytes) {
      if (activeRequestId == id && !token.cancelled) {
        _postPartial(scope, id, bytes);
      }
    }

    // Fire-and-forget: launch the cancellable walk without awaiting it here, so
    // the message handler returns void (see the note above) while a subsequent
    // 'cancel' message can still flip token.cancelled mid-walk.
    () async {
      final timings = collectTimings ? PdfWorkerPhaseTimings() : null;
      final workerClock = collectTimings ? (Stopwatch()..start()) : null;
      Uint8List? out;
      String? error;
      final doc = document;
      try {
        if (doc != null) {
          out = await _recordPageAsync(
            doc,
            imageCache,
            transcriptCache,
            reuseTranscripts,
            page,
            annotations,
            imagePixelRatio,
            decodeImages,
            commandLimit,
            imageDecodeRegion,
            token,
            timings: timings,
            onPartial: wantsPartials ? emitPartial : null,
          );
        }
      } on PdfCancelledException {
        out = null;
      } catch (e, st) {
        out = null; // any failure → the main thread renders this page locally
        error = '$e\n$st';
      }
      // Only clear the active token if it is still ours - a newer record may
      // have replaced it while this one was running.
      if (identical(activeToken, token)) {
        activeToken = null;
        activeRequestId = null;
      }

      workerClock?.stop();
      _postResult(
        scope,
        id,
        out,
        error,
        timings,
        workerClock?.elapsedMicroseconds,
      );
    }();
  }).toJS;
}

void _postResult(
  web.DedicatedWorkerGlobalScope scope,
  int id,
  Uint8List? out,
  String? error,
  PdfWorkerPhaseTimings? timings,
  int? workerUs,
) {
  final result = JSObject()
    ..setProperty('kind'.toJS, 'result'.toJS)
    ..setProperty('id'.toJS, id.toJS);
  _attachTimings(result, timings, workerUs);
  if (out == null) {
    result.setProperty('buffer'.toJS, null);
    if (error != null) result.setProperty('error'.toJS, error.toJS);
    scope.postMessage(result);
    return;
  }
  // Copy to an exact-length buffer, then transfer it (zero-copy).
  final jsBuffer = Uint8List.fromList(out).buffer.toJS;
  result.setProperty('buffer'.toJS, jsBuffer);
  scope.postMessage(result, <JSAny>[jsBuffer].toJS);
}

/// Posts one interim progressive linework prefix (#564) for record [id], without
/// the timings/`result` envelope: the main thread forwards it to the record's
/// onPartial sink and keeps waiting for the `result`. The buffer is transferred
/// zero-copy like a result.
void _postPartial(
  web.DedicatedWorkerGlobalScope scope,
  int id,
  Uint8List partial,
) {
  final jsBuffer = Uint8List.fromList(partial).buffer.toJS;
  final message = JSObject()
    ..setProperty('kind'.toJS, 'partial'.toJS)
    ..setProperty('id'.toJS, id.toJS)
    ..setProperty('buffer'.toJS, jsBuffer);
  scope.postMessage(message, <JSAny>[jsBuffer].toJS);
}

void _postDetailResult(
  web.DedicatedWorkerGlobalScope scope,
  int id,
  Uint8List commands,
  Uint8List plan,
  PdfWorkerPhaseTimings? timings,
  int? workerUs,
) {
  final commandBuffer = Uint8List.fromList(commands).buffer.toJS;
  final planBuffer = Uint8List.fromList(plan).buffer.toJS;
  final result = JSObject()
    ..setProperty('kind'.toJS, 'result'.toJS)
    ..setProperty('id'.toJS, id.toJS)
    ..setProperty('buffer'.toJS, commandBuffer)
    ..setProperty('planBuffer'.toJS, planBuffer);
  _attachTimings(result, timings, workerUs);
  scope.postMessage(result, <JSAny>[commandBuffer, planBuffer].toJS);
}

void _attachTimings(
  JSObject result,
  PdfWorkerPhaseTimings? timings,
  int? workerUs,
) {
  if (timings == null || workerUs == null) return;
  if (PdfPerf.enabled) {
    // Per-job COS-layer delta (reset after attach). The very first job also
    // carries the document-open phases - fine for a diagnostics surface.
    result.setProperty(
        'cosStats'.toJS, jsonEncode(PdfPerf.snapshot().toJson()).toJS);
    PdfPerf.reset();
  }
  result
    ..setProperty('workerUs'.toJS, workerUs.toJS)
    ..setProperty('parseUs'.toJS, timings.parseUs.toJS)
    ..setProperty('interpretUs'.toJS, timings.interpretUs.toJS)
    ..setProperty('streamUs'.toJS, timings.streamUs.toJS)
    ..setProperty('serializeUs'.toJS, timings.serializeUs.toJS)
    ..setProperty('decodeUs'.toJS, timings.decodeUs.toJS)
    ..setProperty('binUs'.toJS, timings.binUs.toJS)
    ..setProperty('transcriptHit'.toJS, timings.transcriptHit.toJS);
  final imageDecode = timings.imageDecodeSummary;
  if (imageDecode != null) {
    result.setProperty('imageDecode'.toJS, imageDecode.toJS);
  }
}

JSUint8Array _jsUint8View(JSObject buffer) {
  final constructor = globalContext['Uint8Array'] as JSFunction?;
  if (constructor == null) throw StateError('Uint8Array is not available');
  return constructor.callAsConstructor<JSUint8Array>(buffer);
}

/// Records one page into a serialized command buffer, yielding periodically
/// so the cancel message handler can fire and set [token.cancelled].
///
/// Duplicated from the isolate backend deliberately: that file imports
/// `dart:isolate`, which does not exist on web, so this entry can't share it.
Future<Uint8List?> _recordPageAsync(
  PdfDocument document,
  PdfImageDecodeCache imageCache,
  PdfWorkerTranscriptCache cache,
  bool reuseTranscripts,
  int pageIndex,
  bool annotations,
  double? imagePixelRatio,
  bool decodeImages,
  int? commandLimit,
  PdfRect? imageDecodeRegion,
  PdfCancellationToken token, {
  PdfWorkerPhaseTimings? timings,
  void Function(Uint8List)? onPartial,
}) async {
  if (pageIndex < 0 || pageIndex >= document.pageCount) return null;
  final page = document.page(pageIndex);
  List<PdfRenderCommand> commands;
  if (!reuseTranscripts || (!decodeImages && commandLimit != null)) {
    // Long-jump previews intentionally stop early; building a full transcript
    // here would defeat their latency bound. Ordinary progressive records have
    // no limit and populate the shared transcript below.
    final previewOperationLimit = decodeImages ? null : commandLimit;
    final recorder = RecordingPdfDevice();
    final interpreter = PdfInterpreter(
      cos: document.cos,
      device: recorder,
      cancellation: token,
    );
    final streamClock = timings == null ? null : (Stopwatch()..start());
    await interpreter.drawPageContentAsync(
      page,
      page.contentBytes(),
      operationLimit: previewOperationLimit,
      yieldInterval: 4096,
    );
    if (streamClock != null) {
      streamClock.stop();
      timings!.streamUs += streamClock.elapsedMicroseconds;
    }
    final interpretClock = timings == null ? null : (Stopwatch()..start());
    if (annotations) interpreter.drawAnnotations(page);
    if (interpretClock != null) {
      interpretClock.stop();
      timings!.interpretUs += interpretClock.elapsedMicroseconds;
    }
    commands = recorder.commands;
  } else {
    final transcript = await cache.transcriptFor(
      document,
      pageIndex,
      annotations,
      token,
      yieldInterval: 4096,
      timings: timings,
      onPartial: onPartial,
    );
    if (transcript == null) return null;
    commands = transcript.sourceCommands;
  }
  if (decodeImages) {
    final decodeClock = timings == null ? null : (Stopwatch()..start());
    final tally = timings == null ? null : _BrowserDecodeTally();
    commands = await _withBrowserDecodedImages(
      document.cos,
      imageCache,
      commands,
      token,
      tally,
      maxImagePixelRatio: imagePixelRatio,
    );
    if (decodeClock != null) {
      decodeClock.stop();
      timings!.decodeUs += decodeClock.elapsedMicroseconds;
    }
    // Report the cache's own state, not just the decode tally: "no reuse" has
    // two very different causes - nothing was ever stored (entries stays 0), or
    // entries exist but the key never matches - and the tally alone cannot tell
    // them apart. #451 burned several device traces on exactly that ambiguity.
    if (tally != null) {
      timings!.imageDecodeSummary = '${tally.format()} '
          'cache=${imageCache.hits}h/${imageCache.misses}m'
          '/${imageCache.length}e';
    }
  }
  // Decode the page's images in the worker too: the buffer carries
  // premultiplied RGBA so the main thread only runs the engine codec. On web
  // this matters more than on native - there is no separate raster thread, so
  // the pure-Dart inflate/colour-convert would otherwise block frames. #73.
  // imagePixelRatio caps each image to display resolution before it crosses the
  // postMessage boundary, so a sheet-sized raster underlay ships at a few MB
  // instead of hundreds. decodeImages false skips the decode entirely for the
  // fast vector-first pass of progressive rendering.
  final serializeClock = timings == null ? null : (Stopwatch()..start());
  final result = serializeCommands(
    commands,
    cos: document.cos,
    decodeImages: decodeImages,
    maxImagePixelRatio: imagePixelRatio,
    pageRasterPixels: pdfPageRasterPixels(page.cropBox, imagePixelRatio),
    imageDecodeRegion: imageDecodeRegion,
    imagePlaceholders: !decodeImages,
    commandLimit: commandLimit,
    imageCache: imageCache,
    compactStateScopes: true,
  );
  if (serializeClock != null) {
    serializeClock.stop();
    timings!.serializeUs += serializeClock.elapsedMicroseconds;
  }
  return result;
}

Future<Uint8List?> _binStripsAsync(
  PdfDocument document,
  PdfWorkerTranscriptCache cache,
  int pageIndex,
  bool annotations,
  List<double> matrix,
  int deviceWidth,
  int deviceHeight,
  double pixelRatio,
  bool slugGlyphs,
  PdfCancellationToken token, {
  PdfWorkerPhaseTimings? timings,
}) async {
  final transcript = await cache.transcriptFor(
    document,
    pageIndex,
    annotations,
    token,
    yieldInterval: 4096,
    timings: timings,
  );
  if (transcript == null) return null;
  final binner = StripPlanBinner(
    pageToDevice: PdfMatrix(
      matrix[0],
      matrix[1],
      matrix[2],
      matrix[3],
      matrix[4],
      matrix[5],
    ),
    deviceWidth: deviceWidth,
    deviceHeight: deviceHeight,
    pixelRatio: pixelRatio,
    slugGlyphs: slugGlyphs,
  );
  final binClock = timings == null ? null : (Stopwatch()..start());
  await binner.bin(transcript.wireCommands, cancellation: token);
  if (binClock != null) {
    binClock.stop();
    timings!.binUs += binClock.elapsedMicroseconds;
  }
  return encodeStripPlan(binner.finish());
}

/// Produces the image-bearing command buffer and the plan binned from that
/// exact round trip in one web-worker job. Keeping the pair together prevents
/// a region-cropped image transform from drifting away from the plan that
/// replays it.
Future<(Uint8List, Uint8List)?> _recordStripDetailAsync(
  PdfDocument document,
  PdfImageDecodeCache imageCache,
  PdfWorkerTranscriptCache cache,
  int pageIndex,
  bool annotations,
  List<double> matrix,
  int deviceWidth,
  int deviceHeight,
  double pixelRatio,
  PdfRect imageDecodeRegion,
  PdfCancellationToken token, {
  PdfWorkerPhaseTimings? timings,
}) async {
  final transcript = await cache.transcriptFor(
    document,
    pageIndex,
    annotations,
    token,
    yieldInterval: 4096,
    timings: timings,
  );
  if (transcript == null) return null;
  var sourceCommands = transcript.sourceCommands;
  if (token.cancelled) throw const PdfCancelledException();

  // DCT images use the browser codec on web. Other image formats continue
  // through serializeCommands' pure-Dart, region-aware decoder.
  final decodeClock = timings == null ? null : (Stopwatch()..start());
  final tally = timings == null ? null : _BrowserDecodeTally();
  sourceCommands = await _withBrowserDecodedImages(
    document.cos,
    imageCache,
    sourceCommands,
    token,
    tally,
  );
  if (decodeClock != null) {
    decodeClock.stop();
    timings!.decodeUs += decodeClock.elapsedMicroseconds;
  }
  if (tally != null) timings!.imageDecodeSummary = tally.format();
  if (token.cancelled) throw const PdfCancelledException();
  final serializeClock = timings == null ? null : (Stopwatch()..start());
  final commandBuffer = serializeCommands(
    sourceCommands,
    cos: document.cos,
    decodeImages: true,
    maxImagePixelRatio: pixelRatio,
    imageDecodeRegion: imageDecodeRegion,
    imageCache: imageCache,
    compactStateScopes: true,
  );
  if (serializeClock != null) {
    serializeClock.stop();
    timings!.serializeUs += serializeClock.elapsedMicroseconds;
  }
  if (commandBuffer == null) return null;
  if (token.cancelled) throw const PdfCancelledException();

  final commands = deserializeCommands(commandBuffer);
  final binner = StripPlanBinner(
    pageToDevice: PdfMatrix(
      matrix[0],
      matrix[1],
      matrix[2],
      matrix[3],
      matrix[4],
      matrix[5],
    ),
    deviceWidth: deviceWidth,
    deviceHeight: deviceHeight,
    pixelRatio: pixelRatio,
  );
  final binClock = timings == null ? null : (Stopwatch()..start());
  await binner.bin(commands, cancellation: token);
  if (binClock != null) {
    binClock.stop();
    timings!.binUs += binClock.elapsedMicroseconds;
  }
  return (commandBuffer, encodeStripPlan(binner.finish()));
}

/// Builds the region-replay spatial index from the page's cached wire
/// transcript and serializes it, or null when the page can't be offloaded.
/// Mirrors the isolate backend's `_buildRegionIndexAsync`; duplicated because
/// this entry can't import `dart:isolate`.
Future<Uint8List?> _buildRegionIndexAsync(
  PdfDocument document,
  PdfWorkerTranscriptCache cache,
  int pageIndex,
  bool annotations,
  int maxCommands,
  bool buildGrid,
  PdfCancellationToken token, {
  PdfWorkerPhaseTimings? timings,
}) async {
  final transcript = await cache.transcriptFor(
    document,
    pageIndex,
    annotations,
    token,
    yieldInterval: 4096,
    timings: timings,
  );
  if (transcript == null) return null;
  if (token.cancelled) throw const PdfCancelledException();
  final index = PdfRegionReplayIndex.build(
    transcript.wireCommands,
    maxCommands: maxCommands,
    buildGrid: buildGrid,
  );
  return serializeRegionReplayIndex(index);
}

Future<List<PdfRenderCommand>> _withBrowserDecodedImages(
  CosDocument cos,
  PdfImageDecodeCache imageCache,
  List<PdfRenderCommand> commands,
  PdfCancellationToken token,
  _BrowserDecodeTally? tally, {
  double? maxImagePixelRatio,
  _BrowserFlateSampleCache? flateSampleCache,
}) async {
  var changed = false;
  final out = <PdfRenderCommand>[];
  for (final command in commands) {
    if (token.cancelled) throw PdfCancelledException();
    switch (command) {
      case PdfDrawImageCommand(:final request):
        if (request.isInline || request.decoded != null) {
          out.add(command);
          continue;
        }
        PdfDecodedPixels? decoded;
        final filters = pdfImageFilters(cos, request.stream.dictionary);
        final isFlate = filters.length == 1 &&
            (filters.single == 'FlateDecode' || filters.single == 'Fl');
        if (isFlate && maxImagePixelRatio != null) {
          // dart2js's package:archive inflate dominated scanned pages even
          // after their RGBA payload was capped to the fit raster. Let Chrome's
          // native Compression Streams implementation inflate simple Flate
          // RGB/gray samples, then use the same target-sized pure-Dart colour
          // conversion as every other decoder. Unsupported image semantics
          // fall through untouched to serializeCommands' general path.
          final target = _browserFlateTarget(cos, request, maxImagePixelRatio);
          if (target != null) {
            decoded = imageCache.get(
              request.stream,
              target.$1,
              target.$2,
            );
            if (decoded == null) {
              decoded = await _decodeBrowserFlate(
                cos,
                request.stream,
                filters.single,
                target.$1,
                target.$2,
                flateSampleCache,
              );
              if (decoded != null) {
                imageCache.put(
                  request.stream,
                  target.$1,
                  target.$2,
                  decoded,
                );
                tally?.flate++;
              } else {
                tally?.decline('flateNative');
              }
            } else {
              tally?.reused();
            }
          }
        } else {
          // The browser JPEG codec decodes at native resolution with no target,
          // so one entry per stream serves every record of the page. Uncached,
          // a page recorded three times in a scroll ran the codec three times -
          // ~330-630ms each in the device trace (#451).
          decoded = imageCache.get(request.stream, null, null);
          if (decoded == null) {
            decoded = await _decodeWithBrowserCodec(cos, request.stream, tally);
            if (decoded != null) {
              imageCache.put(request.stream, null, null, decoded);
            }
          } else {
            tally?.reused();
          }
        }
        if (decoded == null) {
          out.add(command);
        } else {
          changed = true;
          out.add(PdfDrawImageCommand(_withDecodedPixels(request, decoded)));
        }
      case PdfEndSoftMaskedCommand(
          :final luminosity,
          :final backdrop,
          :final maskCommands,
          :final backdropLuminance,
          :final transferScale,
          :final transferOffset,
        ):
        final decodedMaskCommands = await _withBrowserDecodedImages(
          cos,
          imageCache,
          maskCommands,
          token,
          tally,
          maxImagePixelRatio: maxImagePixelRatio,
          flateSampleCache: flateSampleCache,
        );
        if (!identical(decodedMaskCommands, maskCommands)) changed = true;
        out.add(
          PdfEndSoftMaskedCommand(
            luminosity: luminosity,
            backdrop: backdrop,
            maskCommands: decodedMaskCommands,
            backdropLuminance: backdropLuminance,
            transferScale: transferScale,
            transferOffset: transferOffset,
          ),
        );
      default:
        out.add(command);
    }
  }
  return changed ? out : commands;
}

(int, int)? _browserFlateTarget(
  CosDocument cos,
  PdfImageRequest request,
  double ratio,
) {
  if (!globalContext.has('DecompressionStream')) return null;
  final dict = request.stream.dictionary;
  if (cos.resolve(dict['ImageMask']) == const CosBoolean(true) ||
      dict.containsKey('SMask') ||
      dict.containsKey('Mask')) {
    return null;
  }
  final bits = cos.resolve(dict['BitsPerComponent']);
  if (bits is! CosInteger || bits.value != 8) return null;
  final family = pdfImageColorFamily(cos, dict);
  final components = switch (family) {
    'DeviceGray' => 1,
    'DeviceRGB' => 3,
    _ => 0,
  };
  if (components == 0 || pdfImageDecodeRanges(cos, dict, components) != null) {
    return null;
  }
  final colorSpace = cos.resolve(dict['ColorSpace']);
  if (colorSpace is! CosName ||
      (family == 'DeviceGray' &&
          colorSpace.value != 'DeviceGray' &&
          colorSpace.value != 'G') ||
      (family == 'DeviceRGB' &&
          colorSpace.value != 'DeviceRGB' &&
          colorSpace.value != 'RGB')) {
    return null;
  }
  final width = cos.resolve(dict['Width']);
  final height = cos.resolve(dict['Height']);
  if (width is! CosInteger ||
      height is! CosInteger ||
      width.value <= 0 ||
      height.value <= 0) {
    return null;
  }
  final transform = request.transform;
  final widthPts =
      math.sqrt(transform.a * transform.a + transform.b * transform.b);
  final heightPts =
      math.sqrt(transform.c * transform.c + transform.d * transform.d);
  return cappedImagePixelSize(
    width.value,
    height.value,
    widthPts,
    heightPts,
    ratio,
    headroom: 1,
  );
}

Future<PdfDecodedPixels?> _decodeBrowserFlate(
  CosDocument cos,
  CosStream stream,
  String filter,
  int targetWidth,
  int targetHeight,
  _BrowserFlateSampleCache? sampleCache,
) async {
  try {
    final samples = await _inflateBrowserFlateSamples(
      cos,
      stream,
      filter,
      sampleCache,
    );

    // Re-enter the shared image decoder as an unfiltered sample stream. Its
    // direct target-size path expands only targetWidth×targetHeight RGBA,
    // rather than constructing native-resolution RGBA and shrinking it later.
    final entries = Map<String, CosObject>.from(stream.dictionary.entries)
      ..remove('Filter')
      ..remove('DecodeParms')
      ..remove('DP');
    return decodePdfImage(
      cos,
      CosStream(CosDictionary(entries), samples),
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      samplesAreDecoded: true,
    );
  } catch (_) {
    return null;
  }
}

Future<Uint8List> _inflateBrowserFlateSamples(
  CosDocument cos,
  CosStream stream,
  String filter,
  _BrowserFlateSampleCache? sampleCache,
) async {
  final cached = sampleCache?[stream];
  if (cached != null) return cached;

  // stopBeforeFilter still performs object-key decryption, when needed, but
  // leaves the zlib payload for the browser's native inflater.
  final encoded = cos.decodeStreamData(stream, stopBeforeFilter: filter);
  // The document may live in a SharedArrayBuffer so all pooled workers can
  // open one byte snapshot. Blob deliberately rejects shared views; copying
  // this still-compressed payload (tens of KB for a multi-megapixel scan) is
  // cheap and keeps the multi-megabyte inflated plane native.
  final owned = Uint8List.fromList(encoded);
  final decompressor = web.DecompressionStream('deflate');
  // Start the reader before writing so stream backpressure cannot deadlock a
  // large inflated image waiting for a consumer.
  final output = web.Response(decompressor.readable).arrayBuffer().toDart;
  final writer = decompressor.writable.getWriter();
  await writer.write(owned.toJS).toDart;
  await writer.close().toDart;
  final buffer = await output;
  var samples = buffer.toDart.asUint8List();

  final paramsObject = cos.resolve(
    stream.dictionary['DecodeParms'] ?? stream.dictionary['DP'],
  );
  CosDictionary? params;
  if (paramsObject is CosDictionary) {
    params = paramsObject;
  } else if (paramsObject is CosArray && paramsObject.items.isNotEmpty) {
    final first = cos.resolve(paramsObject.items.first);
    if (first is CosDictionary) params = first;
  }
  samples = applyPredictor(samples, params);
  sampleCache?.put(stream, samples);
  return samples;
}

Future<
    ({
      Map<Object, web.CanvasImageSource> images,
      List<web.VideoFrame> frames,
    })?> _browserGrayFlateFrames(
  CosDocument cos,
  List<PdfRenderCommand> commands,
  PdfCancellationToken token,
  _BrowserFlateSampleCache sampleCache,
  _BrowserDecodeTally? tally, {
  double? maxPixelRatio,
}) async {
  if (!globalContext.has('VideoFrame')) {
    tally?.decline('videoFrameUnavailable');
    return null;
  }
  // At very deep zoom Chrome may defer a large VideoFrame colour conversion
  // until the transferred canvas composites, moving work past the worker's
  // ready reply. The RGBA path is faster and more predictable there; the
  // native luma frame targets fit/ordinary zoom where avoiding Dart's
  // resample is the material win.
  if (maxPixelRatio == null || maxPixelRatio > 2.1) {
    tally?.decline('videoFrameDeepZoom');
    return null;
  }
  final images = Map<Object, web.CanvasImageSource>.identity();
  final frames = <web.VideoFrame>[];
  var completed = false;
  try {
    for (final command in commands) {
      switch (command) {
        case PdfSaveCommand() || PdfRestoreCommand():
          continue;
        case PdfDrawImageCommand(:final request):
          if (request.isStencil || request.decoded != null) {
            tally?.decline('videoFrameImageState');
            return null;
          }
          final dict = request.stream.dictionary;
          final filters = pdfImageFilters(cos, dict);
          if (filters.length != 1 ||
              (filters.single != 'FlateDecode' && filters.single != 'Fl') ||
              dict.containsKey('SMask') ||
              dict.containsKey('Mask')) {
            tally?.decline('videoFrameFilter');
            return null;
          }
          final bits = cos.resolve(dict['BitsPerComponent']);
          final colorSpace = cos.resolve(dict['ColorSpace']);
          final width = cos.resolve(dict['Width']);
          final height = cos.resolve(dict['Height']);
          if (bits is! CosInteger ||
              bits.value != 8 ||
              colorSpace is! CosName ||
              (colorSpace.value != 'DeviceGray' && colorSpace.value != 'G') ||
              width is! CosInteger ||
              height is! CosInteger ||
              width.value <= 0 ||
              height.value <= 0 ||
              pdfImageDecodeRanges(cos, dict, 1) != null) {
            tally?.decline('videoFrameFormat');
            return null;
          }
          final samples = await _inflateBrowserFlateSamples(
            cos,
            request.stream,
            filters.single,
            sampleCache,
          );
          if (token.cancelled) throw const PdfCancelledException();
          final lumaBytes = width.value * height.value;
          if (samples.length < lumaBytes) {
            tally?.decline('videoFrameLength');
            return null;
          }
          final chromaBytes =
              ((width.value + 1) ~/ 2) * ((height.value + 1) ~/ 2);
          final yuv = Uint8List(lumaBytes + chromaBytes * 2)
            ..setRange(0, lumaBytes, samples)
            ..fillRange(lumaBytes, lumaBytes + chromaBytes * 2, 128);
          final frame = web.VideoFrame(
            yuv.toJS,
            web.VideoFrameBufferInit(
              format: 'I420',
              codedWidth: width.value,
              codedHeight: height.value,
              timestamp: 0,
              colorSpace: web.VideoColorSpaceInit(
                primaries: 'bt709',
                transfer: 'bt709',
                matrix: 'bt709',
                fullRange: true,
              ),
            ),
          );
          frames.add(frame);
          images[request.stream] = frame;
        default:
          tally?.decline('videoFrameCommand');
          return null;
      }
    }
    if (images.isEmpty) return null;
    completed = true;
    return (images: images, frames: frames);
  } catch (error) {
    tally?.decline('videoFrame:${error.runtimeType}');
    return null;
  } finally {
    if (!completed) {
      for (final frame in frames) {
        frame.close();
      }
    }
  }
}

class _BrowserFlateSampleCache {
  static const maxBytes = 32 * 1024 * 1024;

  final LinkedHashMap<CosStream, Uint8List> _entries =
      LinkedHashMap<CosStream, Uint8List>.identity();
  int _bytes = 0;

  Uint8List? operator [](CosStream stream) {
    final samples = _entries.remove(stream);
    if (samples != null) _entries[stream] = samples;
    return samples;
  }

  void put(CosStream stream, Uint8List samples) {
    if (samples.length > maxBytes) return;
    final old = _entries.remove(stream);
    if (old != null) _bytes -= old.length;
    while (_entries.isNotEmpty && _bytes + samples.length > maxBytes) {
      _bytes -= _entries.remove(_entries.keys.first)!.length;
    }
    _entries[stream] = samples;
    _bytes += samples.length;
  }
}

PdfImageRequest _withDecodedPixels(
  PdfImageRequest request,
  PdfDecodedPixels decoded,
) =>
    PdfImageRequest(
      stream: request.stream,
      transform: request.transform,
      alpha: request.alpha,
      isStencil: request.isStencil,
      stencilColor: request.stencilColor,
      isInline: request.isInline,
      decoded: decoded,
    );

Future<PdfDecodedPixels?> _decodeWithBrowserCodec(
  CosDocument cos,
  CosStream stream,
  _BrowserDecodeTally? tally,
) async {
  if (!_browserImageDecodeAvailable) {
    tally?.decline('noCapability');
    return null;
  }
  final dict = stream.dictionary;
  if (cos.resolve(dict['ImageMask']) == const CosBoolean(true)) {
    tally?.decline('imageMask');
    return null;
  }

  final filters = pdfImageFilters(cos, dict);
  final dctName = filters.contains('DCTDecode')
      ? 'DCTDecode'
      : filters.contains('DCT')
          ? 'DCT'
          : null;
  final dctMaskBytes = pdfImageDctSoftMaskBytes(cos, dict);
  if (dctName == null && dctMaskBytes == null) {
    tally?.decline('notDct');
    return null;
  }

  final PdfImageBase? base;
  if (dctName != null) {
    final family = pdfImageColorFamily(cos, dict);
    if (family == 'DeviceCMYK') {
      // CMYK JPEG bases already decode in pure Dart. Only intervene when the
      // soft mask is DCT-encoded and therefore needs the browser codec.
      if (dctMaskBytes == null) {
        tally?.decline('cmyk');
        return null;
      }
      base = decodePdfImageBase(cos, stream);
    } else {
      final jpeg = cos.decodeStreamData(stream, stopBeforeFilter: dctName);
      base = await _decodeBrowserJpegBase(cos, dict, jpeg);
    }
  } else {
    // Pure base + DCT /SMask: reuse the pure base decoder and only lift the
    // mask through the browser codec.
    base = decodePdfImageBase(cos, stream);
  }
  if (base == null) {
    tally?.decline('decodeNull');
    return null;
  }
  tally?.codec++;

  PdfImageSoftMask? mask;
  if (dctMaskBytes != null) {
    mask = await _decodeBrowserJpegMask(dctMaskBytes);
  }
  mask ??= pdfImageSoftMask(cos, dict) ?? pdfImageStencilMask(cos, dict);
  if (mask == null) {
    return _finishBrowserDecoded(
      base.rgba,
      base.width,
      base.height,
      hasAlpha: !base.opaque,
    );
  }
  final masked = pdfApplyImageAlpha(base.rgba, base.width, base.height, mask);
  return _finishBrowserDecoded(masked.$1, masked.$2, masked.$3, hasAlpha: true);
}

Future<PdfImageBase?> _decodeBrowserJpegBase(
  CosDocument cos,
  CosDictionary dict,
  Uint8List jpeg,
) async {
  final decoded = await _decodeBrowserJpegRgba(jpeg);
  if (decoded == null) return null;
  final components = switch (pdfImageColorFamily(cos, dict)) {
    'DeviceGray' => 1,
    'DeviceRGB' => 3,
    _ => 0,
  };
  final ranges =
      components > 0 ? pdfImageDecodeRanges(cos, dict, components) : null;
  final colorKey =
      components > 0 ? pdfImageColorKeyRanges(cos, dict, components) : null;
  if (ranges != null || colorKey != null) {
    pdfApplyImageDecodeAndColorKey(decoded.rgba, components, ranges, colorKey);
  }
  return PdfImageBase(
    decoded.rgba,
    decoded.width,
    decoded.height,
    opaque: colorKey == null,
  );
}

Future<PdfImageSoftMask?> _decodeBrowserJpegMask(Uint8List jpeg) async {
  final decoded = await _decodeBrowserJpegRgba(jpeg);
  if (decoded == null) return null;
  final alpha = Uint8List(decoded.width * decoded.height);
  for (var i = 0; i < alpha.length; i++) {
    alpha[i] = decoded.rgba[i * 4];
  }
  return PdfImageSoftMask(alpha, decoded.width, decoded.height);
}

PdfDecodedPixels _finishBrowserDecoded(
  Uint8List rgba,
  int width,
  int height, {
  required bool hasAlpha,
}) {
  if (hasAlpha) pdfPremultiplyRgba(rgba);
  return PdfDecodedPixels(rgba, width, height);
}

Future<_BrowserDecodedImage?> _decodeBrowserJpegRgba(Uint8List jpeg) async {
  if (!_browserImageDecodeAvailable) return null;
  web.ImageBitmap? bitmap;
  try {
    final blob = web.Blob(
      <JSAny>[jpeg.toJS].toJS,
      web.BlobPropertyBag(type: 'image/jpeg'),
    );
    final scope = globalContext as web.WorkerGlobalScope;
    bitmap = await scope.createImageBitmap(blob).toDart;
    final width = bitmap.width;
    final height = bitmap.height;
    if (width <= 0 || height <= 0) return null;
    final canvas = web.OffscreenCanvas(width, height);
    final context =
        canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D?;
    if (context == null) return null;
    context.drawImage(bitmap, 0, 0);
    final imageData = context.getImageData(0, 0, width, height);
    return _BrowserDecodedImage(
      Uint8List.fromList(imageData.data.toDart),
      width,
      height,
    );
  } catch (_) {
    return null;
  } finally {
    bitmap?.close();
  }
}

bool get _browserImageDecodeAvailable => _browserImageDecodeMissing().isEmpty;

/// The browser-codec prerequisites absent from this worker scope, or empty when
/// all are present. Reported on the `ready` line (#458): a worker that silently
/// declines every image because, say, its scope has no `OffscreenCanvas` is
/// otherwise indistinguishable in a trace from one whose codec ran.
List<String> _browserImageDecodeMissing() => <String>[
      if (!globalContext.has('Blob')) 'Blob',
      if (!globalContext.has('createImageBitmap')) 'createImageBitmap',
      if (!globalContext.has('OffscreenCanvas')) 'OffscreenCanvas',
    ];

/// Per-job tally of how the browser image codec fared, folded into
/// [PdfWorkerPhaseTimings.imageDecodeSummary] for the phase log (#458). Only
/// allocated when the job collects timings, so production pays nothing.
///
/// Reasons: `noCapability` (the scope lacks the codec — the #458 case),
/// `imageMask`/`cmyk`/`notDct` (expected declines the pure-Dart decoder
/// handles), and `decodeNull` (`createImageBitmap` threw or returned empty).
/// The reason strings avoid the words "fail"/"error" on purpose: they ride the
/// phase log, which the perf harness scans for fatal-error markers.
class _BrowserDecodeTally {
  int codec = 0;
  int flate = 0;

  /// Images served from a previous record's decode instead of re-running the
  /// codec (#451). Reported separately so a trace shows the reuse directly
  /// rather than as an unexplained drop in `codec=`.
  int reusedCount = 0;
  final Map<String, int> _declined = <String, int>{};

  void decline(String reason) =>
      _declined[reason] = (_declined[reason] ?? 0) + 1;

  void reused() => reusedCount++;

  String format() {
    final declined = _declined.values.fold(0, (a, b) => a + b);
    if (codec == 0 && flate == 0 && declined == 0 && reusedCount == 0) {
      return 'none';
    }
    final nativeFlate = flate == 0 ? '' : ' flate=$flate';
    final reuse = reusedCount == 0 ? '' : ' reused=$reusedCount';
    if (declined == 0) return 'codec=$codec$nativeFlate$reuse';
    final reasons =
        _declined.entries.map((e) => '${e.key}:${e.value}').join(',');
    return 'codec=$codec$nativeFlate$reuse declined=$declined($reasons)';
  }
}

class _BrowserDecodedImage {
  const _BrowserDecodedImage(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}
