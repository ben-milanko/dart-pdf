import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/l10n/app_localizations.dart';
import 'package:dart_pdf_editor_app/recents.dart';
import 'package:dart_pdf_editor_app/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final region in ['AU', 'GB', 'US']) {
    testWidgets('settings license label follows English $region',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = PdfEditingPreferences();
      final recents = RecentsStore();
      addTearDown(prefs.dispose);
      addTearDown(recents.dispose);
      await prefs.ready;
      await tester.pumpWidget(MaterialApp(
        locale: Locale('en', region),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Builder(builder: (context) {
          return TextButton(
            onPressed: () =>
                showAppSettings(context, prefs: prefs, recents: recents),
            child: const Text('Settings'),
          );
        })),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      // Cache usage reads IndexedDB in browsers; its unrelated progress spinner
      // need not settle for the Settings route and licence link to be ready.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final tile = find.byKey(const ValueKey('settings-licenses'));
      await tester.ensureVisible(tile);
      expect(
          find.descendant(
              of: tile,
              matching: find
                  .text(region == 'US' ? 'View licenses' : 'View licences')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final region in ['AU', 'GB', 'US', '']) {
    testWidgets('app and editor follow device English $region', (tester) async {
      final british = region == 'AU' || region == 'GB';
      tester.binding.platformDispatcher.localesTestValue = [
        Locale('en', region.isEmpty ? null : region),
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      expect(find.text(british ? 'Centre on paper' : 'Center on paper'),
          findsOneWidget);
      expect(find.text(british ? 'Colour' : 'Color'), findsOneWidget);
      expect(
          find.text(british
              ? 'Align horizontal centres'
              : 'Align horizontal centers'),
          findsOneWidget);
      expect(
          find.text(
              british ? 'Organisation (optional)' : 'Organization (optional)'),
          findsOneWidget);
      expect(find.text(british ? 'OCR cancelled' : 'OCR canceled'),
          findsOneWidget);
      expect(
          find.text(british
              ? 'OCR cancelled after 2 text spans'
              : 'OCR canceled after 2 text spans'),
          findsOneWidget);
      expect(
          find.text(british
              ? 'Browser OCR failed to initialise'
              : 'Browser OCR failed to initialize'),
          findsOneWidget);
      expect(find.text(british ? 'Replaced 2 colours' : 'Replaced 2 colors'),
          findsOneWidget);
      expect(
          find.text(british
              ? 'For a signing certificate from your organisation'
              : 'For a signing certificate from your organization'),
          findsOneWidget);
      expect(find.text(british ? 'Text colour' : 'Text color'), findsOneWidget);
      expect(find.text(british ? 'Recolour…' : 'Recolor…'), findsOneWidget);
      expect(find.text(british ? 'Cancelled' : 'Canceled'), findsOneWidget);
    });
  }

  testWidgets('switching English region updates both delegates',
      (tester) async {
    for (final region in ['US', 'GB', 'AU', 'US']) {
      await tester.pumpWidget(_host(locale: Locale('en', region)));
      // Delegates load synchronously: the spelling changes in this frame.
      expect(find.text(region == 'US' ? 'Color' : 'Colour'), findsOneWidget);
      expect(find.text(region == 'US' ? 'Center on paper' : 'Centre on paper'),
          findsOneWidget);
    }
  });
}

Widget _host({Locale? locale}) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        DartPdfEditorLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        final app = AppLocalizations.of(context)!;
        final editor = DartPdfEditorLocalizations.of(context)!;
        return Scaffold(
            body: Column(children: [
          Text(app.printOptionsCenter),
          Text(app.ocrCancelled),
          Text(app.ocrCancelledAfterSpans(2)),
          Text(app.ocrBrowserInitFailed),
          Text(app.appSigUseOwnCertificateSubtitle),
          Text(editor.colorColorTitle),
          Text(editor.tbAlignHorizontalCenters),
          Text(editor.signIdOrganization),
          Text(editor.tbColorsReplaced(2)),
          Text(editor.tbTextColour),
          Text(editor.menuRecolour),
          Text(editor.sbarStateCancelled),
        ]));
      }),
    );
