// PrintProgressDialog shows "page X of Y" while a print job rasterises pages.
import 'package:dart_pdf_printing/dart_pdf_printing.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dialog's progress bar.
final progressBar = find.byKey(const ValueKey('print-progress-bar'));

void main() {
  Future<void> pump(WidgetTester tester, ValueListenable<(int, int)?> p) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PrintProgressDialog(progress: p)),
    ));
  }

  testWidgets(
      'shows "Preparing…" and an indeterminate bar before the first page',
      (tester) async {
    final progress = ValueNotifier<(int, int)?>(null);
    addTearDown(progress.dispose);
    await pump(tester, progress);

    expect(find.text('Preparing…'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(progressBar);
    expect(bar.value, isNull); // indeterminate
  });

  testWidgets('shows the page counter and a determinate bar as it advances',
      (tester) async {
    final progress = ValueNotifier<(int, int)?>((2, 5));
    addTearDown(progress.dispose);
    await pump(tester, progress);

    expect(find.text('Rendering page 2 of 5…'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(progressBar);
    expect(bar.value, closeTo(0.4, 1e-9));

    // Advancing the notifier updates the dialog in place.
    progress.value = (5, 5);
    await tester.pump();
    expect(find.text('Rendering page 5 of 5…'), findsOneWidget);
    final done = tester.widget<LinearProgressIndicator>(progressBar);
    expect(done.value, closeTo(1.0, 1e-9));
  });
}
