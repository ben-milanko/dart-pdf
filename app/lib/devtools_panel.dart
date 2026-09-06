/// The in-app developer tools panel (F12, or Settings → Developer tools).
///
/// A docked side panel over the editor: frame timings, process/cache memory,
/// the experimental deep-zoom detail mode switch (#314 tile pyramid vs the
/// shipping patch), PdfPerf phase/counter accumulators, session diagnostics,
/// and the captured log. Model state lives in `devtools.dart`; this file is
/// pure presentation. Available in every build mode (release included) unless
/// stripped with `--dart-define=DEVTOOLS=false` ([kDevToolsEnabled]); the
/// debug-engine-only toggles gate themselves inside the panel.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'app_info.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show debugRepaintRainbowEnabled;
import 'package:flutter/services.dart';
// ignore: implementation_imports - the perf facade is deliberately unexported.
import 'package:pdf_cos/perf.dart';
import 'package:url_launcher/url_launcher.dart';

import 'devtools.dart';
import 'file_io.dart';

const _defaultGpuPreviewDownloads = <String, String>{
  'macOS': String.fromEnvironment('PDF_GPU_MACOS_PREVIEW_URL'),
  'Windows': String.fromEnvironment('PDF_GPU_WINDOWS_PREVIEW_URL'),
  'Linux': String.fromEnvironment('PDF_GPU_LINUX_PREVIEW_URL'),
};

/// Identifies the exact artifact that produced a diagnostics export.
///
/// Version and build number are not enough for PR previews, where several
/// commits intentionally share the same package version. Keep the compile-time
/// commit beside them so a report can be matched to its deployed source.
@visibleForTesting
Map<String, String> devToolsBuildIdentity() => <String, String>{
      'appVersion': AppInfo.version,
      'appBuild': AppInfo.buildNumber,
      'buildCommit': AppInfo.buildCommit,
    };

/// Developer tools panel. Create it only off-release. Docks as a side panel on
/// wide screens; pass [bottomSheet] to render it as a phone bottom sheet.
class DevToolsPanel extends StatefulWidget {
  const DevToolsPanel({
    super.key,
    required this.onClose,
    this.session,
    this.viewerController,
    this.documentTitle,
    this.bottomSheet = false,
    this.gpuPreviewDownloads = _defaultGpuPreviewDownloads,
  });

  final VoidCallback onClose;

  /// The active tab's edit session, when one is open.
  final PdfEditingController? session;

  /// The active tab's viewer, used to tie page/backend diagnostics to what the
  /// user was actually looking at when the snapshot was exported.
  final PdfViewerController? viewerController;

  /// Human-readable active tab title. This is diagnostic metadata only.
  final String? documentTitle;

  /// Render as a bottom sheet (phones) rather than a right-docked side panel:
  /// a rounded, height-capped card with a drag-handle affordance and its own
  /// close button, instead of the resizable side dock.
  final bool bottomSheet;

  /// Native builds published beside a web preview, keyed by platform label.
  /// Empty URLs are omitted.
  final Map<String, String> gpuPreviewDownloads;

  @override
  State<DevToolsPanel> createState() => _DevToolsPanelState();
}

class _DevToolsPanelState extends State<DevToolsPanel> {
  final _tools = AppDevTools.instance;
  Timer? _refresh;
  String _logFilter = '';

  @override
  void initState() {
    super.initState();
    // Caches, RSS, and PdfPerf have no change notifications; poll while open.
    _refresh =
        Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return widget.bottomSheet ? _buildBottomSheet(theme) : _buildDocked(theme);
  }

  /// The same docked chrome the editor's own sidebars (Annotations, Pages)
  /// use: shared frame, resize grip, surface color, compact close button.
  /// The width is session-local (no persistence preference).
  Widget _buildDocked(ThemeData theme) {
    return PdfSidebarPanelFrame(
      width: 360,
      minWidth: 300,
      maxWidth: 560,
      dock: PdfPanelDock.right,
      resizable: true,
      bottomSheet: false,
      gripKey: const ValueKey('devtools-resize-grip'),
      onClose: widget.onClose,
      builder: (context, geometry) => Material(
        key: const ValueKey('devtools-panel'),
        color: theme.colorScheme.surfaceContainerLow,
        child: Column(
          children: [
            _header(theme, geometry),
            Expanded(child: _scrollBody(theme, geometry)),
          ],
        ),
      ),
    );
  }

