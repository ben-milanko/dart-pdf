import 'dart:async';

import 'package:flutter/material.dart';

import 'editing/editing_color_picker.dart';
import 'editing/editing_preferences.dart';
import 'pdf_viewer.dart';

/// Shared header chrome for the drop-in shells (PdfReader and
/// PdfEditorView). Package-private: not exported from the library.

const double pdfShellCompactWidth = 700;

/// Whether the shell is narrow enough that side panels should give way to
/// bottom sheets — a phone, or a small window. Below [pdfShellCompactWidth]
/// a docked 280px panel would crowd the page out, so the shells float the
/// panels (and the thumbnail strip) up from the bottom instead.
bool pdfShellUseBottomSheets(BoxConstraints constraints) =>
    constraints.maxWidth.isFinite &&
    constraints.maxWidth < pdfShellCompactWidth;

/// Height of the bottom-sheet area, as a fraction of the content area, the
/// first time a sheet opens. The user drags a sheet's handle to resize it
/// between [_pdfShellSheetMinFactor] and [_pdfShellSheetMaxFactor].
const double _pdfShellSheetHeightFactor = 0.5;
const double _pdfShellSheetMinFactor = 0.25;
const double _pdfShellSheetMaxFactor = 0.9;

/// Lays the active panel [sheets] out as bottom sheets, stacked above one
/// another and anchored to the bottom of the content area. The space above
/// the topmost sheet stays clear, so the page underneath keeps scrolling
/// and taking taps. The whole stack is resizable by dragging a sheet's
/// handle (up to 90% of the area). Returns a [Positioned] — drop it
/// straight into the content [Stack] (only when [sheets] is non-empty).
Widget pdfShellBottomSheets(List<Widget> sheets) =>
    _PdfShellBottomSheetArea(sheets: sheets);

/// Owns the resizable height of the bottom-sheet stack and exposes the
/// resize callback to the sheets' drag handles via [_BottomSheetResizeScope].
class _PdfShellBottomSheetArea extends StatefulWidget {
  const _PdfShellBottomSheetArea({required this.sheets});

  final List<Widget> sheets;

  @override
  State<_PdfShellBottomSheetArea> createState() =>
      _PdfShellBottomSheetAreaState();
}

class _PdfShellBottomSheetAreaState extends State<_PdfShellBottomSheetArea> {
  double _fraction = _pdfShellSheetHeightFactor;
  double _maxHeight = 0;

