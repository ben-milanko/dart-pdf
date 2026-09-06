import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_viewer_example/l10n/app_localizations.dart';

void main() {
  for (final region in ['AU', 'GB', 'US']) {
    testWidgets('example and editor follow device English $region',
        (tester) async {
      tester.binding.platformDispatcher.localesTestValue = [
        Locale('en', region)
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          DartPdfEditorLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          return Column(children: [
            Text(AppLocalizations.of(context)!.exRecognisingPage(1, 3)),
            Text(AppLocalizations.of(context)!.exApiKeyHelper),
            Text(DartPdfEditorLocalizations.of(context)!.shellPageColor),
          ]);
        }),
      ));
      await tester.pumpAndSettle();
      expect(
          find.text(region == 'US'
              ? 'Recognizing page 1 of 3…'
              : 'Recognising page 1 of 3…'),
          findsOneWidget);
      expect(find.text(region == 'US' ? 'Page color…' : 'Page colour…'),
          findsOneWidget);
      // Protocol identifiers retain their required spelling in every locale.
      expect(find.text('Sent as Authorization: Bearer …'), findsOneWidget);
    });
  }
}
