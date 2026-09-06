import 'dart:async';

import 'package:dart_pdf_editor_app/file_io.dart';
import 'package:dart_pdf_editor_app/l10n/app_localizations.dart';
import 'package:dart_pdf_editor_app/language_names.dart';
import 'package:dart_pdf_editor_app/reduce_file_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_test_fixtures/pdf_test_fixtures.dart';

void main() {
  for (final scenario in [
    (
      region: 'AU',
      button: 'Optimise',
      progress: 'Optimising document…',
      result: 'Optimised size',
      step: 'optimisation',
    ),
    (
      region: 'GB',
      button: 'Optimise',
      progress: 'Optimising document…',
      result: 'Optimised size',
      step: 'optimisation',
    ),
    (
      region: 'US',
      button: 'Optimize',
      progress: 'Optimizing document…',
      result: 'Optimized size',
      step: 'optimization',
    ),
  ]) {
    testWidgets('size dialog follows platform English ${scenario.region}',
        (tester) async {
      tester.binding.platformDispatcher.localesTestValue = [
        Locale('en', scenario.region),
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final pending = Completer<PdfCompressionResult>();
      final bytes = buildClassicPdf();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          return TextButton(
            onPressed: () => showReduceFileSizeDialog(
              context,
              bytes: bytes,
              title: 'Report.pdf',
              hasSignatures: false,
              runner: (_, __) => pending.future,
              saveCopy: (_, __, ___) async => SaveResult.cancelled,
            ),
            child: const Text('Open'),
          );
        }),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
          find.widgetWithText(FilledButton, scenario.button), findsOneWidget);
      expect(
        find.text(
            '${scenario.button} the current document, review the savings, '
            'then save a smaller copy.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('reduce-size-run')));
      await tester.pump();
      await tester.pump();
      expect(find.text(scenario.progress), findsOneWidget);

      pending.complete(PdfCompressionResult(
        bytes: bytes,
        bytesBefore: bytes.length + 1000,
        bytesAfter: bytes.length,
        objectsBefore: 5,
        objectsAfter: 4,
        streamsDeflated: 1,
        compacted: true,
        steps: [
          PdfCompressionStep(
            kind: PdfCompressionKind.structure,
            bytesBefore: bytes.length + 1000,
            bytesAfter: bytes.length,
          ),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.text(scenario.result), findsOneWidget);
      expect(find.text('Bytes saved by each ${scenario.step} step:'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('regional English choices have distinct language-picker labels', () {
    expect(
        AppLocalizations.supportedLocales, contains(const Locale('en', 'AU')));
    expect(
        AppLocalizations.supportedLocales, contains(const Locale('en', 'GB')));
    expect(
        languageDisplayName(const Locale('en', 'AU')), 'English (Australia)');
    expect(languageDisplayName(const Locale('en', 'GB')),
        'English (United Kingdom)');
    expect(languageDisplayName(const Locale('en')), 'English');
  });
}
