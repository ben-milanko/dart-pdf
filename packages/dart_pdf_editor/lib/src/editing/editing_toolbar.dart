import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart'
    show PdfLineEnding, PdfStandardFont;

import '../pdf_viewer.dart';
import '../toast.dart';
import 'editing_color_picker.dart';
import 'editing_controller.dart';
import 'editing_font_controls.dart';
import 'editing_fonts.dart';
import 'editing_measure.dart';
import 'line_style.dart';
import 'editing_signature.dart';
import 'editing_stamps.dart';
import 'text_prompt.dart';
import 'tool_shortcuts.dart';

/// Builds a custom widget inside [PdfEditingToolbar].
typedef PdfEditingToolbarWidgetBuilder = Widget Function(
  BuildContext context,
  PdfEditingController controller,
  PdfViewerController viewerController,
);

/// A tool *type* — one dock group in [PdfEditingToolbar]. Pass a subset
/// to [PdfEditingToolbar.groups] (or [PdfEditorFeatures.toolGroups]) to
/// hide whole groups: e.g. `{PdfEditToolGroup.select,
/// PdfEditToolGroup.markup}` shows only the Select and Markup groups.
///
/// This is the coarse axis. The finer [PdfEditingToolbar.tools] hides
/// individual tools *within* the groups that survive this filter.
enum PdfEditToolGroup {
  /// Select / move / resize existing annotations.
  select,

  /// Text-markup actions (highlight, underline, strike out, squiggly).
  markup,

  /// Freehand drawing (ink) and the ink eraser.
  draw,

  /// Rectangle, ellipse, line, arrow, polyline, polygon.
  shapes,

  /// Text box, note, stamp, image, signature.
  insert,

  /// Distance, perimeter and area measurement.
  measure,

  /// Page content, form fields and redaction.
  edit,
}

/// A ready-made toolbar for [PdfEditingController].
///
/// The bar is organised as a **dock** of tool *groups* — Select, Markup,
/// Draw, Shapes, Insert, Measure and Edit — flanked by the global
/// undo/redo, flatten and save actions. Tapping a group raises a
/// **contextual strip** above the dock: the group's tools on the left and
/// the active tool's live settings (colour, stroke, opacity, font,
/// scale…) on the right, so each tool shows only the settings it
/// supports. Selecting an annotation or a page element raises its own
/// strip with the actions and restyle controls that apply to it.
///
/// On narrow (phone) widths the dock collapses to the active tool plus a
/// quick-colour row and a *Tools* handle; the handle opens a bottom sheet
/// with group tabs, a tool grid and the active tool's settings.
///
/// Place it in a Scaffold's `bottomNavigationBar` or as the bottom child
/// of a Column — it sizes to its content. Apps wanting different chrome
/// can skip this widget entirely and drive the controller from their own
/// UI, or add focused host actions with [leading] and [trailing].
class PdfEditingToolbar extends StatefulWidget {
  const PdfEditingToolbar({
    super.key,
    required this.controller,
    required this.viewerController,
    this.onSave,
    this.textPrompt = showPdfTextPrompt,
    this.fontPicker,
    this.palette = defaultPalette,
    this.tools,
    this.groups,
    this.showMarkup = true,
    this.showUndoRedo = true,
    this.showColor = true,
    this.showStyle = true,
    this.showFlatten = true,
    this.leading = const [],
    this.trailing = const [],
  });

  final PdfEditingController controller;

  /// The viewer the markup buttons read the text selection from.
  final PdfViewerController viewerController;

  /// Receives the current revision's bytes when the save button is
  /// pressed; the button is hidden when null. Writing the bytes somewhere
  /// is the app's job.
  final void Function(Uint8List bytes)? onSave;

  /// How the edit-text button asks for replacement text.
  final PdfTextPrompt textPrompt;

  /// How the font menu's "Load font…" entry obtains a custom `.ttf`/`.otf`
  /// file. When null, only the standard families and bundled fonts are
  /// offered (no custom loading).
  final PdfFontPicker? fontPicker;

  /// The colors offered for new annotations.
  final List<Color> palette;

  /// The tools to expose, null meaning all of them. A group disappears
  /// from the dock when none of its tools are in the set. Sub-controls
  /// tied to an armed tool (the stamp picker, the form field-type menu)
  /// follow their tool. Hiding a tool doesn't disable it — it can still
  /// be armed through the controller.
  final Set<PdfEditTool>? tools;

  /// The tool *types* (dock groups) to expose, null meaning all of them.
  /// A group not in the set vanishes from the dock entirely — this is the
  /// way to disable a whole tool type (Measure, Markup, Draw…) without
  /// enumerating each of its tools in [tools].
  ///
  /// Combines with [tools] and [showMarkup]: a group shows only when it
  /// is in this set (when given), is not emptied by [tools], and — for
  /// Markup — [showMarkup] is true. Hiding a group only hides its UI; its
  /// tools can still be armed through the controller.
  final Set<PdfEditToolGroup>? groups;

  /// Whether the Markup group (highlight, underline, strike out, squiggly
  /// — they act on the viewer's text selection) is shown. A convenience
  /// for the common case; equivalent to dropping [PdfEditToolGroup.markup]
  /// from [groups].
  final bool showMarkup;

  /// Whether the undo/redo buttons are shown. The viewer's ⌘Z/⇧⌘Z
  /// shortcuts work either way.
  final bool showUndoRedo;

  /// Whether the colour controls — the palette swatches, the "More
  /// colours…" picker, the eyedropper, and the text-box fill/border colour
  /// rows in the style popup — are shown. Split from [showStyle] so a
  /// colour-locked session can hide the colour changer while leaving
  /// stroke/opacity/font editable.
  final bool showColor;

  /// Whether the style popup (the stroke/opacity/font controls) is
  /// shown. Independent of [showColor]: the popup can show its sliders
  /// and font controls with its colour rows hidden.
  final bool showStyle;

  /// Whether the flatten-annotations button is shown.
  final bool showFlatten;

  /// Custom widgets shown before the stock dock controls. Builders run
  /// inside the toolbar's listenable rebuild, so they can reflect
  /// [controller] or [viewerController] state directly.
  final List<PdfEditingToolbarWidgetBuilder> leading;

  /// Custom widgets shown after the stock dock controls.
  ///
  /// Prefer compact controls such as [IconButton]s or popup buttons so
  /// they fit naturally in the dock's row.
  final List<PdfEditingToolbarWidgetBuilder> trailing;

  static const defaultPalette = [
    Color(0xFFE53935), // red
    Color(0xFFFFD100), // marker yellow
    Color(0xFF43A047), // green
    Color(0xFF1E88E5), // blue
    Color(0xFF000000), // black
  ];

  /// Below this width the dock collapses to a solid bar and tools move
  /// into a bottom sheet. Above it, the desktop dock + contextual strip
  /// show as floating cards. Hosts can read this to decide whether to
  /// dock the toolbar (below this width it's a solid bar, so floating it
  /// over the page would hide content) or let it float.
  static const mobileBreakpoint = 600.0;

  @override
  State<PdfEditingToolbar> createState() => _PdfEditingToolbarState();
}

/// One entry in a tool group — either an armable [PdfEditTool] or a
/// text-markup action ([PdfMarkupKind], which acts on the live text
/// selection rather than arming a tool).
class _GroupTool {
  const _GroupTool.tool(this.tool, this.icon, this.tip) : markup = null;
  const _GroupTool.markup(this.markup, this.icon, this.tip) : tool = null;

  final PdfEditTool? tool;
  final PdfMarkupKind? markup;
  final IconData icon;
  final String tip;
}

/// A dock group: a labelled chip that raises a contextual strip of
/// [tools]. [defaultTool] is armed when the group opens, when arming it
/// is side-effect-free (shapes → rectangle, draw → ink); groups whose
/// first tool has a prerequisite (Measure needs a scale, Insert's
/// signature needs a drawing) leave it null and wait for an explicit tap.
class _ToolGroup {
  const _ToolGroup(this.id, this.label, this.icon, this.tools,
      {this.defaultTool});

  final String id;
  final String label;
  final IconData icon;
  final List<_GroupTool> tools;
  final PdfEditTool? defaultTool;
}

class _PdfEditingToolbarState extends State<PdfEditingToolbar> {
  PdfEditingController get controller => widget.controller;
  PdfViewerController get viewerController => widget.viewerController;

  /// Which group's strip is open when no group tool is armed (Select,
  /// Markup, Measure and Edit can be open with nothing armed). When a
  /// group tool *is* armed, that tool's group always wins.
  String? _openGroupId = 'select';

  /// In-flight opacity while dragging the strip's inline slider over a
  /// selected annotation — it only restyles on release (one revision per
  /// gesture), so the thumb needs its own state meanwhile.
  double? _dragOpacity;

