// PrintProgressDialog shows "page X of Y" while a print job rasterises pages.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_pdf_editor_app/print_progress_dialog.dart';

void main() {
  Future<void> pump(WidgetTester tester, ValueListenable<(int, int)?> p) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PrintProgressDialog(progress: p)),
    ));
  }

  testWidgets('shows "Preparing…" and an indeterminate bar before the first page',
      (tester) async {
    final progress = ValueNotifier<(int, int)?>(null);
    addTearDown(progress.dispose);
    await pump(tester, progress);

    expect(find.text('Preparing…'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(bar.value, isNull); // indeterminate
  });

  testWidgets('shows the page counter and a determinate bar as it advances',
      (tester) async {
    final progress = ValueNotifier<(int, int)?>((2, 5));
    addTearDown(progress.dispose);
    await pump(tester, progress);

    expect(find.text('Rendering page 2 of 5…'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(0.4, 1e-9));

    // Advancing the notifier updates the dialog in place.
    progress.value = (5, 5);
    await tester.pump();
    expect(find.text('Rendering page 5 of 5…'), findsOneWidget);
    final done = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(done.value, closeTo(1.0, 1e-9));
  });
}
