import 'package:dart_pdf_editor/dart_pdf_editor.dart'
    show PdfEditorLocalizations;
import 'package:dart_pdf_printing/l10n/dart_pdf_printing_localizations.dart';
import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// Every [MaterialApp] in the app registers this list.
///
/// It is written out instead of spreading gen-l10n's
/// `AppLocalizations.localizationsDelegates`: that generated list still
/// carries the legacy `flutter_localizations` delegates, which give a
/// material_ui app no Material or Cupertino strings for most locales.
/// [PdfEditorLocalizations.delegates] is the editor's bundle plus
/// material_ui's `GlobalMaterialLocalizations.delegates` (Material,
/// cupertino_ui's Cupertino strings, and widgets).
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  DartPdfPrintingLocalizations.delegate,
  ...PdfEditorLocalizations.delegates,
];