  /// The seven dock groups, in order. Filtered by [PdfEditingToolbar.tools]
  /// and [PdfEditingToolbar.showMarkup] before display.
  static const _groups = <_ToolGroup>[
    _ToolGroup(
        'select',
        'Select',
        Icons.near_me,
        [
          _GroupTool.tool(PdfEditTool.select, Icons.near_me, 'Select'),
        ],
        defaultTool: PdfEditTool.select),
    _ToolGroup('markup', 'Markup', Icons.edit_note, [
      _GroupTool.markup(
          PdfMarkupKind.highlight, Icons.border_color, 'Highlight selection'),
      _GroupTool.markup(PdfMarkupKind.underline, Icons.format_underlined,
          'Underline selection'),
      _GroupTool.markup(PdfMarkupKind.strikeOut, Icons.format_strikethrough,
          'Strike out selection'),
      _GroupTool.markup(PdfMarkupKind.squiggly, Icons.gesture,
          'Squiggly-underline selection'),
    ]),
    _ToolGroup(
        'draw',
        'Draw',
        Icons.draw,
        [
          _GroupTool.tool(PdfEditTool.ink, Icons.draw, 'Draw'),
          _GroupTool.tool(
              PdfEditTool.eraser, Icons.auto_fix_normal, 'Erase ink strokes'),
        ],
        defaultTool: PdfEditTool.ink),
    _ToolGroup(
        'shapes',
        'Shapes',
        Icons.rectangle_outlined,
        [
          _GroupTool.tool(
              PdfEditTool.rectangle, Icons.rectangle_outlined, 'Rectangle'),
          _GroupTool.tool(
              PdfEditTool.ellipse, Icons.circle_outlined, 'Ellipse'),
          _GroupTool.tool(PdfEditTool.line, Icons.horizontal_rule, 'Line'),
          _GroupTool.tool(PdfEditTool.arrow, Icons.arrow_right_alt, 'Arrow'),
          _GroupTool.tool(PdfEditTool.polyline, Icons.timeline, 'Polyline'),
          _GroupTool.tool(PdfEditTool.polygon, Icons.change_history, 'Polygon'),
        ],
        defaultTool: PdfEditTool.rectangle),
    _ToolGroup(
        'insert',
        'Insert',
        Icons.text_fields,
        [
          _GroupTool.tool(PdfEditTool.freeText, Icons.text_fields, 'Text box'),
          _GroupTool.tool(
              PdfEditTool.note, Icons.sticky_note_2_outlined, 'Note'),
          _GroupTool.tool(PdfEditTool.stamp, Icons.approval, 'Stamp'),
          _GroupTool.tool(PdfEditTool.count, Icons.task_alt,
              'Count — tap to drop check-marks and tally them'),
          _GroupTool.tool(PdfEditTool.image, Icons.image_outlined,
              'Image — tap to place, or drag out a box'),
          _GroupTool.tool(PdfEditTool.signature, Icons.history_edu,
              'Signature — tap a page to place it'),
        ],
        defaultTool: PdfEditTool.freeText),
    _ToolGroup('measure', 'Measure', Icons.straighten, [
      _GroupTool.tool(
          PdfEditTool.measureDistance, Icons.straighten, 'Measure distance'),
      _GroupTool.tool(
          PdfEditTool.measurePerimeter, Icons.timeline, 'Measure perimeter'),
      _GroupTool.tool(PdfEditTool.measureArea, Icons.crop_din, 'Measure area'),
    ]),
    _ToolGroup('edit', 'Edit', Icons.design_services, [
      _GroupTool.tool(
          PdfEditTool.content, Icons.format_shapes, 'Edit page content'),
      _GroupTool.tool(PdfEditTool.form, Icons.ballot_outlined,
          'Form fields — tap to select, double-tap to fill, drag to add'),
      _GroupTool.tool(PdfEditTool.redact, Icons.gradient,
          'Redact — drag a region, then apply'),
      _GroupTool.tool(PdfEditTool.snapshot, Icons.crop,
          'Snapshot — drag a region to capture it (paste back as vector)'),
    ]),
  ];

  bool _shows(PdfEditTool tool) => widget.tools?.contains(tool) ?? true;

  /// Whether [group] has any visible entry (the whole group gated by
  /// [PdfEditingToolbar.groups], markup also gated by showMarkup, tools
  /// gated by [PdfEditingToolbar.tools]).
  bool _groupVisible(_ToolGroup group) {
    final kind = PdfEditToolGroup.values.byName(group.id);
    if (widget.groups != null && !widget.groups!.contains(kind)) return false;
    if (group.id == 'markup') return widget.showMarkup;
    return group.tools.any((e) => e.tool != null && _shows(e.tool!));
  }

  List<_ToolGroup> get _visibleGroups =>
      _groups.where(_groupVisible).toList(growable: false);

  _ToolGroup? _groupForTool(PdfEditTool? tool) {
    if (tool == null) return null;
    for (final group in _groups) {
      for (final entry in group.tools) {
        if (entry.tool == tool) return group;
      }
    }
    return null;
  }

  /// The group whose strip is currently shown: an armed tool's group
  /// always wins, otherwise the explicitly opened group.
  _ToolGroup? get _openGroup {
    final armed = _groupForTool(controller.tool);
    final id = armed?.id ?? _openGroupId;
    for (final group in _visibleGroups) {
      if (group.id == id) return group;
    }
    return null;
  }

  // ---- actions (unchanged behaviour from the flat toolbar) ----------------

  void _markup(PdfMarkupKind kind) {
    // capture before the edit: the document swap clears the selection
    final quadsByPage = {
      for (final page in viewerController.selectionPages)
        page: viewerController.selectionRectsOn(page),
    };
    controller.addMarkup(kind, quadsByPage);
  }

  /// Sets the creation colour — and recolours the selected annotations in
  /// place when the whole selection restyles.
  void _applyColor(Color color) {
    controller.color = color;
    if (controller.restyleEditingTextSelection(
        color: color.toARGB32() & 0xFFFFFF)) {
      return;
    }
    if (controller.canRestyleSelected) controller.restyleSelected(color: color);
  }

  void _toggleTool(PdfEditTool value) {
    // disarming a tool drops back to Select (the resting mode), never to a
    // null/no-tool state — tapping the active tool off should leave you
    // able to select and move things, not in limbo
    controller.tool = controller.tool == value ? PdfEditTool.select : value;
    viewerController.clearSelection();
  }

  /// Opens [group]'s strip and, when arming is side-effect-free, arms its
  /// default tool — so its settings are live immediately. Re-tapping the
  /// open group collapses back to the resting Select dock.
  void _openGroupTap(_ToolGroup group) {
    final alreadyOpen = _openGroup?.id == group.id;
    if (alreadyOpen && group.id != 'select') {
      setState(() => _openGroupId = 'select');
      controller.tool = PdfEditTool.select;
      return;
    }
    // tapping the Select chip while Select is already armed disarms it, so
    // the viewer drops back to plain-reader mode (no chip highlighted)
    if (group.id == 'select' && controller.tool == PdfEditTool.select) {
      setState(() => _openGroupId = null);
      controller.tool = null;
      return;
    }
    setState(() => _openGroupId = group.id);
    if (_groupForTool(controller.tool)?.id == group.id) return;
    controller.tool = group.defaultTool;
    if (controller.tool != null) viewerController.clearSelection();
    // markup arms no tool, so its style scope is set explicitly (after the
    // tool reset above, which would otherwise clear it) — this is what lets
    // the highlighter keep its own colour from the other tools'
    if (group.id == 'markup') controller.useMarkupStyleScope();
  }

  /// Arms a tool from a group's strip / grid, routing measure and
  /// signature tools through their prerequisite flows.
  Future<void> _armGroupTool(BuildContext context, PdfEditTool tool) async {
    switch (tool) {
      case PdfEditTool.measureDistance:
      case PdfEditTool.measurePerimeter:
      case PdfEditTool.measureArea:
        await _armMeasureTool(context, tool);
      case PdfEditTool.signature:
        await _toggleSignatureTool(context);
      default:
        _toggleTool(tool);
    }
  }

  Future<void> _setScale(BuildContext context) async {
    final scale =
        await showPdfScaleDialog(context, initial: controller.measurementScale);
    if (scale != null) controller.measurementScale = scale;
  }

  Future<void> _armMeasureTool(BuildContext context, PdfEditTool tool) async {
    if (controller.tool == tool) {
      controller.tool = PdfEditTool.select;
      return;
    }
    if (!controller.hasMeasurementScale) {
      await _setScale(context);
      if (!controller.hasMeasurementScale) return;
    }
    _toggleTool(tool);
  }

  Future<void> _toggleSignatureTool(BuildContext context) async {
    if (controller.tool == PdfEditTool.signature) {
      controller.tool = PdfEditTool.select;
      return;
    }
    if (controller.signature == null && !await _drawSignature(context)) {
      return;
    }
    _toggleTool(PdfEditTool.signature);
  }

  Future<bool> _drawSignature(BuildContext context) async {
    final signature = await showPdfSignatureDialog(context);
    if (signature == null) return false;
    controller.signature = signature;
    // the signature follows the selected colour, so seed it with the ink
    // the user just drew in — they can recolour it from the toolbar after
    controller.color = Color(0xFF000000 | signature.color);
    return true;
  }

