import 'dart:async';
import 'dart:isolate';

import 'package:flutter/painting.dart';

import 'ocr_image.dart';
import 'ocr_model_runner.dart';

/// Runs an unloaded, isolate-sendable [OcrModelRunner] on a long-lived worker
/// isolate.
///
/// Page RGBA bytes cross the isolate boundary as [TransferableTypedData], so
/// the large raster is transferred instead of copied through a structured
/// message. The wrapped runner is loaded and retained by the worker: native
/// sessions are created once, reused for every page, and released there by
/// [dispose]. Only the small recognized-line result returns to the UI isolate.
///
/// The supplied [runner] must not have been loaded yet, and its configuration
/// fields must be isolate-sendable. [OnnxOcrModelRunner] satisfies both rules.
class IsolateOcrModelRunner implements OcrModelRunner {
  IsolateOcrModelRunner(this.runner, {this.debugName = 'pdf-ocr-worker'});

  /// The unloaded runner configuration copied into the worker at [load].
  final OcrModelRunner runner;

  /// Name shown by isolate-aware profiling tools.
  final String debugName;

  Isolate? _isolate;
  ReceivePort? _responses;
  ReceivePort? _errors;
  ReceivePort? _exits;
  StreamSubscription<Object?>? _responseSubscription;
  StreamSubscription<Object?>? _errorSubscription;
  StreamSubscription<Object?>? _exitSubscription;
  SendPort? _commands;
  Completer<SendPort>? _ready;
  Completer<void>? _disposeReply;
  final Map<int, Completer<List<RecognizedTextLine>>> _pending = {};
  Future<void>? _loadFuture;
  var _nextRequest = 0;
  var _disposed = false;
  var _expectedExit = false;

  @override
  Future<void> load() {
    if (_disposed) {
      return Future.error(
        StateError('IsolateOcrModelRunner.load() after dispose()'),
      );
    }
    return _loadFuture ??= _start();
  }

  Future<void> _start() async {
    final responses = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    _responses = responses;
    _errors = errors;
    _exits = exits;
    final ready = Completer<SendPort>();
    _ready = ready;
    _responseSubscription = responses.listen(_onResponse);
    _errorSubscription = errors.listen(_onIsolateError);
    _exitSubscription = exits.listen(_onIsolateExit);
    try {
      _isolate = await Isolate.spawn<(SendPort, OcrModelRunner)>(
        _runOcrWorker,
        (responses.sendPort, runner),
        debugName: debugName,
        errorsAreFatal: true,
        onError: errors.sendPort,
        onExit: exits.sendPort,
      );
      _commands = await ready.future;
    } catch (_) {
      await _closePorts(kill: true);
      rethrow;
    }
  }

  @override
  Future<List<RecognizedTextLine>> recognize(OcrImage image) async {
    if (_disposed) {
      throw StateError('IsolateOcrModelRunner.recognize() after dispose()');
    }
    await load();
    final commands = _commands;
    if (commands == null) throw StateError('OCR worker did not start');
    final id = _nextRequest++;
    final result = Completer<List<RecognizedTextLine>>();
    _pending[id] = result;
    commands.send([
      'recognize',
      id,
      image.width,
      image.height,
      TransferableTypedData.fromList([image.rgba]),
    ]);
    return result.future;
  }

  void _onResponse(Object? raw) {
    if (raw is! List || raw.isEmpty) return;
    switch (raw[0]) {
      case 'ready':
        final port = raw.length > 1 ? raw[1] : null;
        if (port is SendPort && !(_ready?.isCompleted ?? true)) {
          _ready!.complete(port);
        }
      case 'result':
        if (raw.length < 3 || raw[1] is! int) return;
        final completer = _pending.remove(raw[1] as int);
        if (completer == null) return;
        try {
          final rows = raw[2] as List;
          completer.complete([
            for (final value in rows)
              if (value case final List row when row.length >= 6)
                RecognizedTextLine(
                  text: row[0] as String,
                  pixelBounds: Rect.fromLTRB(
                    (row[1] as num).toDouble(),
                    (row[2] as num).toDouble(),
                    (row[3] as num).toDouble(),
                    (row[4] as num).toDouble(),
                  ),
                  confidence: (row[5] as num).toDouble(),
                ),
          ]);
        } catch (error, stack) {
          completer.completeError(error, stack);
        }
      case 'error':
        if (raw.length < 3 || raw[1] is! int) return;
        _pending.remove(raw[1] as int)?.completeError(
              StateError('OCR worker failed: ${raw[2]}'),
              raw.length > 3 ? StackTrace.fromString('${raw[3]}') : null,
            );
      case 'fatal':
        final error = StateError(
          'OCR worker failed to start: ${raw.length > 1 ? raw[1] : 'unknown error'}',
        );
        _fail(
          error,
          raw.length > 2 ? StackTrace.fromString('${raw[2]}') : null,
        );
      case 'disposed':
        _expectedExit = true;
        final reply = _disposeReply;
        if (reply != null && !reply.isCompleted) reply.complete();
    }
  }

