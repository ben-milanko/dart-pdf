import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'editor_screen.dart';
import 'oidc_signin.dart';
import 'oidc_token_cache.dart';
import 'platform_fonts.dart';

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

  // Reuse a still-valid Sigstore login across Digitally sign dialogs instead
  // of re-running the browser OAuth each time. Off the web only (loopback).
  final _oidcTokenProvider =
      kIsWeb ? null : CachingOidcTokenProvider(sigstoreOidcTokenProvider);

  @override
  void initState() {
    super.initState();
    // A small pool gives heavy CAD/image pages real overlap without multiplying
    // document memory too far. Mobile-class targets get a lower default; the
    // perf harness is allowed to be more aggressive.
    pdfRenderWorkerPoolSize = switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia =>
        2,
      _ => 3,
    };
    // Offer the host's installed fonts in the editor's font menu by default.
    // Fire-and-forget: the registry is read when a font menu opens, and an
    // empty result (web, or a locked-down platform) just leaves the base-14,
    // bundled and "Load font…" choices.
    unawaited(_loadPlatformFonts());
  }

  Future<void> _loadPlatformFonts() async {
    try {
      pdfPlatformFonts = await loadPlatformFonts();
    } catch (_) {
      // Font discovery is best-effort; the menu degrades to its other choices.
    }
  }

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
        home: EditorScreen(
          prefs: _prefs,
          launchArgs: widget.launchArgs,
          autoCheckUpdates: true,
          // Keyless signing via Sigstore's public OAuth broker. Loopback
          // capture needs a local server, so it's offered off the web only.
          // A still-valid login is reused rather than re-prompting each time,
          // and pre-selects the keyless identity when the dialog opens.
          oidcTokenProvider: _oidcTokenProvider?.call,
          keylessLoginAvailable: () =>
              _oidcTokenProvider?.hasValidToken ?? false,
        ),
      ),
    );
  }
}
