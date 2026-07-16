import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:pdf_document/pdf_document.dart'
    show
        PdfAlignment,
        PdfFieldType,
        PdfFormField,
        PdfLineEnding,
        PdfStandardFont,
        PdfTextAlign,
        PdfTextFont;

import '../pdf_viewer.dart';
import '../toast.dart';
import 'editing_color_picker.dart';
import 'editing_color_processing.dart';
import 'editing_controller.dart';
import 'editing_font_controls.dart';
import 'editing_fonts.dart';
import 'editing_form_style.dart';
import 'editing_value_field.dart';
import 'editing_measure.dart';
import 'editing_takeoff.dart';
import 'line_style.dart';
import 'editing_signature.dart';
import 'editing_stamps.dart';
import 'text_prompt.dart';
import 'text_style_prompt.dart';
import 'tool_shortcuts.dart';

/// Builds a custom widget inside [PdfEditingToolbar].
typedef PdfEditingToolbarWidgetBuilder = Widget Function(
  BuildContext context,
  PdfEditingController controller,
  PdfViewerController viewerController,
);

/// A tool *type* - one dock group in [PdfEditingToolbar]. Pass a subset
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

  /// Freehand drawing, freehand highlight, and the ink eraser.
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
/// The bar is organised as a **dock** of tool *groups* - Select, Markup,
/// Draw, Shapes, Insert, Measure and Edit - flanked by the global
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
/// of a Column - it sizes to its content. Apps wanting different chrome
/// can skip this widget entirely and drive the controller from their own
/// UI, or add focused host actions with [leading] and [trailing].
class PdfEditingToolbar extends StatefulWidget {
  const PdfEditingToolbar({
    super.key,
    required this.controller,
    required this.viewerController,
    this.onSave,
    this.textPrompt = showPdfTextPrompt,
    this.styledTextPrompt = showPdfStyledTextPrompt,
    this.imagePicker,
    this.formImagePicker,
    this.onExportSelectedContentImage,
    this.fontPicker,
    this.onExportCustomStamps,
    this.onImportCustomStamps,
    this.palette = defaultPalette,
    this.tools,
    this.groups,
    this.toolShortcuts = pdfEditToolShortcuts,
    this.showMarkup = true,
    this.showUndoRedo = true,
    this.showColor = true,
    this.showStyle = true,
    this.showFlatten = true,
    this.showColorProcessing = true,
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

  /// How the "Edit text & style" button asks for replacement text plus
  /// rich-text overrides (colour, size, bold, italic).
  final PdfStyledTextPrompt styledTextPrompt;

  /// How selected page-content images are replaced from the element strip.
  final PdfImagePicker? imagePicker;

  /// How the selected push-button field's toolbar action obtains an image.
  /// PNG and JPEG bytes are accepted. When null, the action is disabled.
  final PdfFormImagePicker? formImagePicker;

  /// How selected page-content images are exported from the element strip.
  /// When null, the Save image button is hidden.
  final PdfSelectedContentImageHandler? onExportSelectedContentImage;

  /// How the font menu's "Load font…" entry obtains a custom `.ttf`/`.otf`
  /// file. When null, only the standard families and bundled fonts are
  /// offered (no custom loading).
  final PdfFontPicker? fontPicker;

  /// Host-provided export for the Manage Stamps dialog.
  final PdfStampExportCallback? onExportCustomStamps;

  /// Host-provided import for the Manage Stamps dialog.
  final PdfStampImportCallback? onImportCustomStamps;

  /// The colors offered for new annotations.
  final List<Color> palette;

  /// Shortcut labels to show in tooltips. Keep this in sync with
  /// [PdfViewer.toolShortcuts] when rebinding keys in the stock editor UI.
  /// Tools omitted from the map show no shortcut label.
  final Map<PdfEditTool, LogicalKeyboardKey> toolShortcuts;

  /// The tools to expose, null meaning all of them. A group disappears
  /// from the dock when none of its tools are in the set. Sub-controls
  /// tied to an armed tool (the form field-type menu, signature redraw)
  /// follow their tool. Hiding a tool doesn't disable it - it can still
  /// be armed through the controller.
  final Set<PdfEditTool>? tools;

  /// The tool *types* (dock groups) to expose, null meaning all of them.
  /// A group not in the set vanishes from the dock entirely - this is the
  /// way to disable a whole tool type (Measure, Markup, Draw…) without
  /// enumerating each of its tools in [tools].
  ///
  /// Combines with [tools] and [showMarkup]: a group shows only when it
  /// is in this set (when given), is not emptied by [tools], and - for
  /// Markup - [showMarkup] is true. Hiding a group only hides its UI; its
  /// tools can still be armed through the controller.
  final Set<PdfEditToolGroup>? groups;

  /// Whether text markup actions (highlight, underline, strike out,
  /// squiggly - they act on the viewer's text selection) are shown. A
  /// convenience for the common case; equivalent to dropping
  /// [PdfEditToolGroup.markup] from [groups]. The Draw group's freehand
  /// Highlight tool is controlled by [PdfEditTool.highlight].
  final bool showMarkup;

  /// Whether the undo/redo buttons are shown. The viewer's ⌘Z/⇧⌘Z
  /// shortcuts work either way.
  final bool showUndoRedo;

  /// Whether the colour controls - the palette swatches, the "More
  /// colours…" picker, the eyedropper, and the text-box fill/border colour
  /// rows in the style popup - are shown. Split from [showStyle] so a
  /// colour-locked session can hide the colour changer while leaving
  /// stroke/opacity/font editable.
  final bool showColor;

  /// Whether the style popup (the stroke/opacity/font controls) is
  /// shown. Independent of [showColor]: the popup can show its sliders
  /// and font controls with its colour rows hidden.
  final bool showStyle;

  /// Whether the flatten-annotations button is shown.
  final bool showFlatten;

  /// Whether the Edit group includes the colour-processing action.
  final bool showColorProcessing;

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

/// One entry in a tool group - either an armable [PdfEditTool] or a
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

enum _SelectedFormOverflowAction {
  edit,
  rename,
  style,
  typeText,
  typeCheckBox,
  typeButton,
  delete,
  flatten,
}

class _PdfEditingToolbarState extends State<PdfEditingToolbar> {
  PdfEditingController get controller => widget.controller;
  PdfViewerController get viewerController => widget.viewerController;

  /// Which group's strip is open when no group tool is armed (Select,
  /// Markup, Measure and Edit can be open with nothing armed). When a
  /// group tool *is* armed, that tool's group always wins.
  String? _openGroupId = 'select';

  /// In-flight opacity while dragging the strip's inline slider over a
  /// selected annotation - it only restyles on release (one revision per
  /// gesture), so the thumb needs its own state meanwhile.
  double? _dragOpacity;

  bool _replacingElementImage = false;
  bool _exportingElementImage = false;

  bool get _showColorProcessingAction =>
      widget.showColorProcessing &&
      (widget.tools == null ||
          widget.tools!.any((tool) => switch (tool) {
                PdfEditTool.content ||
                PdfEditTool.form ||
                PdfEditTool.redact ||
                PdfEditTool.snapshot =>
                  true,
                _ => false,
              }));

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
          _GroupTool.tool(PdfEditTool.highlight, Icons.border_color,
              'Highlight - draw freehand'),
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
          _GroupTool.tool(
              PdfEditTool.cloudPolygon, Icons.cloud_outlined, 'Cloud polygon'),
        ],
        defaultTool: PdfEditTool.rectangle),
    _ToolGroup(
        'insert',
        'Insert',
        Icons.text_fields,
        [
          _GroupTool.tool(PdfEditTool.freeText, Icons.text_fields, 'Text box'),
          _GroupTool.tool(PdfEditTool.callout, Icons.chat_bubble_outline,
              'Callout - drag from the point to where the box goes'),
          _GroupTool.tool(
              PdfEditTool.note, Icons.sticky_note_2_outlined, 'Note'),
          _GroupTool.tool(PdfEditTool.stamp, Icons.approval, 'Stamp'),
          _GroupTool.tool(PdfEditTool.count, Icons.task_alt,
              'Count - tap to drop check-marks and tally them'),
          _GroupTool.tool(PdfEditTool.image, Icons.image_outlined,
              'Image - tap to place, or drag out a box'),
          _GroupTool.tool(PdfEditTool.signature, Icons.history_edu,
              'Signature - tap a page to place it'),
        ],
        defaultTool: PdfEditTool.freeText),
    _ToolGroup('measure', 'Measure', Icons.straighten, [
      _GroupTool.tool(
          PdfEditTool.measureDistance, Icons.straighten, 'Measure distance'),
      _GroupTool.tool(
          PdfEditTool.measurePerimeter, Icons.timeline, 'Measure perimeter'),
      _GroupTool.tool(PdfEditTool.measureArea, Icons.crop_din, 'Measure area'),
      _GroupTool.tool(PdfEditTool.measureVolume, Icons.view_in_ar,
          'Measure volume (area × depth)'),
      _GroupTool.tool(PdfEditTool.measureSlope, Icons.trending_up,
          'Measure slope (rise/run)'),
      _GroupTool.tool(PdfEditTool.measureAngle, Icons.architecture,
          'Measure angle - click three points'),
      _GroupTool.tool(PdfEditTool.measureArc, Icons.gesture,
          'Measure arc length - click three points'),
    ]),
    _ToolGroup('edit', 'Edit', Icons.design_services, [
      _GroupTool.tool(
          PdfEditTool.content, Icons.format_shapes, 'Edit page content'),
      _GroupTool.tool(PdfEditTool.form, Icons.ballot_outlined,
          'Form fields - tap to select, double-tap to fill, drag to add'),
      _GroupTool.tool(PdfEditTool.redact, Icons.gradient,
          'Redact - drag a region, then apply'),
      _GroupTool.tool(PdfEditTool.snapshot, Icons.crop,
          'Snapshot - drag a region to capture it (paste back as vector)'),
    ]),
  ];

