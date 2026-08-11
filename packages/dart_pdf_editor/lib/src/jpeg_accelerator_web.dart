import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'jpeg_turbo_wasm_data.dart';

const _perfLogEnabled = bool.fromEnvironment('PDF_PERF_LOG');

bool _installed = false;

/// Installs a synchronous libjpeg-turbo decoder inside the current browser
/// isolate (normally the dedicated render worker).
///
/// The module is embedded so the precompiled package worker, custom workers,
/// and the local-render fallback all have identical availability without a
/// second asset URL or fetch race. Any unsupported runtime or module failure
/// leaves [pdfDctCmykDecoder] untouched and the portable decoder takes over.
void installPdfJpegAccelerator() {
  if (_installed) return;
  _installed = true;
  try {
    final compressed = base64Decode(pdfJpegTurboWasmGzipBase64);
    final moduleBytes = Uint8List.fromList(
      const GZipDecoder().decodeBytes(compressed),
    );
    final webAssembly = globalContext['WebAssembly'] as JSObject?;
    final moduleConstructor = webAssembly?['Module'] as JSFunction?;
    final instanceConstructor = webAssembly?['Instance'] as JSFunction?;
    if (moduleConstructor == null || instanceConstructor == null) return;

    final module = moduleConstructor.callAsConstructor<JSObject>(
      moduleBytes.toJS,
    );
    final imports = _wasmImports();
    final instance = instanceConstructor.callAsConstructor<JSObject>(
      module,
      imports,
    );
    final exports = instance['exports'] as JSObject?;
    if (exports == null) return;
    final decoder = _TurboJpegWasm(exports);
    if (!decoder.isUsable) return;
    pdfDctCmykDecoder = decoder.decodeCmyk;
    pdfDctGrayDecoder = decoder.decodeGray;
    pdfDctRgbaDecoder = decoder.decodeRgba;
    pdfDeviceCmykToRgba = decoder.convertCmykToRgba;
    pdfComponentBoxDownsampler = decoder.downsampleComponents;
    _perfLog('jpeg-turbo ready wasm=${moduleBytes.length}B');
  } catch (error) {
    // Acceleration is opportunistic. The pure-Dart decoder remains the
    // correctness fallback for old browsers and failed module construction.
    _perfLog('jpeg-turbo unavailable: $error');
  }
}

void _perfLog(String message) {
  if (_perfLogEnabled) _consoleLog('[perf] $message'.toJS);
}

@JS('console.log')
external void _consoleLog(JSAny? message);

JSObject _wasmImports() {
  final zero = (() => 0.toJS).toJS;
  final setjmp = ((JSNumber _) => 0.toJS).toJS;
  void longjmpDart(JSNumber _, JSNumber __) {
    throw StateError('libjpeg-turbo longjmp');
  }

  final longjmp = longjmpDart.toJS;
  void procExitDart(JSNumber code) {
    throw StateError('libjpeg-turbo exited with ${code.toDartInt}');
  }

  final procExit = procExitDart.toJS;

  final env = JSObject()
    ..['setjmp'] = setjmp
    ..['longjmp'] = longjmp;
  final wasi = JSObject()
    ..['environ_get'] = zero
    ..['environ_sizes_get'] = zero
    ..['fd_close'] = zero
    ..['fd_prestat_get'] = zero
    ..['fd_prestat_dir_name'] = zero
    ..['fd_seek'] = zero
    ..['fd_write'] = zero
    ..['random_get'] = zero
    ..['proc_exit'] = procExit;
  return JSObject()
    ..['env'] = env
    ..['wasi_snapshot_preview1'] = wasi;
}

final class _TurboJpegWasm {
  const _TurboJpegWasm(this.exports);

  static const _tjpfCmyk = 11;
  static const _tjpfGray = 6;
  static const _tjpfRgba = 7;

  final JSObject exports;

  bool get isUsable =>
      (exports['memory']?.isA<JSObject>() ?? false) &&
      (exports['malloc']?.isA<JSFunction>() ?? false) &&
      (exports['free']?.isA<JSFunction>() ?? false) &&
      (exports['tjInitDecompress']?.isA<JSFunction>() ?? false) &&
      (exports['tjDecompressHeader3']?.isA<JSFunction>() ?? false) &&
      (exports['tjDecompress2']?.isA<JSFunction>() ?? false) &&
      (exports['tjDestroy']?.isA<JSFunction>() ?? false) &&
      (exports['dartpdf_box_downsample']?.isA<JSFunction>() ?? false) &&
      (exports['dartpdf_cmyk_to_rgba']?.isA<JSFunction>() ?? false);

