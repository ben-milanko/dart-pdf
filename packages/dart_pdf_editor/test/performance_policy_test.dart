import 'package:flutter_test/flutter_test.dart';
import 'package:dart_pdf_editor/dart_pdf_editor.dart';

PdfPerformanceEnvironment env({
  PdfPerformancePlatform platform = PdfPerformancePlatform.desktop,
  int cores = 8,
  int pages = 100,
  int bytes = 20 << 20,
}) =>
    PdfPerformanceEnvironment(
      platform: platform,
      logicalProcessors: cores,
      pageCount: pages,
      documentBytes: bytes,
    );

void main() {
  test('Auto chooses conservative platform and memory-aware worker counts', () {
    const auto = PdfPerformanceMode.auto();
    expect(
        PdfPerformancePolicy.initialWorkerCount(
            env(platform: PdfPerformancePlatform.mobile), auto),
        2);
    expect(
        PdfPerformancePolicy.initialWorkerCount(
            env(platform: PdfPerformancePlatform.desktop), auto),
        3);
    expect(
        PdfPerformancePolicy.initialWorkerCount(
            env(platform: PdfPerformancePlatform.web, cores: 2), auto),
        1);
    expect(PdfPerformancePolicy.initialWorkerCount(env(pages: 6), auto), 1,
        reason: 'short documents do not pay for a pool');
    expect(
        PdfPerformancePolicy.initialWorkerCount(env(bytes: 600 << 20), auto), 1,
        reason: 'each worker holds its own document/decode working set');
    expect(
        PdfPerformancePolicy.initialWorkerCount(
            env(cores: 32), const PdfPerformanceMode.auto(maxWorkers: 2)),
        2);
  });

  test('fixed mode remains fixed under telemetry', () {
    final controller = PdfPerformanceController(
      mode: const PdfPerformanceMode.fixed(
        workerCount: 5,
        previewWindow: 7,
        imagePixelRatioCap: 2.5,
        vectorFirstPreviews: true,
      ),
      environment: env(),
    );
    addTearDown(controller.dispose);

    expect(controller.beginWorkerGeneration(), 5);
    for (var i = 0; i < 20; i++) {
      controller.observe(const PdfPerformanceSample(
        workerRecordDuration: Duration(seconds: 2),
        resultBytes: 64 << 20,
        jankyFrame: true,
      ));
    }
    expect(controller.tuning.workerCount, 5);
    expect(controller.tuning.previewWindow, 7);
    expect(controller.tuning.imagePixelRatioCap, 2.5);
    expect(controller.tuning.vectorFirstPreviews, isTrue);
    expect(controller.diagnostics.observations, 0);
  });

  test('slow samples tune safe knobs live and defer worker resize', () {
    final controller = PdfPerformanceController(
        environment: env(platform: PdfPerformancePlatform.web));
    addTearDown(controller.dispose);
    expect(controller.beginWorkerGeneration(), 3);

    for (var i = 0; i < 3; i++) {
      controller.observe(const PdfPerformanceSample(
        workerRecordDuration: Duration(milliseconds: 220),
        resultBytes: 20 << 20,
        jankyFrame: true,
      ));
    }

    expect(controller.tuning.tier, PdfPerformanceTier.conservative);
    expect(controller.tuning.previewWindow, 2);
    expect(controller.tuning.imagePixelRatioCap, 1.25);
    expect(controller.tuning.vectorFirstPreviews, isTrue);
    expect(controller.diagnostics.currentWorkerCount, 3);
    expect(controller.diagnostics.pendingWorkerCount, 2,
        reason: 'the live pool is never resized during scrolling');
    expect(controller.diagnostics.toString(), contains('next restart'));

    expect(controller.beginWorkerGeneration(), 2);
    expect(controller.diagnostics.pendingWorkerCount, isNull);
  });

  test('cheap samples widen warming only after hysteresis', () {
    final controller = PdfPerformanceController(environment: env());
    addTearDown(controller.dispose);
    controller.beginWorkerGeneration();

    const cheap = PdfPerformanceSample(
      workerRecordDuration: Duration(milliseconds: 12),
      resultBytes: 128 << 10,
    );
    controller.observe(cheap);
    controller.observe(cheap);
    expect(controller.tuning.tier, PdfPerformanceTier.balanced);
    controller.observe(cheap);
    expect(controller.tuning.tier, PdfPerformanceTier.throughput);
    expect(controller.tuning.previewWindow, 10);
    expect(controller.tuning.workerCount, 4);

    // The five-observation cooldown prevents an immediate opposite swing.
    const slow = PdfPerformanceSample(
      workerRecordDuration: Duration(milliseconds: 500),
      resultBytes: 32 << 20,
      jankyFrame: true,
    );
    controller.observe(slow);
    controller.observe(slow);
    controller.observe(slow);
    expect(controller.tuning.tier, PdfPerformanceTier.throughput);
  });

  test('alternating evidence does not oscillate the policy', () {
    final controller = PdfPerformanceController(environment: env());
    addTearDown(controller.dispose);
    const slow = PdfPerformanceSample(
        workerRecordDuration: Duration(milliseconds: 250), jankyFrame: true);
    const cheap =
        PdfPerformanceSample(workerRecordDuration: Duration(milliseconds: 10));
    controller
      ..observe(slow)
      ..observe(cheap)
      ..observe(slow)
      ..observe(cheap);
    expect(controller.tuning.tier, PdfPerformanceTier.balanced);
  });

  test('large documents start conservative before telemetry arrives', () {
    final environment = env(pages: 500, bytes: 300 << 20);
    final controller = PdfPerformanceController(environment: environment);
    addTearDown(controller.dispose);
    expect(controller.tuning.tier, PdfPerformanceTier.conservative);
    expect(controller.tuning.previewWindow, 2);
    expect(controller.tuning.vectorFirstPreviews, isTrue);
    expect(controller.beginWorkerGeneration(), 1);
  });
}