  bool _shows(PdfEditTool tool) => widget.tools?.contains(tool) ?? true;

  bool _entryVisible(_GroupTool entry) {
    final tool = entry.tool;
    if (tool != null) return _shows(tool);
    if (entry.markup != null) return widget.showMarkup;
    return true;
  }

  /// Whether [group] has any visible entry (the whole group gated by
  /// [PdfEditingToolbar.groups], markup also gated by showMarkup, tools
  /// gated by [PdfEditingToolbar.tools]).
  bool _groupVisible(_ToolGroup group) {
    final kind = PdfEditToolGroup.values.byName(group.id);
    if (widget.groups != null && !widget.groups!.contains(kind)) return false;
    if (group.id == 'markup') return widget.showMarkup;
    if (group.id == 'edit' && _showColorProcessingAction) return true;
    return group.tools.any(_entryVisible);
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

  void _applyMarkup(PdfMarkupKind kind, {bool restoreTool = false}) {
    final previousTool = controller.tool;
    if (restoreTool) controller.tool = null;
    controller.useMarkupStyleScope();
    _markup(kind);
    if (restoreTool && previousTool != null) controller.tool = previousTool;
  }

  /// Sets the creation colour - and recolours the selected annotations in
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
    // null/no-tool state - tapping the active tool off should leave you
    // able to select and move things, not in limbo
    controller.tool = controller.tool == value ? PdfEditTool.select : value;
    viewerController.clearSelection();
  }