  Uint8List? convertCmykToRgba(Uint8List samples) {
    if (samples.isEmpty || samples.length.isOdd || samples.length % 4 != 0) {
      return null;
    }
    var input = 0;
    var output = 0;
    final clock = _perfLogEnabled ? (Stopwatch()..start()) : null;
    try {
      input = _call('malloc', [samples.length]);
      output = _call('malloc', [samples.length]);
      if (input == 0 || output == 0) return null;
      Uint8List.view(_memoryBuffer(), input, samples.length).setAll(0, samples);
      if (_call(
            'dartpdf_cmyk_to_rgba',
            [input, output, samples.length ~/ 4],
          ) !=
          0) {
        return null;
      }
      final rgba = Uint8List(samples.length)
        ..setAll(0, Uint8List.view(_memoryBuffer(), output, samples.length));
      if (clock != null) {
        _perfLog(
          'jpeg-turbo cmyk-rgba pixels=${samples.length ~/ 4} '
          'ms=${(clock.elapsedMicroseconds / 1000).toStringAsFixed(1)}',
        );
      }
      return rgba;
    } catch (error) {
      _perfLog('jpeg-turbo cmyk-rgba unavailable: $error');
      rethrow;
    } finally {
      if (output != 0) _callVoid('free', [output]);
      if (input != 0) _callVoid('free', [input]);
    }
  }

  Uint8List? downsampleComponents(
    Uint8List samples,
    int width,
    int height,
    int components,
    int targetWidth,
    int targetHeight,
  ) {
    if (width <= 0 ||
        height <= 0 ||
        components <= 0 ||
        components > 8 ||
        targetWidth <= 0 ||
        targetHeight <= 0 ||
        targetWidth > width ||
        targetHeight > height ||
        samples.length < width * height * components) {
      return null;
    }
    var input = 0;
    var output = 0;
    final outputLength = targetWidth * targetHeight * components;
    try {
      input = _call('malloc', [samples.length]);
      output = _call('malloc', [outputLength]);
      if (input == 0 || output == 0) return null;
      Uint8List.view(_memoryBuffer(), input, samples.length).setAll(0, samples);
      if (_call('dartpdf_box_downsample', [
            input,
            width,
            height,
            components,
            output,
            targetWidth,
            targetHeight,
          ]) !=
          0) {
        return null;
      }
      return Uint8List(outputLength)
        ..setAll(
          0,
          Uint8List.view(_memoryBuffer(), output, outputLength),
        );
    } finally {
      if (output != 0) _callVoid('free', [output]);
      if (input != 0) _callVoid('free', [input]);
    }
  }

