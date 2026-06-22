import 'package:dart_pdf_editor/dart_pdf_editor.dart';

/// Web (and any other target without `dart:io`) can't read OS font files, so
/// the editor's platform-font menu stays empty there — the base-14 families,
/// the bundled fonts and "Load font…" still apply.
Future<List<PdfPlatformFont>> loadPlatformFonts() async => const [];
