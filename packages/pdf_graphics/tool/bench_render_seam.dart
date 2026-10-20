// Benchmark for issue #309's "transfer half": is passing an image-free render
// command graph directly across a native isolate `SendPort` cheaper than the
// `serializeCommands`/`deserializeCommands` codec round-trip the native render
// worker pays today?
//
// The codec exists because a Web Worker can only receive structured-cloneable
// data over `postMessage`; the question #309 raised is whether the *native*
// isolate adapter should skip it and hand the `List<PdfRenderCommand>` straight
// over the port instead ("native transfer, web codec" as two adapters).
//
// Run:
//   cd packages/pdf_graphics
//   fvm dart run tool/bench_render_seam.dart
//
// Finding (see doc/dev-log/2026-07-17-seam-transfer-measurement.md): the raw
// object-graph copy the VM performs for `port.send(commands)` is several times
// SLOWER than the compact byte codec + zero-copy `TransferableTypedData`, and
// the cost lands on the *receiving* (UI) isolate. The transfer half is a
// regression on the dense-page workload it targeted; it is not implemented.
import 'dart:async';
import 'dart:isolate';

import 'package:pdf_graphics/pdf_graphics.dart';

/// A synthetic image-free page of [count] fills/strokes, each a small cubic
/// path - the "dense CAD page (~100k commands)" shape #309 calls out.
List<PdfRenderCommand> buildDenseVectorPage(int count) {
  final commands = <PdfRenderCommand>[];
  var x = 0.0, y = 0.0;
  for (var i = 0; i < count; i++) {
    x = (x + 3.14159) % 800;
    y = (y + 2.71828) % 600;
    final path = PdfPath([
      PdfMoveTo(x, y),
      PdfLineTo(x + 12.5, y + 4.25),
      PdfCubicTo(x + 1, y + 2, x + 3, y + 4, x + 20.75, y + 9.5),
      PdfLineTo(x + 2.5, y + 30.125),
      const PdfClosePath(),
    ]);
    commands.add(i.isEven
        ? PdfFillPathCommand(
            path, const PdfColor(0.1, 0.2, 0.3), PdfFillRule.nonzero, 1)
        : PdfStrokePathCommand(
            path, const PdfColor(0, 0, 0), const PdfStroke(width: 0.75), 0.9));
  }
  return commands;
}

/// An isolate that bounces whatever it receives straight back, so a round-trip
/// pays the VM's object-graph copy once in each direction.
Future<void> _echoIsolate(SendPort reply) async {
  final port = ReceivePort();
  reply.send(port.sendPort);
  await for (final message in port) {
    final m = message as List<Object?>;
    (m[0] as SendPort).send(m[1]);
  }
}

String _ms(int micros, int iters) => (micros / iters / 1000).toStringAsFixed(2);

Future<void> _measure(int cmdCount) async {
  final commands = buildDenseVectorPage(cmdCount);

  // Correctness + warm-up for the codec path.
  final wire = serializeCommands(commands, compactStateScopes: true);
  if (wire == null) {
    print('serialize returned null (unexpected for an image-free buffer)');
    return;
  }
  final back = deserializeCommands(wire);
  assert(back.length == commands.length);

  const iters = 15;
  var serUs = 0, deserUs = 0;
  for (var i = 0; i < iters; i++) {
    final sw = Stopwatch()..start();
    final buf = serializeCommands(commands, compactStateScopes: true)!;
    serUs += sw.elapsedMicroseconds;
    sw
      ..reset()
      ..start();
    deserializeCommands(buf);
    deserUs += sw.elapsedMicroseconds;
  }

  final fromEcho = ReceivePort();
  final isolate = await Isolate.spawn(_echoIsolate, fromEcho.sendPort);
  final broadcast = fromEcho.asBroadcastStream();
  final echoPort = await broadcast.first as SendPort;

  Future<Object?> bounce(Object? payload) {
    final rp = ReceivePort();
    final done = rp.first;
    echoPort.send([rp.sendPort, payload]);
    return done;
  }

  // Sendability + warm-up for the raw-object path.
  final bounced = await bounce(commands) as List;
  assert(bounced.length == commands.length);

  const rawIters = 8; // this path is slow; fewer iterations keep it bearable
  var rawUs = 0;
  for (var i = 0; i < rawIters; i++) {
    final sw = Stopwatch()..start();
    await bounce(commands);
    rawUs += sw.elapsedMicroseconds;
  }

  isolate.kill(priority: Isolate.immediate);
  fromEcho.close();

  print('\n=== $cmdCount image-free commands '
      '(${(wire.length / 1e6).toStringAsFixed(1)} MB wire) ===');
  print('  codec serialize   (worker, off UI) : ${_ms(serUs, iters)} ms');
  print('  codec deserialize (UI thread)       : ${_ms(deserUs, iters)} ms');
  print('  raw object graph  round-trip        : ${_ms(rawUs, rawIters)} ms '
      '(~${_ms(rawUs ~/ 2, rawIters)} ms one crossing, on the receiver)');
}

void main() async {
  print('render-worker seam: codec byte round-trip vs raw isolate transfer');
  for (final count in [10000, 100000]) {
    await _measure(count);
  }
  print('\nThe native record path pays serialize off-thread + a zero-copy '
      'TransferableTypedData transfer; only deserialize lands on the UI '
      'thread. Replacing that with port.send(commands) moves a much larger '
      'object-graph copy onto the receiving isolate. Transfer half rejected.');
}
