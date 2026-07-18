import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'devtools.dart';
import 'editor_screen.dart';
import 'keyless_signing.dart';
import 'oidc_signin.dart';
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

  // Reuse a Sigstore login across Digitally sign dialogs: cache the id_token,
  // refresh it silently when it expires, and only sign in via the browser when
  // there's nothing to reuse. Off the web only (loopback needs a local server).
  final _oidcTokenProvider = kIsWeb ? null : SigstoreSignInManager();

  @override
  void initState() {
    super.initState();
    // Log/frame-timing capture for the F12 developer tools.
    if (kDevToolsEnabled) AppDevTools.instance.install();
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
    // Proactive process-level ceiling across the viewer's budgeted caches
    // (decoded images 256 MB + render records + previews + thumbnails + tiles
    // can sum past 600 MB, and desktop OSes deliver the memory-pressure signal
    // that used to be the only trim too late, if at all - see the 2026-07-18
    // memory audit). The split between the ceiling and the per-cache budgets
    // is heuristic pending a re-run of benchmark_image_cache_budget_test.
    PdfCacheRegistry.instance.maxTotalWeight = switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia =>
        192 << 20,
      _ => 384 << 20,
    };
    // Persisted devtools options (deep-zoom mode, overlays, worker count)
    // override the defaults above once loaded.
    if (kDevToolsEnabled) unawaited(AppDevTools.instance.restoreOptions());
    // Offer the host's installed fonts in the editor's font menu by default.
    // Fire-and-forget: the registry is read when a font menu opens, and an
    // empty result (web, or a locked-down platform) just leaves the base-14,
    // bundled and "Load font…" choices.
    unawaited(_loadPlatformFonts());
  }

  Future<void> _loadPlatformFonts() async {
    try {
      pdfPlatformFonts = await loadPlatformFonts();
    } catch (e) {
      // Font discovery is best-effort; the menu degrades to its other choices.
      AppDevTools.instance
          .addLog('platform font discovery failed: $e', level: DevLogLevel.error);
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
        // Share the same signing login across every window (see build()).
        oidcTokenProvider: _oidcTokenProvider?.call,
        oidcSilentTokenProvider: _oidcTokenProvider == null
            ? null
            : (context) => _oidcTokenProvider.silentToken(),
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
      // Keyless signing via Sigstore's public OAuth broker. Loopback capture
      // needs a local server, so it's offered off the web only. A still-valid
      // login is reused rather than re-prompting each time.
      oidcTokenProvider: _oidcTokenProvider?.call,
      // Silent source for pre-selecting keyless on open: it never opens the
      // browser (returns null when interactive sign-in would be needed).
      oidcSilentTokenProvider: _oidcTokenProvider == null
          ? null
          : (context) => _oidcTokenProvider.silentToken(),
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
    this.oidcTokenProvider,
    this.oidcSilentTokenProvider,
    this.persistSession = true,
  });

  final PdfEditingPreferences prefs;
  final List<String> launchArgs;
  final bool autoCheckUpdates;
  final bool persistSession;

  /// Keyless signing token providers, forwarded to the [EditorScreen]. Shared
  /// across every window so one signing login is reused everywhere.
  final OidcTokenProvider? oidcTokenProvider;
  final OidcTokenProvider? oidcSilentTokenProvider;

  /// Opens another window; null when multi-window support is unavailable, which
  /// hides the "New window" affordances.
  final void Function(BuildContext context)? onNewWindow;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [prefs, AppDevTools.instance.showPerformanceOverlay]),
      builder: (context, _) => MaterialApp(
        title: 'DartPDF',
        showPerformanceOverlay:
            AppDevTools.instance.showPerformanceOverlay.value,
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
          oidcTokenProvider: oidcTokenProvider,
          oidcSilentTokenProvider: oidcSilentTokenProvider,
          persistSession: persistSession,
        ),
      ),
    );
  }
}