  Future<void> _editElementText(BuildContext context) async {
    final element = controller.selectedElement;
    if (element == null) return;
    final text = await widget.textPrompt(
      context,
      title: 'Replace text',
      initial: element.text ?? '',
      multiline: false,
    );
    if (text == null || text.isEmpty || text == element.text) return;
    controller.replaceSelectedElementText(text);
  }

  void _flatten(BuildContext context) {
    final flattened = controller.flattenAllAnnotations();
    _flattenToast(
      context,
      flattened
          ? 'Annotations flattened into the pages'
          : 'No annotations to flatten',
      undoable: flattened,
    );
  }

  void _flattenForm(BuildContext context) {
    final flattened = controller.flattenFormFields();
    _flattenToast(
      context,
      flattened
          ? 'Form fields flattened into the pages'
          : 'No form fields to flatten',
      undoable: flattened,
    );
  }

  void _flattenToast(BuildContext context, String message,
      {required bool undoable}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: pdfFloatingToastMargin(context),
        duration: const Duration(seconds: 4),
        action: undoable && controller.canUndo
            ? SnackBarAction(label: 'Undo', onPressed: controller.undo)
            : null,
      ));
  }

  Future<void> _applyRedactions(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('pdf-redaction-confirm'),
        title: const Text('Apply redactions?'),
        content: const Text(
            'The marked content will be permanently removed from the '
            'document. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('pdf-redaction-confirm-apply'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final burned = controller.applyRedactions();
    _flattenToast(
      context,
      burned ? 'Redactions applied' : 'No redactions to apply',
      undoable: false,
    );
  }

  Future<void> _editSelectedText(BuildContext context) async {
    final annotation = controller.selectedAnnotation;
    if (annotation == null) return;
    if (annotation.subtype == 'FreeText' &&
        controller.requestEditSelectedTextInline()) {
      return;
    }
    final text = await widget.textPrompt(
      context,
      title: switch (annotation.subtype) {
        'FreeText' => 'Text',
        'Stamp' => 'Stamp text',
        _ => 'Note',
      },
      initial: controller.selectedText ?? '',
      multiline: annotation.subtype != 'Stamp',
    );
    if (text == null || text.isEmpty) return;
    controller.setSelectedText(text);
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Listener(
      // a touch here (arming a tool is usually the first touch) reveals
      // the touch-only controls before the page is ever touched
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.touch) {
          controller.noteTouchInput();
        }
      },
      // transparent so the dock + contextual strip read as floating cards
      // over the page, not a solid edge-to-edge bar; the Material is only
      // here to host ink for the swatches and chips
      child: Material(
        type: MaterialType.transparency,
        child: ListenableBuilder(
          listenable: Listenable.merge([controller, viewerController]),
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) =>
                constraints.maxWidth < PdfEditingToolbar.mobileBreakpoint
                    ? _buildMobile(context)
                    : _buildDesktop(context),
          ),
        ),
      ),
    );
  }

  // ---- desktop: dock + contextual strip -----------------------------------

  Widget _buildDesktop(BuildContext context) {
    final strip = _desktopStrip(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (strip != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: strip,
            ),
          _dock(context),
        ],
      ),
    );
  }

  /// The contextual strip above the dock: a selected annotation's actions,
  /// a selected element's actions, or the open group's tools + settings.
  /// Null when resting (Select active, nothing selected).
  Widget? _desktopStrip(BuildContext context) {
    final selectedAnnot = controller.selectedAnnotation;
    if (selectedAnnot != null) return _selectionStrip(context);
    if (controller.selectedElement != null) return _elementStrip(context);
    final group = _openGroup;
    if (group == null || group.id == 'select') return null;
    return _groupStrip(context, group);
  }

  /// A horizontally-centred floating card. When the controls overflow, the
  /// controls scroll inside the card so the rounded card edge never gets
  /// clipped by the viewer or scrollbar gutter.
  Widget _centeredCard(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(8),
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        child: Container(
          key: const ValueKey('pdf-editing-toolbar-card'),
          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          decoration: _cardDecoration(context),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: scheme.outlineVariant),
      // border-first depth: a soft lift in light themes, flat in dark
      boxShadow: dark
          ? null
          : const [
              BoxShadow(
                  color: Color(0x2E000000),
                  blurRadius: 8,
                  offset: Offset(0, 3)),
              BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 3,
                  offset: Offset(0, 1)),
            ],
    );
  }

  Widget _dock(BuildContext context) {
    final groups = _visibleGroups;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final builder in widget.leading)
          builder(context, controller, viewerController),
        if (widget.leading.isNotEmpty) const _DockDivider(),
        if (widget.showUndoRedo) ...[
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo (⌘Z)',
            onPressed: controller.canUndo ? controller.undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: 'Redo (⇧⌘Z)',
            onPressed: controller.canRedo ? controller.redo : null,
          ),
          const _DockDivider(),
        ],
        for (final group in groups)
          _GroupChip(
            key: ValueKey('pdf-group-${group.id}'),
            group: group,
            active: _openGroup?.id == group.id,
            onTap: () => _openGroupTap(group),
          ),
        // Flatten now lives in the Edit group's strip, not the dock.
        // Save stays available for standalone hosts, but the drop-in
        // shells hide it here and surface it in their header (near Open).
        if (widget.onSave != null) ...[
          const _DockDivider(),
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: 'Save… (⌘S / Ctrl+S)',
            onPressed: () => widget.onSave!(controller.bytes),
          ),
        ],
        if (widget.trailing.isNotEmpty) ...[
          const _DockDivider(),
          for (final builder in widget.trailing)
            builder(context, controller, viewerController),
        ],
      ],
    );
    return _centeredCard(context, child: row);
  }

  /// The tools-left / settings-right card for an open [group].
  Widget _groupStrip(BuildContext context, _ToolGroup group) {
    final hasTextSelection = viewerController.hasSelection;
    // the Edit group's tools (content/form/redact) read as bare icons —
    // too cryptic for destructive document edits — so they get text labels
    final labelled = group.id == 'edit';
    final toolButtons = <Widget>[];
    for (final entry in group.tools) {
      if (entry.tool != null && !_shows(entry.tool!)) continue;
      if (entry.markup != null) {
        toolButtons.add(IconButton(
          icon: Icon(entry.icon),
          tooltip: entry.tip,
          onPressed: hasTextSelection ? () => _markup(entry.markup!) : null,
        ));
      } else if (labelled) {
        final tool = entry.tool!;
        toolButtons.add(_LabeledToolButton(
          icon: entry.icon,
          label: switch (tool) {
            PdfEditTool.content => 'Content',
            PdfEditTool.form => 'Form',
            PdfEditTool.redact => 'Redact',
            PdfEditTool.snapshot => 'Snapshot',
            _ => _entryLabel(entry),
          },
          tooltip: _entryTip(entry),
          active: controller.tool == tool,
          onTap: () => _armGroupTool(context, tool),
        ));
      } else {
        final tool = entry.tool!;
        toolButtons.add(IconButton(
          icon: Icon(entry.icon),
          tooltip: _entryTip(entry),
          isSelected: controller.tool == tool,
          onPressed: () => _armGroupTool(context, tool),
        ));
      }
    }

    final settings = _groupSettings(context, group);
    final row = IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _StripLabel(
                group.label,
                hint: group.id == 'markup' && !hasTextSelection
                    ? 'Select text to use markup'
                    : null,
              ),
              ...toolButtons,
            ]),
          ),
          if (settings.isNotEmpty) ...[
            const _StripDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: settings),
            ),
          ],
        ],
      ),
    );
    return _centeredCard(context, padding: EdgeInsets.zero, child: row);
  }

  /// The settings cluster for the active tool of [group].
  List<Widget> _groupSettings(BuildContext context, _ToolGroup group) {
    final tool = controller.tool;
    final fields = _groupStyleFields(group);
    switch (group.id) {
      case 'markup':
        return [
          ..._colorCluster(context),
          if (widget.showColor && widget.showStyle) const _MiniDivider(),
          _opacitySlider(context),
          ..._tuneTrailing(context, fields),
        ];
      case 'draw':
        if (tool == PdfEditTool.eraser) {
          return [
            ..._drawToolExtras(context),
            ..._tuneTrailing(context, fields),
          ];
        }
        return [
          ..._colorCluster(context),
          if (widget.showColor) const _MiniDivider(),
          _strokePresets(context),
          const _MiniDivider(),
          _opacitySlider(context),
          ..._drawToolExtras(context),
          ..._tuneTrailing(context, fields),
        ];
      case 'shapes':
        return [
          ..._colorCluster(context),
          if (widget.showColor) const _MiniDivider(),
          _strokePresets(context),
          const _MiniDivider(),
          _opacitySlider(context),
          ..._tuneTrailing(context, fields),
        ];
      case 'insert':
        return [
          ..._colorCluster(context),
          if (widget.showColor) const _MiniDivider(),
          _opacitySlider(context),
          ..._insertToolExtras(context),
          ..._tuneTrailing(context, fields),
        ];
      case 'measure':
        return [
          ..._colorCluster(context),
          if (widget.showColor) const _MiniDivider(),
          _strokePresets(context),
          const _MiniDivider(),
          _scaleChip(context),
          ..._tuneTrailing(context, fields),
        ];
      case 'edit':
        return _editToolExtras(context);
      default:
        return const [];
    }
  }

  /// Draw-tool sub-controls: the finger/pen toggle and the manual ink
  /// commit/discard buttons.
  List<Widget> _drawToolExtras(BuildContext context) {
    final tool = controller.tool;
    return [
      if ((tool == PdfEditTool.ink || tool == PdfEditTool.eraser) &&
          controller.hasTouchInput)
        IconButton(
          icon: const Icon(Icons.touch_app),
          tooltip: controller.fingerDrawsInk
              ? 'Finger draws — tap so it scrolls instead'
              : 'Finger scrolls (pen draws) — tap so it draws',
          isSelected: controller.fingerDrawsInk,
          onPressed: () =>
              controller.fingerDrawsInk = !controller.fingerDrawsInk,
        ),
      if (controller.hasPendingInk && !controller.inkAutoCommits) ...[
        IconButton(
          icon: const Icon(Icons.check),
          tooltip: 'Add ink annotation',
          onPressed: controller.finishInk,
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Discard drawing',
          onPressed: controller.discardInk,
        ),
      ],
    ];
  }

  /// Insert-tool sub-controls: the custom-stamp picker and the redraw
  /// button for the signature tool.
  List<Widget> _insertToolExtras(BuildContext context) {
    return [
      if (controller.tool == PdfEditTool.stamp)
        IconButton(
          icon: const Icon(Icons.style),
          tooltip: 'Custom stamps…',
          isSelected: controller.activeStamp != null,
          onPressed: () => showPdfStampPicker(context, controller: controller),
        ),
      if (controller.tool == PdfEditTool.signature)
        IconButton(
          icon: const Icon(Icons.restart_alt),
          tooltip: 'Draw a new signature…',
          onPressed: () => _drawSignature(context),
        ),
      if (controller.tool == PdfEditTool.count)
        Tooltip(
          message: 'Check-marks on the document',
          child: Chip(
            key: const ValueKey('pdf-count-tally'),
            avatar: const Icon(Icons.task_alt, size: 18),
            label: Text('${controller.checkMarkCount}'),
            visualDensity: VisualDensity.compact,
          ),
        ),
    ];
  }

  /// Edit-group sub-controls: the form field-type menu + form flatten,
  /// and the redaction apply button (each shows only with its tool armed),
  /// plus the document-wide Flatten action (which moved here from the
  /// dock, gated by [PdfEditingToolbar.showFlatten]).
  List<Widget> _editToolExtras(BuildContext context) {
    final tool = controller.tool;
    final flatten = widget.showFlatten
        ? _LabeledToolButton(
            icon: Icons.layers_outlined,
            label: 'Flatten',
            tooltip: 'Flatten annotations into the pages',
            active: false,
            onTap: () => _flatten(context),
          )
        : null;
    if (tool == PdfEditTool.form) {
      return [
        if (flatten != null) ...[flatten, const _MiniDivider()],
        PopupMenuButton<PdfFormFieldKind>(
          key: const ValueKey('pdf-form-field-type'),
          tooltip: 'New field type — drag on a page to add one',
          icon: Icon(switch (controller.newFormFieldKind) {
            PdfFormFieldKind.text => Icons.text_fields,
            PdfFormFieldKind.checkBox => Icons.check_box_outlined,
            PdfFormFieldKind.pushButton => Icons.smart_button,
          }),
          initialValue: controller.newFormFieldKind,
          onSelected: (kind) => controller.newFormFieldKind = kind,
          itemBuilder: (context) => const [
            PopupMenuItem(
              key: ValueKey('pdf-form-type-text'),
              value: PdfFormFieldKind.text,
              child: Text('Text field'),
            ),
            PopupMenuItem(
              key: ValueKey('pdf-form-type-checkbox'),
              value: PdfFormFieldKind.checkBox,
              child: Text('Check box'),
            ),
            PopupMenuItem(
              key: ValueKey('pdf-form-type-button'),
              value: PdfFormFieldKind.pushButton,
              child: Text('Image button'),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.layers_clear_outlined),
          tooltip: 'Flatten form — bake values into the pages',
          onPressed:
              controller.acroForm == null ? null : () => _flattenForm(context),
        ),
      ];
    }
    if (tool == PdfEditTool.redact) {
      return [
        if (flatten != null) ...[flatten, const _MiniDivider()],
        IconButton(
          key: const ValueKey('pdf-apply-redactions'),
          icon: const Icon(Icons.check),
          tooltip: 'Apply redactions (irreversible)',
          onPressed: controller.hasRedactionMarks
              ? () => _applyRedactions(context)
              : null,
        ),
      ];
    }
    return [if (flatten != null) flatten];
  }

  /// The strip shown while an annotation is selected: delete + edit-text,
  /// then the restyle settings that apply (colour, opacity, the tune
  /// popup carries stroke/font/etc).
  Widget _selectionStrip(BuildContext context) {
    final canRestyle = controller.canRestyleSelected;
    final settings = <Widget>[
      if (widget.showColor && canRestyle) ..._colorCluster(context),
      if (widget.showColor && canRestyle && widget.showStyle)
        const _MiniDivider(),
      if (canRestyle) _opacitySlider(context),
      ..._tuneTrailing(context, _selectionStyleFields()),
    ];
    final row = IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _StripLabel(switch (controller.selectedAnnotationSlots.length) {
                1 => 'Selection',
                final n => '$n selected',
              }),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: switch (controller.selectedAnnotationSlots.length) {
                  1 => 'Delete annotation',
                  final n => 'Delete $n annotations',
                },
                onPressed: controller.deleteSelected,
              ),
              if (controller.canEditSelectedText)
                IconButton(
                  key: const ValueKey('pdf-edit-selected-text'),
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit annotation text',
                  onPressed: () => _editSelectedText(context),
                ),
              if (controller.canRestyleSelectedText)
                IconButton(
                  icon: const Icon(Icons.fit_screen),
                  tooltip: 'Autosize text box (Alt+Z)',
                  onPressed: controller.autosizeSelectedTextBox,
                ),
            ]),
          ),
          if (settings.isNotEmpty) ...[
            const _StripDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: settings),
            ),
          ],
        ],
      ),
    );
    return _centeredCard(context, padding: EdgeInsets.zero, child: row);
  }

  /// The strip shown while a page-content element is selected.
  Widget _elementStrip(BuildContext context) {
    final row = Row(mainAxisSize: MainAxisSize.min, children: [
      const _StripLabel('Element'),
      IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete element',
        onPressed: controller.deleteSelectedElement,
      ),
      if (controller.canEditSelectedElementText)
        IconButton(
          icon: const Icon(Icons.edit),
          tooltip: 'Replace text',
          onPressed: () => _editElementText(context),
        ),
    ]);
    return _centeredCard(
      context,
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      child: row,
    );
  }

  // ---- inline settings clusters -------------------------------------------

  /// The palette swatches + custom-colour picker + eyedropper. Empty when
  /// [PdfEditingToolbar.showColor] is off.
  List<Widget> _colorCluster(BuildContext context) {
    if (!widget.showColor) return const [];
    final scheme = Theme.of(context).colorScheme;
    return [
      for (final color in widget.palette)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: InkWell(
            onTap: () => _applyColor(color),
            customBorder: const CircleBorder(),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: controller.color == color
                      ? scheme.primary
                      : scheme.outline,
                  width: controller.color == color ? 3 : 1,
                ),
              ),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Tooltip(
          message: 'More colors…',
          child: Material(
            key: const ValueKey('pdf-more-colors'),
            color: Colors.transparent,
            shape: CircleBorder(side: BorderSide(color: scheme.outline)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
                final picked = await showPdfColorPicker(context,
                    initial: controller.color,
                    initialFormat: controller.preferences.colorPickerFormat,
                    onFormatChanged: (format) =>
                        controller.preferences.colorPickerFormat = format);
                if (picked != null) _applyColor(picked);
              },
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Icon(Icons.palette_outlined,
                      color: controller.color, size: 20),
                ),
              ),
            ),
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.colorize),
        tooltip: 'Pick a color from the page',
        isSelected: controller.isPickingColor,
        onPressed: () => controller.isPickingColor
            ? controller.cancelColorPick()
            : controller.startColorPick(),
      ),
    ];
  }

  /// Four quick stroke-width presets. The precise slider stays in the
  /// tune popup; these set the common weights in one tap.
  Widget _strokePresets(BuildContext context) {
    const presets = [1.5, 3.0, 5.0, 8.0];
    final scheme = Theme.of(context).colorScheme;
    final restyling = controller.canRestyleSelected;
    final current = restyling
        ? (controller.selectedAnnotationStyle?.strokeWidth ??
            controller.strokeWidth)
        : controller.strokeWidth;
    void set(double w) {
      controller.strokeWidth = w;
      if (restyling) controller.restyleSelected(strokeWidth: w);
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final w in presets)
        Tooltip(
          message:
              'Stroke ${w.toStringAsFixed(w == w.roundToDouble() ? 0 : 1)}',
          child: InkWell(
            onTap: () => set(w),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 36,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (current - w).abs() < 0.4
                    ? scheme.primary.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Container(
                width: 20,
                height: (w + 1).clamp(2, 10),
                decoration: BoxDecoration(
                  color: (current - w).abs() < 0.4
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
    ]);
  }

  /// A compact inline opacity slider with a percentage readout. While an
  /// annotation is selected it restyles it on release (one revision per
  /// gesture); otherwise it sets the creation default live.
  Widget _opacitySlider(BuildContext context) {
    final restyling = controller.canRestyleSelected;
    final value = _dragOpacity ??
        (restyling ? controller.selectedAnnotationStyle?.opacity : null) ??
        controller.opacity;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Padding(
        padding: EdgeInsets.only(right: 2),
        child: Icon(Icons.opacity, size: 18),
      ),
      SizedBox(
        width: 96,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: value.clamp(0.1, 1),
            min: 0.1,
            max: 1,
            onChanged: (v) {
              setState(() => _dragOpacity = v);
              if (!restyling) controller.opacity = v;
            },
            onChangeEnd: (v) {
              controller.opacity = v;
              if (restyling) controller.restyleSelected(opacity: v);
              setState(() => _dragOpacity = null);
            },
          ),
        ),
      ),
      SizedBox(
        width: 38,
        child: Text(
          '${(value * 100).round()}%',
          style: TextStyle(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ]);
  }

  /// The measure scale chip — its ratio label, opening the calibration
  /// dialog on tap.
  Widget _scaleChip(BuildContext context) {
    return _SettingChip(
      key: const ValueKey('pdf-measure-scale'),
      leading: 'Scale',
      value: controller.measurementScale?.ratioLabel ?? 'Set…',
      onTap: () => _setScale(context),
    );
  }

  /// The tune popup trigger (and nothing else), or empty when
  /// [PdfEditingToolbar.showStyle] is off or [fields] carries nothing
  /// relevant. A font context renders the trigger as the design's font
  /// chip rather than the gear icon.
  List<Widget> _tuneTrailing(BuildContext context, _StyleFields fields) {
    if (!widget.showStyle || fields.isEmpty) return const [];
    return [
      if (fields.font) const _MiniDivider(),
      _StyleMenu(
        controller: controller,
        palette: widget.palette,
        showColor: widget.showColor,
        fields: fields,
        fontChipTrigger: fields.font,
        fontPicker: widget.fontPicker,
      ),
    ];
  }

  /// The style controls relevant to [group]'s active tool — see
  /// [_StyleFields]. Drives the tune popup so a rectangle never offers a
  /// font picker, ink never offers line endings, and so on.
  _StyleFields _groupStyleFields(_ToolGroup group) {
    final tool = controller.tool;
    switch (group.id) {
      case 'draw':
        if (tool == PdfEditTool.eraser) return const _StyleFields(eraser: true);
        return const _StyleFields(stroke: true, opacity: true);
      case 'shapes':
        return _StyleFields(
          stroke: true,
          opacity: true,
          lineType: true,
          lineEndings: tool == PdfEditTool.line || tool == PdfEditTool.polyline,
          shapeFill: tool == PdfEditTool.rectangle ||
              tool == PdfEditTool.ellipse ||
              tool == PdfEditTool.polygon,
        );
      case 'insert':
        return const _StyleFields(opacity: true, font: true, boxColors: true);
      case 'measure':
        return const _StyleFields(stroke: true, opacity: true, font: true);
      case 'markup':
        return const _StyleFields(opacity: true);
      default:
        return const _StyleFields();
    }
  }

  /// The style controls relevant to the current annotation selection — by
  /// the primary selection's subtype, gated by what can actually restyle.
  _StyleFields _selectionStyleFields() {
    final annotation = controller.selectedAnnotation;
    if (annotation == null) return const _StyleFields();
    final canStroke = controller.canRestyleSelected;
    switch (annotation.subtype) {
      case 'FreeText':
        final text = controller.canRestyleSelectedText;
        return _StyleFields(opacity: true, font: text, boxColors: text);
      case 'Square':
      case 'Circle':
      case 'Polygon':
        return _StyleFields(
            stroke: canStroke,
            opacity: true,
            lineType: controller.canSetLineStyleSelected,
            shapeFill: controller.canFillSelected);
      case 'Line':
      case 'PolyLine':
        return _StyleFields(
            stroke: canStroke,
            opacity: true,
            lineType: controller.canSetLineStyleSelected,
            lineEndings: controller.canSetLineEndings);
      case 'Ink':
        return _StyleFields(stroke: canStroke, opacity: true);
      default:
        // markup, stamps, notes: opacity is the only shared restyle
        return const _StyleFields(opacity: true);
    }
  }

  // ---- mobile: collapsed dock + bottom sheet ------------------------------

  Widget _buildMobile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tool = controller.tool;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6) +
          EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: SafeArea(
        top: false,
        child: Row(children: [
          if (widget.showUndoRedo) ...[
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Undo (⌘Z)',
              visualDensity: VisualDensity.compact,
              onPressed: controller.canUndo ? controller.undo : null,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              tooltip: 'Redo (⇧⌘Z)',
              visualDensity: VisualDensity.compact,
              onPressed: controller.canRedo ? controller.redo : null,
            ),
          ],
          Expanded(
            child: Row(children: [
              const SizedBox(width: 4),
              Icon(_activeToolIcon(tool), size: 22, color: scheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _activeToolLabel(tool),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ]),
          ),
          ..._mobileTrailing(context),
          const SizedBox(width: 6),
          _GroupChip.toolsHandle(
            key: const ValueKey('pdf-tools-handle'),
            onTap: () => _openToolSheet(context),
          ),
        ]),
      ),
    );
  }

  /// The mobile dock's trailing cluster, between the active-tool label and
  /// the Tools handle. It shows only what's relevant to the moment so the
  /// colour swatches never sit dead next to a tool that ignores them.
  /// A selected annotation gets its own quick actions (delete, edit text) —
  /// the better use of the space the request asks for, since those were
  /// otherwise unreachable from the dock; an armed colour-using tool gets
  /// the swatches; anything else leaves the space to the tool label.
  List<Widget> _mobileTrailing(BuildContext context) {
    if (controller.hasAnnotationSelection) {
      return [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: switch (controller.selectedAnnotationSlots.length) {
            1 => 'Delete annotation',
            final n => 'Delete $n annotations',
          },
          visualDensity: VisualDensity.compact,
          onPressed: controller.deleteSelected,
        ),
        if (controller.canEditSelectedText)
          IconButton(
            key: const ValueKey('pdf-edit-selected-text'),
            icon: const Icon(Icons.edit),
            tooltip: 'Edit annotation text',
            visualDensity: VisualDensity.compact,
            onPressed: () => _editSelectedText(context),
          ),
      ];
    }
    if (widget.showColor && controller.toolUsesColor) {
      return _mobileSwatches(context);
    }
    return const [];
  }

  /// The first three palette swatches, sized for the mobile dock.
  List<Widget> _mobileSwatches(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    var i = 0;
    return [
      for (final color in widget.palette.take(3))
        Padding(
          key: ValueKey('pdf-mobile-swatch-${i++}'),
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: InkWell(
            onTap: () => _applyColor(color),
            customBorder: const CircleBorder(),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: controller.color == color
                      ? scheme.primary
                      : scheme.outline,
                  width: controller.color == color ? 3 : 1,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  IconData _activeToolIcon(PdfEditTool? tool) {
    if (tool == null) return Icons.near_me;
    for (final group in _groups) {
      for (final entry in group.tools) {
        if (entry.tool == tool) return entry.icon;
      }
    }
    return Icons.near_me;
  }

  String _activeToolLabel(PdfEditTool? tool) {
    if (tool == null) return 'Select';
    for (final group in _groups) {
      for (final entry in group.tools) {
        if (entry.tool == tool) {
          // the tip's leading clause is the tool's name
          final tip = entry.tip;
          final dash = tip.indexOf(' —');
          return dash == -1 ? tip : tip.substring(0, dash);
        }
      }
    }
    return 'Select';
  }

  /// Opens the mobile tools sheet: group tabs, a tool grid, and the active
  /// tool's settings. The tab state lives in the sheet so switching groups
  /// doesn't arm anything until a tool is tapped.
  Future<void> _openToolSheet(BuildContext context) async {
    final groups = _visibleGroups;
    var tabId = _openGroup?.id ?? groups.first.id;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => ListenableBuilder(
          listenable: Listenable.merge([controller, viewerController]),
          builder: (context, _) {
            final group = groups.firstWhere((g) => g.id == tabId,
                orElse: () => groups.first);
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final g in groups)
                          Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: _GroupChip(
                              key: ValueKey('pdf-group-tab-${g.id}'),
                              group: g,
                              active: g.id == tabId,
                              onTap: () {
                                setSheetState(() => tabId = g.id);
                                // markup arms no tool — scope it so its
                                // settings row edits markup's own style
                                if (g.id == 'markup') {
                                  controller.useMarkupStyleScope();
                                }
                              },
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    _SheetSectionLabel(
                      group.label,
                      hint:
                          group.id == 'markup' && !viewerController.hasSelection
                              ? 'Select text to use markup'
                              : null,
                    ),
                    const SizedBox(height: 10),
                    _sheetToolGrid(sheetContext, group),
                    ..._sheetSettings(sheetContext, group),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sheetToolGrid(BuildContext context, _ToolGroup group) {
    final hasTextSelection = viewerController.hasSelection;
    final entries =
        group.tools.where((e) => e.markup != null || _shows(e.tool!)).toList();
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.15,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (final entry in entries)
          _SheetToolTile(
            icon: entry.icon,
            label: entry.markup != null
                ? entry.tip.replaceAll(' selection', '')
                : _entryLabel(entry),
            active: entry.tool != null && controller.tool == entry.tool,
            enabled: entry.markup == null || hasTextSelection,
            onTap: () async {
              if (entry.markup != null) {
                _markup(entry.markup!);
                if (context.mounted) Navigator.of(context).pop();
              } else {
                await _armGroupTool(context, entry.tool!);
              }
            },
          ),
      ],
    );
  }

  static String _entryLabel(_GroupTool entry) {
    final dash = entry.tip.indexOf(' —');
    return dash == -1 ? entry.tip : entry.tip.substring(0, dash);
  }

  /// A tool's tooltip with its keyboard shortcut appended (e.g.
  /// "Rectangle (R)"), so the bindings in [pdfEditToolShortcuts] are
  /// discoverable on hover. Markups and unbound tools keep the plain tip.
  static String _entryTip(_GroupTool entry) {
    final tool = entry.tool;
    final key = tool == null ? null : pdfEditToolShortcutLabel(tool);
    return key == null ? entry.tip : '${entry.tip} ($key)';
  }

  /// The settings block under the sheet's tool grid — reuses the same
  /// inline clusters as the desktop strip, laid out in rows.
  List<Widget> _sheetSettings(BuildContext context, _ToolGroup group) {
    final settings = _groupSettings(context, group)
        .where((w) => w is! _MiniDivider)
        .toList();
    if (settings.isEmpty) return const [];
    return [
      const SizedBox(height: 14),
      const Divider(height: 1),
      const SizedBox(height: 14),
      Wrap(
        spacing: 10,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: settings,
      ),
    ];
  }
}

/// A thin vertical divider between dock clusters.
class _DockDivider extends StatelessWidget {
  const _DockDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: Theme.of(context).colorScheme.outlineVariant,
      );
}

/// The full-height divider between a strip's tools and settings segments.
class _StripDivider extends StatelessWidget {
  const _StripDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 8),
        color: Theme.of(context).colorScheme.outlineVariant,
      );
}

/// A short vertical divider between setting clusters within a strip.
class _MiniDivider extends StatelessWidget {
  const _MiniDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: Theme.of(context).colorScheme.outlineVariant,
      );
}

