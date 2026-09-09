import 'package:flutter/widgets.dart';
import 'dart_pdf_printing_localizations.dart';
import 'dart_pdf_printing_localizations_en.dart';

/// English fallback allows the print UI to work in a bare MaterialApp.
DartPdfPrintingLocalizations printL10n(BuildContext context) =>
    Localizations.of<DartPdfPrintingLocalizations>(
        context, DartPdfPrintingLocalizations) ??
    DartPdfPrintingLocalizationsEn();
