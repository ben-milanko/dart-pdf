import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';

import 'editor_screen.dart';

/// The DartPDF application. Owns the device-local UI preferences so
/// the MaterialApp can follow the persisted light/dark choice and every
/// editing session shares the same tool styles, panel layout, and viewport
/// memory.
class DartPdfEditorApp extends StatefulWidget {
  const DartPdfEditorApp({super.key, this.launchArgs = const []});

  /// Command-line arguments the app was launched with (desktop file opens).
  final List<String> launchArgs;

  @override
  State<DartPdfEditorApp> createState() => _DartPdfEditorAppState();
}

class _DartPdfEditorAppState extends State<DartPdfEditorApp> {
  final _prefs = PdfEditingPreferences();

  @override
  void dispose() {
    _prefs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) => MaterialApp(
        title: 'DartPDF',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        themeMode: _prefs.themeMode,
        home: EditorScreen(prefs: _prefs, launchArgs: widget.launchArgs),
      ),
    );
  }
}
