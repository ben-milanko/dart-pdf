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
    constraints.maxWidth.isFinite && constraints.maxWidth < pdfShellCompactWidth;

/// Fraction of the content area a single bottom-sheet panel rises to when
/// it is the only one open; several share the area evenly.
const double _pdfShellSheetHeightFactor = 0.55;

/// Lays the active panel [sheets] out as bottom sheets, stacked above one
/// another and anchored to the bottom of the content area. The space above
/// the topmost sheet stays clear, so the page underneath keeps scrolling
/// and taking taps. Returns a [Positioned] — drop it straight into the
/// content [Stack] (only when [sheets] is non-empty).
Widget pdfShellBottomSheets(List<Widget> sheets) {
  return Positioned.fill(
    child: LayoutBuilder(
      builder: (context, constraints) {
        // each sheet rises to a fraction of the area; the whole stack is
        // capped at the area height so two open sheets share it rather than
        // overflowing off the top
        final maxSheet = constraints.maxHeight * _pdfShellSheetHeightFactor;
        return Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final sheet in sheets)
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxSheet),
                      child: sheet,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// The chrome around a side panel presented as a bottom sheet on a small
/// screen: rounded top, a drag handle that swipes down to dismiss, and a
/// titled header with a close button. The panel [child] fills the rest.
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
          // the handle and header swipe down to dismiss, the Material
          // bottom-sheet idiom
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 200) onClose();
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

/// The shells' slim header bar: a leading group (search, page number)
/// and a trailing group (panel toggles), pushed apart when there is
/// room and scrolling horizontally when there isn't.
class PdfShellBar extends StatelessWidget {
  const PdfShellBar({super.key, required this.leading, required this.trailing});

  final List<Widget> leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 48,
        // a Spacer can't live in an unbounded-width Row, so the gap
        // comes from spaceBetween over a min-width-constrained Row
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
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
          ),
        ),
      ),
    );
  }
}

enum _ViewOption { annotations, formHighlight, reflow, pageColor }

/// The "view options" popup both shells offer: display-only settings
/// (annotation visibility, form-field highlight, paper color) that live
/// in [PdfEditingPreferences] and never touch the document.
class PdfShellViewOptionsButton extends StatelessWidget {
  const PdfShellViewOptionsButton({
    super.key,
    required this.preferences,
    this.reflow = false,
    this.pageColor = true,
  });

  final PdfEditingPreferences preferences;
  final bool reflow;

  /// Whether the "Page color…" item is offered. With it false the paper
  /// color can't be changed here — for hosts that set [pageColor] from
  /// the document programmatically and lock it.
  final bool pageColor;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ViewOption>(
      key: const ValueKey('pdf-shell-view-options'),
      tooltip: 'View options',
      icon: const Icon(Icons.display_settings_outlined),
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      onSelected: (option) async {
        switch (option) {
          case _ViewOption.annotations:
            preferences.showAnnotations = !preferences.showAnnotations;
          case _ViewOption.formHighlight:
            preferences.highlightFormFields = !preferences.highlightFormFields;
          case _ViewOption.reflow:
            preferences.showReflowView = !preferences.showReflowView;
          case _ViewOption.pageColor:
            final color = await showPdfColorPicker(
              context,
              initial: preferences.pageColor,
              initialFormat: preferences.colorPickerFormat,
              onFormatChanged: (format) =>
                  preferences.colorPickerFormat = format,
            );
            if (color != null) preferences.pageColor = color;
        }
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
          const PopupMenuItem(
            key: ValueKey('pdf-shell-page-color'),
            value: _ViewOption.pageColor,
            child: Text('Page color…'),
          ),
      ],
    );
  }
}

/// A compact header toggle for one of the side panels.
class PdfShellToggleButton extends StatelessWidget {
  const PdfShellToggleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(icon),
      tooltip: tooltip,
      isSelected: selected,
      onPressed: onPressed,
    );
  }
}
