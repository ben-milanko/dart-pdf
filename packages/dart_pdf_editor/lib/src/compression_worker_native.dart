import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart';

import '../compression_worker.dart';
import 'compression_worker_protocol.dart';

PdfCompressionTask startCompressionTask(
  Uint8List bytes,
  PdfCompressionOptions options,
) =>
    _NativeCompressionTask(bytes, options);

class _NativeCompressionTask extends PdfCompressionTask {
  _NativeCompressionTask(Uint8List bytes, PdfCompressionOptions options) {
    _port.listen(_onMessage);
    unawaited(_start(bytes, options));
  }

  final _port = ReceivePort();
  final _result = Completer<PdfCompressionResult>();
  Isolate? _isolate;
  bool _hasStarted = false;

  @override
  Future<PdfCompressionResult> get result => _result.future;

  @override
  bool get hasStarted => _hasStarted;

  Future<void> _start(Uint8List bytes, PdfCompressionOptions options) async {
    try {
      final isolate = await Isolate.spawn(
        _compress,
        (
          _port.sendPort,
          TransferableTypedData.fromList([bytes]),
          compressionOptionsToJson(options),
        ),
        onError: _port.sendPort,
        onExit: _port.sendPort,
        errorsAreFatal: true,
        debugName: 'PDF size optimisation',
      );
      if (_result.isCompleted) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        _isolate = isolate;
      }
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _onMessage(dynamic message) {
    if (_result.isCompleted) return;
    if (message == 'started') {
      _hasStarted = true;
      return;
    }
    try {
      if (message is List && message.first is TransferableTypedData) {
        final bytes =
            (message[0] as TransferableTypedData).materialize().asUint8List();
        final result = compressionResultFromJson(bytes, message[1] as String);
        _result.complete(result);
        _release();
      } else if (message is List && message.length == 2) {
        _fail(StateError(message[0].toString()),
            StackTrace.fromString(message[1].toString()));
      } else {
        _fail(StateError('The PDF optimisation worker stopped unexpectedly.'));
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
    _port.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  @override
  void cancel() => _fail(const PdfCompressionCancelledException());
}

void _compress((SendPort, TransferableTypedData, String) request) {
  try {
    final bytes = request.$2.materialize().asUint8List();
    final options = compressionOptionsFromJson(request.$3);
    request.$1.send('started');
    final result =
        PdfCompressor.optimize(PdfDocument.open(bytes), options: options);
    request.$1.send([
      TransferableTypedData.fromList([result.bytes]),
      compressionReportToJson(result),
    ]);
  } catch (error, stack) {
    request.$1.send([error.toString(), stack.toString()]);
  }
}
