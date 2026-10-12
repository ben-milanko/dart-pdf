import 'package:dart_pdf_editor_app/l10n/app_delegates.dart';
import 'package:dart_pdf_editor_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('generated app locales use English as the final fallback', () {
    expect(AppLocalizations.supportedLocales.first, const Locale('en'));
  });

  final unsupportedPreferences = <String, List<Locale>?>{
    'uninitialized': null,
    'empty': const [],
    'C locale': const [Locale('c')],
    'undetermined': const [Locale('und')],
    'unsupported Finnish': const [Locale('fi', 'FI')],
  };
  for (final entry in unsupportedPreferences.entries) {
    test('${entry.key} preferences fall back to English', () {
      expect(
        basicLocaleListResolution(
          entry.value,
          AppLocalizations.supportedLocales,
        ),
        const Locale('en'),
      );
    });
  }

  for (final locale in AppLocalizations.supportedLocales) {
    test('explicit supported locale $locale remains selected', () {
      expect(
        basicLocaleListResolution([locale], AppLocalizations.supportedLocales),
        locale,
      );
    });
  }

  test('a later supported preference wins over the fallback', () {
    expect(
      basicLocaleListResolution(
        const [Locale('fi', 'FI'), Locale('ja', 'JP')],
        AppLocalizations.supportedLocales,
      ),
      const Locale('ja'),
    );
  });

  test('unlisted English region uses generic English', () {
    expect(
      basicLocaleListResolution(
        const [Locale('en', 'NZ')],
        AppLocalizations.supportedLocales,
      ),
      const Locale('en'),
    );
  });

  testWidgets('C device locale renders English open-file text left to right',
      (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('c')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('Open a PDF'), findsOneWidget);
    final context = tester.element(find.byKey(const ValueKey('open-file')));
    expect(Localizations.localeOf(context), const Locale('en'));
    expect(Directionality.of(context), TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic device locale keeps Arabic text and right to left',
      (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [
      Locale('ar', 'EG'),
    ];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.text('فتح ملف PDF'), findsOneWidget);
    final context = tester.element(find.byKey(const ValueKey('open-file')));
    expect(Localizations.localeOf(context), const Locale('ar'));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an explicit language still overrides an unsupported device',
      (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('c')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(_host(locale: const Locale('ar')));
    await tester.pumpAndSettle();
    expect(find.text('فتح ملف PDF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _host({Locale? locale}) => MaterialApp(
      locale: locale,
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: basicLocaleListResolution,
      home: Builder(builder: (context) {
        return Scaffold(
          body: Text(
            AppLocalizations.of(context)!.welcomeOpenPdf,
            key: const ValueKey('open-file'),
          ),
        );
      }),
    );