  void _onIsolateError(Object? raw) {
    final values = raw is List ? raw : const [];
    final error = StateError(
      'OCR worker isolate error: ${values.isNotEmpty ? values[0] : raw}',
    );
    _fail(
      error,
      values.length > 1 ? StackTrace.fromString('${values[1]}') : null,
    );
  }

  void _onIsolateExit(Object? _) {
    if (_expectedExit) return;
    _fail(StateError('OCR worker exited unexpectedly'));
  }

  void _fail(Object error, [StackTrace? stack]) {
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(error, stack);
    }
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(error, stack);
    }
    _pending.clear();
    final disposeReply = _disposeReply;
    if (disposeReply != null && !disposeReply.isCompleted) {
      disposeReply.completeError(error, stack);
    }
    unawaited(_closePorts(kill: true));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final loadFuture = _loadFuture;
    if (loadFuture == null) return;
    try {
      try {
        await loadFuture;
      } catch (_) {
        // Loading already reported its original error to the caller. Dispose
        // remains best-effort so a cleanup in `finally` cannot replace that
        // failure with the same worker-start error a second time.
        return;
      }
      final commands = _commands;
      if (commands != null) {
        final reply = Completer<void>();
        _disposeReply = reply;
        commands.send(const ['dispose']);
        await reply.future;
      }
    } finally {
      await _closePorts(kill: true);
    }
  }

  Future<void> _closePorts({required bool kill}) async {
    if (kill) _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    await _responseSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _exitSubscription?.cancel();
    _responseSubscription = null;
    _errorSubscription = null;
    _exitSubscription = null;
    _responses?.close();
    _errors?.close();
    _exits?.close();
    _responses = null;
    _errors = null;
    _exits = null;
  }
}

Future<void> _runOcrWorker((SendPort, OcrModelRunner) bootstrap) async {
  final (responses, runner) = bootstrap;
  final commands = ReceivePort();
  var runnerLoaded = false;
  try {
    await runner.load();
    runnerLoaded = true;
    responses.send(['ready', commands.sendPort]);
    await for (final raw in commands) {
      if (raw is! List || raw.isEmpty) continue;
      if (raw[0] == 'dispose') {
        await runner.dispose();
        runnerLoaded = false;
        responses.send(const ['disposed']);
        break;
      }
      if (raw[0] != 'recognize' || raw.length < 5) continue;
      final id = raw[1] as int;
      try {
        final bytes =
            (raw[4] as TransferableTypedData).materialize().asUint8List();
        final lines = await runner.recognize(
          OcrImage(rgba: bytes, width: raw[2] as int, height: raw[3] as int),
        );
        responses.send([
          'result',
          id,
          [
            for (final line in lines)
              [
                line.text,
                line.pixelBounds.left,
                line.pixelBounds.top,
                line.pixelBounds.right,
                line.pixelBounds.bottom,
                line.confidence,
              ],
          ],
        ]);
      } catch (error, stack) {
        responses.send(['error', id, '$error', '$stack']);
      }
    }
  } catch (error, stack) {
    responses.send(['fatal', '$error', '$stack']);
  } finally {
    commands.close();
    if (runnerLoaded) {
      try {
        await runner.dispose();
      } catch (_) {
        // Preserve the original worker failure; disposal is best-effort here.
      }
    }
  }
}