  PdfDctCmykSamples? decodeCmyk(
    Uint8List jpegBytes, {
    int? targetWidth,
    int? targetHeight,
  }) {
    final decoded = _decodeSamples(
      jpegBytes,
      pixelFormat: _tjpfCmyk,
      pixelStride: 4,
      label: 'cmyk',
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    return decoded == null
        ? null
        : PdfDctCmykSamples(
            decoded.samples,
            decoded.width,
            decoded.height,
          );
  }

  PdfDctGraySamples? decodeGray(
    Uint8List jpegBytes, {
    int? targetWidth,
    int? targetHeight,
  }) {
    final decoded = _decodeSamples(
      jpegBytes,
      pixelFormat: _tjpfGray,
      pixelStride: 1,
      label: 'gray',
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    return decoded == null
        ? null
        : PdfDctGraySamples(
            decoded.samples,
            decoded.width,
            decoded.height,
          );
  }

  PdfDctRgbaSamples? decodeRgba(
    Uint8List jpegBytes, {
    int? targetWidth,
    int? targetHeight,
  }) {
    final decoded = _decodeSamples(
      jpegBytes,
      pixelFormat: _tjpfRgba,
      pixelStride: 4,
      label: 'rgba',
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    return decoded == null
        ? null
        : PdfDctRgbaSamples(
            decoded.samples,
            decoded.width,
            decoded.height,
          );
  }

  ({Uint8List samples, int width, int height})? _decodeSamples(
    Uint8List jpegBytes, {
    required int pixelFormat,
    required int pixelStride,
    required String label,
    int? targetWidth,
    int? targetHeight,
  }) {
    if (jpegBytes.isEmpty) return null;
    final clock = _perfLogEnabled ? (Stopwatch()..start()) : null;
    var input = 0;
    var handle = 0;
    var metadata = 0;
    var output = 0;
    var exactOutput = 0;
    try {
      input = _call('malloc', [jpegBytes.length]);
      if (input == 0) return null;
      Uint8List.view(_memoryBuffer(), input, jpegBytes.length)
          .setAll(0, jpegBytes);

      handle = _call('tjInitDecompress');
      if (handle == 0) return null;
      metadata = _call('malloc', [16]);
      if (metadata == 0) return null;
      final headerStatus = _call('tjDecompressHeader3', [
        handle,
        input,
        jpegBytes.length,
        metadata,
        metadata + 4,
        metadata + 8,
        metadata + 12,
      ]);
      if (headerStatus != 0) {
        _perfLog('jpeg-turbo $label header failed status=$headerStatus');
        return null;
      }

      final header = ByteData.view(_memoryBuffer(), metadata, 16);
      final nativeWidth = header.getUint32(0, Endian.little);
      final nativeHeight = header.getUint32(4, Endian.little);
      final (width, height) = _scaledDimensions(
        nativeWidth,
        nativeHeight,
        targetWidth,
        targetHeight,
      );
      final outputLength = width * height * pixelStride;
      if (width <= 0 || height <= 0 || outputLength <= 0) return null;

      output = _call('malloc', [outputLength]);
      if (output == 0) return null;
      final decodeStatus = _call('tjDecompress2', [
        handle,
        input,
        jpegBytes.length,
        output,
        width,
        width * pixelStride,
        height,
        pixelFormat,
        0,
      ]);
      if (decodeStatus != 0) {
        _perfLog(
          'jpeg-turbo $label decode failed status=$decodeStatus '
          '${nativeWidth}x$nativeHeight target=${targetWidth ?? 0}x'
          '${targetHeight ?? 0}',
        );
        return null;
      }

      var resultWidth = width;
      var resultHeight = height;
      var resultOutput = output;
      var resultLength = outputLength;
      if (targetWidth != null && targetHeight != null) {
        final exactWidth = targetWidth.clamp(1, width);
        final exactHeight = targetHeight.clamp(1, height);
        if (exactWidth < width || exactHeight < height) {
          final exactLength = exactWidth * exactHeight * pixelStride;
          exactOutput = _call('malloc', [exactLength]);
          if (exactOutput != 0 &&
              _call('dartpdf_box_downsample', [
                    output,
                    width,
                    height,
                    pixelStride,
                    exactOutput,
                    exactWidth,
                    exactHeight,
                  ]) ==
                  0) {
            resultWidth = exactWidth;
            resultHeight = exactHeight;
            resultOutput = exactOutput;
            resultLength = exactLength;
          }
        }
      }
      final samples = Uint8List(resultLength)
        ..setAll(
          0,
          Uint8List.view(_memoryBuffer(), resultOutput, resultLength),
        );
      if (clock != null) {
        _perfLog(
          'jpeg-turbo $label ${resultWidth}x$resultHeight '
          'target=${targetWidth ?? 0}x${targetHeight ?? 0} '
          'ms=${(clock.elapsedMicroseconds / 1000).toStringAsFixed(1)}',
        );
      }
      return (
        samples: samples,
        width: resultWidth,
        height: resultHeight,
      );
    } finally {
      final cleanupClock = _perfLogEnabled ? (Stopwatch()..start()) : null;
      if (exactOutput != 0) _callVoid('free', [exactOutput]);
      if (output != 0) _callVoid('free', [output]);
      if (metadata != 0) _callVoid('free', [metadata]);
      if (handle != 0) _call('tjDestroy', [handle]);
      if (input != 0) _callVoid('free', [input]);
      if (cleanupClock != null) {
        _perfLog(
          'jpeg-turbo $label cleanup '
          'ms=${(cleanupClock.elapsedMicroseconds / 1000).toStringAsFixed(1)}',
        );
      }
    }
  }

  int _call(String name, [List<int> arguments = const []]) {
    final result = exports.callMethodVarArgs<JSNumber>(
      name.toJS,
      arguments.map((argument) => argument.toJS).toList(growable: false),
    );
    return result.toDartInt;
  }

  void _callVoid(String name, [List<int> arguments = const []]) {
    exports.callMethodVarArgs<JSAny?>(
      name.toJS,
      arguments.map((argument) => argument.toJS).toList(growable: false),
    );
  }

  ByteBuffer _memoryBuffer() {
    final memory = exports['memory'] as JSObject;
    return (memory['buffer'] as JSArrayBuffer).toDart;
  }
}

/// Chooses the smallest libjpeg-turbo scaled-IDCT size that still covers the
/// requested raster. The codec supports every eighth from 1/8 through 1; its
/// `TJSCALED` rule rounds each dimension up before the shared PDF pipeline
/// performs the small final box reduction to the exact target.
(int, int) _scaledDimensions(
  int width,
  int height,
  int? targetWidth,
  int? targetHeight,
) {
  if (targetWidth == null ||
      targetHeight == null ||
      targetWidth <= 0 ||
      targetHeight <= 0 ||
      (targetWidth >= width && targetHeight >= height)) {
    return (width, height);
  }
  for (var numerator = 1; numerator < 8; numerator++) {
    final scaledWidth = (width * numerator + 7) ~/ 8;
    final scaledHeight = (height * numerator + 7) ~/ 8;
    if (scaledWidth >= targetWidth && scaledHeight >= targetHeight) {
      return (scaledWidth, scaledHeight);
    }
  }
  return (width, height);
}
