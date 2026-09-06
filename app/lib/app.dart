import 'dart:async';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:dart_pdf_editor_assets/dart_pdf_editor_assets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'adaptive_memory.dart';
import 'devtools.dart';
import 'document_tab.dart';
import 'editor_screen.dart';
import 'keyless_signing.dart';
import 'l10n/app_localizations.dart';
import 'oidc_signin.dart';
import 'platform_fonts.dart';
import 'tab_drag.dart';
import 'window_support.dart';

/// The DartPDF application. Owns the device-local UI preferences so
/// the MaterialApp can follow the persisted light/dark choice and every
/// editing session shares the same tool styles, panel layout, and viewport
/// memory.
///
/// Experimental secondary windows reuse this state so preferences, memory
/// budgets, developer options, and the keyless-signing session remain
/// process-wide rather than being initialized once per native window.
class DartPdfEditorApp extends StatefulWidget {
  const DartPdfEditorApp({super.key, this.launchArgs = const []});

  /// Command-line arguments the app was launched with (desktop file opens).
  final List<String> launchArgs;

  @override
  State<DartPdfEditorApp> createState() => _DartPdfEditorAppState();
}

class _DartPdfEditorAppState extends State<DartPdfEditorApp> {
  final _prefs = PdfEditingPreferences();
  final _tabDragCoordinator = TabDragCoordinator();
  late final AdaptiveMemoryBudgetController _memoryBudget =
      AdaptiveMemoryBudgetController();

  // Reuse a Sigstore login across Digitally sign dialogs: cache the id_token,
  // refresh it silently when it expires, and only sign in via the browser when
  // there's nothing to reuse. Off the web only (loopback needs a local server).
  final _oidcTokenProvider = kIsWeb ? null : SigstoreSignInManager();

  @override
  void initState() {
    super.initState();
    // Register the optional bundled editor fonts + web render worker so the app
    // keeps the full-featured editor. A viewer-only app would drop the
    // dart_pdf_editor_assets dependency and this call to save the ~1.7 MB.
    registerBundledEditorAssets();
    // Competitive-harness-only zero-copy presentation experiment. Keeping it
    // URL-gated means normal users and correctness suites stay on the complete
    // SkWasm renderer while `PERF_DART_QUERY=domSurface=1` can A/B the worker-
    // owned OffscreenCanvas path against PDFium with the identical journey.
    PdfPageView.webDomRasterPresentation =
        Uri.base.queryParameters['domSurface'] == '1';
    // Log/frame-timing capture for the F12 developer tools.
    if (kDevToolsEnabled) AppDevTools.instance.install();
    // A small pool gives native heavy CAD/image pages real overlap without
    // multiplying document memory too far. In Chromium, one worker matched
    // two-worker visual latency on the real-world journey while removing a
    // complete document/decode working set; the runtime performance policy
    // uses the same web default.
    pdfRenderWorkerPoolSize = kIsWeb
        ? 1
        : switch (defaultTargetPlatform) {
            TargetPlatform.android ||
            TargetPlatform.iOS ||
            TargetPlatform.fuchsia =>
              2,
            _ => 3,
          };
    // Warm the render worker now, before any document is opened: on the web this
    // fetches, compiles, and boots the ~1 MB worker script (~1.45 s on a phone,
    // #450) so that cost overlaps the user choosing a file instead of blocking
    // the first render. A later open adopts the pre-booted worker and only hands
    // off the document. No-op off-web (isolate spawn is cheap).
    PdfRenderWorker.prewarm(count: pdfRenderWorkerPoolSize);
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
    // Cross-page ceiling over the base rasters, detail patches, and retained-
    // scene images the live pages in the scroll cacheExtent hold at once - the
    // additive-per-page memory #405 measured. Farther-from-viewport pages are
    // reclaimed first when the sum exceeds this; the on-screen page and its
    // neighbours always fit.
    PdfLiveRasterBudget.instance.maxBytes = pdfDefaultLiveRasterBudgetBytes();
    // Persisted developer overrides load before the adaptive memory sampler.
    // Fresh installs stay in Auto; an older build's explicit page-raster
    // setting is migrated as a fixed diagnostic override.
    unawaited(_startMemoryBudget());
    // Offer the host's installed fonts in the editor's font menu by default.
    // Fire-and-forget: the registry is read when a font menu opens, and an
    // empty result (web, or a locked-down platform) just leaves the base-14,
    // bundled and "Load font…" choices.
    unawaited(_loadPlatformFonts());
  }

  Future<void> _startMemoryBudget() async {
    if (kDevToolsEnabled) await AppDevTools.instance.restoreOptions();
    if (!mounted) return;
    await _memoryBudget.start(periodic: !runningUnderFlutterTest);
  }

