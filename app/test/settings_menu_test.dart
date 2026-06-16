import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dart_pdf_editor_app/editor_screen.dart';

void main() {
  late PdfEditingPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = PdfEditingPreferences();
  });

  tearDown(() => prefs.dispose());

  testWidgets('settings offer default application setup', (tester) async {
    await tester.pumpWidget(MaterialApp(home: EditorScreen(prefs: prefs)));
    await tester.pump();

    await tester.tap(find.byTooltip('DartPDF menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-default-app')), findsOneWidget);
    expect(find.text('Set up as default application'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-default-app')));
    await tester.pumpAndSettle();

    expect(find.text('Set up as default application'), findsWidgets);
    expect(find.textContaining('PDF'), findsWidgets);
  });
}
