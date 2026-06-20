import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/app.dart';

void main() {
  setUp(() {
    // The mock store is process-global; reset it so a prior test's persisted
    // preferences never leak into this one.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('boots into the empty state with an Open button',
      (WidgetTester tester) async {
    await tester.pumpWidget(const DartPdfEditorApp());
    await tester.pump();

    // No document open yet: the empty state offers a way in.
    expect(find.widgetWithText(FilledButton, 'Open a PDF'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
  });
}
