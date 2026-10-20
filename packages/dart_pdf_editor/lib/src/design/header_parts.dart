// The stock header's pieces, handed to a host's PdfEditorView.headerBuilder
// so it can compose its own header (or nav bar) from them. Widgets-layer
// only: the parts are built by the editor; this file only carries them.

import 'package:flutter/widgets.dart';

/// Builds the editor's header from the stock [PdfHeaderParts]
/// (`PdfEditorView.headerBuilder`).
typedef PdfHeaderBuilder = Widget Function(
    BuildContext context, PdfHeaderParts parts);

/// The stock header's controls, for a `PdfEditorView.headerBuilder` that
/// lays out its own header: place the parts you want, in your own bar, next
/// to your own controls.
///
/// ```dart
/// PdfEditorView(
///   controller: controller,
///   headerBuilder: (context, parts) => parts.bar(
///     leading: [parts.pageNumber, parts.zoom, parts.search].nonNulls.toList(),
///     trailing: [
///       myShareButton,
///       ...[parts.viewOptions, parts.panelSwitch, parts.save].nonNulls,
///     ],
///   ),
/// )
/// ```
///
/// A part is null when its feature is off (`PdfEditorFeatures`), when the
/// view mode hides it (page grid, reflow), or - [save] - without an
/// `onSave`. Each part is a live widget bound to the editor: mount it at
/// most once, and not alongside [stock] (the search field owns a focus
/// node).
@immutable
class PdfHeaderParts {
  /// The parts the editor built. Hosts receive these; they do not
  /// construct them (except in tests).
  const PdfHeaderParts({
    required this.compact,
    required this.stock,
    required Widget Function(
            List<Widget> leading, List<Widget> trailing, Color? color)
        barBuilder,
    required Widget? Function(bool includeSave) controlsBuilder,
    this.pageNumber,
    this.zoom,
    this.search,
    this.viewOptions,
    this.panelSwitch,
    this.save,
    Widget? Function(bool enabledWhenUnchanged)? saveBuilder,
  })  : _barBuilder = barBuilder,
        _controlsBuilder = controlsBuilder,
        _saveBuilder = saveBuilder;

  /// Whether the editor is narrower than its compact width
  /// (`PdfEditorThemeData.compactWidth`, 700 by default) - where the stock
  /// header keeps only the page number and search, and gathers the rest
  /// into a Controls sheet ([controls]).
  final bool compact;

  /// The stock header, exactly as the editor builds it without a
  /// `headerBuilder` (wrap it, or put your own bar beside it).
  final Widget stock;

  /// The page number field ("3 / 12", type to jump).
  final Widget? pageNumber;

  /// The zoom control (zoom out, the percentage menu, zoom in).
  final Widget? zoom;

  /// The search field.
  final Widget? search;

  /// The view options button (view modes, page colour, guides, author,
  /// shortcuts).
  final Widget? viewOptions;

  /// The panel switch (thumbnails, bookmarks, annotations, library,
  /// properties, search results).
  final Widget? panelSwitch;

  /// The save button (`PdfEditorView.onSave`, labelled and iconed by
  /// `saveButtonLabel`/`saveButtonIcon`; disabled while there is nothing to
  /// save). Null without `onSave` or with `showSaveButton: false`.
  final Widget? save;

  final Widget Function(
      List<Widget> leading, List<Widget> trailing, Color? color) _barBuilder;
  final Widget? Function(bool includeSave) _controlsBuilder;
  final Widget? Function(bool enabledWhenUnchanged)? _saveBuilder;

  /// The save button, like [save], for a host that wants it to stay live
  /// while the document is unchanged ([enabledWhenUnchanged]) - where saving
  /// an untouched file is still the point, as when the button shares or
  /// exports the file. Pressing it then calls `PdfEditorView.onSave` even
  /// with nothing to save; the ⌘S / Ctrl+S shortcut still saves only when
  /// there is something to save (or with `PdfEditorView.alwaysAllowSave`).
  /// Use it in place of [save], not beside it. Null when [save] is.
  Widget? saveButton({bool enabledWhenUnchanged = false}) {
    if (!enabledWhenUnchanged || save == null) return save;
    return _saveBuilder?.call(true) ?? save;
  }

  /// A bar in the stock header's look (height, surface, bottom rule, the
  /// header's icon colour), with [leading] at the start and [trailing] at
  /// the end, scrolling sideways when they do not fit. Unlike [stock] it
  /// does not collapse when [compact] - pick fewer parts there, plus
  /// [controls]. [color] replaces the stock fill (pass your app bar's
  /// colour, or a transparent one, to make it read as part of your own
  /// header).
  Widget bar({
    List<Widget> leading = const [],
    List<Widget> trailing = const [],
    Color? color,
  }) =>
      _barBuilder(leading, trailing, color);

  /// The compact header's "more" button: it opens the Controls sheet with
  /// the zoom control, the view modes, view options, the panels and (with
  /// [includeSave]) save - everything the compact [stock] header leaves
  /// out. Null when the sheet would be empty.
  Widget? controls({bool includeSave = true}) => _controlsBuilder(includeSave);
}
