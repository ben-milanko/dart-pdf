import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'editor_screen.dart';
import 'platform_fonts.dart';
import 'window_support.dart';

/// The DartPDF application. Owns the device-local UI preferences so
/// the MaterialApp can follow the persisted light/dark choice and every
/// editing session shares the same tool styles, panel layout, and viewport
/// memory.
///
/// When multi-window support is enabled ([multiWindowSupported]), every
/// additional OS window opened from the "New window" action renders another
/// [_DartPdfWindow] backed by *this* app's [_prefs], so theme and tool styles
/// stay in lock-step across windows. The preferences outlive every window and
/// are disposed here with the app.
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

  /// Opens another top-level window hosting a fresh editor that shares this
  /// app's preferences. [context] must belong to a currently open window (any
  /// one works) so the new window joins the same registry. A no-op when
  /// windowing isn't available.
  void _openNewWindow(BuildContext context) {
    openRegularWindow(
      context,
      title: 'DartPDF',
      builder: (context) => _DartPdfWindow(
        prefs: _prefs,
        onNewWindow: _openNewWindow,
        // Only the primary window owns the single persisted session; extra
        // windows start empty so they don't reopen or clobber it.
        persistSession: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _DartPdfWindow(
      prefs: _prefs,
      launchArgs: widget.launchArgs,
      autoCheckUpdates: true,
      onNewWindow: multiWindowSupported ? _openNewWindow : null,
    );
  }
}

/// One window's worth of DartPDF: a themed [MaterialApp] around an
/// [EditorScreen]. Reused for the primary window and every window opened via
/// "New window", all sharing the same [prefs] so theme/tool changes propagate
/// everywhere at once.
class _DartPdfWindow extends StatelessWidget {
  const _DartPdfWindow({
    required this.prefs,
    this.launchArgs = const [],
    this.autoCheckUpdates = false,
    this.onNewWindow,
    this.persistSession = true,
  });

  final PdfEditingPreferences prefs;
  final List<String> launchArgs;
  final bool autoCheckUpdates;
  final bool persistSession;

  /// Opens another window; null when multi-window support is unavailable, which
  /// hides the "New window" affordances.
  final void Function(BuildContext context)? onNewWindow;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => MaterialApp(
        title: 'DartPDF',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        themeMode: prefs.themeMode,
        home: EditorScreen(
          prefs: prefs,
          launchArgs: launchArgs,
          autoCheckUpdates: autoCheckUpdates,
          onNewWindow: onNewWindow,
          persistSession: persistSession,
        ),
      ),
    );
  }
}