  /// Opens [group]'s strip and, when arming is side-effect-free, arms its
  /// default tool - so its settings are live immediately. Re-tapping the
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
    if (controller.tool != null) {
      viewerController.clearSelection();
    }
    // markup arms no tool, so its style scope is set explicitly (after the
    // tool reset above, which would otherwise clear it) - this is what lets
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
      case PdfEditTool.measureVolume:
      case PdfEditTool.measureSlope:
      case PdfEditTool.measureAngle:
      case PdfEditTool.measureArc:
        await _armMeasureTool(context, tool);
      case PdfEditTool.signature:
        await _toggleSignatureTool(context);
      default:
        _toggleTool(tool);
    }
  }

  Future<void> _setScale(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final scale = await showPdfScaleDialog(
      context,
      initial: controller.measurementScale,
      onCalibrate: () {
        controller.tool = PdfEditTool.calibrate;
        messenger?.showSnackBar(const SnackBar(
          content: Text('Draw a line of known length to calibrate the scale.'),
        ));
      },
    );
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
    // the user just drew in - they can recolour it from the toolbar after
    controller.color = Color(0xFF000000 | signature.color);
    return true;
  }

  void _armStampToolForMenu() {
    if (controller.tool == PdfEditTool.stamp) return;
    controller.tool = PdfEditTool.stamp;
    viewerController.clearSelection();
  }

  Future<void> _manageStamps(BuildContext context) => showPdfStampPicker(
        context,
        controller: controller,
        imagePicker: widget.imagePicker,
        onExportStamps: widget.onExportCustomStamps,
        onImportStamps: widget.onImportCustomStamps,
      );

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
    // bundled fallbacks let composite (/Type0) edits draw characters the
    // document's own (possibly subsetted) font lacks
    final fallbacks = await loadFallbackFonts();
    controller.replaceSelectedElementText(text, fallbackFonts: fallbacks);
  }

  Future<void> _editElementTextStyle(BuildContext context) async {
    final element = controller.selectedElement;
    if (element == null) return;
    final result = await widget.styledTextPrompt(
      context,
      initial: element.text ?? '',
      palette: widget.palette,
      pickFont: _pickStyledFont,
    );
    if (result == null) return;
    if (result.text.isEmpty ||
        (result.text == element.text && result.style.isEmpty)) {
      return;
    }
    // bundled fallbacks let composite (/Type0) edits draw characters the
    // document's own (possibly subsetted) font lacks
    final fallbacks = await loadFallbackFonts();
    controller.replaceStyledSelectedElementText(result.text, result.style,
        fallbackFonts: fallbacks);
  }

  /// Opens the editor's normal font menu (the same one the tune popup and
  /// properties panel use) for the styled-text dialog, returning the chosen
  /// font without touching the controller's own default.
  Future<PdfTextFont?> _pickStyledFont(BuildContext context) async {
    PdfTextFont? chosen;
    await showPdfFontMenu(
      context: context,
      controller: controller,
      fontPicker: widget.fontPicker,
      onSelected: (font) => chosen = font,
    );
    return chosen;
  }

  Future<void> _reflowElementText(BuildContext context) async {
    final element = controller.selectedElement;
    if (element == null) return;
    final text = await widget.textPrompt(
      context,
      title: 'Reflow paragraph',
      initial: element.text ?? '',
      multiline: true,
    );
    if (text == null || text == element.text) return;
    final reflowed = controller.reflowSelectedElementText(text);
    if (!reflowed && context.mounted) {
      ScaffoldMessenger.maybeOf(context)
        ?..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: const Text(
              "Couldn't reflow - this isn't a single-column paragraph this "
              'tool can re-wrap. Try Replace text instead.'),
          behavior: SnackBarBehavior.floating,
          margin: pdfFloatingToastMargin(context),
        ));
    }
  }

  Future<void> _replaceElementImage(BuildContext context) async {
    final picker = widget.imagePicker;
    if (picker == null || _replacingElementImage) return;
    setState(() => _replacingElementImage = true);
    try {
      final bytes = await picker(context);
      if (bytes == null) return;
      final replaced = await controller.replaceSelectedElementImageAsync(bytes);
      if (!replaced && context.mounted) {
        ScaffoldMessenger.maybeOf(context)
          ?..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: const Text("Couldn't replace image"),
            behavior: SnackBarBehavior.floating,
            margin: pdfFloatingToastMargin(context),
          ));
      }
    } finally {
      if (mounted) setState(() => _replacingElementImage = false);
    }
  }

  Future<void> _exportElementImage(BuildContext context) async {
    final handler = widget.onExportSelectedContentImage;
    if (handler == null || _exportingElementImage) return;
    setState(() => _exportingElementImage = true);
    try {
      final image = await controller.exportSelectedElementImage();
      if (!context.mounted || image == null) return;
      await handler(context, image);
    } finally {
      if (mounted) setState(() => _exportingElementImage = false);
    }
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

  /// The selected radio widget's on-state. A field can have several widget
  /// dictionaries, so the field name alone is not enough to identify which
  /// option the toolbar should choose.
  String? _selectedRadioState(PdfFormField field) {
    final selected = controller.selectedAnnotation;
    if (selected == null) return null;
    for (var i = 0; i < field.widgets.length; i++) {
      if (identical(field.widgets[i], selected.dict)) {
        return field.widgetOnState(i);
      }
    }
    return null;
  }

  /// Runs the selected field's value action from the contextual toolbar.
  /// Selection is deliberately separate from activation: a right-click only
  /// selects, then this explicit control edits/toggles/chooses the value.
  Future<void> _editSelectedFormField(BuildContext context) async {
    final name = controller.selectedWidgetFieldName;
    if (name == null) return;
    final field = controller.acroForm?.fieldNamed(name);
    if (field == null || field.isReadOnly) return;
    switch (field.type) {
      case PdfFieldType.text:
        final value = await widget.textPrompt(
          context,
          title: 'Field value',
          initial: field.value ?? '',
          multiline: field.isMultiline,
        );
        if (value != null) controller.setFormFieldText(name, value);
      case PdfFieldType.checkBox:
        controller.toggleFormCheckBox(name);
      case PdfFieldType.radioGroup:
        final state = _selectedRadioState(field);
        if (state != null) controller.setFormRadioValue(name, state);
      case PdfFieldType.comboBox || PdfFieldType.listBox:
        if (field.options.isEmpty) return;
        final overlay =
            Overlay.of(context).context.findRenderObject()! as RenderBox;
        final toolbar = context.findRenderObject();
        final anchor = toolbar is RenderBox && toolbar.attached
            ? toolbar.localToGlobal(Offset(toolbar.size.width / 2, 0))
            : overlay.size.center(Offset.zero);
        final picked = await showMenu<String>(
          context: context,
          position: RelativeRect.fromRect(
            anchor & Size.zero,
            Offset.zero & overlay.size,
          ),
          items: [
            for (final (export, display) in field.options)
              PopupMenuItem(
                key: ValueKey('pdf-selected-form-option-$export'),
                value: export,
                child: Text(display),
              ),
          ],
        );
        if (picked != null) controller.setFormChoiceValue(name, picked);
      case PdfFieldType.pushButton:
        final picker = widget.formImagePicker;
        if (picker == null) return;
        final bytes = await picker(context, field);
        if (bytes != null) {
          await controller.setFormButtonImageAsync(name, bytes);
        }
      case PdfFieldType.signature || PdfFieldType.unknown:
        return;
    }
  }

  Future<void> _renameSelectedFormField(BuildContext context) async {
    final name = controller.selectedWidgetFieldName;
    if (name == null) return;
    final renamed = await widget.textPrompt(
      context,
      title: 'Field name',
      initial: name,
    );
    if (renamed == null || renamed.isEmpty || renamed == name) return;
    controller.renameFormField(name, renamed);
  }

  ({IconData icon, String tooltip, bool enabled}) _selectedFormEditAction(
      PdfFormField field) {
    final enabled = !field.isReadOnly;
    return switch (field.type) {
      PdfFieldType.text => (
          icon: Icons.edit_outlined,
          tooltip: 'Edit field value',
          enabled: enabled
        ),
      PdfFieldType.checkBox => (
          icon: field.isChecked
              ? Icons.check_box_outline_blank
              : Icons.check_box_outlined,
          tooltip: field.isChecked ? 'Clear check' : 'Check field',
          enabled: enabled,
        ),
      PdfFieldType.radioGroup => (
          icon: Icons.radio_button_checked,
          tooltip: 'Select this option',
          enabled: enabled && _selectedRadioState(field) != null,
        ),
      PdfFieldType.comboBox || PdfFieldType.listBox => (
          icon: Icons.list_alt_outlined,
          tooltip: 'Choose field value',
          enabled: enabled && field.options.isNotEmpty,
        ),
      PdfFieldType.pushButton => (
          icon: Icons.image_outlined,
          tooltip: 'Set field image',
          enabled: enabled && widget.formImagePicker != null,
        ),
      PdfFieldType.signature || PdfFieldType.unknown => (
          icon: Icons.edit_off_outlined,
          tooltip: 'This field has no editable value action',
          enabled: false,
        ),
    };
  }

  /// Direct controls for a selected field. These replace the old field
  /// context menu so right-click can remain a predictable selection gesture.
  List<Widget> _selectedFormFieldActions(BuildContext context) {
    final name = controller.selectedWidgetFieldName;
    final field = name == null ? null : controller.acroForm?.fieldNamed(name);
    if (field == null) return const [];
    final edit = _selectedFormEditAction(field);
    return [
      IconButton(
        key: const ValueKey('pdf-selected-form-edit'),
        icon: Icon(edit.icon),
        tooltip: edit.tooltip,
        onPressed: edit.enabled ? () => _editSelectedFormField(context) : null,
      ),
      IconButton(
        key: const ValueKey('pdf-selected-form-rename'),
        icon: const Icon(Icons.drive_file_rename_outline),
        tooltip: 'Rename field',
        onPressed: () => _renameSelectedFormField(context),
      ),
      PdfSelectedFormFieldTypeMenu(
        controller: controller,
        buttonKey: const ValueKey('pdf-selected-form-field-type'),
        itemKeyPrefix: 'pdf-selected-form-type',
      ),
      IconButton(
        key: const ValueKey('pdf-selected-form-delete'),
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete field',
        onPressed: controller.deleteSelected,
      ),
      if (widget.showFlatten)
        IconButton(
          key: const ValueKey('pdf-selected-form-flatten'),
          icon: const Icon(Icons.layers_clear_outlined),
          tooltip: 'Flatten form - bake values into the pages',
          onPressed: () => _flattenForm(context),
        ),
    ];
  }

  /// Compact counterpart to [_selectedFormFieldActions]. The selected field's
  /// controls live behind one toolbar button so they fit beside the fixed
  /// undo/redo and tools controls even on a 320pt-wide phone.
  List<Widget> _selectedFormFieldMobileActions(BuildContext context) {
    final name = controller.selectedWidgetFieldName;
    final field = name == null ? null : controller.acroForm?.fieldNamed(name);
    if (field == null) return const [];
    final edit = _selectedFormEditAction(field);
    return [
      PopupMenuButton<_SelectedFormOverflowAction>(
        key: const ValueKey('pdf-selected-form-more'),
        tooltip: 'Field actions',
        icon: const Icon(Icons.dynamic_form_outlined),
        onSelected: (action) async {
          switch (action) {
            case _SelectedFormOverflowAction.edit:
              await _editSelectedFormField(context);
            case _SelectedFormOverflowAction.rename:
              await _renameSelectedFormField(context);
            case _SelectedFormOverflowAction.style:
              final overlay =
                  Overlay.of(context).context.findRenderObject()! as RenderBox;
              final toolbar = context.findRenderObject();
              final anchor = toolbar is RenderBox && toolbar.attached
                  ? toolbar.localToGlobal(Offset(toolbar.size.width / 2, 0))
                  : overlay.size.center(Offset.zero);
              await showPdfFormTextStylePopup(
                context: context,
                position: anchor,
                controller: controller,
                fontPicker: widget.fontPicker,
              );
            case _SelectedFormOverflowAction.typeText:
              controller.changeSelectedFormFieldKind(PdfFormFieldKind.text);
            case _SelectedFormOverflowAction.typeCheckBox:
              controller.changeSelectedFormFieldKind(PdfFormFieldKind.checkBox);
            case _SelectedFormOverflowAction.typeButton:
              controller
                  .changeSelectedFormFieldKind(PdfFormFieldKind.pushButton);
            case _SelectedFormOverflowAction.delete:
              controller.deleteSelected();
            case _SelectedFormOverflowAction.flatten:
              _flattenForm(context);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            key: const ValueKey('pdf-selected-form-edit'),
            value: _SelectedFormOverflowAction.edit,
            enabled: edit.enabled,
            child: ListTile(
              dense: true,
              leading: Icon(edit.icon),
              title: Text(edit.tooltip),
            ),
          ),
          const PopupMenuItem(
            key: ValueKey('pdf-selected-form-rename'),
            value: _SelectedFormOverflowAction.rename,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.drive_file_rename_outline),
              title: Text('Rename field…'),
            ),
          ),
          if (controller.canStyleSelectedFormField)
            const PopupMenuItem(
              key: ValueKey('pdf-selected-form-style'),
              value: _SelectedFormOverflowAction.style,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.text_format),
                title: Text('Text style…'),
              ),
            ),
          PopupMenuItem(
            key: const ValueKey('pdf-selected-form-type-text'),
            value: _SelectedFormOverflowAction.typeText,
            enabled: field.type != PdfFieldType.text,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.text_fields),
              title: Text('Convert to text field'),
            ),
          ),
          PopupMenuItem(
            key: const ValueKey('pdf-selected-form-type-checkbox'),
            value: _SelectedFormOverflowAction.typeCheckBox,
            enabled: field.type != PdfFieldType.checkBox,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.check_box_outlined),
              title: Text('Convert to check box'),
            ),
          ),
          PopupMenuItem(
            key: const ValueKey('pdf-selected-form-type-button'),
            value: _SelectedFormOverflowAction.typeButton,
            enabled: field.type != PdfFieldType.pushButton,
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.smart_button),
              title: Text('Convert to image button'),
            ),
          ),
          const PopupMenuItem(
            key: ValueKey('pdf-selected-form-delete'),
            value: _SelectedFormOverflowAction.delete,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.delete_outline),
              title: Text('Delete field'),
            ),
          ),
          if (widget.showFlatten)
            const PopupMenuItem(
              key: ValueKey('pdf-selected-form-flatten'),
              value: _SelectedFormOverflowAction.flatten,
              child: ListTile(
                dense: true,
                leading: Icon(Icons.layers_clear_outlined),
                title: Text('Flatten form'),
              ),
            ),
        ],
      ),
    ];
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

  Future<void> _showColorProcessing(BuildContext context) async {
    final count = await showPdfColorProcessingDialog(
      context,
      controller: controller,
      preferences: controller.preferences,
    );
    if (count == null || !context.mounted) return;
    final message = switch (count) {
      0 => 'No matching colors found',
      1 => 'Replaced 1 color',
      _ => 'Replaced $count colors',
    };
    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: pdfFloatingToastMargin(context),
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
            // disabled while the document matches what was opened - there's
            // nothing to write until an edit bumps the revision cursor
            onPressed: controller.isModified
                ? () => widget.onSave!(controller.bytes)
                : null,
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
    // the Edit group's tools (content/form/redact) read as bare icons -
    // too cryptic for destructive document edits - so they get text labels
    final labelled = group.id == 'edit';
    final toolButtons = <Widget>[];
    for (final entry in group.tools) {
      if (!_entryVisible(entry)) continue;
      if (entry.markup != null) {
        toolButtons.add(IconButton(
          icon: Icon(entry.icon),
          tooltip: entry.tip,
          onPressed: hasTextSelection
              ? () =>
                  _applyMarkup(entry.markup!, restoreTool: group.id != 'markup')
              : null,
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
        if (tool == PdfEditTool.stamp) {
          toolButtons.add(_StampToolPopupButton(
            controller: controller,
            tooltip: _entryTip(entry),
            active: controller.tool == tool,
            onArm: _armStampToolForMenu,
            onManage: _manageStamps,
          ));
        } else {
          toolButtons.add(IconButton(
            icon: Icon(entry.icon),
            tooltip: _entryTip(entry),
            isSelected: controller.tool == tool,
            onPressed: () => _armGroupTool(context, tool),
          ));
        }
      }
    }
    if (group.id == 'edit' && _showColorProcessingAction) {
      toolButtons.add(_LabeledToolButton(
        key: const ValueKey('pdf-toolbar-color-processing'),
        icon: Icons.palette_outlined,
        label: 'Color',
        tooltip: 'Color processing - find and replace page-content colors',
        active: false,
        onTap: () => _showColorProcessing(context),
      ));
    }
    if (group.id == 'measure') {
      toolButtons.add(_takeoffButton(context));
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
        if (tool == null && viewerController.hasSelection) {
          return [
            ..._colorCluster(context),
            if (widget.showColor && widget.showStyle) const _MiniDivider(),
            _opacitySlider(context),
            ..._tuneTrailing(context, fields),
          ];
        }
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
      if ((tool == PdfEditTool.ink ||
              tool == PdfEditTool.highlight ||
              tool == PdfEditTool.eraser) &&
          controller.hasTouchInput)
        IconButton(
          icon: const Icon(Icons.touch_app),
          tooltip: controller.fingerDrawsInk
              ? 'Finger draws - tap so it scrolls instead'
              : 'Finger scrolls (pen draws) - tap so it draws',
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

  /// Insert-tool sub-controls: the redraw button for the signature tool.
  List<Widget> _insertToolExtras(BuildContext context) {
    return [
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
          tooltip: 'New field type - drag on a page to add one',
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
              height: 34,
              child: Text('Text field'),
            ),
            PopupMenuItem(
              key: ValueKey('pdf-form-type-checkbox'),
              value: PdfFormFieldKind.checkBox,
              height: 34,
              child: Text('Check box'),
            ),
            PopupMenuItem(
              key: ValueKey('pdf-form-type-button'),
              value: PdfFormFieldKind.pushButton,
              height: 34,
              child: Text('Image button'),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.layers_clear_outlined),
          tooltip: 'Flatten form - bake values into the pages',
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
    final selectedFieldName = controller.selectedWidgetFieldName;
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
              _StripLabel(selectedFieldName == null
                  ? switch (controller.selectedAnnotationSlots.length) {
                      1 => 'Selection',
                      final n => '$n selected',
                    }
                  : 'Field: $selectedFieldName'),
              if (selectedFieldName != null)
                ..._selectedFormFieldActions(context)
              else
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
          if (controller.canAlignSelected) ...[
            const _StripDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
              child: _alignmentCluster(context),
            ),
          ],
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

  /// The align/distribute buttons shown while two or more annotations are
  /// selected: edge + centre alignment, then even-spacing distribution
  /// (which needs three, so those disable below that). Each button defers
  /// to [PdfEditingController.alignSelected].
  Widget _alignmentCluster(BuildContext context) {
    final canDistribute = controller.canDistributeSelected;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _alignButton(
          PdfAlignment.left, Icons.align_horizontal_left, 'Align left'),
      _alignButton(PdfAlignment.horizontalCenter, Icons.align_horizontal_center,
          'Align horizontal centers'),
      _alignButton(
          PdfAlignment.right, Icons.align_horizontal_right, 'Align right'),
      const _MiniDivider(),
      _alignButton(PdfAlignment.top, Icons.align_vertical_top, 'Align top'),
      _alignButton(PdfAlignment.verticalCenter, Icons.align_vertical_center,
          'Align vertical centers'),
      _alignButton(
          PdfAlignment.bottom, Icons.align_vertical_bottom, 'Align bottom'),
      const _MiniDivider(),
      _alignButton(PdfAlignment.distributeHorizontal,
          Icons.horizontal_distribute, 'Distribute horizontally',
          enabled: canDistribute),
      _alignButton(PdfAlignment.distributeVertical, Icons.vertical_distribute,
          'Distribute vertically',
          enabled: canDistribute),
    ]);
  }

  /// One alignment button. Disabled buttons (distribution with too few
  /// annotations) still render so the cluster's layout stays stable.
  Widget _alignButton(PdfAlignment alignment, IconData icon, String tooltip,
      {bool enabled = true}) {
    return IconButton(
      key: ValueKey('pdf-align-${alignment.name}'),
      icon: Icon(icon),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? () => controller.alignSelected(alignment) : null,
    );
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
      if (controller.canEditSelectedElementText) ...[
        IconButton(
          key: const ValueKey('pdf-replace-element-text'),
          icon: const Icon(Icons.edit),
          tooltip: 'Replace text',
          onPressed: () => _editElementText(context),
        ),
        IconButton(
          key: const ValueKey('pdf-style-element-text'),
          icon: const Icon(Icons.format_color_text),
          tooltip: 'Edit text & style',
          onPressed: () => _editElementTextStyle(context),
        ),
        IconButton(
          key: const ValueKey('pdf-reflow-element-text'),
          icon: const Icon(Icons.wrap_text),
          tooltip: 'Reflow paragraph',
          onPressed: () => _reflowElementText(context),
        ),
      ],
      if (controller.canReplaceSelectedElementImage &&
          widget.onExportSelectedContentImage != null)
        IconButton(
          key: const ValueKey('pdf-save-element-image'),
          icon: _exportingElementImage
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
          tooltip: 'Save image',
          onPressed: _exportingElementImage
              ? null
              : () => _exportElementImage(context),
        ),
      if (controller.canReplaceSelectedElementImage &&
          widget.imagePicker != null)
        IconButton(
          key: const ValueKey('pdf-replace-element-image'),
          icon: _replacingElementImage
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_outlined),
          tooltip: 'Replace image',
          onPressed: _replacingElementImage
              ? null
              : () => _replaceElementImage(context),
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
      PdfSliderValueField(
        value: value,
        min: 0.1,
        max: 1,
        width: 40,
        display: (v) => '${(v * 100).round()}%',
        parse: _parsePercent,
        onSubmit: (v) {
          controller.opacity = v;
          if (restyling) controller.restyleSelected(opacity: v);
          setState(() => _dragOpacity = null);
        },
      ),
    ]);
  }

  /// The measure scale chip - its ratio label, opening the calibration
  /// dialog on tap.
  Widget _scaleChip(BuildContext context) {
    return _SettingChip(
      key: const ValueKey('pdf-measure-scale'),
      leading: 'Scale',
      value: controller.measurementScale?.ratioLabel ?? 'Set…',
      onTap: () => _setScale(context),
    );
  }

  Widget _takeoffButton(BuildContext context) {
    return _LabeledToolButton(
      key: const ValueKey('pdf-takeoff-totals'),
      icon: Icons.functions,
      label: 'Totals',
      tooltip: 'Takeoff totals',
      active: false,
      onTap: () => _showTakeoffPanel(context),
    );
  }

  void _showTakeoffPanel(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: PdfTakeoffPanel(controller: controller),
        ),
      ),
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

  /// The style controls relevant to [group]'s active tool - see
  /// [_StyleFields]. Drives the tune popup so a rectangle never offers a
  /// font picker, ink never offers line endings, and so on.
  _StyleFields _groupStyleFields(_ToolGroup group) {
    final tool = controller.tool;
    switch (group.id) {
      case 'draw':
        if (tool == null && viewerController.hasSelection) {
          return const _StyleFields(opacity: true);
        }
        if (tool == PdfEditTool.eraser) return const _StyleFields(eraser: true);
        return const _StyleFields(stroke: true, opacity: true);
      case 'shapes':
        return _StyleFields(
          stroke: true,
          strokeColor: true,
          opacity: true,
          lineType: true,
          lineEndings: tool == PdfEditTool.line || tool == PdfEditTool.polyline,
          shapeFill: tool == PdfEditTool.rectangle ||
              tool == PdfEditTool.ellipse ||
              tool == PdfEditTool.polygon ||
              tool == PdfEditTool.cloudPolygon,
        );
      case 'insert':
        return const _StyleFields(opacity: true, font: true, boxColors: true);
      case 'measure':
        return _StyleFields(
          stroke: true,
          opacity: true,
          font: true,
          // open measurements (distance/slope lines, perimeter/angle/arc
          // polylines) carry endings; closed area/volume polygons don't
          lineEndings: tool == PdfEditTool.measureDistance ||
              tool == PdfEditTool.measureSlope ||
              tool == PdfEditTool.measurePerimeter ||
              tool == PdfEditTool.measureAngle ||
              tool == PdfEditTool.measureArc,
        );
      case 'markup':
        return const _StyleFields(opacity: true);
      default:
        return const _StyleFields();
    }
  }

  /// The style controls relevant to the current annotation selection - by
  /// the primary selection's subtype, gated by what can actually restyle.
  _StyleFields _selectionStyleFields() {
    final annotation = controller.selectedAnnotation;
    if (annotation == null) return const _StyleFields();
    final behavior = annotation.behavior;
    final canStroke = controller.canRestyleSelected;
    switch (annotation.subtype) {
      case 'Widget':
        // a form text field: its own style block, nothing else
        return _StyleFields(formField: controller.canStyleSelectedFormField);
      case 'FreeText':
        final text = controller.canRestyleSelectedText;
        return _StyleFields(
            opacity: behavior.supportsOpacity, font: text, boxColors: text);
      case 'Square':
      case 'Circle':
      case 'Polygon':
        return _StyleFields(
            stroke: canStroke && behavior.supportsStrokeWidth,
            // the outline colour of shapes and revision clouds
            strokeColor: canStroke && behavior.supportsStrokeWidth,
            opacity: behavior.supportsOpacity,
            // a /Polygon area measurement carries a caption font
            font: controller.canRestyleMeasurementCaption,
            lineType: controller.canSetLineStyleSelected,
            shapeFill: controller.canFillSelected);
      case 'Line':
      case 'PolyLine':
        return _StyleFields(
            stroke: canStroke && behavior.supportsStrokeWidth,
            strokeColor: canStroke && behavior.supportsStrokeWidth,
            opacity: behavior.supportsOpacity,
            // a measurement (/Line distance, /PolyLine perimeter) carries one
            font: controller.canRestyleMeasurementCaption,
            lineType: controller.canSetLineStyleSelected,
            lineEndings: controller.canSetLineEndings);
      case 'Ink':
        return _StyleFields(
            stroke: canStroke && behavior.supportsStrokeWidth,
            strokeColor: canStroke && behavior.supportsStrokeWidth,
            opacity: behavior.supportsOpacity);
      default:
        // Markup and stamps expose opacity; notes and foreign subtypes do not.
        return _StyleFields(opacity: behavior.supportsOpacity);
    }
  }

  // ---- mobile: collapsed dock + bottom sheet ------------------------------

  Widget _buildMobile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tool = controller.tool;
    final compactToolLabel = controller.selectedElement != null;
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
              if (!compactToolLabel) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _activeToolLabel(tool),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
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
  /// A selected annotation gets its own quick actions (delete, edit text) -
  /// the better use of the space the request asks for, since those were
  /// otherwise unreachable from the dock; an armed colour-using tool gets
  /// the swatches; anything else leaves the space to the tool label.
  List<Widget> _mobileTrailing(BuildContext context) {
    if (controller.hasAnnotationSelection) {
      if (controller.selectedWidgetFieldName != null) {
        return _selectedFormFieldMobileActions(context);
      }
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
    if (controller.selectedElement != null) {
      return [
        IconButton(
          key: const ValueKey('pdf-mobile-delete-element'),
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete element',
          visualDensity: VisualDensity.compact,
          onPressed: controller.deleteSelectedElement,
        ),
        if (controller.canEditSelectedElementText) ...[
          // the mobile dock is width-constrained, so its single edit button
          // opens the styled editor (a superset of plain replace - it edits
          // the text and, optionally, its colour/size/weight).
          IconButton(
            key: const ValueKey('pdf-replace-element-text'),
            icon: const Icon(Icons.format_color_text),
            tooltip: 'Edit text & style',
            visualDensity: VisualDensity.compact,
            onPressed: () => _editElementTextStyle(context),
          ),
          IconButton(
            key: const ValueKey('pdf-reflow-element-text'),
            icon: const Icon(Icons.wrap_text),
            tooltip: 'Reflow paragraph',
            visualDensity: VisualDensity.compact,
            onPressed: () => _reflowElementText(context),
          ),
        ],
        if (controller.canReplaceSelectedElementImage &&
            widget.onExportSelectedContentImage != null)
          IconButton(
            key: const ValueKey('pdf-save-element-image'),
            icon: _exportingElementImage
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
            tooltip: 'Save image',
            visualDensity: VisualDensity.compact,
            onPressed: _exportingElementImage
                ? null
                : () => _exportElementImage(context),
          ),
        if (controller.canReplaceSelectedElementImage &&
            widget.imagePicker != null)
          IconButton(
            key: const ValueKey('pdf-replace-element-image'),
            icon: _replacingElementImage
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.image_outlined),
            tooltip: 'Replace image',
            visualDensity: VisualDensity.compact,
            onPressed: _replacingElementImage
                ? null
                : () => _replaceElementImage(context),
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
    switch (tool) {
      case PdfEditTool.content:
        return 'Content';
      case PdfEditTool.form:
        return 'Form';
      case PdfEditTool.redact:
        return 'Redact';
      case PdfEditTool.snapshot:
        return 'Snapshot';
      default:
        break;
    }
    for (final group in _groups) {
      for (final entry in group.tools) {
        if (entry.tool == tool) {
          // the tip's leading clause is the tool's name
          final tip = entry.tip;
          final dash = tip.indexOf(' -');
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
                                // markup arms no tool - scope it so its
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
    final entries = group.tools.where(_entryVisible).toList();
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.15,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (final entry in entries)
          if (entry.tool == PdfEditTool.stamp)
            _StampSheetToolTile(
              controller: controller,
              active: controller.tool == PdfEditTool.stamp,
              onArm: _armStampToolForMenu,
              onManage: _manageStamps,
            )
          else
            _SheetToolTile(
              icon: entry.icon,
              label: entry.markup != null
                  ? entry.tip.replaceAll(' selection', '')
                  : _entryLabel(entry),
              active: entry.tool != null && controller.tool == entry.tool,
              enabled: entry.markup == null || hasTextSelection,
              onTap: () async {
                if (entry.markup != null) {
                  _applyMarkup(entry.markup!,
                      restoreTool: group.id != 'markup');
                  if (context.mounted) Navigator.of(context).pop();
                } else {
                  await _armGroupTool(context, entry.tool!);
                }
              },
            ),
        if (group.id == 'measure')
          _SheetToolTile(
            key: const ValueKey('pdf-takeoff-totals'),
            icon: Icons.functions,
            label: 'Totals',
            active: false,
            enabled: true,
            onTap: () {
              Navigator.of(context).pop();
              if (mounted) _showTakeoffPanel(this.context);
            },
          ),
        if (group.id == 'edit' && _showColorProcessingAction)
          _SheetToolTile(
            key: const ValueKey('pdf-toolbar-color-processing'),
            icon: Icons.palette_outlined,
            label: 'Color',
            active: false,
            enabled: true,
            onTap: () {
              Navigator.of(context).pop();
              _showColorProcessing(this.context);
            },
          ),
      ],
    );
  }

  static String _entryLabel(_GroupTool entry) {
    final dash = entry.tip.indexOf(' -');
    return dash == -1 ? entry.tip : entry.tip.substring(0, dash);
  }

  /// A tool's tooltip with its keyboard shortcut appended (e.g.
  /// "Rectangle (R)"), so the bindings in [pdfEditToolShortcuts] are
  /// discoverable on hover. Markups and unbound tools keep the plain tip.
  String _entryTip(_GroupTool entry) {
    final tool = entry.tool;
    final key = tool == null
        ? null
        : pdfEditToolShortcutLabel(tool, shortcuts: widget.toolShortcuts);
    return key == null ? entry.tip : '${entry.tip} ($key)';
  }

  /// The settings block under the sheet's tool grid - reuses the same
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
    super.key,
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

class _StampToolPopupButton extends StatelessWidget {
  const _StampToolPopupButton({
    required this.controller,
    required this.tooltip,
    required this.active,
    required this.onArm,
    required this.onManage,
  });

  final PdfEditingController controller;
  final String tooltip;
  final bool active;
  final VoidCallback onArm;
  final Future<void> Function(BuildContext context) onManage;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        _StampMenuPanel(
          controller: controller,
          dialogContext: context,
          onArm: onArm,
          onManage: onManage,
        ),
      ],
      builder: (context, menuController, child) => IconButton(
        key: const ValueKey('pdf-stamp-tool-popup'),
        icon: const Icon(Icons.approval),
        tooltip: tooltip,
        isSelected: active,
        onPressed: () {
          onArm();
          menuController.isOpen
              ? menuController.close()
              : menuController.open();
        },
      ),
    );
  }
}

class _StampSheetToolTile extends StatelessWidget {
  const _StampSheetToolTile({
    required this.controller,
    required this.active,
    required this.onArm,
    required this.onManage,
  });

  final PdfEditingController controller;
  final bool active;
  final VoidCallback onArm;
  final Future<void> Function(BuildContext context) onManage;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        _StampMenuPanel(
          controller: controller,
          dialogContext: context,
          onArm: onArm,
          onManage: onManage,
        ),
      ],
      builder: (context, menuController, child) => _SheetToolTile(
        key: const ValueKey('pdf-stamp-sheet-tool-popup'),
        icon: Icons.approval,
        label: 'Stamp',
        active: active,
        enabled: true,
        onTap: () {
          onArm();
          menuController.isOpen
              ? menuController.close()
              : menuController.open();
        },
      ),
    );
  }
}

