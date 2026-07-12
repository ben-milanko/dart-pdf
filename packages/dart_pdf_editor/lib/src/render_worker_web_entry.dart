import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:pdf_graphics/raster.dart';
import 'package:web/web.dart' as web;

import 'render_worker_transcript_cache.dart';

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
  var reuseTranscripts = true;
  var collectTimings = false;
  PdfCancellationToken? activeToken;
  int? activeRequestId;
  final transcriptCache = PdfWorkerTranscriptCache();

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
        if (collectTimings) openClock = Stopwatch()..start();
        final buffer = data.getProperty('bytes'.toJS) as JSObject;
        final bytes = shared
            ? _jsUint8View(buffer).toDart
            : (buffer as JSArrayBuffer).toDart.asUint8List();
        document = PdfDocument.open(bytes);
      } catch (_) {
        document = null; // bad transfer / broken document → local renders
      }
      // ALWAYS reply ready, even on failure, so the client never hangs.
      openClock?.stop();
      final ready = JSObject()
        ..setProperty('kind'.toJS, 'ready'.toJS)
        ..setProperty('shared'.toJS, shared.toJS);
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
    final imageDecodeRegion =
        regionLeft != null &&
            regionBottom != null &&
            regionRight != null &&
            regionTop != null
        ? PdfRect(regionLeft, regionBottom, regionRight, regionTop)
        : null;

    final token = PdfCancellationToken();
    activeToken = token;
    activeRequestId = id;
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
  result
    ..setProperty('workerUs'.toJS, workerUs.toJS)
    ..setProperty('parseUs'.toJS, timings.parseUs.toJS)
    ..setProperty('interpretUs'.toJS, timings.interpretUs.toJS)
    ..setProperty('streamUs'.toJS, timings.streamUs.toJS)
    ..setProperty('serializeUs'.toJS, timings.serializeUs.toJS)
    ..setProperty('decodeUs'.toJS, timings.decodeUs.toJS)
    ..setProperty('binUs'.toJS, timings.binUs.toJS)
    ..setProperty('transcriptHit'.toJS, timings.transcriptHit.toJS);
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
    );
    if (transcript == null) return null;
    commands = transcript.sourceCommands;
  }
  if (decodeImages) {
    final decodeClock = timings == null ? null : (Stopwatch()..start());
    commands = await _withBrowserDecodedImages(document.cos, commands, token);
    if (decodeClock != null) {
      decodeClock.stop();
      timings!.decodeUs += decodeClock.elapsedMicroseconds;
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
    imageDecodeRegion: imageDecodeRegion,
    imagePlaceholders: !decodeImages,
    commandLimit: commandLimit,
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
  sourceCommands = await _withBrowserDecodedImages(
    document.cos,
    sourceCommands,
    token,
  );
  if (decodeClock != null) {
    decodeClock.stop();
    timings!.decodeUs += decodeClock.elapsedMicroseconds;
  }
  if (token.cancelled) throw const PdfCancelledException();
  final serializeClock = timings == null ? null : (Stopwatch()..start());
  final commandBuffer = serializeCommands(
    sourceCommands,
    cos: document.cos,
    decodeImages: true,
    maxImagePixelRatio: pixelRatio,
    imageDecodeRegion: imageDecodeRegion,
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

Future<List<PdfRenderCommand>> _withBrowserDecodedImages(
  CosDocument cos,
  List<PdfRenderCommand> commands,
  PdfCancellationToken token,
) async {
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
        final decoded = await _decodeWithBrowserCodec(cos, request.stream);
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
          maskCommands,
          token,
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

PdfImageRequest _withDecodedPixels(
  PdfImageRequest request,
  PdfDecodedPixels decoded,
) => PdfImageRequest(
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
) async {
  if (!_browserImageDecodeAvailable) return null;
  final dict = stream.dictionary;
  if (cos.resolve(dict['ImageMask']) == const CosBoolean(true)) return null;

  final filters = pdfImageFilters(cos, dict);
  final dctName = filters.contains('DCTDecode')
      ? 'DCTDecode'
      : filters.contains('DCT')
      ? 'DCT'
      : null;
  final dctMaskBytes = pdfImageDctSoftMaskBytes(cos, dict);
  if (dctName == null && dctMaskBytes == null) return null;

  final PdfImageBase? base;
  if (dctName != null) {
    final family = pdfImageColorFamily(cos, dict);
    if (family == 'DeviceCMYK') {
      // CMYK JPEG bases already decode in pure Dart. Only intervene when the
      // soft mask is DCT-encoded and therefore needs the browser codec.
      if (dctMaskBytes == null) return null;
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
  if (base == null) return null;

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
  final ranges = components > 0
      ? pdfImageDecodeRanges(cos, dict, components)
      : null;
  final colorKey = components > 0
      ? pdfImageColorKeyRanges(cos, dict, components)
      : null;
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

bool get _browserImageDecodeAvailable =>
    globalContext.has('Blob') &&
    globalContext.has('createImageBitmap') &&
    globalContext.has('OffscreenCanvas');

class _BrowserDecodedImage {
  const _BrowserDecodedImage(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}
