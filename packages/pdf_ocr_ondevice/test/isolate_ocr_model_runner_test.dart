import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_ocr_ondevice/pdf_ocr_ondevice.dart';

class _BusyRunner implements OcrModelRunner {
  _BusyRunner({this.fail = false, this.failLoad = false});

  final bool fail;
  final bool failLoad;
  var _loaded = false;
  var _calls = 0;

  @override
  Future<void> load() async {
    if (failLoad) throw StateError('synthetic load failure');
    _loaded = true;
  }

  @override
  Future<List<RecognizedTextLine>> recognize(OcrImage image) async {
    if (!_loaded) throw StateError('not loaded');
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsedMilliseconds < 120) {
      // Deliberately occupy the isolate with representative synchronous
      // pre/post-processing work. A root-isolate runner would starve timers.
    }
    if (fail) throw StateError('synthetic inference failure');
    _calls++;
    return [
      RecognizedTextLine(
        text: '${image.width}x${image.height} call $_calls',
        pixelBounds: const Rect.fromLTWH(1, 2, 3, 4),
        confidence: 0.75,
      ),
    ];
  }

  @override
  Future<void> dispose() async => _loaded = false;
}

OcrImage _image() => OcrImage(
      rgba: Uint8List.fromList([10, 20, 30, 255, 40, 50, 60, 255]),
      width: 2,
      height: 1,
    );

void main() {
  test('keeps the calling isolate responsive during inference', () async {
    final runner = IsolateOcrModelRunner(_BusyRunner());
    addTearDown(runner.dispose);
    await runner.load();

    var ticks = 0;
    final heartbeat = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks++,
    );
    final lines = await runner.recognize(_image());
    heartbeat.cancel();

    expect(
      ticks,
      greaterThan(3),
      reason: 'worker inference must not starve the caller event loop',
    );
    expect(lines.single.text, '2x1 call 1');
    expect(lines.single.pixelBounds, const Rect.fromLTWH(1, 2, 3, 4));
    expect(lines.single.confidence, 0.75);
  });

  test('loads once and reuses the worker-owned runner', () async {
    final runner = IsolateOcrModelRunner(_BusyRunner());
    addTearDown(runner.dispose);

    await runner.load();
    await runner.load();
    expect((await runner.recognize(_image())).single.text, endsWith('call 1'));
    expect((await runner.recognize(_image())).single.text, endsWith('call 2'));
  });

  test(
    'returns inference failures without killing the worker protocol',
    () async {
      final runner = IsolateOcrModelRunner(_BusyRunner(fail: true));
      addTearDown(runner.dispose);

      await expectLater(
        runner.recognize(_image()),
        throwsA(
          isA<StateError>().having(
            (error) => '$error',
            'message',
            contains('synthetic inference failure'),
          ),
        ),
      );
      await expectLater(
        runner.recognize(_image()),
        throwsA(isA<StateError>()),
        reason: 'a page-level error must not terminate the long-lived worker',
      );
    },
  );

  test('a load failure is reported once and dispose remains safe', () async {
    final runner = IsolateOcrModelRunner(_BusyRunner(failLoad: true));

    await expectLater(
      runner.load(),
      throwsA(
        isA<StateError>().having(
          (error) => '$error',
          'message',
          contains('synthetic load failure'),
        ),
      ),
    );
    await expectLater(runner.dispose(), completes);
  });
}