class _StampMenuPanel extends StatelessWidget {
  const _StampMenuPanel({
    required this.controller,
    required this.dialogContext,
    required this.onArm,
    required this.onManage,
  });

  final PdfEditingController controller;
  final BuildContext dialogContext;
  final VoidCallback onArm;
  final Future<void> Function(BuildContext context) onManage;

  int get _currentColor => controller.color.toARGB32() & 0xFFFFFF;

  void _select(MenuController menuController, PdfCustomStamp? stamp) {
    onArm();
    controller.activeStamp = stamp;
    menuController.close();
  }

  String? _detail(PdfCustomStamp stamp) {
    final parts = [
      if (stamp.type != null && stamp.type!.trim().isNotEmpty)
        stamp.type!.trim(),
      if (stamp.tags.isNotEmpty) stamp.tags.join(', '),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final menuController = MenuController.maybeOf(context)!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final active = controller.activeStamp;
        final preview =
            active ?? PdfCustomStamp(text: 'TEXT', color: _currentColor);
        final stamps = controller.customStamps;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320, maxHeight: 440),
          child: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Stamp',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        key: const ValueKey('pdf-stamp-menu-preview'),
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: PdfStampPreview(
                            stamp: preview,
                            templateValues:
                                controller.resolvedStampTemplateValues,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    primary: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MenuItemButton(
                          key: const ValueKey('pdf-stamp-menu-classic'),
                          leadingIcon: active == null
                              ? const Icon(Icons.check)
                              : const SizedBox(width: 24),
                          onPressed: () => _select(menuController, null),
                          child: const Text('Type text each time'),
                        ),
                        for (var i = 0; i < stamps.length; i++)
                          _StampMenuItem(
                            key: ValueKey('pdf-stamp-menu-custom-$i'),
                            stamp: stamps[i],
                            detail: _detail(stamps[i]),
                            selected: stamps[i] == active,
                            templateValues:
                                controller.resolvedStampTemplateValues,
                            onPressed: () => _select(menuController, stamps[i]),
                          ),
                        if (stamps.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'No custom stamps',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                MenuItemButton(
                  key: const ValueKey('pdf-stamp-menu-manage'),
                  leadingIcon: const Icon(Icons.tune),
                  onPressed: () {
                    onArm();
                    menuController.close();
                    if (dialogContext.mounted) onManage(dialogContext);
                  },
                  child: const Text('Manage stamps…'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StampMenuItem extends StatelessWidget {
  const _StampMenuItem({
    super.key,
    required this.stamp,
    required this.detail,
    required this.selected,
    required this.templateValues,
    required this.onPressed,
  });

  final PdfCustomStamp stamp;
  final String? detail;
  final bool selected;
  final Map<String, String> templateValues;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon:
          selected ? const Icon(Icons.check) : const SizedBox(width: 24),
      child: SizedBox(
        width: 230,
        child: Row(children: [
          SizedBox(
            width: 112,
            height: 38,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: PdfStampPreview(
                stamp: stamp,
                templateValues: templateValues,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stamp.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (detail != null)
                  Text(
                    detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// A tile in the mobile sheet's tool grid: icon above a label.
class _SheetToolTile extends StatelessWidget {
  const _SheetToolTile({
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
/// - the faint hint colour used for strip labels and disabled tiles.
extension _FaintColor on ColorScheme {
  Color get onSurfaceFaintOr => onSurfaceVariant.withValues(alpha: 0.75);
}

/// Which controls the style popup should show for the active context -
/// each tool/selection only carries the settings it can actually use, so
/// the popup never shows (say) a font picker while a rectangle is armed.
/// Parses a points readout ("12.0 pt") back to its number.
double? _parsePoints(String s) =>
    double.tryParse(s.replaceAll(RegExp('[^0-9.]'), ''));

/// Parses a percent readout ("40%") back to the 0..1 underlying value.
double? _parsePercent(String s) {
  final n = double.tryParse(s.replaceAll(RegExp('[^0-9.]'), ''));
  return n == null ? null : n / 100;
}

class _StyleFields {
  const _StyleFields({
    this.stroke = false,
    this.strokeColor = false,
    this.opacity = false,
    this.lineType = false,
    this.lineEndings = false,
    this.font = false,
    this.boxColors = false,
    this.shapeFill = false,
    this.eraser = false,
    this.formField = false,
  });

  final bool stroke;

  /// The stroke/outline colour row - shapes (including revision clouds) and
  /// the line family. Distinct from [shapeFill], the interior fill.
  final bool strokeColor;

  final bool opacity;

  /// The line-type dropdown (solid / dashed / dotted / dash-dot) - shapes
  /// and the line family.
  final bool lineType;
  final bool lineEndings;

  /// Font size + family (free text).
  final bool font;

  /// The text-box fill + border colour rows (free text).
  final bool boxColors;

  /// The shape interior-fill colour row (rectangle / ellipse).
  final bool shapeFill;

  /// Eraser radius - replaces every other control while the eraser is armed.
  final bool eraser;

  /// The form text field style block (font, alignment, auto-size, size,
  /// multiline, colour) - a single text-field widget is selected.
  final bool formField;

  bool get isEmpty =>
      !stroke &&
      !strokeColor &&
      !opacity &&
      !lineType &&
      !lineEndings &&
      !font &&
      !boxColors &&
      !shapeFill &&
      !eraser &&
      !formField;
}

/// The style popup: sliders for stroke width, opacity, and font size,
/// the font family for free text, and the text box's fill and border
/// colors. With a free-text annotation selected, the text controls show
/// - and change - that annotation's style; otherwise they set the style
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

  /// Which controls to show - see [_StyleFields].
  final _StyleFields fields;

  /// How the font menu's "Load font…" entry loads a custom font.
  final PdfFontPicker? fontPicker;

  final PdfEditingController controller;

  /// The colors offered as text/fill/border swatches (the toolbar's palette).
  final List<Color> palette;

  /// Whether the text, text-box fill, and border color rows are shown. The
  /// stroke/opacity/font controls show regardless - this only hides the
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
  /// selected annotation - the annotation only restyles on release (one
  /// revision per gesture), so the thumb needs its own state meanwhile.
  double? _draggingFontSize;

  /// Same, for the stroke-width and opacity sliders restyling a
  /// selected annotation.
  double? _draggingStroke;
  double? _draggingOpacity;
  double? _draggingLineSpacing;
  double? _draggingCharSpacing;
  double? _draggingFontWidth;
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
    } else if (controller.canRestyleMeasurementCaption) {
      controller.setSelectedMeasurementCaption(font: font);
    }
  }

  void _setTextAlign(PdfTextAlign align) =>
      controller.setSelectedTextAlign(align);

  static int? _rgb(Color? color) =>
      color == null ? null : color.toARGB32() & 0xFFFFFF;

  void _setTextFill(Color? color) {
    controller.textFillColor = color; // the new default either way
    if (controller.canRestyleSelectedText) {
      controller.restyleSelectedText(fill: (_rgb(color),));
    }
  }

  void _setTextColor(Color? color) {
    if (color == null) return;
    controller.color = color; // the new default either way
    if (controller.restyleEditingTextSelection(color: _rgb(color))) return;
    if (controller.canRestyleSelected) {
      controller.restyleSelected(color: color);
    }
  }

  void _setShapeFill(Color? color) {
    controller.shapeFillColor = color; // the new default either way
    if (controller.canFillSelected) {
      controller.restyleSelected(fill: (color,));
    }
  }

  /// The shape/cloud/line outline colour. Sets the creation default and
  /// restyles the selected shapes in place, mirroring the toolbar swatches.
  void _setStrokeColor(Color? color) {
    if (color == null) return;
    controller.color = color; // the new default either way
    if (controller.canRestyleSelected) {
      controller.restyleSelected(color: color);
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
  /// Shares [PdfColorSwatchRow] with the content text-style dialog.
  Widget _boxColorRow({
    required BuildContext context,
    required String label,
    required String keyPrefix,
    required Color? value,
    required ValueChanged<Color?> onChanged,
    bool allowNone = true,
  }) =>
      PdfColorSwatchRow(
        label: label,
        keyPrefix: keyPrefix,
        value: value,
        palette: widget.palette,
        onChanged: onChanged,
        allowNone: allowNone,
      );

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
        // ListenableBuilder - it needs its own listener to track sliders
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final fields = widget.fields;
            final selectedStyle = controller.selectedTextStyle;
            // a selected measurement exposes its caption font/size the same
            // way a free text exposes its own; the font rows drive whichever
            // is non-null
            final captionStyle = controller.selectedMeasurementCaptionStyle;
            // with a restylable selection the stroke/opacity sliders
            // show - and change - its style; otherwise the defaults
            final restylingAnnotation = controller.canRestyleSelected;
            // the eraser doesn't paint, so none of the stroke/opacity/
            // font/line controls apply to it - while it's armed the menu
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
            final textValue = restyling
                ? Color(0xFF000000 |
                    (boxStyle?.color ??
                        controller.selectedAnnotation?.color ??
                        (controller.color.toARGB32() & 0xFFFFFF)))
                : controller.color;
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
            // shape/cloud/line outline: a selected shape shows its own /C,
            // else the creation default
            final strokeColorValue = restylingAnnotation
                ? (annotationStyle?.color ?? controller.color)
                : controller.color;
            return Container(
              width: 300,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (fields.formField)
                    PdfFormFieldStyleControls(
                      controller: controller,
                      fontPicker: widget.fontPicker,
                    ),
                  if (isEraser)
                    _slider(
                      key: const ValueKey('pdf-eraser-size'),
                      label: 'Eraser size',
                      value: controller.eraserRadius,
                      min: 2,
                      max: 40,
                      display: (v) => '${v.round()} pt',
                      parse: _parsePoints,
                      onChanged: (v) =>
                          controller.eraserRadius = v.roundToDouble(),
                    ),
                  if (fields.stroke)
                    _slider(
                      label: 'Stroke width',
                      value: strokeValue,
                      min: 0.5,
                      max: 12,
                      display: (v) => '${v.toStringAsFixed(1)} pt',
                      parse: _parsePoints,
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
                      display: (v) => '${(v * 100).round()}%',
                      parse: _parsePercent,
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
                  if (fields.strokeColor && widget.showColor)
                    _boxColorRow(
                      context: context,
                      label: 'Outline',
                      keyPrefix: 'pdf-shape-outline',
                      value: strokeColorValue,
                      onChanged: _setStrokeColor,
                      allowNone: false,
                    ),
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
                          captionStyle?.size ??
                          controller.fontSize,
                      min: 8,
                      max: 48,
                      display: (v) => '${v.round()} pt',
                      parse: _parsePoints,
                      onChanged: (v) {
                        setState(() => _draggingFontSize = v.roundToDouble());
                        if (selectedStyle == null && captionStyle == null) {
                          controller.fontSize = v.roundToDouble();
                        }
                      },
                      onChangeEnd: (v) {
                        final size = v.roundToDouble();
                        if (controller.restyleEditingTextSelection(
                            size: size)) {
                          controller.fontSize = size;
                          setState(() => _draggingFontSize = null);
                          return;
                        }
                        if (controller.canRestyleSelectedText) {
                          controller.fontSize = size;
                          controller.restyleSelectedText(size: size);
                        } else if (controller.canRestyleMeasurementCaption) {
                          // a selected measurement keeps its own caption size;
                          // don't disturb the creation default
                          controller.setSelectedMeasurementCaption(size: size);
                        } else {
                          controller.fontSize = size;
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
                              // the box's real face (embedded/bundled shows its
                              // own name, not "Sans")
                              currentFont: controller.selectedTextFont ??
                                  captionStyle?.font ??
                                  controller.activeFont ??
                                  controller.fontFamily,
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
                          font: selectedStyle?.font ??
                              captionStyle?.font ??
                              controller.fontFamily,
                          onChanged: _setFont,
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(children: [
                        const SizedBox(width: 86, child: Text('Align')),
                        TextAlignToggles(
                          align: controller.selectedTextAlign ??
                              controller.textAlign ??
                              PdfTextAlign.left,
                          onChanged: _setTextAlign,
                        ),
                        const Spacer(),
                        // whole-box underline (a per-run underline is set from
                        // the inline editor's style chip)
                        IconButton(
                          key: const ValueKey('pdf-text-underline'),
                          icon: const Icon(Icons.format_underlined, size: 18),
                          tooltip: 'Underline',
                          isSelected: controller.selectedFreeTextStyle
                                  ?.underline ??
                              controller.textUnderline,
                          onPressed: () => controller.setSelectedTextBoxStyle(
                              underline: !(controller.selectedFreeTextStyle
                                      ?.underline ??
                                  controller.textUnderline)),
                        ),
                      ]),
                    ),
                    if (captionStyle == null) ...[
                      _slider(
                        key: const ValueKey('pdf-text-line-spacing'),
                        label: 'Line spacing',
                        value: _draggingLineSpacing ??
                            controller.selectedFreeTextStyle?.lineSpacing ??
                            controller.lineSpacing,
                        min: 0.8,
                        max: 3,
                        display: (v) => '${v.toStringAsFixed(1)}×',
                        onChanged: (v) =>
                            setState(() => _draggingLineSpacing = v),
                        onChangeEnd: (v) {
                          controller.setSelectedTextBoxStyle(lineSpacing: v);
                          setState(() => _draggingLineSpacing = null);
                        },
                      ),
                      _slider(
                        key: const ValueKey('pdf-text-char-spacing'),
                        label: 'Char spacing',
                        value: _draggingCharSpacing ??
                            controller.selectedFreeTextStyle?.charSpacing ??
                            controller.charSpacing,
                        min: -2,
                        max: 10,
                        display: (v) => '${v.toStringAsFixed(1)} pt',
                        parse: _parsePoints,
                        onChanged: (v) =>
                            setState(() => _draggingCharSpacing = v),
                        onChangeEnd: (v) {
                          controller.setSelectedTextBoxStyle(charSpacing: v);
                          setState(() => _draggingCharSpacing = null);
                        },
                      ),
                      _slider(
                        key: const ValueKey('pdf-text-font-width'),
                        label: 'Font width',
                        value: _draggingFontWidth ??
                            controller
                                .selectedFreeTextStyle?.horizontalScale ??
                            controller.fontWidth,
                        min: 50,
                        max: 200,
                        display: (v) => '${v.round()}%',
                        parse: _parsePoints,
                        onChanged: (v) =>
                            setState(() => _draggingFontWidth = v),
                        onChangeEnd: (v) {
                          controller.setSelectedTextBoxStyle(fontWidth: v);
                          setState(() => _draggingFontWidth = null);
                        },
                      ),
                    ],
                  ],
                  if (fields.boxColors && widget.showColor) ...[
                    _boxColorRow(
                      context: context,
                      label: 'Text colour',
                      keyPrefix: 'pdf-text-color',
                      value: textValue,
                      onChanged: _setTextColor,
                      allowNone: false,
                    ),
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
    required String Function(double) display,
    double? Function(String)? parse,
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
      // the readout is editable: type an exact value (general rule across
      // the editing UI) - committing routes through the change-end callback,
      // or onChanged for sliders that have none (live-only)
      PdfSliderValueField(
        key: key is ValueKey ? ValueKey('${key.value}-input') : null,
        value: value,
        min: min,
        max: max,
        width: 56,
        display: display,
        parse: parse,
        onSubmit: onChangeEnd ?? onChanged,
      ),
    ]);
  }
}

/// The Insert / free-text font chip - "Aa  Sans  14" - that opens the
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

/// Draws a short segment with [ending] rendered at one end - the preview
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
