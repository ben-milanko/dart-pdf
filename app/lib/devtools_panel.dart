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

import 'package:dart_pdf_editor/dart_pdf_editor.dart';

import 'app_info.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show debugRepaintRainbowEnabled;
import 'package:flutter/services.dart';
// ignore: implementation_imports - the perf facade is deliberately unexported.
import 'package:pdf_cos/perf.dart';

import 'devtools.dart';
import 'file_io.dart';

/// Developer tools panel. Create it only off-release. Docks as a side panel on
/// wide screens; pass [bottomSheet] to render it as a phone bottom sheet.
class DevToolsPanel extends StatefulWidget {
  const DevToolsPanel({
    super.key,
    required this.onClose,
    this.session,
    this.bottomSheet = false,
  });

  final VoidCallback onClose;

  /// The active tab's edit session, when one is open.
  final PdfEditingController? session;

  /// Render as a bottom sheet (phones) rather than a right-docked side panel:
  /// a rounded, height-capped card with a drag-handle affordance and its own
  /// close button, instead of the resizable side dock.
  final bool bottomSheet;

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
    _refresh = Timer.periodic(
        const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return widget.bottomSheet
        ? _buildBottomSheet(theme)
        : _buildDocked(theme);
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
        padding:
            EdgeInsets.only(bottom: 16, left: geometry.contentStartInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _framesSection(theme),
            _memorySection(theme),
            _workersSection(theme),
            _deepZoomSection(theme),
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
      'appVersion': AppInfo.version,
      'appBuild': AppInfo.buildNumber,
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
        'caches': [
          for (final cache in PdfCacheRegistry.instance.snapshot())
            {
              'label': cache.label,
              'entries': cache.length,
              'bytes': cache.weight,
              'budgetBytes': cache.maxWeight,
            },
        ],
      },
      'renderWorkers': pdfRenderWorkerPoolSize,
      'deepZoomMode': _deepZoomMode,
      if (store != null)
        'tileStore': {
          'tiles': store.tileCount,
          'retainedBytes': store.retainedBytes,
          'inFlight': store.inFlightCount,
          'scheduled': store.debugTilesScheduled,
          'landed': store.debugTilesLanded,
          'discarded': store.debugTilesDiscarded,
          'batches': store.debugBatchesDispatched,
        },
      'pdfPerf': PdfPerf.snapshot().toJson(),
      if (session != null)
        'session': {
          'pages': session.document.pageCount,
          'currentRevisionBytes': session.bytes.length,
          'sessionBufferBytes': session.sessionBufferBytes,
          'revisions': session.revisionCount,
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
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .split('.')
        .first;
    final result = await saveJsonAs(
      context,
      const JsonEncoder.withIndent('  ').convert(snapshot),
      'dartpdf-devtools-$stamp.json',
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
            Text('$pdfRenderWorkerPoolSize',
                style: theme.textTheme.bodyMedium),
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
          Text(value,
              style: theme.textTheme.bodySmall!
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
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
    showDialog<void>(
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

  static String _mb(num bytes) => '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';

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

  Widget _memorySection(ThemeData theme) {
    final rss = _tools.currentRssBytes;
    final peak = _tools.maxRssBytes;
    final caches = PdfCacheRegistry.instance.snapshot();
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
        for (final cache in caches)
          _kv(
              theme,
              '  ${cache.label} (${cache.length})',
              cache.maxWeight > 0
                  ? '${_mb(cache.weight)} / ${_mb(cache.maxWeight)}'
                  : _mb(cache.weight),
              help: _cacheExplanation(cache.label)),
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
          help: 'Streams the render stack\'s diagnostic log lines '
              '(vector-first routing, worker requests, detail settles, '
              'jank markers) through debugPrint into this log. Also lights '
              'up the PdfPerf accumulators. Chatty - enable to diagnose, '
              'then turn it off.',
          value: PdfPerfLog.enabled,
          onChanged: (v) => setState(() {
            PdfPerfLog.enabled = v;
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
                    final time =
                        entry.time.toIso8601String().substring(11, 19);
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
