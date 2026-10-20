import 'package:flutter/widgets.dart';

import '../../l10n/dart_pdf_editor_localizations.dart';
import '../../l10n/dart_pdf_editor_localizations_en.dart';

/// Resolves the editor UI's localizations for [context], falling back to
/// English when the host app hasn't registered
/// [DartPdfEditorLocalizations.delegate] - package widgets therefore work
/// out of the box, and hosts opt into translations by adding
/// [DartPdfEditorLocalizations.localizationsDelegates] to their app.
DartPdfEditorLocalizations pdfL10n(BuildContext context) =>
    Localizations.of<DartPdfEditorLocalizations>(
        context, DartPdfEditorLocalizations) ??
    DartPdfEditorLocalizationsEn();