/// The uppercase group/context label at the left of a contextual strip.
class _StripLabel extends StatelessWidget {
  const _StripLabel(this.text, {this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8, left: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: scheme.onSurfaceFaintOr,
            ),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                hint!,
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The section label above the mobile sheet's tool grid.
class _SheetSectionLabel extends StatelessWidget {
  const _SheetSectionLabel(this.text, {this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: scheme.onSurfaceFaintOr,
          ),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              hint!,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// A pill-shaped dock group chip (icon + label), or the mobile "Tools"
/// handle.
class _GroupChip extends StatelessWidget {
  const _GroupChip({
    super.key,
    required this.group,
    required this.active,
    required this.onTap,
  }) : _toolsHandle = false;

  const _GroupChip.toolsHandle({
    super.key,
    required this.onTap,
  })  : group = null,
        active = true,
        _toolsHandle = true;

  final _ToolGroup? group;
  final bool active;
  final VoidCallback onTap;
  final bool _toolsHandle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = active;
    final fg = on ? scheme.primary : scheme.onSurfaceVariant;
    final label = _toolsHandle ? 'Tools' : group!.label;
    final icon = _toolsHandle ? Icons.keyboard_arrow_up : group!.icon;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: on ? scheme.primary.withValues(alpha: 0.15) : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: on ? scheme.primary.withValues(alpha: 0.55) : scheme.outline,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 14, 0),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_toolsHandle) ...[
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: fg)),
                  const SizedBox(width: 6),
                  Icon(icon, size: 18, color: fg),
                ] else ...[
                  Icon(icon, size: 19, color: fg),
                  const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: fg)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon + text button used for the Edit group's tools (and its
/// Flatten action), where a bare icon would be too cryptic for the
/// document-altering operations they trigger.
class _LabeledToolButton extends StatelessWidget {
  const _LabeledToolButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = active ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: active
              ? scheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: active
                  ? scheme.primary.withValues(alpha: 0.55)
                  : scheme.outline,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tile in the mobile sheet's tool grid: icon above a label.
class _SheetToolTile extends StatelessWidget {
  const _SheetToolTile({
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
        ? scheme.onSurfaceFaintOr
        : active
            ? scheme.primary
            : scheme.onSurfaceVariant;
    return Material(
      color:
          active ? scheme.primary.withValues(alpha: 0.14) : Colors.transparent,
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
    );
  }
}

/// A compact labelled chip for a setting that opens a dialog (the measure
/// scale). Shows a leading label and the current value.
class _SettingChip extends StatelessWidget {
  const _SettingChip({
    super.key,
    required this.leading,
    required this.value,
    required this.onTap,
  });

