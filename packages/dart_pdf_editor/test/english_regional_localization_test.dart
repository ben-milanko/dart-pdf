import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final region in ['AU', 'GB', 'US']) {
    testWidgets('editor dialogs use device English $region', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PdfEditingPreferences();
      addTearDown(preferences.dispose);
      await preferences.ready;
      tester.binding.platformDispatcher.localesTestValue = [
        Locale('en', region)
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates:
            DartPdfEditorLocalizations.localizationsDelegates,
        supportedLocales: DartPdfEditorLocalizations.supportedLocales,
        home: Scaffold(body: Builder(builder: (context) {
          return Column(children: [
            TextButton(
              onPressed: () =>
                  showPdfEditingGuidesDialog(context, preferences: preferences),
              child: const Text('Guides'),
            ),
            TextButton(
              onPressed: () =>
                  showPdfColorPicker(context, initial: Colors.blue),
              child: const Text('Picker'),
            ),
          ]);
        })),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guides'));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Snap annotation edges and ${region == 'US' ? 'centers' : 'centres'} • Hold Alt to bypass'),
          findsOneWidget);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Picker'));
      await tester.pumpAndSettle();
      expect(find.text(region == 'US' ? 'Color' : 'Colour'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