  void _resizeBy(double dy) {
    if (_maxHeight <= 0) return;
    // dragging the handle up (negative dy) grows the sheet
    final next = (_fraction - dy / _maxHeight)
        .clamp(_pdfShellSheetMinFactor, _pdfShellSheetMaxFactor);
    if (next != _fraction) setState(() => _fraction = next);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _maxHeight = constraints.maxHeight;
          return Align(
            alignment: Alignment.bottomCenter,
            child: _BottomSheetResizeScope(
              resizeBy: _resizeBy,
              child: SizedBox(
                height: constraints.maxHeight * _fraction,
                // a bounded height, so Flexible can share it: one sheet
                // fills it, several split it evenly
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    for (final sheet in widget.sheets) Flexible(child: sheet),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Hands a bottom sheet's drag handle the area's resize callback. Absent
/// when [PdfPanelBottomSheet] is used outside [pdfShellBottomSheets], in
/// which case the handle only dismisses.
class _BottomSheetResizeScope extends InheritedWidget {
  const _BottomSheetResizeScope({
    required this.resizeBy,
    required super.child,
  });

  /// Grows (negative dy) or shrinks (positive dy) the sheet stack.
  final void Function(double dy) resizeBy;

  static _BottomSheetResizeScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BottomSheetResizeScope>();

  @override
  bool updateShouldNotify(_BottomSheetResizeScope oldWidget) => false;
}

/// The chrome around a side panel presented as a bottom sheet on a small
/// screen: rounded top, a drag handle that resizes the sheet (and flicks
/// down to dismiss), and a titled header with a close button. The panel
/// [child] fills the rest.
class PdfPanelBottomSheet extends StatelessWidget {
  const PdfPanelBottomSheet({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
    this.closeKey,
  });

  /// The panel's name, shown in the header.
  final String title;

  /// Dismisses the sheet — the shells turn the panel's visibility
  /// preference off.
  final VoidCallback onClose;

  /// The panel itself, built in its bottom-sheet layout (full width, no
  /// side resize grip).
  final Widget child;

  /// A key for the close button, for tests.
  final Key? closeKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resize = _BottomSheetResizeScope.maybeOf(context);
    return Material(
      color: scheme.surfaceContainerLow,
      elevation: 8,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // the handle resizes the sheet (drag up to grow, down to shrink)
          // and dismisses on a fast downward flick — the Material
          // bottom-sheet idiom. With no resize scope (standalone use) it
          // only dismisses, on a gentler flick.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: resize == null
                ? null
                : (details) => resize.resizeBy(details.delta.dy),
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity > (resize == null ? 200 : 700)) onClose();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      IconButton(
                        key: closeKey,
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                        visualDensity: VisualDensity.compact,
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Persists a viewer's scroll position and zoom per document, so the
/// shells reopen a document where the user left it.
///
/// It tracks the latest viewport as the user scrolls/zooms (cheaply, in
/// memory) and writes it to [PdfEditingPreferences] on a debounce; [flush]
/// forces a write (on dispose), and [rekey] switches documents — saving
/// the outgoing one and restoring the incoming one. Used package-private
/// by both shells.
class PdfViewportMemory {
  PdfViewportMemory({
    required this.viewer,
    required this.preferences,
    required String documentKey,
  }) : _documentKey = documentKey {
    viewer.viewportChanges.addListener(_onViewportChanged);
    // the debounced write can lose the last position when the app goes
    // away before it fires — on the web a closed/hidden tab never disposes
    // this — so flush on every "going away" lifecycle transition too
    _lifecycle = AppLifecycleListener(
      onHide: flush,
      onPause: flush,
      onDetach: flush,
    );
    _restore(documentKey);
  }

  final PdfViewerController viewer;
  final PdfEditingPreferences preferences;
  String _documentKey;

  PdfViewport? _last;
  Timer? _saveTimer;
  late final AppLifecycleListener _lifecycle;

  /// Time to wait after the last scroll/zoom before writing to disk.
  static const _debounce = Duration(milliseconds: 400);

  void _onViewportChanged() {
    // capture now (the viewer is live), debounce only the disk write — so
    // [flush] has a fresh position even after the viewer detaches
    final viewport = viewer.captureViewport();
    if (viewport != null) _last = viewport;
    _saveTimer ??= Timer(_debounce, _writePending);
  }

  void _writePending() {
    _saveTimer = null;
    if (_last != null) preferences.setViewport(_documentKey, _last);
  }

  Future<void> _restore(String key) async {
    await preferences.ready;
    if (key != _documentKey) return; // document swapped while loading
    final viewport = preferences.viewportFor(key);
    if (viewport != null) viewer.restoreViewport(viewport);
  }

  /// Switches to a different document: writes the outgoing one's position,
  /// then restores the incoming one's.
  void rekey(String documentKey) {
    if (documentKey == _documentKey) return;
    flush();
    _documentKey = documentKey;
    _last = null;
    _restore(documentKey);
  }

  /// Writes the latest known position immediately — call before disposing.
  void flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_last != null) preferences.setViewport(_documentKey, _last);
  }

  void dispose() {
    flush();
    _lifecycle.dispose();
    viewer.viewportChanges.removeListener(_onViewportChanged);
  }
}

bool pdfShellShowThumbnailSidebar(
  PdfEditingPreferences preferences,
  BoxConstraints constraints,
) {
  final compact = constraints.maxWidth.isFinite &&
      constraints.maxWidth < pdfShellCompactWidth;
  return preferences.showThumbnailSidebar &&
      (!compact || preferences.hasShowThumbnailSidebarPreference);
}

/// A right-side shell control that collapses into the mobile Controls sheet.
class PdfShellControlItem {
  const PdfShellControlItem({
    required this.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.enabled = true,
  });

  final Key key;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final bool enabled;
}

/// The shells' slim header bar: a leading group (search, page number)
/// and a trailing group (panel toggles), pushed apart when there is room.
/// On compact screens the trailing group becomes a single Controls button
/// that opens a large-button bottom sheet.
class PdfShellBar extends StatelessWidget {
  const PdfShellBar({
    super.key,
    required this.leading,
    required this.trailing,
    this.compactLeading,
    this.compactControls = const [],
    this.compactSheetChildren = const [],
  });

  final List<Widget> leading;
  final List<Widget> trailing;

  /// Leading controls to keep directly in the header on compact layouts.
  ///
  /// When omitted, [leading] is reused. Pass a smaller set and move bulky
  /// controls to [compactSheetChildren] to keep phone headers usable.
  final List<Widget>? compactLeading;

  final List<PdfShellControlItem> compactControls;
  final List<Widget> compactSheetChildren;

  Future<void> _showControls(BuildContext context) {
    final controls = compactControls;
    final children = compactSheetChildren;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ShellControlsSheetScope(
        close: () => Navigator.of(context).maybePop(),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Controls',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (children.isNotEmpty) ...[
                  const _ShellSheetSectionLabel('View'),
                  const SizedBox(height: 10),
                  for (final child in children) child,
                  const SizedBox(height: 14),
                ],
                if (controls.isNotEmpty) ...[
                  const _ShellSheetSectionLabel('Shell'),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.15,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    children: [
                      for (final control in controls)
                        _ShellControlTile(
                          key: control.key,
                          icon: control.icon,
                          label: control.label,
                          active: control.selected,
                          enabled: control.enabled,
                          onTap: () {
                            Navigator.of(context).pop();
                            control.onPressed();
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: Border(
          bottom:
              BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      // Keep the icon buttons a single, consistent colour: an IconButton
      // resolves its own foreground, but a PopupMenuButton's icon (the
      // view-options button) falls back to the ambient IconTheme, which
      // otherwise reads black87 rather than onSurfaceVariant.
      child: IconTheme.merge(
        data: IconThemeData(
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        child: SizedBox(
          height: 48,
          // a Spacer can't live in an unbounded-width Row, so the gap
          // comes from spaceBetween over a min-width-constrained Row
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (pdfShellUseBottomSheets(constraints)) {
                final compactHeader = compactLeading ?? leading;
                return Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          const SizedBox(width: 8),
                          ...compactHeader,
                          const SizedBox(width: 4),
                        ]),
                      ),
                    ),
                    if (compactControls.isNotEmpty ||
                        compactSheetChildren.isNotEmpty)
                      IconButton(
                        key: const ValueKey('pdf-shell-controls'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.more_horiz),
                        tooltip: 'Controls',
                        onPressed: () => unawaited(_showControls(context)),
                      ),
                    const SizedBox(width: 8),
                  ],
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [const SizedBox(width: 8), ...leading],
                      ),
                      Row(
                        children: [...trailing, const SizedBox(width: 8)],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class PdfShellZoomControl extends StatefulWidget {
  const PdfShellZoomControl({super.key, required this.controller});

  final PdfViewerController controller;

  @override
  State<PdfShellZoomControl> createState() => _PdfShellZoomControlState();
}

class _PdfShellZoomControlState extends State<PdfShellZoomControl> {
  static const List<double> _presets = [0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4];

  @override
  void initState() {
    super.initState();
    widget.controller.viewportChanges.addListener(_changed);
  }

  @override
  void didUpdateWidget(PdfShellZoomControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.viewportChanges.removeListener(_changed);
    widget.controller.viewportChanges.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.viewportChanges.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final zoom = widget.controller.zoom;
    final percent = (zoom * 100).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<double>(
          key: const ValueKey('pdf-shell-zoom-menu'),
          tooltip: 'Zoom',
          initialValue: _nearestPreset(zoom),
          onSelected: widget.controller.setZoom,
          itemBuilder: (context) => [
            for (final value in _presets)
              PopupMenuItem<double>(
                key: ValueKey('pdf-shell-zoom-${(value * 100).round()}'),
                value: value,
                child: Text('${(value * 100).round()}%'),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$percent%',
                  key: const ValueKey('pdf-shell-zoom-label'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('pdf-shell-zoom-reset'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.fit_screen),
          tooltip: 'Reset zoom',
          onPressed:
              (zoom - 1).abs() < 0.005 ? null : widget.controller.resetZoom,
        ),
      ],
    );
  }

  double? _nearestPreset(double zoom) {
    for (final value in _presets) {
      if ((value - zoom).abs() < 0.005) return value;
    }
    return null;
  }
}

class _ShellSheetSectionLabel extends StatelessWidget {
  const _ShellSheetSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.72),
        ),
      );
}

class _ShellControlTile extends StatelessWidget {
  const _ShellControlTile({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.55)
        : active
            ? scheme.primary
            : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: active,
      enabled: enabled,
      label: label,
      child: Material(
        color: active
            ? scheme.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? scheme.primary.withValues(alpha: 0.4)
                    : Colors.transparent,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22, color: fg),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellControlsSheetScope extends InheritedWidget {
  const _ShellControlsSheetScope({required this.close, required super.child});

  final VoidCallback close;

  static _ShellControlsSheetScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShellControlsSheetScope>();

  @override
  bool updateShouldNotify(_ShellControlsSheetScope oldWidget) => false;
}

void _maybeCloseShellControls(BuildContext context) {
  final scope = _ShellControlsSheetScope.maybeOf(context);
  if (scope == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) => scope.close());
}

enum _ViewOption { annotations, formHighlight, reflow, pageColor, author }

Future<void> _selectViewOption(
  BuildContext context,
  _ViewOption option, {
  required PdfEditingPreferences preferences,
  required bool pageColor,
  required VoidCallback? onAuthorPressed,
}) async {
  switch (option) {
    case _ViewOption.annotations:
      preferences.showAnnotations = !preferences.showAnnotations;
    case _ViewOption.formHighlight:
      preferences.highlightFormFields = !preferences.highlightFormFields;
    case _ViewOption.reflow:
      preferences.showReflowView = !preferences.showReflowView;
    case _ViewOption.pageColor:
      if (!pageColor) return;
      final color = await showPdfColorPicker(
        context,
        initial: preferences.pageColor,
        initialFormat: preferences.colorPickerFormat,
        onFormatChanged: (format) => preferences.colorPickerFormat = format,
      );
      if (color != null) preferences.pageColor = color;
    case _ViewOption.author:
      onAuthorPressed?.call();
  }
}

Future<void> showPdfShellViewOptionsSheet(
  BuildContext context, {
  required PdfEditingPreferences preferences,
  bool reflow = false,
  bool pageColor = true,
  bool author = false,
  String? authorName,
  VoidCallback? onAuthorPressed,
}) {
  String hex(Color color) {
    final value = color.toARGB32() & 0x00ffffff;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('View options',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              SwitchListTile(
                key: const ValueKey('pdf-shell-show-annotations'),
                secondary: const Icon(Icons.comment_outlined),
                title: const Text('Show annotations'),
                value: preferences.showAnnotations,
                onChanged: (_) async {
                  await _selectViewOption(
                    context,
                    _ViewOption.annotations,
                    preferences: preferences,
                    pageColor: pageColor,
                    onAuthorPressed: onAuthorPressed,
                  );
                  setSheetState(() {});
                },
              ),
              SwitchListTile(
                key: const ValueKey('pdf-shell-highlight-forms'),
                secondary: const Icon(Icons.dynamic_form_outlined),
                title: const Text('Highlight form fields'),
                value: preferences.highlightFormFields,
                onChanged: (_) async {
                  await _selectViewOption(
                    context,
                    _ViewOption.formHighlight,
                    preferences: preferences,
                    pageColor: pageColor,
                    onAuthorPressed: onAuthorPressed,
                  );
                  setSheetState(() {});
                },
              ),
              if (reflow)
                SwitchListTile(
                  key: const ValueKey('pdf-shell-reflow-view'),
                  secondary: const Icon(Icons.article_outlined),
                  title: const Text('Reflow text'),
                  value: preferences.showReflowView,
                  onChanged: (_) async {
                    await _selectViewOption(
                      context,
                      _ViewOption.reflow,
                      preferences: preferences,
                      pageColor: pageColor,
                      onAuthorPressed: onAuthorPressed,
                    );
                    setSheetState(() {});
                  },
                ),
              if (pageColor)
                ListTile(
                  key: const ValueKey('pdf-shell-page-color'),
                  leading: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: preferences.pageColor,
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outline),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  title: const Text('Page color…'),
                  trailing: Text(hex(preferences.pageColor)),
                  onTap: () async {
                    await _selectViewOption(
                      context,
                      _ViewOption.pageColor,
                      preferences: preferences,
                      pageColor: pageColor,
                      onAuthorPressed: onAuthorPressed,
                    );
                    setSheetState(() {});
                  },
                ),
              if (author)
                ListTile(
                  key: const ValueKey('pdf-shell-author'),
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Default author…'),
                  subtitle: Text(
                    authorName == null || authorName.trim().isEmpty
                        ? 'Not set'
                        : authorName,
                  ),
                  onTap: onAuthorPressed,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The "view options" popup both shells offer: display-only settings
/// (annotation visibility, form-field highlight, paper color) that live
/// in [PdfEditingPreferences] and never touch the document.
class PdfShellViewOptionsButton extends StatelessWidget {
  const PdfShellViewOptionsButton({
    super.key,
    required this.preferences,
    this.reflow = false,
    this.pageColor = true,
    this.author = false,
    this.authorName,
    this.onAuthorPressed,
  });

  final PdfEditingPreferences preferences;
  final bool reflow;

  /// Whether the "Page color…" item is offered. With it false the paper
  /// color can't be changed here — for hosts that set [pageColor] from
  /// the document programmatically and lock it.
  final bool pageColor;

  /// Whether the display menu includes the default annotation author.
  /// The shell owns the prompt because the author affects new annotations,
  /// not the rendered PDF page itself.
  final bool author;

  /// The current default annotation author, shown in the display menu.
  final String? authorName;

  /// Opens the host prompt for editing the default annotation author.
  final VoidCallback? onAuthorPressed;

  String _hex(Color color) {
    final value = color.toARGB32() & 0x00ffffff;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ViewOption>(
      key: const ValueKey('pdf-shell-view-options'),
      tooltip: 'View options',
      icon: const Icon(Icons.display_settings_outlined),
      // match the bar's IconButtons; a PopupMenuButton icon otherwise
      // defaults to black87 instead of onSurfaceVariant
      iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      onSelected: (option) async {
        await _selectViewOption(
          context,
          option,
          preferences: preferences,
          pageColor: pageColor,
          onAuthorPressed: onAuthorPressed,
        );
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          key: const ValueKey('pdf-shell-show-annotations'),
          value: _ViewOption.annotations,
          checked: preferences.showAnnotations,
          child: const Text('Show annotations'),
        ),
        CheckedPopupMenuItem(
          key: const ValueKey('pdf-shell-highlight-forms'),
          value: _ViewOption.formHighlight,
          checked: preferences.highlightFormFields,
          child: const Text('Highlight form fields'),
        ),
        if (reflow)
          CheckedPopupMenuItem(
            key: const ValueKey('pdf-shell-reflow-view'),
            value: _ViewOption.reflow,
            checked: preferences.showReflowView,
            child: const Text('Reflow text'),
          ),
        if (pageColor)
          PopupMenuItem(
            key: const ValueKey('pdf-shell-page-color'),
            value: _ViewOption.pageColor,
            child: ListTile(
              leading: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: preferences.pageColor,
                  border:
                      Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              title: const Text('Page color…'),
              trailing: Text(_hex(preferences.pageColor)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (author)
          PopupMenuItem(
            key: const ValueKey('pdf-shell-author'),
            value: _ViewOption.author,
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Default author…'),
              subtitle: Text(
                authorName == null || authorName!.trim().isEmpty
                    ? 'Not set'
                    : authorName!,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}

/// One item in the shell's grouped panel switch.
class PdfShellPanelItem {
  const PdfShellPanelItem({
    required this.key,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final Key key;
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;
}

/// The Pages / Annotations / Properties switch from the shell header.
///
/// It is still built from [IconButton]s so callers and tests can keep
/// addressing each button by key, but the border makes the three loose
/// toggles read as one "Panels" control.
class PdfShellPanelSwitch extends StatelessWidget {
  const PdfShellPanelSwitch({super.key, required this.items});

  final List<PdfShellPanelItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (items.length > 1)
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 6),
            child: Text(
              'Panels',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in items)
                  IconButton(
                    key: item.key,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor:
                          item.selected ? scheme.surface : Colors.transparent,
                      foregroundColor: item.selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    icon: Icon(item.icon),
                    tooltip: item.tooltip,
                    isSelected: item.selected,
                    onPressed: () {
                      item.onPressed();
                      _maybeCloseShellControls(context);
                    },
                  ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