  final String leading;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(leading,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(width: 6),
            Text(value,
                style: TextStyle(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                )),
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 16, color: scheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

/// A small fallback for `colorScheme.onSurfaceFaint` (not a Material role)
/// — the faint hint colour used for strip labels and disabled tiles.
extension _FaintColor on ColorScheme {
  Color get onSurfaceFaintOr => onSurfaceVariant.withValues(alpha: 0.75);
}

/// Which controls the style popup should show for the active context —
/// each tool/selection only carries the settings it can actually use, so
/// the popup never shows (say) a font picker while a rectangle is armed.
class _StyleFields {
  const _StyleFields({
    this.stroke = false,
    this.opacity = false,
    this.lineType = false,
    this.lineEndings = false,
    this.font = false,
    this.boxColors = false,
    this.shapeFill = false,
    this.eraser = false,
  });

  final bool stroke;
  final bool opacity;

  /// The line-type dropdown (solid / dashed / dotted / dash-dot) — shapes
  /// and the line family.
  final bool lineType;
  final bool lineEndings;

  /// Font size + family (free text).
  final bool font;

  /// The text-box fill + border colour rows (free text).
  final bool boxColors;

  /// The shape interior-fill colour row (rectangle / ellipse).
  final bool shapeFill;

  /// Eraser radius — replaces every other control while the eraser is armed.
  final bool eraser;

  bool get isEmpty =>
      !stroke &&
      !opacity &&
      !lineType &&
      !lineEndings &&
      !font &&
      !boxColors &&
      !shapeFill &&
      !eraser;
}

/// The style popup: sliders for stroke width, opacity, and font size,
/// the font family for free text, and the text box's fill and border
/// colors. With a free-text annotation selected, the text controls show
/// — and change — that annotation's style; otherwise they set the style
/// new text is created with. Only the [fields] relevant to the active
/// tool or selection are rendered.
class _StyleMenu extends StatefulWidget {
  const _StyleMenu({
    required this.controller,
    required this.palette,
    required this.fields,
    this.showColor = true,
    this.fontChipTrigger = false,
    this.fontPicker,
  });

  /// Which controls to show — see [_StyleFields].
  final _StyleFields fields;

  /// How the font menu's "Load font…" entry loads a custom font.
  final PdfFontPicker? fontPicker;

  final PdfEditingController controller;

  /// The colors offered as fill/border swatches (the toolbar's palette).
  final List<Color> palette;

  /// Whether the text-box fill/border color rows are shown. The
  /// stroke/opacity/font controls show regardless — this only hides the
  /// color rows so a color-locked session keeps the sliders.
  final bool showColor;

  /// Render the trigger as the design's font chip (Insert / a free-text
  /// selection) rather than the gear icon.
  final bool fontChipTrigger;

  @override
  State<_StyleMenu> createState() => _StyleMenuState();
}

class _StyleMenuState extends State<_StyleMenu> {
  PdfEditingController get controller => widget.controller;

  /// The font-size slider's in-flight value while dragging over a
  /// selected annotation — the annotation only restyles on release (one
  /// revision per gesture), so the thumb needs its own state meanwhile.
  double? _draggingFontSize;

  /// Same, for the stroke-width and opacity sliders restyling a
  /// selected annotation.
  double? _draggingStroke;
  double? _draggingOpacity;
  bool _holdingTextEditFocus = false;

  @override
  void dispose() {
    _endTextEditFocusHold();
    super.dispose();
  }

  void _beginTextEditFocusHold() {
    if (_holdingTextEditFocus || !controller.isEditingText) return;
    _holdingTextEditFocus = true;
    controller.beginEditingTextFocusHold();
  }

  void _endTextEditFocusHold() {
    if (!_holdingTextEditFocus) return;
    _holdingTextEditFocus = false;
    controller.endEditingTextFocusHold();
  }

  void _setFont(PdfStandardFont font) {
    controller.fontFamily = font; // the new default either way
    if (controller.restyleEditingTextSelection(font: font)) return;
    if (controller.canRestyleSelectedText) {
      controller.restyleSelectedText(font: font);
    }
  }

  static int? _rgb(Color? color) =>
      color == null ? null : color.toARGB32() & 0xFFFFFF;

  void _setTextFill(Color? color) {
    controller.textFillColor = color; // the new default either way
    if (controller.canRestyleSelectedText) {
      controller.restyleSelectedText(fill: (_rgb(color),));
    }
  }

  void _setShapeFill(Color? color) {
    controller.shapeFillColor = color; // the new default either way
    if (controller.canFillSelected) {
      controller.restyleSelected(fill: (color,));
    }
  }

  void _setTextBorder(Color? color) {
    controller.textBorderColor = color;
    if (controller.canRestyleSelectedText) {
      controller.restyleSelectedText(
          border: (_rgb(color),),
          // setting a border gives it the current stroke width; clearing
          // one leaves the width field alone
          borderWidth: color == null ? null : controller.strokeWidth);
    }
  }

  /// One text-box color row: a "none" swatch, the palette, and a custom
  /// picker. [onChanged] receives the chosen color, or null for none.
  Widget _boxColorRow({
    required BuildContext context,
    required String label,
    required String keyPrefix,
    required Color? value,
    required ValueChanged<Color?> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    Widget swatch(
            {required Key key,
            required Color? color,
            required bool selected,
            required VoidCallback onTap}) =>
        Padding(
          // 1px keeps six swatches + the picker inside the menu's 268px
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: InkWell(
            key: key,
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color ?? const Color(0xFFFFFFFF),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outline,
                  width: selected ? 3 : 1,
                ),
              ),
              child: color == null
                  ? const CustomPaint(painter: _NoneSlashPainter())
                  : null,
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        SizedBox(width: 86, child: Text(label)),
        swatch(
          key: ValueKey('$keyPrefix-none'),
          color: null,
          selected: value == null,
          onTap: () => onChanged(null),
        ),
        for (var i = 0; i < widget.palette.length; i++)
          swatch(
            key: ValueKey('$keyPrefix-$i'),
            color: widget.palette[i],
            selected: value != null &&
                (value.toARGB32() & 0xFFFFFF) ==
                    (widget.palette[i].toARGB32() & 0xFFFFFF),
            onTap: () => onChanged(widget.palette[i]),
          ),
        IconButton(
          icon: const Icon(Icons.palette_outlined, size: 18),
          tooltip: 'More colors…',
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            final picked = await showPdfColorPicker(context,
                initial: value ?? const Color(0xFFFFFFFF));
            if (picked != null) onChanged(picked);
          },
        ),
      ]),
    );
  }

