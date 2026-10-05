import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_app/l10n/app_delegates.dart';
import 'package:dart_pdf_editor_app/l10n/app_localizations.dart';
import 'package:dart_pdf_printing/l10n/dart_pdf_printing_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// The app's delegate list is written out by hand because gen-l10n's
// AppLocalizations.localizationsDelegates still lists the legacy
// flutter_localizations delegates, which give a material_ui MaterialApp no
// Material strings outside English (a Ukrainian app crashed on the first
// MaterialLocalizations.of with them).
void main() {
  for (final locale in const [Locale('uk'), Locale('de'), Locale('ar')]) {
    testWidgets('every bundle resolves for $locale', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (context) {
          captured = context;
          return const SizedBox();
        }),
      ));
      expect(tester.takeException(), isNull);
      expect(AppLocalizations.of(captured)!.localeName, locale.languageCode);
      expect(DartPdfEditorLocalizations.of(captured), isNotNull);
      expect(DartPdfPrintingLocalizations.of(captured), isNotNull);
      // material_ui's own translation, not the English default.
      final material = MaterialLocalizations.of(captured);
      expect(material, isNot(isA<DefaultMaterialLocalizations>()));
      expect(material.cancelButtonLabel,
          isNot(const DefaultMaterialLocalizations().cancelButtonLabel));
    });
  }
}
