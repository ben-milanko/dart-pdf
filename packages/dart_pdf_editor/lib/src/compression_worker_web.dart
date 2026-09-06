import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';
import 'package:web/web.dart' as web;

import '../compression_worker.dart';
import 'compression_worker_protocol.dart';
import 'render_worker.dart' show pdfRenderWorkerScriptUrl;

PdfCompressionTask startCompressionTask(
  Uint8List bytes,
  PdfCompressionOptions options,
) =>
    _WebCompressionTask(bytes, options);

class _WebCompressionTask extends PdfCompressionTask {
  _WebCompressionTask(Uint8List bytes, PdfCompressionOptions options)
      : _bytes = bytes,
        _options = options {
    try {
      final url = pdfRenderWorkerScriptUrl;
      if (url == null || url.isEmpty) {
        throw StateError('The PDF optimisation worker is not configured.');
      }
      final worker = _worker = web.Worker(url.toJS);
      worker.onmessage = _onMessage.toJS;
      worker.onerror = ((web.Event event) {
        _fail(StateError('Could not load the PDF optimisation worker. '
            'Reload the app and try again.'));
      }).toJS;
      worker.onmessageerror = ((web.MessageEvent event) {
        _fail(StateError('Could not read the PDF optimisation worker result.'));
      }).toJS;
      // An older cached render worker ignores the handshake. Never send work
      // until support is confirmed, or silently freeze the UI as a fallback.
      _readyTimeout = Timer(const Duration(seconds: 30), () {
        _fail(StateError('The PDF optimisation worker did not start. '
            'Reload the app and try again.'));
      });
      worker.postMessage(
          JSObject()..setProperty('kind'.toJS, 'compressionHello'.toJS));
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  Uint8List? _bytes;
  final PdfCompressionOptions _options;
  final _result = Completer<PdfCompressionResult>();
  web.Worker? _worker;
  Timer? _readyTimeout;
  bool _sent = false;
  bool _hasStarted = false;

  @override
  Future<PdfCompressionResult> get result => _result.future;

  @override
  bool get hasStarted => _hasStarted;

  void _onMessage(web.MessageEvent event) {
    if (_result.isCompleted) return;
    try {
      final data = event.data as JSObject;
      final kind = (data.getProperty('kind'.toJS) as JSString).toDart;
      if (kind == 'compressionReady' && !_sent) {
        final version =
            (data.getProperty('version'.toJS) as JSNumber?)?.toDartInt;
        if (version != compressionWorkerProtocolVersion) {
          throw StateError('The PDF optimisation worker is out of date. '
              'Reload the app and try again.');
        }
        _readyTimeout?.cancel();
        _sent = true;
        // Transfer our own exact copy: transferring the caller's backing
        // buffer would detach the open document's bytes in a JS build.
        final buffer = Uint8List.fromList(_bytes!).buffer.toJS;
        _bytes = null;
        _worker!.postMessage(
          JSObject()
            ..setProperty('kind'.toJS, 'compress'.toJS)
            ..setProperty('bytes'.toJS, buffer)
            ..setProperty(
                'options'.toJS, compressionOptionsToJson(_options).toJS),
          <JSAny>[buffer].toJS,
        );
      } else if (kind == 'compressionStarted') {
        _hasStarted = true;
      } else if (kind == 'compressionResult') {
        final bytes = (data.getProperty('bytes'.toJS) as JSArrayBuffer)
            .toDart
            .asUint8List();
        final report = (data.getProperty('report'.toJS) as JSString).toDart;
        _result.complete(compressionResultFromJson(bytes, report));
        _release();
      } else if (kind == 'compressionError') {
        _fail(StateError((data.getProperty('error'.toJS) as JSString).toDart));
      }
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (_result.isCompleted) return;
    _result.completeError(error, stack);
    _release();
  }

  void _release() {
    _readyTimeout?.cancel();
    _readyTimeout = null;
    _worker?.terminate();
    _worker = null;
    _bytes = null;
  }

  @override
  void cancel() => _fail(const PdfCompressionCancelledException());
}