  Future<void> _loadPlatformFonts() async {
    try {
      pdfPlatformFonts = await loadPlatformFonts();
    } catch (e) {
      // Font discovery is best-effort; the menu degrades to its other choices.
      AppDevTools.instance.addLog('platform font discovery failed: $e',
          level: DevLogLevel.error);
    }
  }

  @override
  void dispose() {
    _memoryBudget.dispose();
    _tabDragCoordinator.dispose();
    _prefs.dispose();
    super.dispose();
  }

  bool _openNewWindow(
    BuildContext context, {
    DocumentHandoff? document,
  }) {
    return openRegularWindow(
      context,
      title: 'DartPDF',
      builder: (_) => _DartPdfWindow(
        prefs: _prefs,
        tabDragCoordinator: _tabDragCoordinator,
        onNewWindow: _openNewWindow,
        initialHandoff: document,
        oidcTokenProvider: _oidcTokenProvider?.call,
        oidcSilentTokenProvider: _oidcTokenProvider == null
            ? null
            : (context) => _oidcTokenProvider.silentToken(),
        // Only the primary owns process-wide file opens, crash recovery,
        // session persistence, update checks, and the application-exit prompt.
        ownsApplicationSession: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _DartPdfWindow(
      prefs: _prefs,
      tabDragCoordinator: _tabDragCoordinator,
      launchArgs: widget.launchArgs,
      autoCheckUpdates: true,
      onNewWindow: multiWindowSupported ? _openNewWindow : null,
      oidcTokenProvider: _oidcTokenProvider?.call,
      oidcSilentTokenProvider: _oidcTokenProvider == null
          ? null
          : (context) => _oidcTokenProvider.silentToken(),
    );
  }
}

/// One native window's Material application and editor screen.
///
/// Each window needs its own Navigator, focus tree, overlays, and editor tabs,
/// while the owning [DartPdfEditorApp] supplies shared process state.
class _DartPdfWindow extends StatelessWidget {
  const _DartPdfWindow({
    required this.prefs,
    required this.tabDragCoordinator,
    this.launchArgs = const [],
    this.autoCheckUpdates = false,
    this.onNewWindow,
    this.initialHandoff,
    this.oidcTokenProvider,
    this.oidcSilentTokenProvider,
    this.ownsApplicationSession = true,
  });

  final PdfEditingPreferences prefs;
  final TabDragCoordinator tabDragCoordinator;
  final List<String> launchArgs;
  final bool autoCheckUpdates;
  final bool ownsApplicationSession;
  final DocumentHandoff? initialHandoff;
  final OidcTokenProvider? oidcTokenProvider;
  final OidcTokenProvider? oidcSilentTokenProvider;
  final bool Function(
    BuildContext context, {
    DocumentHandoff? document,
  })? onNewWindow;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        prefs,
        AppDevTools.instance.showPerformanceOverlay,
        AppDevTools.instance.localeOverride,
      ]),
      builder: (context, _) => MaterialApp(
        title: 'DartPDF',
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          DartPdfEditorLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        // The effective locale (DevTools override, else the persisted Settings
        // choice, else null = "System default") is passed as `locale` rather
        // than only consulted inside the resolution callback. This matters:
        // WidgetsApp re-resolves the locale when `locale` changes, but NOT when
        // an external value the callback reads changes - so driving it purely
        // from the callback made a runtime language switch appear to do nothing
        // until the next rebuild for another reason. Feeding it here re-resolves
        // immediately when the user picks a language or flips the DevTools
        // override.
        locale: AppDevTools.instance.localeOverride.value ?? prefs.locale,
        // The DevTools override still wins and is returned verbatim, so it can
        // force a locale that isn't in supportedLocales (untranslated app
        // strings fall back to English, but Directionality and the Material
        // delegates follow it - enough to test the RTL sweep). With no
        // override, defer to Flutter's own algorithm over the preferred-locale
        // list (the Settings locale when set, else the FULL platform list) so
        // the normal fallback chain is unchanged.
        localeListResolutionCallback: (locales, supportedLocales) {
          final override = AppDevTools.instance.localeOverride.value;
          if (override != null) return override;
          return basicLocaleListResolution(locales, supportedLocales);
        },
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
          tabDragCoordinator: tabDragCoordinator,
          launchArgs: launchArgs,
          autoCheckUpdates: autoCheckUpdates,
          onNewWindow: onNewWindow,
          initialHandoff: initialHandoff,
          oidcTokenProvider: oidcTokenProvider,
          oidcSilentTokenProvider: oidcSilentTokenProvider,
          ownsApplicationSession: ownsApplicationSession,
        ),
      ),
    );
  }
}
