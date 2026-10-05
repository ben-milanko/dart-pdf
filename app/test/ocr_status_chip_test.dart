// The app-bar OCR chip: its spinner always turns (so a long page still reads
// as alive), completion rides a bar along the bottom edge - determinate when
// the job knows how far along it is, sweeping otherwise - and the close
// button cancels.
import 'package:dart_pdf_editor_app/ocr_status.dart';
import 'package:dart_pdf_editor_app/ocr_status_chip.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpChip(
    WidgetTester tester,
    OcrJobStatus status, {
    VoidCallback? onCancel,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(actions: [
          OcrStatusChip(status: status, onCancel: onCancel ?? () {}),
        ]),
      ),
    ));
  }

  CircularProgressIndicator spinner(WidgetTester tester) =>
      tester.widget(find.byKey(const ValueKey('ocr-status-spinner')));

  LinearProgressIndicator bar(WidgetTester tester) =>
      tester.widget(find.byKey(const ValueKey('ocr-status-progress')));

  testWidgets('a single page in progress spins and shows no completion',
      (tester) async {
    await pumpChip(
      tester,
      const OcrJobStatus(
        phase: OcrPhase.recognising,
        title: 'Scan.pdf',
        page: 1,
        pageCount: 1,
      ),
    );
    expect(find.text('Reading text…'), findsOneWidget);
    expect(find.text('OCR 1/1'), findsNothing);
    expect(spinner(tester).value, isNull, reason: 'always turning');
    expect(bar(tester).value, 0);
  });

  testWidgets('the bar eases to the new fraction as pages finish',
      (tester) async {
    await pumpChip(
      tester,
      const OcrJobStatus(
        phase: OcrPhase.recognising,
        title: 'Scan.pdf',
        page: 2,
        pageCount: 4,
      ),
    );
    expect(find.text('OCR page 2 of 4'), findsOneWidget);
    expect(bar(tester).value, closeTo(0.25, 1e-9));

    await pumpChip(
      tester,
      const OcrJobStatus(
        phase: OcrPhase.recognising,
        title: 'Scan.pdf',
        page: 3,
        pageCount: 4,
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    final mid = bar(tester).value!;
    expect(mid, greaterThan(0.25));
    expect(mid, lessThan(0.5));
    await tester.pump(const Duration(milliseconds: 200));
    expect(bar(tester).value, closeTo(0.5, 1e-9));
  });

  testWidgets('download shows its percent; preparing sweeps', (tester) async {
    await pumpChip(
      tester,
      const OcrJobStatus(
        phase: OcrPhase.downloading,
        title: 'Scan.pdf',
        downloadFraction: 0.4,
      ),
    );
    expect(find.text('Downloading model 40%'), findsOneWidget);
    expect(bar(tester).value, closeTo(0.4, 1e-9));

    await pumpChip(
      tester,
      const OcrJobStatus(phase: OcrPhase.preparing, title: 'Scan.pdf'),
    );
    await tester.pump();
    expect(find.text('Loading OCR model…'), findsOneWidget);
    expect(bar(tester).value, isNull, reason: 'switches to sweeping');
  });

  testWidgets('cancel button calls onCancel', (tester) async {
    var cancelled = 0;
    await pumpChip(
      tester,
      const OcrJobStatus(phase: OcrPhase.finishing, title: 'Scan.pdf'),
      onCancel: () => cancelled++,
    );
    await tester.tap(find.byKey(const ValueKey('ocr-status-cancel')));
    expect(cancelled, 1);
  });
}