  /// A short human label for a line ending in the picker.
  static String _endingLabel(PdfLineEnding ending) => switch (ending) {
        PdfLineEnding.none => 'None',
        PdfLineEnding.square => 'Square',
        PdfLineEnding.circle => 'Circle',
        PdfLineEnding.diamond => 'Diamond',
        PdfLineEnding.openArrow => 'Open arrow',
        PdfLineEnding.closedArrow => 'Closed arrow',
        PdfLineEnding.butt => 'Butt',
        PdfLineEnding.rOpenArrow => 'Open arrow (rev.)',
        PdfLineEnding.rClosedArrow => 'Closed arrow (rev.)',
        PdfLineEnding.slash => 'Slash',
      };

  /// One line-ending dropdown (start or end), each item previewed with a
  /// tiny icon of the shape on a short segment. [atEnd] orients the
  /// preview so the start picker draws its ending on the left.
  Widget _lineEndingRow({
    required BuildContext context,
    required String label,
    required String keyValue,
    required bool atEnd,
    required PdfLineEnding value,
    required ValueChanged<PdfLineEnding> onChanged,
  }) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        SizedBox(width: 86, child: Text(label)),
        Expanded(
          child: DropdownButton<PdfLineEnding>(
            key: ValueKey(keyValue),
            isExpanded: true,
            isDense: true,
            value: value,
            items: [
              for (final ending in PdfLineEnding.values)
                DropdownMenuItem(
                  value: ending,
                  child: Row(children: [
                    SizedBox(
                      width: 36,
                      height: 14,
                      child: CustomPaint(
                        painter: _LineEndingPainter(ending,
                            atEnd: atEnd, color: color),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(_endingLabel(ending),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
            ],
            onChanged: (ending) {
              if (ending != null) onChanged(ending);
            },
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      onClose: _endTextEditFocusHold,
      menuChildren: [
        // the menu lives in its own overlay, outside the toolbar's
        // ListenableBuilder — it needs its own listener to track sliders
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final fields = widget.fields;
            final selectedStyle = controller.selectedTextStyle;
            // with a restylable selection the stroke/opacity sliders
            // show — and change — its style; otherwise the defaults
            final restylingAnnotation = controller.canRestyleSelected;
            // the eraser doesn't paint, so none of the stroke/opacity/
            // font/line controls apply to it — while it's armed the menu
            // collapses to just the eraser-size slider
            final isEraser = fields.eraser;
            final annotationStyle =
                restylingAnnotation ? controller.selectedAnnotationStyle : null;
            final strokeValue = _draggingStroke ??
                annotationStyle?.strokeWidth ??
                controller.strokeWidth;
            final opacityValue = _draggingOpacity ??
                annotationStyle?.opacity ??
                controller.opacity;
            // with a free text selected the rows show its own box style;
            // otherwise the creation defaults
            // line endings: edit a selected /Line or /PolyLine in place,
            // else set the creation defaults while a line tool is armed
            final lineEndingTarget = controller.canSetLineEndings;
            final lineEndings = lineEndingTarget
                ? controller.selectedLineEndings!
                : (controller.lineStartEnding, controller.lineEndEnding);
            final restyling = controller.canRestyleSelectedText;
            final boxStyle =
                restyling ? controller.selectedAnnotation?.freeTextStyle : null;
            final fillValue = restyling
                ? (boxStyle?.fillColor != null
                    ? Color(0xFF000000 | boxStyle!.fillColor!)
                    : null)
                : controller.textFillColor;
            final borderValue = restyling
                ? (boxStyle?.borderColor != null &&
                        (boxStyle?.borderWidth ?? 0) > 0
                    ? Color(0xFF000000 | boxStyle!.borderColor!)
                    : null)
                : controller.textBorderColor;
            // shape interior fill: a selected shape shows its own /IC,
            // else the creation default
            final shapeFillValue = controller.canFillSelected
                ? controller.selectedShapeFill
                : controller.shapeFillColor;
            return Container(
              width: 300,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isEraser)
                    _slider(
                      key: const ValueKey('pdf-eraser-size'),
                      label: 'Eraser size',
                      value: controller.eraserRadius,
                      min: 2,
                      max: 40,
                      display: '${controller.eraserRadius.round()} pt',
                      onChanged: (v) =>
                          controller.eraserRadius = v.roundToDouble(),
                    ),
                  if (fields.stroke)
                    _slider(
                      label: 'Stroke width',
                      value: strokeValue,
                      min: 0.5,
                      max: 12,
                      display: '${strokeValue.toStringAsFixed(1)} pt',
                      onChanged: (v) {
                        setState(() => _draggingStroke = v);
                        if (!restylingAnnotation) controller.strokeWidth = v;
                      },
                      onChangeEnd: (v) {
                        controller.strokeWidth = v;
                        if (restylingAnnotation) {
                          controller.restyleSelected(strokeWidth: v);
                        }
                        setState(() => _draggingStroke = null);
                      },
                    ),
                  if (fields.opacity)
                    _slider(
                      label: 'Opacity',
                      value: opacityValue,
                      min: 0.1,
                      max: 1,
                      display: '${(opacityValue * 100).round()}%',
                      onChanged: (v) {
                        setState(() => _draggingOpacity = v);
                        if (!restylingAnnotation) controller.opacity = v;
                      },
                      onChangeEnd: (v) {
                        controller.opacity = v;
                        if (restylingAnnotation) {
                          controller.restyleSelected(opacity: v);
                        }
                        setState(() => _draggingOpacity = null);
                      },
                    ),
                  if (fields.lineType)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Expanded(child: Text('Line type')),
                          DropdownButton<PdfLineStyle>(
                            key: const ValueKey('pdf-line-type'),
                            isDense: true,
                            value: restylingAnnotation
                                ? (controller.selectedLineStyle ??
                                    controller.lineStyle)
                                : controller.lineStyle,
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final style in PdfLineStyle.values)
                                DropdownMenuItem(
                                  value: style,
                                  key: ValueKey('pdf-line-type-${style.name}'),
                                  child: Text(style.label),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              controller.lineStyle = value;
                              if (restylingAnnotation &&
                                  controller.canSetLineStyleSelected) {
                                controller.restyleSelected(lineStyle: value);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  if (fields.lineEndings) ...[
                    _lineEndingRow(
                      context: context,
                      label: 'Line start',
                      keyValue: 'pdf-line-start-ending',
                      atEnd: false,
                      value: lineEndings.$1,
                      onChanged: (ending) {
                        controller.lineStartEnding = ending;
                        if (controller.canSetLineEndings) {
                          controller.setSelectedLineEndings(start: ending);
                        }
                      },
                    ),
                    _lineEndingRow(
                      context: context,
                      label: 'Line end',
                      keyValue: 'pdf-line-end-ending',
                      atEnd: true,
                      value: lineEndings.$2,
                      onChanged: (ending) {
                        controller.lineEndEnding = ending;
                        if (controller.canSetLineEndings) {
                          controller.setSelectedLineEndings(end: ending);
                        }
                      },
                    ),
                  ],
                  if (fields.shapeFill && widget.showColor)
                    _boxColorRow(
                      context: context,
                      label: 'Fill',
                      keyPrefix: 'pdf-shape-fill',
                      value: shapeFillValue,
                      onChanged: _setShapeFill,
                    ),
                  if (fields.font)
                    _slider(
                      label: 'Font size',
                      value: _draggingFontSize ??
                          selectedStyle?.size ??
                          controller.fontSize,
                      min: 8,
                      max: 48,
                      display:
                          '${(_draggingFontSize ?? selectedStyle?.size ?? controller.fontSize).round()} pt',
                      onChanged: (v) {
                        setState(() => _draggingFontSize = v.roundToDouble());
                        if (selectedStyle == null) {
                          controller.fontSize = v.roundToDouble();
                        }
                      },
                      onChangeEnd: (v) {
                        final size = v.roundToDouble();
                        controller.fontSize = size;
                        if (controller.restyleEditingTextSelection(
                            size: size)) {
                          setState(() => _draggingFontSize = null);
                          return;
                        }
                        if (controller.canRestyleSelectedText) {
                          controller.restyleSelectedText(size: size);
                        }
                        setState(() => _draggingFontSize = null);
                      },
                    ),
                  if (fields.font) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        const SizedBox(width: 86, child: Text('Font')),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: PdfFontMenuButton(
                              controller: controller,
                              fontPicker: widget.fontPicker,
                            ),
                          ),
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: [
                        const SizedBox(width: 86, child: Text('Style')),
                        FontStyleToggles(
                          font: selectedStyle?.font ?? controller.fontFamily,
                          onChanged: _setFont,
                        ),
                      ]),
                    ),
                  ],
                  if (fields.boxColors && widget.showColor) ...[
                    _boxColorRow(
                      context: context,
                      label: 'Text fill',
                      keyPrefix: 'pdf-text-fill',
                      value: fillValue,
                      onChanged: _setTextFill,
                    ),
                    _boxColorRow(
                      context: context,
                      label: 'Text border',
                      keyPrefix: 'pdf-text-border',
                      value: borderValue,
                      onChanged: _setTextBorder,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
      builder: (context, menu, _) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          void toggle() {
            if (menu.isOpen) {
              menu.close();
              return;
            }
            _beginTextEditFocusHold();
            menu.open();
          }

          final tip =
              widget.fields.eraser ? 'Eraser size' : 'Stroke, opacity, font';
          Widget holdOnPointerDown(Widget child) => Listener(
                onPointerDown: (_) => _beginTextEditFocusHold(),
                child: Focus(
                  canRequestFocus: false,
                  descendantsAreFocusable: false,
                  child: child,
                ),
              );
          if (widget.fontChipTrigger) {
            return holdOnPointerDown(
              _FontChip(
                controller: controller,
                tooltip: tip,
                onTap: toggle,
              ),
            );
          }
          return holdOnPointerDown(
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: tip,
              onPressed: toggle,
            ),
          );
        },
      ),
    );
  }

  Widget _slider({
    Key? key,
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Row(key: key, children: [
      SizedBox(width: 86, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ),
      SizedBox(width: 44, child: Text(display, textAlign: TextAlign.end)),
    ]);
  }
}

/// The Insert / free-text font chip — "Aa  Sans  14" — that opens the
/// style popup. Reflects the selected free text's style, else the
/// creation defaults.
class _FontChip extends StatelessWidget {
  const _FontChip({
    required this.controller,
    required this.tooltip,
    required this.onTap,
  });

  final PdfEditingController controller;
  final String tooltip;
  final VoidCallback onTap;

  static String _familyLabel(PdfStandardFont font) {
    final base = font.family.label;
    final suffix = switch ((font.isBold, font.isItalic)) {
      (true, true) => ' BI',
      (true, false) => ' B',
      (false, true) => ' I',
      (false, false) => '',
    };
    return '$base$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = controller.selectedTextStyle;
    final font = style?.font ?? controller.fontFamily;
    final size = (style?.size ?? controller.fontSize).round();
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Aa',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(width: 8),
              Text(_familyLabel(font), style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text('$size',
                  style: TextStyle(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  )),
              const SizedBox(width: 2),
              Icon(Icons.expand_more, size: 16, color: scheme.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Draws a short segment with [ending] rendered at one end — the preview
/// icon for the line-ending dropdown. Purely indicative geometry (not the
/// exact appearance the editor generates), oriented so [atEnd] puts the
/// ending on the right.
class _LineEndingPainter extends CustomPainter {
  const _LineEndingPainter(this.ending,
      {required this.atEnd, required this.color});

  final PdfLineEnding ending;
  final bool atEnd;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final cy = size.height / 2;
    // the tip is the end the shape decorates; the line runs to the far side
    final tipX = atEnd ? size.width - 2.0 : 2.0;
    final farX = atEnd ? 2.0 : size.width - 2.0;
    // unit vector from tip back along the line, and the perpendicular
    final ux = farX > tipX ? 1.0 : -1.0;
    final tip = Offset(tipX, cy);
    canvas.drawLine(Offset(farX, cy), tip, stroke);
    const s = 6.0; // characteristic size in preview px
    Offset at(double along, double across) =>
        Offset(tip.dx + ux * along, cy + across);
    switch (ending) {
      case PdfLineEnding.none:
        break;
      case PdfLineEnding.closedArrow:
      case PdfLineEnding.openArrow:
        final path = Path()
          ..moveTo(at(s, -s * 0.4).dx, at(s, -s * 0.4).dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(at(s, s * 0.4).dx, at(s, s * 0.4).dy);
        if (ending == PdfLineEnding.closedArrow) {
          path.close();
          canvas.drawPath(path, fill);
        } else {
          canvas.drawPath(path, stroke);
        }
      case PdfLineEnding.rClosedArrow:
      case PdfLineEnding.rOpenArrow:
        final path = Path()
          ..moveTo(at(0, -s * 0.4).dx, at(0, -s * 0.4).dy)
          ..lineTo(at(s, 0).dx, at(s, 0).dy)
          ..lineTo(at(0, s * 0.4).dx, at(0, s * 0.4).dy);
        if (ending == PdfLineEnding.rClosedArrow) {
          path.close();
          canvas.drawPath(path, fill);
        } else {
          canvas.drawPath(path, stroke);
        }
      case PdfLineEnding.diamond:
        final path = Path()
          ..moveTo(at(s * 0.5, 0).dx, at(s * 0.5, 0).dy)
          ..lineTo(at(0, -s * 0.5).dx, at(0, -s * 0.5).dy)
          ..lineTo(at(-s * 0.5, 0).dx, at(-s * 0.5, 0).dy)
          ..lineTo(at(0, s * 0.5).dx, at(0, s * 0.5).dy)
          ..close();
        canvas.drawPath(path, fill);
      case PdfLineEnding.square:
        canvas.drawRect(
            Rect.fromCenter(center: tip, width: s, height: s), fill);
      case PdfLineEnding.circle:
        canvas.drawCircle(tip, s * 0.5, fill);
      case PdfLineEnding.butt:
        canvas.drawLine(at(0, -s * 0.5), at(0, s * 0.5), stroke);
      case PdfLineEnding.slash:
        canvas.drawLine(Offset(tip.dx - s * 0.3, cy + s * 0.5),
            Offset(tip.dx + s * 0.3, cy - s * 0.5), stroke);
    }
  }

  @override
  bool shouldRepaint(_LineEndingPainter old) =>
      old.ending != ending || old.atEnd != atEnd || old.color != color;
}

/// The "no color" swatch's red diagonal slash.
class _NoneSlashPainter extends CustomPainter {
  const _NoneSlashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
        Offset(3, size.height - 3),
        Offset(size.width - 3, 3),
        Paint()
          ..color = const Color(0xFFE53935)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_NoneSlashPainter oldDelegate) => false;
}