  /// Phone presentation: a rounded, height-capped card anchored to the bottom.
  /// The frame runs in [PdfSidebarPanelFrame.bottomSheet] mode (no grip, no
  /// fixed cross-axis size), so this owns the rounded surface, the height cap,
  /// and the grab-handle affordance.
  Widget _buildBottomSheet(ThemeData theme) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    return PdfSidebarPanelFrame(
      width: 360,
      minWidth: 300,
      maxWidth: 560,
      dock: PdfPanelDock.bottom,
      resizable: false,
      bottomSheet: true,
      gripKey: const ValueKey('devtools-resize-grip'),
      onClose: widget.onClose,
      builder: (context, geometry) => Material(
        key: const ValueKey('devtools-panel'),
        color: theme.colorScheme.surfaceContainerLow,
        elevation: 8,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _grabHandle(theme),
              _header(theme, geometry),
              Flexible(child: _scrollBody(theme, geometry)),
            ],
          ),
        ),
      ),
    );
  }

  /// The scrolling stack of sections, shared by both presentations. An eager
  /// column, not a lazy list: every section stays live so its metrics keep
  /// updating (and are findable) off-screen.
  Widget _scrollBody(ThemeData theme, PdfSidebarPanelGeometry geometry) {
    return ListenableBuilder(
      listenable: _tools,
      builder: (context, _) => SingleChildScrollView(
        padding: EdgeInsets.only(bottom: 16, left: geometry.contentStartInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _framesSection(theme),
            _localeSection(theme),
            _memorySection(theme),
            _workersSection(theme),
            _deepZoomSection(theme),
            _tileBackendSection(theme),
            _perfSection(theme),
            if (widget.session != null) _sessionSection(theme),
            _logSection(theme),
          ],
        ),
      ),
    );
  }

  Widget _grabHandle(ThemeData theme) => Container(
        width: 32,
        height: 4,
        margin: const EdgeInsets.only(top: 8, bottom: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _header(ThemeData theme, PdfSidebarPanelGeometry geometry) {
    // In bottom-sheet mode the frame renders no close button (it owns no
    // chrome), so the sheet supplies its own.
    final closeButton =
        geometry.closeButton(key: const ValueKey('devtools-close')) ??
            (widget.bottomSheet
                ? IconButton(
                    key: const ValueKey('devtools-close'),
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Close',
                    onPressed: widget.onClose,
                  )
                : null);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          12 + geometry.contentStartInset, 8, closeButton != null ? 4 : 12, 4),
      child: Row(
        children: [
          Icon(Icons.build_outlined,
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Developer tools', style: theme.textTheme.titleMedium),
          ),
          IconButton(
            key: const ValueKey('devtools-export'),
            icon: const Icon(Icons.download_outlined, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: 'Export snapshot as JSON',
            onPressed: () => unawaited(_exportSnapshot()),
          ),
          if (closeButton != null) closeButton,
        ],
      ),
    );
  }

  /// One JSON document with everything the panel shows, for offline analysis
  /// (spreadsheets, diffing two sessions, attaching to an issue).
  Future<void> _exportSnapshot() async {
    final frames = _tools.frameStats();
    final session = widget.session;
    final store = PdfPageView.tileStoreDetail
        ? (PdfPageView.debugTileStoreOverride ?? PdfTileStore.instance)
        : PdfPageView.debugTileStoreOverride;
    final snapshot = <String, Object?>{
      'tool': 'dartpdf-devtools',
      'exportedAt': DateTime.now().toIso8601String(),
      // Which build produced this export. Without it a report cannot be tied
      // to a revision - "slow on 2.0.0" is unactionable when several builds
      // share that version.
      ...devToolsBuildIdentity(),
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'buildMode': kDebugMode
          ? 'debug'
          : kReleaseMode
              ? 'release'
              : 'profile',
      'frames': {
        'window': frames.frames,
        'fps': frames.fps,
        'avgBuildMs': frames.avgBuildMs,
        'avgRasterMs': frames.avgRasterMs,
        'worstFrameMs': frames.worstFrameMs,
        'jankFrames': frames.jankFrames,
      },
      'memory': {
        'rssBytes': _tools.currentRssBytes,
        'rssHighWaterBytes': _tools.maxRssBytes,
        'cacheTotalBytes': PdfCacheRegistry.instance.totalWeight,
        'cacheCeilingBytes': PdfCacheRegistry.instance.maxTotalWeight,
        'pageRasterCacheBytes': _tools.pageRasterCachePolicy.value.maxBytes,
        'pageRasterCacheEntryBytes':
            _tools.pageRasterCachePolicy.value.maxEntryBytes,
        'pageRasterCacheMode': _tools.pageRasterCacheMode.name,
        'pageRasterCacheReason': _tools.pageRasterCacheReason,
        'safeProcessLimitBytes': _tools.safeProcessLimitBytes,
        'caches': [
          for (final cache in PdfCacheRegistry.instance.snapshot())
            {
              'label': cache.label,
              'entries': cache.length,
              'bytes': cache.weight,
              'budgetBytes': cache.maxWeight,
              'hits': cache.hits,
              'misses': cache.misses,
              'evictions': cache.evictions,
            },
        ],
      },
      'renderWorkers': pdfRenderWorkerPoolSize,
      'deepZoomMode': _deepZoomMode,
      'tileRasterBackend': {
        'requested': _tools.tileRasterBackendMode.value.name,
        'debugLabel': _tools.tileRasterBackend.debugLabel,
        'platformSupported':
            _tools.flutterGpuTileRasterBackend.isPlatformSupported,
        'observedOutcome': _tileBackendOutcome(),
        'maxTextureBytes': _tools.flutterGpuTileRasterBackend.maxTextureBytes,
        'maxGeometryBytes': _tools.flutterGpuTileRasterBackend.maxGeometryBytes,
        'overprintApproximation': _tools.gpuOverprintApproximation,
        'stats': _tools.flutterGpuTileRasterBackend.stats.toJson(),
      },
      'tileRasterPages': PdfTileRasterDiagnostics.instance.snapshot(),
      if (store != null)
        'tileStore': {
          'tiles': store.tileCount,
          'namespaces': store.debugNamespaceCount,
          'retainedBytes': store.retainedBytes,
          'inFlight': store.inFlightCount,
          'scheduled': store.debugTilesScheduled,
          'landed': store.debugTilesLanded,
          'discarded': store.debugTilesDiscarded,
          'batches': store.debugBatchesDispatched,
        },
      'pdfPerf': PdfPerf.snapshot().toJson(),
      if (widget.viewerController != null)
        'activeView': {
          'documentTitle': widget.documentTitle,
          'currentPage': widget.viewerController!.currentPage + 1,
          'pagePresentationEpoch':
              widget.viewerController!.pagePresentationEpoch,
          'tileCacheNamespace':
              widget.viewerController!.tileCacheNamespaceIdentity,
        },
      if (session != null)
        'session': {
          'documentTitle': widget.documentTitle,
          'sessionIdentity': identityHashCode(session),
          'documentIdentity': identityHashCode(session.document),
          'tileCacheNamespace':
              widget.viewerController?.tileCacheNamespaceIdentity,
          'pages': session.document.pageCount,
          'currentPage': widget.viewerController == null
              ? null
              : widget.viewerController!.currentPage + 1,
          'pageColor':
              '#${session.preferences.pageColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
          'showAnnotations': session.preferences.showAnnotations,
          'highlightFormFields': session.preferences.highlightFormFields,
          'currentRevisionBytes': session.bytes.length,
          'sessionBufferBytes': session.sessionBufferBytes,
          'revisions': session.revisionCount,
          'revisionId': session.revisionId,
          'lastWorkerRevisionIncremental': session.lastRevisionDelta != null,
          'pagePresentationEpoch':
              widget.viewerController?.pagePresentationEpoch,
          'currentPageRenderStamp': widget.viewerController == null
              ? null
              : session.pageRenderStamp(
                  widget.viewerController!.currentPage,
                ),
          'currentPageContentStamp': widget.viewerController == null
              ? null
              : session.pageContentRenderStamp(
                  widget.viewerController!.currentPage,
                ),
          'currentPageDestructiveStamp': widget.viewerController == null
              ? null
              : session.pageDestructiveStamp(
                  widget.viewerController!.currentPage,
                ),
        },
      'log': [
        for (final entry in _tools.log)
          {
            'time': entry.time.toIso8601String(),
            'level': entry.level.name,
            'message': entry.message,
          },
      ],
    };
    final stamp =
        DateTime.now().toIso8601String().replaceAll(':', '').split('.').first;
    final result = await saveJsonAs(
      context,
      const JsonEncoder.withIndent('  ').convert(snapshot),
      'dartpdf-devtools-$stamp.json',
      // The developer tools stay English (excluded from the app l10n).
      typeLabel: 'DartPDF stamps',
    );
    _tools.addLog('devtools: snapshot export ${result.runtimeType}');
  }

  // --- render workers -------------------------------------------------------

  static const _workersHelp =
      'Background isolates that interpret pages and decode images off the UI '
      'thread. More workers overlap heavy pages but each holds its own parsed '
      'copy of the document. Changes apply to the NEXT spawned pool - reopen '
      'the document or switch tabs to respawn.';

  Widget _workersSection(ThemeData theme) => _section(theme, 'Render workers', [
        Row(
          children: [
            Expanded(
              child: Tooltip(
                message: _workersHelp,
                waitDuration: const Duration(milliseconds: 600),
                child: InkWell(
                  onTap: () => _explain('Render worker pool', _workersHelp),
                  child: Text('Pool size', style: theme.textTheme.bodySmall),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('devtools-workers-down'),
              icon: const Icon(Icons.remove, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: pdfRenderWorkerPoolSize > 1
                  ? () => setState(() {
                        pdfRenderWorkerPoolSize--;
                        _persist();
                      })
                  : null,
            ),
            Text('$pdfRenderWorkerPoolSize', style: theme.textTheme.bodyMedium),
            IconButton(
              key: const ValueKey('devtools-workers-up'),
              icon: const Icon(Icons.add, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: pdfRenderWorkerPoolSize < 8
                  ? () => setState(() {
                        pdfRenderWorkerPoolSize++;
                        _persist();
                      })
                  : null,
            ),
          ],
        ),
        Text(
          'Applies to the next worker pool: reopen the document or switch '
          'tabs to respawn.',
          style: theme.textTheme.bodySmall!
              .copyWith(color: theme.colorScheme.outline),
        ),
      ]);

  /// A short menu of locales for exercising localization at runtime - RTL ones
  /// especially, to test the directional-layout sweep. Only English app
  /// strings ship today, so a non-English pick shows the Material widgets'
  /// own translations (and RTL layout for Arabic/Hebrew) while app text falls
  /// back to English.
  static const List<(Locale?, String)> _testLocales = [
    (null, 'System default'),
    (Locale('en'), 'English'),
    (Locale('es'), 'Español (Spanish)'),
    (Locale('de'), 'Deutsch (German)'),
    (Locale('fr'), 'Français (French)'),
    (Locale('ja'), '日本語 (Japanese)'),
    (Locale('ar'), 'العربية (Arabic) — RTL'),
    (Locale('he'), 'עברית (Hebrew) — RTL'),
  ];

  Widget _localeSection(ThemeData theme) {
    final override = AppDevTools.instance.localeOverride;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return _section(theme, 'Locale (testing)', [
      DropdownButton<Locale?>(
        key: const ValueKey('devtools-locale-dropdown'),
        isExpanded: true,
        value: override.value,
        items: [
          for (final (locale, label) in _testLocales)
            DropdownMenuItem<Locale?>(
              value: locale,
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (locale) => setState(() => override.value = locale),
      ),
      Text(
        'Forces the whole app onto a locale, bypassing platform resolution. '
        'Only English translations ship today, so other locales show the '
        'Material widgets translated (and RTL layout for Arabic/Hebrew) while '
        'app strings fall back to English. Session-only - not persisted.',
        style: theme.textTheme.bodySmall!
            .copyWith(color: theme.colorScheme.outline),
      ),
      const SizedBox(height: 4),
      _kv(theme, 'Layout direction',
          rtl ? 'RTL (right-to-left)' : 'LTR (left-to-right)',
          help: 'The ambient Directionality the app is currently laying out '
              'with. RTL locales (Arabic, Hebrew) flip it; the chrome mirrors '
              'via EdgeInsetsDirectional / AlignmentDirectional.'),
    ]);
  }

  Widget _section(ThemeData theme, String title, List<Widget> children,
          {Widget? trailing}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleSmall),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 4),
            ...children,
            const Divider(height: 20),
          ],
        ),
      );

  /// One metric row. With [help], the row explains itself twice over: the
  /// text as a hover tooltip, and a tap opens the same explanation as a
  /// dialog (for touch, and for reading at leisure).
  Widget _kv(ThemeData theme, String key, String value, {String? help}) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            child: Text(key, style: theme.textTheme.bodySmall),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall!.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    if (help == null) return row;
    return Tooltip(
      message: help,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: () => _explain(key.trim(), help),
        child: row,
      ),
    );
  }

  void _explain(String title, String text) {
    showPdfDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 420, child: Text(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// A switch row with the same tooltip + tap-dialog explanation as [_kv]:
  /// the tooltip covers the whole tile, and an info affordance opens the
  /// dialog (the tile's own tap has to stay the toggle).
  Widget _helpSwitch(
    ThemeData theme, {
    required Key? key,
    required String title,
    required String help,
    Widget? subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) =>
      Tooltip(
        message: help,
        waitDuration: const Duration(milliseconds: 600),
        child: SwitchListTile(
          key: key,
          dense: true,
          contentPadding: EdgeInsets.zero,
          secondary: IconButton(
            icon: const Icon(Icons.info_outline, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'What is this?',
            onPressed: () => _explain(title, help),
          ),
          title: Text(title),
          subtitle: subtitle,
          value: value,
          onChanged: onChanged,
        ),
      );

  static String _mb(num bytes) =>
      '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';

  // --- frames ---------------------------------------------------------------

  Widget _framesSection(ThemeData theme) {
    final stats = _tools.frameStats();
    return _section(theme, 'Frames', [
      _kv(theme, 'FPS (last ${stats.frames} frames)',
          stats.frames == 0 ? 'idle' : stats.fps.toStringAsFixed(1),
          help: 'Frame rate over the sampled window (up to 120 frames). '
              'Flutter only produces frames when something animates or '
              'repaints, so "idle" while nothing moves is normal and good.'),
      _kv(
          theme,
          'Avg build / raster',
          '${stats.avgBuildMs.toStringAsFixed(1)} / '
              '${stats.avgRasterMs.toStringAsFixed(1)} ms',
          help: 'Average per-frame time on the UI thread (widget build/layout) '
              'and the raster thread (painting the frame on the GPU). Either '
              'one exceeding ~16.7 ms means dropped frames at 60 Hz.'),
      _kv(theme, 'Worst frame', '${stats.worstFrameMs.toStringAsFixed(1)} ms',
          help: 'The slowest single frame in the window, build + raster '
              'combined. One bad frame is a visible hitch even when the '
              'averages look fine.'),
      _kv(theme, 'Jank frames (>16.7 ms)', '${stats.jankFrames}',
          help: 'Frames in the window whose build + raster exceeded 16.7 ms - '
              'each one missed a 60 Hz deadline and was visible as jank.'),
      if (!kReleaseMode)
        _helpSwitch(
          theme,
          key: null,
          title: 'Performance overlay',
          help: "Flutter's built-in overlay graphing UI-thread and raster-"
              'thread frame times on top of the app. Available in debug and '
              'profile builds; profile numbers are the meaningful ones.',
          value: _tools.showPerformanceOverlay.value,
          onChanged: (v) => setState(() {
            _tools.showPerformanceOverlay.value = v;
            _persist();
          }),
        ),
      if (kDebugMode)
        _helpSwitch(
          theme,
          key: null,
          title: 'Repaint rainbow',
          help: 'Debug-only: every repainted region cycles through colors on '
              'each repaint, showing what actually repaints. If the whole '
              'page flashes on scroll, something is forcing full-screen '
              'repaints.',
          value: debugRepaintRainbowEnabled,
          onChanged: (v) => setState(() => debugRepaintRainbowEnabled = v),
        ),
    ]);
  }

  // --- memory ---------------------------------------------------------------

  static const _pageRasterBudgets = <(int, String)>[
    (-1, 'Auto (recommended)'),
    (0, 'Off'),
    (32 << 20, '32 MB'),
    (64 << 20, '64 MB'),
    (128 << 20, '128 MB'),
    (256 << 20, '256 MB'),
    (512 << 20, '512 MB'),
    (1 << 30, '1 GB'),
    (2 << 30, '2 GB'),
    (5 * (1 << 30), '5 GB'),
    (8 * (1 << 30), '8 GB'),
  ];

  static const _pageRasterEntryBudgets = <(int, String)>[
    (0, 'Off'),
    (4 << 20, '4 MB'),
    (8 << 20, '8 MB'),
    (16 << 20, '16 MB'),
    (32 << 20, '32 MB'),
    (64 << 20, '64 MB'),
    (128 << 20, '128 MB'),
    (256 << 20, '256 MB'),
    (512 << 20, '512 MB'),
    (1 << 30, '1 GB'),
  ];
  static const _gpuBudgets = <(int, String)>[
    (64 << 20, '64 MB'),
    (128 << 20, '128 MB'),
    (256 << 20, '256 MB'),
    (512 << 20, '512 MB'),
    (1 << 30, '1 GB'),
    (2 << 30, '2 GB'),
    (4 * (1 << 30), '4 GB'),
    (8 * (1 << 30), '8 GB'),
  ];
  static const _fixedEntrySeedBytes = 256 << 20;

  // Full-raster warm (#614) as a single selector. -1 is off, 0 is the whole
  // document, a positive value is that many pages either side. Enabled modes
  // also use their bounded directional window during slow scrolling.
  static const _rasterWarmChoices = <(int, String)>[
    (-1, 'Off'),
    (2, 'Nearby +/-2'),
    (5, 'Nearby +/-5'),
    (0, 'Whole document'),
  ];

  static String _rasterWarmLabel(PdfPageRasterWarmPolicy policy) {
    if (!policy.enabled) return 'Off';
    final slowWindow = policy.mode == PdfPageRasterWarmMode.nearby
        ? math.min(policy.window, policy.slowScrollWindow)
        : policy.slowScrollWindow;
    final idle = policy.mode == PdfPageRasterWarmMode.nearby
        ? 'Idle ±${policy.window}'
        : 'All idle';
    return '$idle · slow →$slowWindow';
  }

  void _setPageRasterWarm(int choice) {
    _tools.setPageRasterWarmPolicy(switch (choice) {
      < 0 => const PdfPageRasterWarmPolicy.disabled(),
      0 => const PdfPageRasterWarmPolicy.document(),
      final window => PdfPageRasterWarmPolicy.nearby(window: window),
    });
    _persist();
    setState(() {});
  }

  Widget _byteBudgetControl(
    ThemeData theme, {
    required Key key,
    required String title,
    required String help,
    required int value,
    String? valueLabel,
    required List<(int, String)> choices,
    required ValueChanged<int> onChanged,
  }) =>
      Row(
        children: [
          Expanded(
            child: Tooltip(
              message: help,
              waitDuration: const Duration(milliseconds: 600),
              child: InkWell(
                onTap: () => _explain(title, help),
                child: Text(title, style: theme.textTheme.bodySmall),
              ),
            ),
          ),
          PopupMenuButton<int>(
            key: key,
            tooltip: 'Change $title',
            onSelected: onChanged,
            itemBuilder: (context) => [
              for (final (bytes, label) in choices)
                PopupMenuItem<int>(
                  value: bytes,
                  child: Text(label),
                ),
            ],
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 0, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    valueLabel ?? _byteBudgetLabel(value),
                    style: theme.textTheme.bodySmall!.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
        ],
      );

  static String _byteBudgetLabel(int bytes) {
    if (bytes < 0) return 'Auto';
    if (bytes == 0) return 'Off';
    if (bytes % (1 << 30) == 0) return '${bytes ~/ (1 << 30)} GB';
    return '${bytes ~/ (1 << 20)} MB';
  }

  void _setPageRasterCache({int? maxBytes, int? maxEntryBytes}) {
    final wasAuto = _tools.pageRasterCacheAuto;
    final current = wasAuto
        ? _tools.pageRasterCachePolicy.value
        : _tools.fixedPageRasterCachePolicy;
    // Entering fixed mode from Auto should carry a useful per-page admission
    // limit with it. Keeping the dormant fixed default (16 MB) made a 5 GB
    // preset reject an ordinary capped CAD raster such as 8192×812 (25.4 MB),
    // which made the total selector look broken. Once fixed mode is active,
    // later total changes preserve the user's explicit non-zero per-page
    // choice; moving from Off seeds it again.
    final shouldSeedEntry = maxBytes != null &&
        maxEntryBytes == null &&
        (wasAuto || current.maxEntryBytes == 0);
    final seededEntry = shouldSeedEntry
        ? maxBytes == 0
            ? 0
            : math.min(
                maxBytes,
                math.max(current.maxEntryBytes, _fixedEntrySeedBytes),
              )
        : current.maxEntryBytes;
    _tools.setPageRasterCachePolicy(PdfPageRasterCachePolicy(
      maxBytes: maxBytes ?? current.maxBytes,
      maxEntryBytes: maxEntryBytes ?? seededEntry,
    ));
    _persist();
    setState(() {});
  }

  Widget _memorySection(ThemeData theme) {
    final rss = _tools.currentRssBytes;
    final peak = _tools.maxRssBytes;
    final caches = PdfCacheRegistry.instance.snapshot();
    final rasterPolicy = _tools.pageRasterCachePolicy.value;
    final rasterAuto = _tools.pageRasterCacheAuto;
    return _section(
      theme,
      'Memory',
      [
        _kv(theme, 'Process RSS', rss == null ? 'n/a on web' : _mb(rss),
            help: 'Resident set size of the whole process: Dart heaps for '
                'every isolate, the engine, GPU-backed images, and native '
                'allocations. This is the number the OS acts on (macOS '
                'pauses the app over it). Not observable from a web tab.'),
        if (peak != null)
          _kv(theme, 'RSS high-water', _mb(peak),
              help: 'The highest resident set size the process has reached '
                  'since launch. Memory freed later does not lower it.'),
        _kv(theme, 'Budgeted caches (this isolate)',
            _mb(PdfCacheRegistry.instance.totalWeight),
            help: 'Sum of every budgeted LRU cache registered in the main '
                'isolate: decoded images, render records, previews, '
                'thumbnails, and deep-zoom tiles when active.'),
        _kv(
            theme,
            'Coordinated ceiling',
            PdfCacheRegistry.instance.maxTotalWeight == 0
                ? 'off'
                : _mb(PdfCacheRegistry.instance.maxTotalWeight),
            help: 'Process-level cap across all registered caches, enforced '
                'proactively as caches grow rather than waiting for the '
                "platform's memory-pressure signal (which desktop OSes "
                'deliver too late, if at all). Over the ceiling, every cache '
                'is trimmed proportionally, least-recently-used first.'),
        _byteBudgetControl(
          theme,
          key: const ValueKey('devtools-page-raster-budget'),
          title: 'Visited-page rasters',
          help: 'Full-resolution rasters kept after a page scrolls out of the '
              'viewer build window. Raising this makes revisits instant at the '
              'cost of RAM; Off keeps only the small fast-scroll previews. '
              'Changes apply immediately and persist across restarts.',
          value: rasterAuto ? -1 : _tools.fixedPageRasterCachePolicy.maxBytes,
          valueLabel: rasterAuto
              ? 'Auto · ${_byteBudgetLabel(rasterPolicy.maxBytes)}'
              : null,
          choices: _pageRasterBudgets,
          onChanged: (value) {
            if (value < 0) {
              _tools.useAutoPageRasterCache();
              _persist();
              setState(() {});
            } else {
              _setPageRasterCache(maxBytes: value);
            }
          },
        ),
        if (rasterAuto)
          _kv(
            theme,
            'Largest cached page',
            _byteBudgetLabel(rasterPolicy.maxEntryBytes),
            help: 'Auto derives the per-page admission limit from the total '
                'headroom, capped at 256 MB. Switch the total cache to a fixed '
                'preset to override it.',
          )
        else
          _byteBudgetControl(
            theme,
            key: const ValueKey('devtools-page-raster-entry-budget'),
            title: 'Largest cached page',
            help: 'Per-page admission limit for the visited-page raster cache. '
                'Large CAD sheets and high-DPI pages above this size are not '
                'retained even when the total budget has room. The lower of '
                'this value and the total budget is effective.',
            value: _tools.fixedPageRasterCachePolicy.maxEntryBytes,
            choices: _pageRasterEntryBudgets,
            onChanged: (value) => _setPageRasterCache(maxEntryBytes: value),
          ),
        _byteBudgetControl(
          theme,
          key: const ValueKey('devtools-page-raster-warm'),
          title: 'Page raster warm',
          help: 'Spends genuine viewer idle time rasterizing pages ahead of '
              'navigation, so arriving on them paints instantly instead of '
              'rendering first. During sustained slow scrolling, an '
              'accelerated backend also keeps up to three pages sharp in the '
              'travel direction, one GPU submission at a time; fast motion, '
              'foreground work, and direction changes stop further work. '
              'Unsupported pages use the exact Canvas fallback only after '
              'scrolling is idle. Both paths stay inside the visited-page '
              'raster budget, '
              'so a large file settles into a moving window rather than '
              'growing without limit.',
          value: _tools.pageRasterWarmPolicy.value.mode ==
                  PdfPageRasterWarmMode.disabled
              ? -1
              : _tools.pageRasterWarmPolicy.value.window,
          valueLabel: _rasterWarmLabel(_tools.pageRasterWarmPolicy.value),
          choices: _rasterWarmChoices,
          onChanged: _setPageRasterWarm,
        ),
        if (_tools.safeProcessLimitBytes case final limit?)
          _kv(
            theme,
            'Auto process target',
            _mb(limit),
            help: 'Conservative process RSS target derived from physical RAM, '
                'currently available memory, and any platform process limit. '
                'The cache allocation leaves an additional safety reserve '
                'below this target.',
          ),
        _kv(
          theme,
          'Raster policy reason',
          _tools.pageRasterCacheReason,
          help: 'Why Auto chose its current effective limit. Growth is slow; '
              'low headroom and memory pressure shrink it immediately.',
        ),
        if (!rasterAuto)
          Text(
            'Fixed presets remain subject to the process-wide safety ceiling.',
            style: theme.textTheme.bodySmall!
                .copyWith(color: theme.colorScheme.outline),
          ),
        for (final cache in caches)
          _kv(
              theme,
              '  ${cache.label} (${cache.length})',
              cache.maxWeight > 0
                  ? '${_mb(cache.weight)} / ${_mb(cache.maxWeight)}'
                      ' · ${cache.hits}/${cache.misses}/${cache.evictions}'
                  : '${_mb(cache.weight)}'
                      ' · ${cache.hits}/${cache.misses}/${cache.evictions}',
              help: '${_cacheExplanation(cache.label)} '
                  'Trailing counters are hits/misses/evictions.'),
        Text(
          'Worker isolates hold parsed documents and command transcripts, '
          'not decoded pixels; their memory is not itemized here.',
          style: theme.textTheme.bodySmall!
              .copyWith(color: theme.colorScheme.outline),
        ),
      ],
      trailing: TextButton(
        key: const ValueKey('devtools-clear-caches'),
        onPressed: () {
          final freed = PdfCacheRegistry.instance.handleMemoryPressure();
          _tools.clearGpuImageCache();
          _tools.addLog('devtools: cleared caches, freed ${_mb(freed)}');
          setState(() {});
        },
        child: const Text('Clear'),
      ),
    );
  }

  /// Per-cache explanations keyed by [PdfBudgetedCache.debugLabel], with a
  /// generic fallback for labels this map has not caught up with.
  static const _cacheHelp = <String, String>{
    'decoded-image': 'Decoded raster images (RGBA, GPU-backed) shared by every '
        'render path in the main isolate. Weighed by pixel bytes; the budget '
        'is platform-tiered (256 MB desktop).',
    'render-record': 'Interpreted page command records returned by the render '
        'workers, weighed by their decoded image bytes, so a revisited page '
        'replays instead of re-interpreting.',
    'tiles': 'The deep-zoom tile pyramid (#314): fixed-size GPU-resident '
        'tiles per zoom bucket, weighed by pixel bytes. Only populated when '
        'a tile mode is active.',
  };

  String _cacheExplanation(String label) =>
      _cacheHelp[label] ??
      'A budgeted least-recently-used cache registered for coordinated '
          'trimming and memory pressure. The parenthesized number is its '
          'entry count; the value is retained bytes (and budget).';

  // --- deep-zoom detail mode ------------------------------------------------

  static const _modePatch = AppDevTools.modePatch;
  static const _modeTiles = AppDevTools.modeTiles;
  static const _modeBatched = AppDevTools.modeBatched;

  String get _deepZoomMode => _tools.deepZoomMode;

  void _setDeepZoomMode(String mode) {
    _tools.setDeepZoomMode(mode);
    _persist();
    setState(() {});
  }

  /// Every option change writes the whole set - devtools options survive an
  /// app restart.
  void _persist() => unawaited(_tools.persistOptions());

  Widget _deepZoomSection(ThemeData theme) {
    final store = PdfPageView.tileStoreDetail
        ? (PdfPageView.debugTileStoreOverride ?? PdfTileStore.instance)
        : PdfPageView.debugTileStoreOverride;
    return _section(theme, 'Deep-zoom detail (#314)', [
      RadioGroup<String>(
        groupValue: _deepZoomMode,
        onChanged: (v) => v == null ? null : _setDeepZoomMode(v),
        child: Column(
          children: [
            for (final (mode, subtitle) in const [
              (_modePatch, 'Shipping path: one detail patch per settle'),
              (_modeTiles, 'Tile pyramid, one readback per 512² tile'),
              (
                _modeBatched,
                'Tile pyramid, one slab readback per settle, GPU-sliced'
              ),
            ])
              RadioListTile<String>(
                key: ValueKey('devtools-mode-$mode'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: mode,
                title: Text(mode),
                subtitle: Text(subtitle),
              ),
          ],
        ),
      ),
      Text('A mode change applies from the next zoom or pan settle.',
          style: theme.textTheme.bodySmall!
              .copyWith(color: theme.colorScheme.outline)),
      _helpSwitch(
        theme,
        key: const ValueKey('devtools-tile-borders'),
        title: 'Tile / patch borders',
        help: 'Outlines what sharpens the visible slice: green borders are '
            'exact-bucket tiles, orange are upscaled coarser-bucket '
            'fallbacks, purple is the legacy single detail patch. The Pages '
            'sidebar mirrors it per thumbnail (cached tiles green - dimmer '
            'for coarser buckets - patch purple), so you can see the whole '
            "pyramid's coverage at a glance. Nothing outlined at deep zoom "
            'means the tile path is not engaging for this page.',
        value: pdfDebugPaintDetailBounds.value,
        onChanged: (v) => setState(() {
          pdfDebugPaintDetailBounds.value = v;
          _persist();
        }),
      ),
      _helpSwitch(
        theme,
        key: const ValueKey('devtools-render-window'),
        title: 'Render window in thumbnails',
        help: 'Outlines (teal) in the Pages sidebar the pages whose '
            'page-view state is currently live - the lazy list\'s render '
            'window. Each live page can retain a full-page raster, a detail '
            'patch, and a scene with decoded images, so this window is '
            'where per-page memory goes.',
        value: pdfDebugShowRenderWindow.value,
        onChanged: (v) => setState(() {
          pdfDebugShowRenderWindow.value = v;
          _persist();
        }),
      ),
      if (store != null) ...[
        const SizedBox(height: 4),
        _kv(theme, 'Tiles retained',
            '${store.tileCount} (${_mb(store.retainedBytes)})',
            help: 'GPU-resident tiles currently cached across all zoom '
                'buckets, and their pixel bytes. Bounded by the tile budget '
                '(96 MB default), evicting least-recently-used.'),
        _kv(theme, 'In flight', '${store.inFlightCount}',
            help: 'Tiles whose raster has been scheduled but has not landed '
                'yet. A settle over an untiled area spikes this, then it '
                'drains to zero.'),
        _kv(
            theme,
            'Scheduled / landed / discarded',
            '${store.debugTilesScheduled} / ${store.debugTilesLanded} / '
                '${store.debugTilesDiscarded}',
            help: 'Lifetime counters: rasters requested, tiles that entered '
                'the cache, and completions thrown away because the page was '
                'edited or invalidated while they were in flight.'),
        _kv(theme, 'Batches dispatched', '${store.debugBatchesDispatched}',
            help: 'Slab readbacks issued in batched mode: missing tiles of '
                'one settle are rastered as one region readback and sliced '
                'GPU-side, instead of one readback per tile.'),
      ],
    ]);
  }

  // --- tile raster backend -------------------------------------------------

  static String _backendLabel(TileRasterBackendMode mode) => switch (mode) {
        TileRasterBackendMode.canvas => 'Canvas',
        TileRasterBackendMode.flutterGpu => 'flutter_gpu',
      };

  String _tileBackendOutcome() {
    final mode = _tools.tileRasterBackendMode.value;
    final backend = _tools.flutterGpuTileRasterBackend;
    final stats = backend.stats;
    if (mode == TileRasterBackendMode.canvas) return 'Canvas selected';
    if (!backend.isPlatformSupported) {
      return 'Canvas fallback (flutter_gpu unavailable)';
    }
    if (_deepZoomMode == _modePatch) return 'Waiting for a tile mode';
    return switch (stats.lastTileRoute) {
      'flutter_gpu' => stats.sessionsRejected > 0 || stats.rasterFallbacks > 0
          ? 'flutter_gpu latest (mixed lifetime)'
          : 'flutter_gpu rendering',
      'flutter_gpu-session' => 'GPU session accepted; awaiting a tile',
      'canvas-fallback' => stats.activeSessions > 0
          ? 'Canvas fallback latest (GPU also active)'
          : 'Canvas fallback',
      _ => stats.activeSessions > 0
          ? 'GPU session active; awaiting next tile'
          : 'Not sampled yet',
    };
  }

  static String _averageMs(int micros, int count) =>
      count == 0 ? 'n/a' : '${(micros / count / 1000).toStringAsFixed(2)} ms';

  void _setGpuBudget({int? textureBytes, int? geometryBytes}) {
    _tools.setGpuTileBudgets(
      maxTextureBytes: textureBytes,
      maxGeometryBytes: geometryBytes,
    );
    _persist();
    setState(() {});
  }

  Widget _gpuPreviewDownload(String platform, String url) {
    return OutlinedButton.icon(
      key: ValueKey('devtools-download-gpu-${platform.toLowerCase()}'),
      onPressed: () => unawaited(
        launchUrl(
          Uri.base.resolve(url),
          mode: LaunchMode.externalApplication,
        ),
      ),
      icon: const Icon(Icons.download, size: 18),
      label: Text(platform),
    );
  }

  Widget _tileBackendSection(ThemeData theme) {
    final backend = _tools.flutterGpuTileRasterBackend;
    final stats = backend.stats;
    final mode = _tools.tileRasterBackendMode.value;
    final gpuSamples = stats.sessionsCreated + stats.sessionsRejected;
    final fallbackCount = stats.sessionsRejected + stats.rasterFallbacks;
    final previewDownloads = widget.gpuPreviewDownloads.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList(growable: false);
    return _section(
      theme,
      'Tile raster backend',
      [
        Row(
          children: [
            Expanded(
              child:
                  Text('Preferred backend', style: theme.textTheme.bodySmall),
            ),
            PopupMenuButton<TileRasterBackendMode>(
              key: const ValueKey('devtools-tile-backend'),
              tooltip: 'Switch tile raster backend',
              onSelected: (value) {
                _tools.setTileRasterBackendMode(value);
                _persist();
                setState(() {});
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: TileRasterBackendMode.canvas,
                  child: Text('Canvas'),
                ),
                PopupMenuItem(
                  value: TileRasterBackendMode.flutterGpu,
                  enabled: backend.isPlatformSupported,
                  child: Text(backend.isPlatformSupported
                      ? 'flutter_gpu'
                      : 'flutter_gpu (unavailable)'),
                ),
              ],
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 0, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_backendLabel(mode), style: theme.textTheme.bodySmall),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
        _kv(theme, 'Observed outcome', _tileBackendOutcome(),
            help: 'The latest route this backend instance actually took, '
                'plus whether its lifetime contains mixed routes. GPU support '
                'is conservative and scene-scoped: unsupported commands or a '
                'runtime failure retire that scene\'s GPU session and replay '
                'it through Canvas.'),
        _kv(
          theme,
          'flutter_gpu availability',
          backend.isPlatformSupported
              ? 'Native build · context checked lazily'
              : 'Unavailable · Canvas only',
          help: 'The native companion is compiled in on native builds, but '
              'does not acquire the Impeller GPU context until the first tile '
              'session so first paint is unaffected. Web uses a compile-time '
              'stub and always stays on Canvas.',
        ),
        _helpSwitch(
          theme,
          key: const ValueKey('devtools-gpu-route-overlay'),
          title: 'Render route overlay',
          help: 'Borders and badges every mounted page with the route its '
              'deep-zoom detail tiles actually took: green for GPU (naming '
              'the backend, tile count, and command count), amber for a '
              'Canvas fallback (naming the reason), blue for a deliberately '
              'requested Canvas, grey while no detail tiles have been asked '
              'for yet. The route is per scene, not per tile - the whole '
              "page's detail session is accepted or declined together. The "
              'initial fitted page raster is Canvas either way.',
          value: pdfDebugShowGpuRasterRoutes.value,
          onChanged: (value) => setState(() {
            pdfDebugShowGpuRasterRoutes.value = value;
            _persist();
          }),
        ),
        if (previewDownloads.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: previewDownloads
                    .map((entry) => _gpuPreviewDownload(entry.key, entry.value))
                    .toList(growable: false),
              ),
            ),
          ),
        _byteBudgetControl(
          theme,
          key: const ValueKey('devtools-gpu-texture-budget'),
          title: 'Texture ceiling',
          help: 'Strict backend-wide ceiling for decoded image textures, '
              'including textures pinned by active scenes. This is not '
              'allocated up front. Higher values improve reuse in image-heavy '
              'documents but sit outside Dart heap/cache accounting and can '
              'increase OS memory pressure.',
          value: backend.maxTextureBytes,
          choices: _gpuBudgets,
          onChanged: (value) => _setGpuBudget(textureBytes: value),
        ),
        _byteBudgetControl(
          theme,
          key: const ValueKey('devtools-gpu-geometry-budget'),
          title: 'Geometry ceiling',
          help: 'Strict ceiling for reusable 16 MB GPU geometry blocks. This '
              'is not allocated up front. Higher values let more command-heavy '
              'CAD scenes stay compiled concurrently; when pinned scenes '
              'cannot fit, that scene falls back to Canvas.',
          value: backend.maxGeometryBytes,
          choices: _gpuBudgets,
          onChanged: (value) => _setGpuBudget(geometryBytes: value),
        ),
        _helpSwitch(
          theme,
          key: const ValueKey('devtools-gpu-overprint-approximation'),
          title: 'Approximate non-black overprint',
          help: 'Experimental and intentionally inexact. Uses source-over for '
              'non-black overprint so more CAD pages can stay on flutter_gpu. '
              'Off keeps the exact Canvas fallback and is the default.',
          value: _tools.gpuOverprintApproximation,
          onChanged: (value) {
            _tools.setGpuOverprintApproximation(value);
            _persist();
            setState(() {});
          },
        ),
        _kv(
          theme,
          'GPU sessions',
          '${stats.sessionsCreated} accepted / '
              '${stats.sessionsRejected} rejected / '
              '${stats.rasterFallbacks} runtime fallback',
          help: 'Lifetime scene-session outcomes. A rejection occurs before '
              'GPU replay; a runtime fallback occurs during scene compile, '
              'resource upload, or tile submission.',
        ),
        _kv(
          theme,
          'Live sessions / leases',
          '${stats.activeSessions} scenes · '
              '${stats.activeTextureLeases} texture · '
              '${stats.activeGeometryLeases} geometry',
          help: 'Resources pinned by currently mounted retained scenes. Cache '
              'eviction cannot reclaim a resource until its live lease ends.',
        ),
        if (stats.lastRejection case final reason?)
          _kv(theme, 'Last fallback reason', reason,
              help: 'The latest reason flutter_gpu declined or failed a scene. '
                  'This is expected for PDF features outside the exact GPU '
                  'subset and does not make the page fail to render.'),
        _kv(
          theme,
          'Scene compile',
          '${stats.scenesCompiled} · '
              '${_averageMs(stats.compileMicros, stats.scenesCompiled)} avg',
          help: 'One-time retained-scene tessellation, buffer creation, and '
              'image upload. It should grow per scene, not per tile or LoD.',
        ),
        _kv(
          theme,
          'Exact clip masks',
          '${stats.clipPathsCompiled} paths · '
              '${stats.clipMaskRebuilds} tile rebuilds',
          help: 'Non-rectangular PDF clip paths compiled once with the scene '
              'and exact stencil intersections rebuilt when selected commands '
              'change clip stack. Rectangular clips stay on the cheaper '
              'hardware-scissor route.',
        ),
        _kv(
          theme,
          'Tile replay',
          '${stats.tilesRendered} tiles · '
              '${_averageMs(stats.issueMicros, stats.tilesRendered)} issue '
              'avg · ${stats.tilesRendered == 0 ? 'n/a' : (stats.selectedCommands / stats.tilesRendered).toStringAsFixed(1)} commands/tile',
          help: 'GPU tiles rendered, synchronous texture/pass encoding and '
              'submission time, and spatially selected commands per tile.',
        ),
        _kv(
          theme,
          'GPU completion',
          '${stats.completedSubmissions} done · '
              '${_averageMs(stats.completionMicros, stats.completedSubmissions)} avg · '
              '${(stats.maxCompletionMicros / 1000).toStringAsFixed(1)} ms worst · '
              '${stats.inFlightSubmissions} in flight',
          help: 'Command-buffer submit-to-completion latency, including time '
              'queued behind earlier GPU work. A growing in-flight count or '
              'large worst latency reveals deferred raster-thread pressure '
              'that synchronous submit timing cannot see. '
              '${stats.failedSubmissions} submissions reported failure.',
        ),
        _kv(
          theme,
          'Texture cache',
          '${_mb(stats.textureBytes)} / ${_mb(backend.maxTextureBytes)} '
              '(peak ${_mb(stats.peakTextureBytes)})',
          help: 'Decoded image textures shared across pages and scenes under '
              'a strict byte budget. Active scene leases count against it.',
        ),
        _kv(
          theme,
          'Texture hit / miss / evict',
          '${stats.textureCacheHits} / ${stats.textureCacheMisses} / '
              '${stats.textureEvictions}',
          help: 'Cross-scene content-cache outcomes. Repeated images should '
              'raise hits instead of uploads.',
        ),
        _kv(
          theme,
          'Uploads direct / readback',
          '${stats.textureDirectUploads} / ${stats.textureReadbacks}',
          help: 'Direct raw-pixel texture uploads versus ui.Image CPU '
              'readbacks. Readbacks are a compatibility path and should stay '
              'near zero on the expensive image/soft-mask workload.',
        ),
        _kv(
          theme,
          'Geometry pool',
          '${_mb(stats.geometryBytes)} / ${_mb(backend.maxGeometryBytes)} '
              '(peak ${_mb(stats.peakGeometryBytes)}, '
              '${stats.geometryBuffers} buffers)',
          help: 'Reusable GPU geometry buffers shared by compiled scenes. '
              'Buffers are leased until submitted work completes, then reused '
              'to prevent fast CAD navigation from outrunning native GC.',
        ),
        _kv(
          theme,
          'Budget fallbacks',
          '${stats.textureBudgetFallbacks} texture / '
              '${stats.geometryBudgetFallbacks} geometry',
          help: 'Scenes that could not fit while live resources were pinned '
              'and therefore switched to Canvas rather than exceeding the '
              'configured GPU budgets.',
        ),
        Text(
          mode == TileRasterBackendMode.flutterGpu
              ? 'Switching is live. The current tile cache is invalidated and '
                  'the base raster stays visible while the selected backend '
                  'repopulates it. Only tile detail modes use this backend.'
              : 'Canvas is the universal path. Historical GPU counters stay '
                  'visible until reset.',
          style: theme.textTheme.bodySmall!
              .copyWith(color: theme.colorScheme.outline),
        ),
        if (gpuSamples > 0 || stats.textureBytes > 0)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: const ValueKey('devtools-clear-gpu-textures'),
              onPressed: () {
                _tools.clearGpuImageCache();
                _tools.addLog('devtools: cleared reusable GPU image cache');
                setState(() {});
              },
              child: const Text('Clear texture cache'),
            ),
          ),
      ],
      trailing: TextButton(
        key: const ValueKey('devtools-reset-gpu-stats'),
        onPressed: gpuSamples == 0 && fallbackCount == 0
            ? null
            : () {
                stats.reset();
                _tools.addLog('devtools: reset GPU backend counters');
                setState(() {});
              },
        child: const Text('Reset'),
      ),
    );
  }

  // --- PdfPerf --------------------------------------------------------------

  Widget _perfSection(ThemeData theme) {
    final stats = PdfPerf.snapshot();
    return _section(
      theme,
      'PdfPerf (main isolate)',
      [
        _helpSwitch(
          theme,
          key: null,
          title: 'Collect phase timings',
          help: "PdfPerf: the PDF stack's zero-overhead instrumentation "
              '(enum-indexed phase timers and counters across parsing, '
              'filters, fonts, saving). Off, each site costs one branch; on, '
              'accumulators fill and show below. Main isolate only - worker '
              'time is not included.',
          subtitle: kPdfPerfCompiledIn
              ? null
              : const Text('compiled out (PDF_PERF=false)'),
          value: PdfPerf.enabled,
          onChanged: kPdfPerfCompiledIn
              ? (v) => setState(() => PdfPerf.enabled = v)
              : null,
        ),
        if (stats.isEmpty)
          Text('No samples yet - open or edit a document.',
              style: theme.textTheme.bodySmall!
                  .copyWith(color: theme.colorScheme.outline))
        else ...[
          for (final phase in PdfPerfPhase.values)
            if (stats.phaseCallCount(phase) > 0)
              _kv(
                  theme,
                  phase.name,
                  '${(stats.phaseTotalUs(phase) / 1000).toStringAsFixed(1)} ms '
                  '(${stats.phaseCallCount(phase)}×)',
                  help: 'Accumulated wall time and begin/end pair count for '
                      'the "${phase.name}" instrumented phase since enable '
                      'or reset. Phases nest, so totals can overlap.'),
          for (final count in PdfPerfCount.values)
            if (stats.count(count) > 0)
              _kv(theme, count.name, '${stats.count(count)}',
                  help: 'Monotonic counter "${count.name}" - a structural '
                      'fact or byte volume bumped on the hot path, not a '
                      'timing. Resets with the Reset button.'),
        ],
      ],
      trailing: TextButton(
        onPressed: () => setState(PdfPerf.reset),
        child: const Text('Reset'),
      ),
    );
  }

  // --- session --------------------------------------------------------------

  Widget _sessionSection(ThemeData theme) {
    final session = widget.session!;
    return _section(theme, 'Session', [
      _kv(theme, 'Pages', '${session.document.pageCount}',
          help: 'Page count of the active document.'),
      if (widget.viewerController != null)
        _kv(
          theme,
          'Page presentation epoch',
          '${widget.viewerController!.pagePresentationEpoch ?? '-'}',
          help: 'Advances after page insert, remove, or reorder. A rendering '
              'artifact report should show the current epoch and a new tile '
              'namespace after a structural edit.',
        ),
      _kv(theme, 'Current revision', _mb(session.bytes.length),
          help: 'Byte size of the document as it stands now - what Save '
              'writes. Every edit appends an incremental revision, so this '
              'grows with edits.'),
      _kv(
          theme,
          'Session buffer (grow-only)',
          '${_mb(session.sessionBufferBytes)} over '
              '${session.revisionCount} revision(s)',
          help: 'Total bytes retained by the edit session: every revision is '
              'a byte prefix of one grow-only buffer (that is what makes '
              'undo/redo cheap). It only grows within a session - watch it '
              'when chasing memory growth during heavy editing; image stamps '
              'embed their full bytes.'),
      _kv(theme, 'Undo / redo',
          '${session.canUndo ? 'yes' : 'no'} / ${session.canRedo ? 'yes' : 'no'}',
          help: 'Whether an undo or redo step is available. Undo rewinds the '
              'revision cursor; redo replays forward until a new edit forks '
              'history.'),
    ]);
  }

  // --- log ------------------------------------------------------------------

  Widget _logSection(ThemeData theme) {
    final entries = _tools.log
        .where((e) =>
            _logFilter.isEmpty ||
            e.message.toLowerCase().contains(_logFilter.toLowerCase()))
        .toList()
        .reversed
        .toList();
    return _section(
      theme,
      'Log (${entries.length})',
      [
        _helpSwitch(
          theme,
          key: const ValueKey('devtools-log-touch'),
          title: 'Log touch input',
          help: 'Summarizes every touch/stylus gesture over the viewer (down, '
              'up, net move, path length, duration) into this log, and captures '
              "the viewer's own gesture decisions - which pan/zoom recognizer "
              'claimed each drag. The tool for touch reports that only happen '
              'on-device (e.g. "panning does nothing while zoomed"): enable it, '
              'reproduce the gesture, then read or export the log. Filter for '
              '"touch" or "gesture" to isolate.',
          value: _tools.logTouchInput,
          onChanged: (v) => setState(() {
            _tools.logTouchInput = v;
            _persist();
          }),
        ),
        _helpSwitch(
          theme,
          key: const ValueKey('devtools-perf-log'),
          title: 'Verbose render log (PdfPerfLog)',
          help: 'Streams the render stack\'s diagnostic trace '
              '(worker requests/replies, interprets, rasters, jank markers) '
              'into this log as "perf:" lines, so the exported JSON carries '
              'the render path too. Chatty - the 500-entry ring evicts older '
              'lines quickly, so reproduce the problem and export promptly, '
              'then turn it off.',
          value: _tools.logPerfTrace,
          onChanged: (v) => setState(() {
            _tools.logPerfTrace = v;
            _persist();
          }),
        ),
        TextField(
          key: const ValueKey('devtools-log-filter'),
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.filter_alt_outlined, size: 16),
            hintText: 'Filter',
          ),
          onChanged: (v) => setState(() => _logFilter = v),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('No log entries.',
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: theme.colorScheme.outline)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final time = entry.time.toIso8601String().substring(11, 19);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        '$time  ${entry.message}',
                        style: theme.textTheme.bodySmall!.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: entry.level == DevLogLevel.error
                              ? theme.colorScheme.error
                              : null,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () {
              final text = _tools.log
                  .map((e) => '${e.time.toIso8601String()} '
                      '[${e.level.name}] ${e.message}')
                  .join('\n');
              Clipboard.setData(ClipboardData(text: text));
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: _tools.clearLog,
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
