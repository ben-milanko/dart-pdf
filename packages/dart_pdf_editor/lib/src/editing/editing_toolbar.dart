import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart'
    show
        PdfAlignment,
        PdfEmbeddedFont,
        PdfFieldType,
        PdfFormField,
        PdfLineEnding,
        PdfStandardFont,
        PdfTextAlign,
        PdfTextFont;

import '../dialog.dart';
import '../l10n/pdf_l10n.dart';
import '../pdf_viewer.dart';
import '../toast.dart';
import 'annotation_presentation.dart';
import 'editing_color_pick.dart';
import 'editing_color_processing.dart';
import 'editing_controller.dart';
import 'editing_font_controls.dart';
import 'editing_fonts.dart';
import 'editing_form_style.dart';
import 'editing_value_field.dart';
import 'editing_measure.dart';
import 'editing_panel.dart';
import 'editing_takeoff.dart';
import 'line_style.dart';
import 'editing_signature.dart';
import 'editing_stamps.dart';
import 'editing_tool_behavior.dart';
import 'text_prompt.dart';
import 'text_style_prompt.dart';
import 'tool_shortcuts.dart';

/// Builds a custom widget inside [PdfEditingToolbar].
typedef PdfEditingToolbarWidgetBuilder = Widget Function(
  BuildContext context,
  PdfEditingController controller,
  PdfViewerController viewerController,
);

/// A ready-made toolbar for [PdfEditingController].
///
/// The bar is organised as a **dock** with a compact Hand / Select navigation
/// cluster followed by the editing tool *groups* - Markup, Draw, Shapes,
/// Insert, Measure and Edit - and the global undo/redo, flatten and save
/// actions. Tapping an editing group raises a **contextual strip** above the
/// dock: the group's tools on the left and the active tool's live settings
/// (colour, stroke, opacity, font, scale…) on the right, so each tool shows
/// only the settings it supports. Selecting an annotation or a page element
/// raises its own strip with the actions and restyle controls that apply to
/// it.
///
/// On narrow (phone) widths the dock collapses to an active-tool switcher, a
/// quick-colour row and a *Tools* handle. The switcher recalls recently used
/// tools and clears back to Hand mode; the handle opens a bottom sheet with
/// group tabs, a tool grid and the active tool's settings.
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
    this.dock = PdfPanelDock.bottom,
    this.compact,
    this.cardAlignment = Alignment.center,
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

  /// How the image tool ([PdfEditTool.image]) sources a picture to insert,
  /// and how selected page-content images are replaced from the element
  /// strip. Typically a file picker returning PNG or JPEG bytes.
  ///
  /// When null the image tool is dropped from the Insert group (rather than
  /// left as a button that no-ops) and the element strip's replace-image
  /// action is hidden. See [PdfViewer.imagePicker].
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
  final Map<PdfEditTool, PdfToolShortcut> toolShortcuts;

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

  /// The edge this toolbar is docked to.
  ///
  /// Left and right docks render the primary controls as a vertical rail,
  /// with any contextual strip opening inward. Top and bottom docks retain
  /// the standard horizontal layout. Compact/mobile mode remains horizontal.
  final PdfPanelDock dock;

  /// Overrides the width-based compact/mobile layout decision.
  ///
  /// Drop-in shells set this from the whole window width so docked panels
  /// cannot accidentally turn a desktop toolbar into the phone bar by
  /// narrowing only the viewer region. Null keeps the standalone toolbar's
  /// automatic behavior.
  final bool? compact;

  /// Alignment of the floating desktop cards within the width supplied by
  /// the host. The drop-in editor uses this when the toolbar is docked to the
  /// left or right edge. Compact/mobile mode ignores it.
  final AlignmentGeometry cardAlignment;

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

/// One entry in a tool group - either an armable [PdfEditTool] or an armable
/// text-markup tool ([PdfMarkupKind]).
class _GroupTool {
  const _GroupTool.tool(this.tool, this.icon) : markup = null;
  const _GroupTool.markup(this.markup, this.icon) : tool = null;

  final PdfEditTool? tool;
  final PdfMarkupKind? markup;
  final IconData icon;
}

typedef _ToolChoice = ({PdfEditTool? tool, PdfMarkupKind? markup});

/// A dock group: a labelled chip that raises a contextual strip of
/// [tools]. [defaultTool] is armed when the group opens, when arming it
/// is side-effect-free (shapes → rectangle, draw → ink); groups whose
/// first tool has a prerequisite (Measure needs a scale, Insert's
/// signature needs a drawing) leave it null and wait for an explicit tap.
class _ToolGroup {
  const _ToolGroup(this.id, this.icon, this.tools, {this.defaultTool});

  final String id;
  final IconData icon;
  final List<_GroupTool> tools;
  final PdfEditTool? defaultTool;

  /// The localized group name (the stable [id] is the translation key).
  String label(BuildContext context) {
    final l = pdfL10n(context);
    return switch (id) {
      'select' => l.tbGroupSelect,
      'markup' => l.tbGroupMarkup,
      'draw' => l.tbGroupDraw,
      'shapes' => l.tbGroupShapes,
      'insert' => l.tbGroupInsert,
      'measure' => l.tbGroupMeasure,
      'edit' => l.tbGroupEdit,
      _ => id,
    };
  }
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
  static const _mobileRecentToolLimit = 4;
  static const _mobileToolSwitcherMaxWidth = 180.0;
  static const Object _clearToolMenuChoice = Object();

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

  /// Most-recently-used armable tools for the mobile quick switcher. This is
  /// deliberately session state: a host may expose a different tool set in
  /// each editor, and opening the full sheet remains the discovery path.
  final List<_ToolChoice> _recentTools = [];
  _ToolChoice? _lastObservedTool;

  _ToolChoice get _activeToolChoice => controller.markupTool != null
      ? (tool: null, markup: controller.markupTool)
      : (tool: controller.tool, markup: null);

  @override
  void initState() {
    super.initState();
    _resetRecentTools();
    controller.addListener(_trackRecentTool);
  }

  @override
  void didUpdateWidget(PdfEditingToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_trackRecentTool);
    _resetRecentTools();
    controller.addListener(_trackRecentTool);
  }

  @override
  void dispose() {
    controller.removeListener(_trackRecentTool);
    super.dispose();
  }

  void _resetRecentTools() {
    _recentTools.clear();
    _lastObservedTool = _activeToolChoice;
    final choice = _activeToolChoice;
    if (choice.tool != null || choice.markup != null) {
      _recordRecentTool(choice);
    }
  }

  void _trackRecentTool() {
    final choice = _activeToolChoice;
    if (choice == _lastObservedTool) return;
    _lastObservedTool = choice;
    // Null is Hand/reader mode rather than Select. Temporary null transitions
    // while changing tools must not displace genuine history.
    if (choice.tool != null || choice.markup != null) {
      _recordRecentTool(choice);
    }
  }

  void _recordRecentTool(_ToolChoice choice) {
    if (!_toolChoiceIsVisible(choice)) return;
    _recentTools
      ..remove(choice)
      ..insert(0, choice);
    final keep = _mobileRecentToolLimit + 1; // current + previous tools
    if (_recentTools.length > keep) {
      _recentTools.removeRange(keep, _recentTools.length);
    }
  }

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
        Icons.near_me,
        [
          _GroupTool.tool(PdfEditTool.select, Icons.near_me),
        ],
        defaultTool: PdfEditTool.select),
    _ToolGroup('markup', Icons.edit_note, [
      _GroupTool.markup(PdfMarkupKind.highlight, Icons.border_color),
      _GroupTool.markup(PdfMarkupKind.underline, Icons.format_underlined),
      _GroupTool.markup(PdfMarkupKind.strikeOut, Icons.format_strikethrough),
      _GroupTool.markup(PdfMarkupKind.squiggly, Icons.gesture),
    ]),
    _ToolGroup(
        'draw',
        Icons.draw,
        [
          _GroupTool.tool(PdfEditTool.ink, Icons.draw),
          _GroupTool.tool(PdfEditTool.highlight, Icons.border_color),
          _GroupTool.tool(PdfEditTool.eraser, Icons.auto_fix_normal),
        ],
        defaultTool: PdfEditTool.ink),
    _ToolGroup(
        'shapes',
        Icons.rectangle_outlined,
        [
          _GroupTool.tool(PdfEditTool.rectangle, Icons.rectangle_outlined),
          _GroupTool.tool(PdfEditTool.ellipse, Icons.circle_outlined),
          _GroupTool.tool(PdfEditTool.line, Icons.horizontal_rule),
          _GroupTool.tool(PdfEditTool.arrow, Icons.arrow_right_alt),
          _GroupTool.tool(PdfEditTool.polyline, Icons.timeline),
          _GroupTool.tool(PdfEditTool.polygon, Icons.change_history),
          _GroupTool.tool(PdfEditTool.cloudPolygon, Icons.cloud_outlined),
        ],
        defaultTool: PdfEditTool.rectangle),
    _ToolGroup(
        'insert',
        Icons.text_fields,
        [
          _GroupTool.tool(PdfEditTool.freeText, Icons.text_fields),
          _GroupTool.tool(PdfEditTool.callout, Icons.chat_bubble_outline),
          _GroupTool.tool(PdfEditTool.note, Icons.sticky_note_2_outlined),
          _GroupTool.tool(PdfEditTool.stamp, Icons.approval),
          _GroupTool.tool(PdfEditTool.count, Icons.task_alt),
          _GroupTool.tool(PdfEditTool.image, Icons.image_outlined),
          _GroupTool.tool(PdfEditTool.signature, Icons.history_edu),
          _GroupTool.tool(PdfEditTool.signatureBox, Icons.draw_outlined),
        ],
        defaultTool: PdfEditTool.freeText),
    _ToolGroup('measure', Icons.straighten, [
      _GroupTool.tool(PdfEditTool.measureDistance, Icons.straighten),
      _GroupTool.tool(PdfEditTool.measurePerimeter, Icons.timeline),
      _GroupTool.tool(PdfEditTool.measureArea, Icons.crop_din),
      _GroupTool.tool(PdfEditTool.measureVolume, Icons.view_in_ar),
      _GroupTool.tool(PdfEditTool.measureSlope, Icons.trending_up),
      _GroupTool.tool(PdfEditTool.measureAngle, Icons.architecture),
      _GroupTool.tool(PdfEditTool.measureArc, Icons.gesture),
    ]),
    _ToolGroup('edit', Icons.design_services, [
      _GroupTool.tool(PdfEditTool.content, Icons.format_shapes),
      _GroupTool.tool(PdfEditTool.form, Icons.ballot_outlined),
      _GroupTool.tool(PdfEditTool.link, Icons.link),
      _GroupTool.tool(PdfEditTool.redact, Icons.gradient),
      _GroupTool.tool(PdfEditTool.snapshot, Icons.crop),
    ]),
  ];

  /// The bare, localized name of a tool - shown on labelled buttons, the
  /// mobile tool tiles, and the active-tool caption. The enum is the key.
  String _toolName(BuildContext context, PdfEditTool tool) {
    final l = pdfL10n(context);
    return switch (tool) {
      PdfEditTool.select => l.tbNameSelect,
      PdfEditTool.ink => l.tbNameDraw,
      PdfEditTool.highlight => l.tbNameHighlight,
      PdfEditTool.eraser => l.tbNameEraser,
      PdfEditTool.rectangle => l.tbNameRectangle,
      PdfEditTool.ellipse => l.tbNameEllipse,
      PdfEditTool.line => l.tbNameLine,
      PdfEditTool.arrow => l.tbNameArrow,
      PdfEditTool.polyline => l.tbNamePolyline,
      PdfEditTool.polygon => l.tbNamePolygon,
      PdfEditTool.cloudPolygon => l.tbNameCloudPolygon,
      PdfEditTool.measureDistance => l.tbNameMeasureDistance,
      PdfEditTool.measurePerimeter => l.tbNameMeasurePerimeter,
      PdfEditTool.measureArea => l.tbNameMeasureArea,
      PdfEditTool.measureVolume => l.tbNameMeasureVolume,
      PdfEditTool.measureSlope => l.tbNameMeasureSlope,
      PdfEditTool.measureAngle => l.tbNameMeasureAngle,
      PdfEditTool.measureArc => l.tbNameMeasureArc,
      PdfEditTool.calibrate => l.measCalibrate,
      PdfEditTool.freeText => l.tbNameTextBox,
      PdfEditTool.callout => l.tbNameCallout,
      PdfEditTool.note => l.tbNameNote,
      PdfEditTool.stamp => l.tbNameStamp,
      PdfEditTool.count => l.tbNameCount,
      PdfEditTool.signature => l.tbNameSignature,
      PdfEditTool.image => l.tbNameImage,
      PdfEditTool.content => l.tbToolContent,
      PdfEditTool.form => l.tbToolForm,
      PdfEditTool.link => l.toolLink,
      PdfEditTool.redact => l.tbToolRedact,
      PdfEditTool.snapshot => l.tbToolSnapshot,
      PdfEditTool.signatureBox => l.tbNameDigitalSignature,
    };
  }

  /// The full tooltip for a tool. Tools whose tip is just their name fall
  /// through to [_toolName]; the rest carry a fuller how-to hint.
  String _toolTip(BuildContext context, PdfEditTool tool) {
    final l = pdfL10n(context);
    return switch (tool) {
      PdfEditTool.highlight => l.tbTipHighlightDraw,
      PdfEditTool.callout => l.tbTipCallout,
      PdfEditTool.count => l.tbTipCount,
      PdfEditTool.image => l.tbTipImage,
      PdfEditTool.signature => l.tbTipSignature,
      PdfEditTool.signatureBox => l.tbTipDigitalSignature,
      PdfEditTool.measureAngle => l.tbTipMeasureAngle,
      PdfEditTool.measureArc => l.tbTipMeasureArc,
      PdfEditTool.content => l.tbTipContent,
      PdfEditTool.form => l.tbTipForm,
      PdfEditTool.redact => l.tbTipRedact,
      PdfEditTool.snapshot => l.tbTipSnapshot,
      _ => _toolName(context, tool),
    };
  }

  /// The bare, localized name of a text-markup tool (for mobile tiles).
  String _markupName(BuildContext context, PdfMarkupKind markup) {
    final l = pdfL10n(context);
    return switch (markup) {
      PdfMarkupKind.highlight => l.tbMarkupHighlight,
      PdfMarkupKind.underline => l.tbMarkupUnderline,
      PdfMarkupKind.strikeOut => l.tbMarkupStrikeOut,
      PdfMarkupKind.squiggly => l.tbMarkupSquiggly,
    };
  }

  /// The full tooltip for a text-markup tool.
  String _markupTip(BuildContext context, PdfMarkupKind markup) {
    final l = pdfL10n(context);
    return switch (markup) {
      PdfMarkupKind.highlight => l.tbMarkupHighlightTip,
      PdfMarkupKind.underline => l.tbMarkupUnderlineTip,
      PdfMarkupKind.strikeOut => l.tbMarkupStrikeOutTip,
      PdfMarkupKind.squiggly => l.tbMarkupSquigglyTip,
    };
  }

  bool _shows(PdfEditTool tool) => widget.tools?.contains(tool) ?? true;

  bool _entryVisible(_GroupTool entry) {
    final tool = entry.tool;
    if (tool != null) {
      // The image tool can't insert anything without an [imagePicker] to
      // source the picture, so drop it from the Insert group rather than
      // show a button that silently no-ops. Wire [imagePicker] to offer it.
      if (tool == PdfEditTool.image && widget.imagePicker == null) return false;
      return _shows(tool);
    }
    if (entry.markup != null) return widget.showMarkup;
    return true;
  }

  bool _toolIsVisible(PdfEditTool tool) {
    for (final group in _visibleGroups) {
      for (final entry in group.tools) {
        if (entry.tool == tool && _entryVisible(entry)) return true;
      }
    }
    return false;
  }

  bool _toolChoiceIsVisible(_ToolChoice choice) {
    final markup = choice.markup;
    if (markup != null) return widget.showMarkup && _groupVisible(_groups[1]);
    final tool = choice.tool;
    return tool != null && _toolIsVisible(tool);
  }

  List<_ToolChoice> get _previousVisibleTools {
    final current = _activeToolChoice;
    return _recentTools
        .where((choice) => choice != current && _toolChoiceIsVisible(choice))
        .take(_mobileRecentToolLimit)
        .toList(growable: false);
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
    final armed = controller.markupTool != null
        ? _groups.firstWhere((group) => group.id == 'markup')
        : _groupForTool(controller.tool);
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

  void _chooseMarkup(PdfMarkupKind kind) {
    controller.markupTool = kind;
    if (!viewerController.hasSelection) return;
    _markup(kind);
    viewerController.clearSelection();
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

  void _activateHandMode() {
    if (controller.isHandMode) return;
    setState(() => _openGroupId = null);
    controller.activateHandMode();
    viewerController.clearSelection();
  }

  void _activateSelectMode() {
    if (controller.tool == PdfEditTool.select) return;
    setState(() => _openGroupId = 'select');
    controller.tool = PdfEditTool.select;
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
      initial: controller.preferences.measurementScale,
      onCalibrate: () {
        controller.tool = PdfEditTool.calibrate;
        messenger?.showSnackBar(SnackBar(
          content: Text(pdfL10n(context).tbCalibrateScaleHint),
        ));
      },
    );
    if (scale != null) controller.preferences.measurementScale = scale;
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
    final drawn = controller.preferences.signature == null;
    if (drawn && !await _drawSignature(context)) return;
    _toggleTool(PdfEditTool.signature);
    // Arming the tool restores the signature style scope over whatever
    // _drawSignature just seeded, so seed it again now the scope is live.
    if (drawn) _seedSignatureStyle(controller.preferences.signature!);
  }

  Future<bool> _drawSignature(BuildContext context) async {
    final signature = await showPdfSignatureDialog(
      context,
      initialColor: controller.color,
      initialStrokeWidth: controller.preferences.strokeWidth,
      pickColor: (context, initial) =>
          pickEditingColor(context, controller, initial: initial),
    );
    if (signature == null) return false;
    controller.preferences.signature = signature;
    _seedSignatureStyle(signature);
    return true;
  }

  /// Points the tool's colour and pen width at what [signature] was drawn
  /// with - the placed ink follows the toolbar, not the record, so this is
  /// what makes the stamp match the pad. Both stay editable afterwards.
  void _seedSignatureStyle(PdfInkSignature signature) {
    controller.color = Color(0xFF000000 | signature.color);
    controller.preferences.strokeWidth = signature.strokeWidth;
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
      title: pdfL10n(context).tbReplaceText,
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
      title: pdfL10n(context).tbReflowParagraph,
      initial: element.text ?? '',
      multiline: true,
    );
    if (text == null || text == element.text) return;
    final reflowed = controller.reflowSelectedElementText(text);
    if (!reflowed && context.mounted) {
      ScaffoldMessenger.maybeOf(context)
        ?..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(pdfL10n(context).tbReflowFailed),
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
            content: Text(pdfL10n(context).tbReplaceImageFailed),
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
          ? pdfL10n(context).tbAnnotationsFlattened
          : pdfL10n(context).tbNoAnnotationsToFlatten,
      undoable: flattened,
    );
  }

  void _flattenForm(BuildContext context) {
    final flattened = controller.flattenFormFields();
    _flattenToast(
      context,
      flattened
          ? pdfL10n(context).tbFormFieldsFlattened
          : pdfL10n(context).tbNoFormFieldsToFlatten,
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
          title: pdfL10n(context).tbFieldValue,
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
      title: pdfL10n(context).tbFieldName,
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
        tooltip: pdfL10n(context).tbRenameField,
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
        tooltip: pdfL10n(context).tbDeleteField,
        onPressed: controller.deleteSelected,
      ),
      if (widget.showFlatten)
        IconButton(
          key: const ValueKey('pdf-selected-form-flatten'),
          icon: const Icon(Icons.layers_clear_outlined),
          tooltip: pdfL10n(context).tbFlattenFormBakeValues,
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
        tooltip: pdfL10n(context).tbFieldActions,
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
          PopupMenuItem(
            key: const ValueKey('pdf-selected-form-rename'),
            value: _SelectedFormOverflowAction.rename,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(pdfL10n(context).tbRenameFieldEllipsis),
            ),
          ),
          if (controller.canStyleSelectedFormField)
            PopupMenuItem(
              key: const ValueKey('pdf-selected-form-style'),
              value: _SelectedFormOverflowAction.style,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.text_format),
                title: Text(pdfL10n(context).tbTextStyleEllipsis),
              ),
            ),
          PopupMenuItem(
            key: const ValueKey('pdf-selected-form-type-text'),
            value: _SelectedFormOverflowAction.typeText,
            enabled: field.type != PdfFieldType.text,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.text_fields),
              title: Text(pdfL10n(context).tbConvertToTextField),
            ),
          ),
          PopupMenuItem(
            key: const ValueKey('pdf-selected-form-type-checkbox'),
            value: _SelectedFormOverflowAction.typeCheckBox,
            enabled: field.type != PdfFieldType.checkBox,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.check_box_outlined),
              title: Text(pdfL10n(context).tbConvertToCheckBox),
            ),
          ),
          PopupMenuItem(
            key: const ValueKey('pdf-selected-form-type-button'),
            value: _SelectedFormOverflowAction.typeButton,
            enabled: field.type != PdfFieldType.pushButton,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.smart_button),
              title: Text(pdfL10n(context).tbConvertToImageButton),
            ),
          ),
          PopupMenuItem(
            key: const ValueKey('pdf-selected-form-delete'),
            value: _SelectedFormOverflowAction.delete,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.delete_outline),
              title: Text(pdfL10n(context).tbDeleteField),
            ),
          ),
          if (widget.showFlatten)
            PopupMenuItem(
              key: const ValueKey('pdf-selected-form-flatten'),
              value: _SelectedFormOverflowAction.flatten,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.layers_clear_outlined),
                title: Text(pdfL10n(context).tbFlattenForm),
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
            ? SnackBarAction(
                label: pdfL10n(context).undo, onPressed: controller.undo)
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
    final message = pdfL10n(context).tbColorsReplaced(count);
    ScaffoldMessenger.maybeOf(context)
      ?..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: pdfFloatingToastMargin(context),
      ));
  }

  Future<void> _applyRedactions(BuildContext context) async {
    final confirmed = await showPdfDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('pdf-redaction-confirm'),
        title: Text(pdfL10n(context).tbApplyRedactionsTitle),
        content: Text(pdfL10n(context).tbApplyRedactionsMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(pdfL10n(context).cancel),
          ),
          FilledButton(
            key: const ValueKey('pdf-redaction-confirm-apply'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(pdfL10n(context).apply),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final burned = controller.applyRedactions();
    _flattenToast(
      context,
      burned
          ? pdfL10n(context).tbRedactionsApplied
          : pdfL10n(context).tbNoRedactionsToApply,
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
        'FreeText' => pdfL10n(context).tbTextTitle,
        'Stamp' => pdfL10n(context).tbStampText,
        _ => pdfL10n(context).tbNoteTitle,
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
            builder: (context, constraints) {
              final compact = widget.compact ??
                  (!widget.dock.isHorizontal &&
                      constraints.maxWidth <
                          PdfEditingToolbar.mobileBreakpoint);
              return compact
                  ? _buildMobile(context, width: constraints.maxWidth)
                  : _buildDesktop(context);
            },
          ),
        ),
      ),
    );
  }

  // ---- desktop: dock + contextual strip -----------------------------------

  /// The contextual toolbar follows the primary dock: a side dock stacks
  /// controls vertically, while a top/bottom dock keeps the familiar row.
  Axis get _stripAxis =>
      widget.dock.isHorizontal ? Axis.vertical : Axis.horizontal;

  Widget _stripFlex(List<Widget> children) => Flex(
        direction: _stripAxis,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      );

  Widget _intrinsicStrip(Widget child) => _stripAxis == Axis.horizontal
      ? IntrinsicHeight(child: child)
      : IntrinsicWidth(child: child);

  Widget _buildDesktop(BuildContext context) {
    final strip = _desktopStrip(context);
    if (widget.dock.isHorizontal) {
      final rail = _dock(context);
      final children = <Widget>[
        if (widget.dock == PdfPanelDock.right && strip != null) ...[
          Flexible(child: strip),
          const SizedBox(width: 8),
        ],
        rail,
        if (widget.dock == PdfPanelDock.left && strip != null) ...[
          const SizedBox(width: 8),
          Flexible(child: strip),
        ],
      ];
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children,
        ),
      );
    }
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

  /// A dock-aligned floating card. When the controls overflow, they scroll
  /// along the toolbar's axis so the rounded card edge never gets clipped by
  /// the viewer or scrollbar gutter.
  Widget _centeredCard(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(8),
    Axis scrollDirection = Axis.horizontal,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: widget.cardAlignment,
        child: Container(
          key: const ValueKey('pdf-editing-toolbar-card'),
          constraints: scrollDirection == Axis.horizontal
              ? BoxConstraints(maxWidth: constraints.maxWidth)
              : BoxConstraints(maxHeight: constraints.maxHeight),
          decoration: _cardDecoration(context),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: scrollDirection,
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
    final axis = widget.dock.isHorizontal ? Axis.vertical : Axis.horizontal;
    final groups = _visibleGroups;
    final showNavigationModes = groups.any((group) => group.id == 'select');
    final editingGroups =
        groups.where((group) => group.id != 'select').toList(growable: false);
    final children = <Widget>[
      for (final builder in widget.leading)
        builder(context, controller, viewerController),
      if (widget.leading.isNotEmpty) _DockDivider(axis: axis),
      if (widget.showUndoRedo) ...[
        IconButton(
          key: const ValueKey('pdf-undo'),
          icon: const Icon(Icons.undo),
          tooltip: pdfL10n(context).tbUndoShortcut,
          onPressed: controller.canUndo ? controller.undo : null,
        ),
        IconButton(
          key: const ValueKey('pdf-redo'),
          icon: const Icon(Icons.redo),
          tooltip: pdfL10n(context).tbRedoShortcut,
          onPressed: controller.canRedo ? controller.redo : null,
        ),
        _DockDivider(axis: axis),
      ],
      if (showNavigationModes) ...[
        _NavigationModeGroup(
          axis: axis,
          handLabel: pdfL10n(context).tbNameHand,
          selectLabel: _entryTip(context, _groups.first.tools.single),
          handActive: controller.isHandMode,
          selectActive: controller.tool == PdfEditTool.select,
          onHand: _activateHandMode,
          onSelect: _activateSelectMode,
        ),
        if (editingGroups.isNotEmpty ||
            widget.onSave != null ||
            widget.trailing.isNotEmpty)
          _DockDivider(axis: axis),
      ],
      for (final group in editingGroups)
        _GroupChip(
          key: ValueKey('pdf-group-${group.id}'),
          group: group,
          active: _openGroup?.id == group.id,
          vertical: axis == Axis.vertical,
          onTap: () => _openGroupTap(group),
        ),
      // Flatten now lives in the Edit group's strip, not the dock.
      // Save stays available for standalone hosts, but the drop-in
      // shells hide it here and surface it in their header (near Open).
      if (widget.onSave != null) ...[
        _DockDivider(axis: axis),
        IconButton(
          icon: const Icon(Icons.save_alt),
          tooltip: pdfL10n(context).tbSaveShortcut,
          // disabled while the document matches what was opened - there's
          // nothing to write until an edit bumps the revision cursor
          onPressed: controller.isModified
              ? () => widget.onSave!(controller.bytes)
              : null,
        ),
      ],
      if (widget.trailing.isNotEmpty) ...[
        _DockDivider(axis: axis),
        for (final builder in widget.trailing)
          builder(context, controller, viewerController),
      ],
    ];
    final dock = Flex(
      direction: axis,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
    return _centeredCard(
      context,
      child: dock,
      scrollDirection: axis,
    );
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
          key: ValueKey('pdf-markup-${entry.markup!.name}'),
          icon: Icon(entry.icon),
          tooltip: _markupTip(context, entry.markup!),
          isSelected: controller.markupTool == entry.markup,
          onPressed: () => _chooseMarkup(entry.markup!),
        ));
      } else if (labelled) {
        final tool = entry.tool!;
        toolButtons.add(_LabeledToolButton(
          key: ValueKey('pdf-tool-${tool.name}'),
          icon: entry.icon,
          label: _toolName(context, tool),
          tooltip: _entryTip(context, entry),
          active: controller.tool == tool,
          onTap: () => _armGroupTool(context, tool),
        ));
      } else {
        final tool = entry.tool!;
        if (tool == PdfEditTool.stamp) {
          toolButtons.add(_StampToolPopupButton(
            controller: controller,
            tooltip: _entryTip(context, entry),
            active: controller.tool == tool,
            onArm: _armStampToolForMenu,
            onManage: _manageStamps,
          ));
        } else {
          toolButtons.add(IconButton(
            key: ValueKey('pdf-tool-${tool.name}'),
            icon: Icon(entry.icon),
            tooltip: _entryTip(context, entry),
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
        label: pdfL10n(context).tbColorLabel,
        tooltip: pdfL10n(context).tbColorProcessingTooltip,
        active: false,
        onTap: () => _showColorProcessing(context),
      ));
    }
    if (group.id == 'measure') {
      toolButtons.add(_takeoffButton(context));
    }

    final settings = _groupSettings(context, group, axis: _stripAxis);
    final strip = _intrinsicStrip(
      _stripFlex([
        Padding(
          padding: _stripAxis == Axis.horizontal
              ? const EdgeInsets.fromLTRB(12, 7, 10, 7)
              : const EdgeInsets.fromLTRB(7, 12, 7, 10),
          child: _stripFlex([
            _StripLabel(
              group.label(context),
              axis: _stripAxis,
              hint: group.id == 'markup' &&
                      !hasTextSelection &&
                      controller.markupTool == null
                  ? pdfL10n(context).tbSelectTextForMarkup
                  : null,
            ),
            ...toolButtons,
          ]),
        ),
        if (settings.isNotEmpty) ...[
          _StripDivider(axis: _stripAxis),
          Padding(
            padding: _stripAxis == Axis.horizontal
                ? const EdgeInsets.fromLTRB(10, 7, 12, 7)
                : const EdgeInsets.fromLTRB(7, 10, 7, 12),
            child: _stripFlex(settings),
          ),
        ],
      ]),
    );
    return _centeredCard(
      context,
      padding: EdgeInsets.zero,
      scrollDirection: _stripAxis,
      child: strip,
    );
  }

  /// The settings cluster for the active tool of [group].
  List<Widget> _groupSettings(
    BuildContext context,
    _ToolGroup group, {
    Axis axis = Axis.horizontal,
  }) {
    final tool = controller.tool;
    final fields = _groupStyleFields(group);
    switch (group.id) {
      case 'markup':
        return [
          ..._colorCluster(context),
          if (widget.showColor && widget.showStyle) _MiniDivider(axis: axis),
          _opacitySlider(context),
          ..._tuneTrailing(context, fields, axis: axis),
        ];
      case 'draw':
        if (tool == null && viewerController.hasSelection) {
          return [
            ..._colorCluster(context),
            if (widget.showColor && widget.showStyle) _MiniDivider(axis: axis),
            _opacitySlider(context),
            ..._tuneTrailing(context, fields, axis: axis),
          ];
        }
        if (tool == PdfEditTool.eraser) {
          return [
            ..._drawToolExtras(context),
            ..._tuneTrailing(context, fields, axis: axis),
          ];
        }
        return [
          ..._colorCluster(context),
          if (widget.showColor) _MiniDivider(axis: axis),
          _strokePresets(context),
          _MiniDivider(axis: axis),
          _opacitySlider(context),
          ..._drawToolExtras(context),
          ..._tuneTrailing(context, fields, axis: axis),
        ];
      case 'shapes':
        return [
          ..._colorCluster(context),
          if (widget.showColor) _MiniDivider(axis: axis),
          _strokePresets(context),
          _MiniDivider(axis: axis),
          _opacitySlider(context),
          ..._tuneTrailing(context, fields, axis: axis),
        ];
      case 'insert':
        return [
          ..._colorCluster(context),
          if (widget.showColor) _MiniDivider(axis: axis),
          _opacitySlider(context),
          ..._insertToolExtras(context),
          ..._tuneTrailing(context, fields, axis: axis),
        ];
      case 'measure':
        return [
          ..._colorCluster(context),
          if (widget.showColor) _MiniDivider(axis: axis),
          _strokePresets(context),
          _MiniDivider(axis: axis),
          _scaleChip(context),
          ..._tuneTrailing(context, fields, axis: axis),
        ];
      case 'edit':
        return _editToolExtras(context, axis: axis);
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
          tooltip: controller.preferences.fingerDrawsInk
              ? pdfL10n(context).tbFingerDraws
              : pdfL10n(context).tbFingerScrolls,
          isSelected: controller.preferences.fingerDrawsInk,
          onPressed: () => controller.preferences.fingerDrawsInk =
              !controller.preferences.fingerDrawsInk,
        ),
      if (controller.hasPendingInk && !controller.inkAutoCommits) ...[
        IconButton(
          icon: const Icon(Icons.check),
          tooltip: pdfL10n(context).tbAddInkAnnotation,
          onPressed: controller.finishInk,
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: pdfL10n(context).tbDiscardDrawing,
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
          tooltip: pdfL10n(context).tbDrawNewSignature,
          onPressed: () => _drawSignature(context),
        ),
      if (controller.tool == PdfEditTool.count)
        Tooltip(
          message: pdfL10n(context).tbCheckMarksOnDocument,
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
  List<Widget> _editToolExtras(
    BuildContext context, {
    Axis axis = Axis.horizontal,
  }) {
    final tool = controller.tool;
    final flatten = widget.showFlatten
        ? _LabeledToolButton(
            icon: Icons.layers_outlined,
            label: pdfL10n(context).tbFlattenLabel,
            tooltip: pdfL10n(context).tbFlattenAnnotationsTooltip,
            active: false,
            onTap: () => _flatten(context),
          )
        : null;
    if (tool == PdfEditTool.form) {
      return [
        if (flatten != null) ...[flatten, _MiniDivider(axis: axis)],
        PopupMenuButton<PdfFormFieldKind>(
          key: const ValueKey('pdf-form-field-type'),
          tooltip: pdfL10n(context).tbNewFieldType,
          icon: Icon(switch (controller.newFormFieldKind) {
            PdfFormFieldKind.text => Icons.text_fields,
            PdfFormFieldKind.checkBox => Icons.check_box_outlined,
            PdfFormFieldKind.pushButton => Icons.smart_button,
          }),
          initialValue: controller.newFormFieldKind,
          onSelected: (kind) => controller.newFormFieldKind = kind,
          itemBuilder: (context) => [
            PopupMenuItem(
              key: const ValueKey('pdf-form-type-text'),
              value: PdfFormFieldKind.text,
              height: 34,
              child: Text(pdfL10n(context).tbTextFieldOption),
            ),
            PopupMenuItem(
              key: const ValueKey('pdf-form-type-checkbox'),
              value: PdfFormFieldKind.checkBox,
              height: 34,
              child: Text(pdfL10n(context).tbCheckBoxOption),
            ),
            PopupMenuItem(
              key: const ValueKey('pdf-form-type-button'),
              value: PdfFormFieldKind.pushButton,
              height: 34,
              child: Text(pdfL10n(context).tbImageButtonOption),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.layers_clear_outlined),
          tooltip: pdfL10n(context).tbFlattenFormBakeValues,
          onPressed:
              controller.acroForm == null ? null : () => _flattenForm(context),
        ),
      ];
    }
    if (tool == PdfEditTool.redact) {
      return [
        if (flatten != null) ...[flatten, _MiniDivider(axis: axis)],
        IconButton(
          key: const ValueKey('pdf-apply-redactions'),
          icon: const Icon(Icons.check),
          tooltip: pdfL10n(context).tbApplyRedactionsTooltip,
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
    if (controller.isCroppingImage) return _cropStrip(context);
    final canRestyle = controller.canRestyleSelected;
    final selectedFieldName = controller.selectedWidgetFieldName;
    final settings = <Widget>[
      if (widget.showColor && canRestyle) ..._colorCluster(context),
      if (widget.showColor && canRestyle && widget.showStyle)
        _MiniDivider(axis: _stripAxis),
      if (canRestyle) _opacitySlider(context),
      ..._tuneTrailing(
        context,
        _selectionStyleFields(),
        axis: _stripAxis,
      ),
    ];
    final strip = _intrinsicStrip(
      _stripFlex([
        Padding(
          padding: _stripAxis == Axis.horizontal
              ? const EdgeInsets.fromLTRB(12, 7, 10, 7)
              : const EdgeInsets.fromLTRB(7, 12, 7, 10),
          child: _stripFlex([
            _StripLabel(
              selectedFieldName == null
                  ? pdfL10n(context).tbSelectionCount(
                      controller.selectedAnnotationSlots.length)
                  : pdfL10n(context).tbFieldNamed(selectedFieldName),
              axis: _stripAxis,
            ),
            if (selectedFieldName != null)
              ..._selectedFormFieldActions(context)
            else
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: pdfL10n(context).tbDeleteAnnotations(
                    controller.selectedAnnotationSlots.length),
                onPressed: controller.deleteSelected,
              ),
            if (controller.canCropSelected)
              IconButton(
                key: const ValueKey('pdf-crop-image'),
                icon: const Icon(Icons.crop),
                tooltip: pdfL10n(context).tbCropImage,
                onPressed: controller.beginImageCrop,
              ),
            if (controller.canEditSelectedText)
              IconButton(
                key: const ValueKey('pdf-edit-selected-text'),
                icon: const Icon(Icons.edit),
                tooltip: pdfL10n(context).tbEditAnnotationText,
                onPressed: () => _editSelectedText(context),
              ),
            if (controller.canRestyleSelectedText)
              IconButton(
                key: const ValueKey('pdf-autosize-text-box'),
                icon: const Icon(Icons.fit_screen),
                tooltip: pdfL10n(context).tbAutosizeTextBox,
                onPressed: controller.autosizeSelectedTextBox,
              ),
            if (controller.canAutosizeSelectedTextFont)
              IconButton(
                key: const ValueKey('pdf-autosize-text-font'),
                icon: const Icon(Icons.format_size),
                tooltip: pdfL10n(context).tbAutosizeTextFont,
                onPressed: controller.autosizeSelectedTextFont,
              ),
          ]),
        ),
        if (controller.canAlignSelected) ...[
          _StripDivider(axis: _stripAxis),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
            child: _alignmentCluster(context, axis: _stripAxis),
          ),
        ],
        if (settings.isNotEmpty) ...[
          _StripDivider(axis: _stripAxis),
          Padding(
            padding: _stripAxis == Axis.horizontal
                ? const EdgeInsets.fromLTRB(10, 7, 12, 7)
                : const EdgeInsets.fromLTRB(7, 10, 7, 12),
            child: _stripFlex(settings),
          ),
        ],
      ]),
    );
    return _centeredCard(
      context,
      padding: EdgeInsets.zero,
      scrollDirection: _stripAxis,
      child: strip,
    );
  }

  /// The toolbar shown while the interactive image-crop tool is armed: a
  /// label, a reset-crop action, then cancel/apply. The on-page crop overlay
  /// carries its own confirm/cancel chips; these mirror them for keyboard and
  /// pointer users who reach for the toolbar.
  Widget _cropStrip(BuildContext context) {
    final l10n = pdfL10n(context);
    final hasCrop = controller.selectedAnnotation?.imageStampCrop != null;
    final strip = _intrinsicStrip(
      _stripFlex([
        Padding(
          padding: _stripAxis == Axis.horizontal
              ? const EdgeInsets.fromLTRB(12, 7, 4, 7)
              : const EdgeInsets.fromLTRB(7, 12, 7, 4),
          child: _stripFlex([
            _StripLabel(l10n.tbCroppingImage, axis: _stripAxis),
            if (hasCrop)
              IconButton(
                key: const ValueKey('pdf-crop-reset'),
                icon: const Icon(Icons.restart_alt),
                tooltip: l10n.tbCropReset,
                onPressed: () {
                  controller.cancelImageCrop();
                  controller.resetSelectedImageCrop();
                },
              ),
          ]),
        ),
        _StripDivider(axis: _stripAxis),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          child: _stripFlex([
            IconButton(
              key: const ValueKey('pdf-crop-cancel-toolbar'),
              icon: const Icon(Icons.close),
              tooltip: l10n.tbCropCancel,
              onPressed: controller.cancelImageCrop,
            ),
            IconButton(
              key: const ValueKey('pdf-crop-apply-toolbar'),
              icon: const Icon(Icons.check),
              tooltip: l10n.tbCropApply,
              onPressed: controller.commitImageCrop,
            ),
          ]),
        ),
      ]),
    );
    return _centeredCard(
      context,
      padding: EdgeInsets.zero,
      scrollDirection: _stripAxis,
      child: strip,
    );
  }

  /// The align/distribute buttons shown while two or more annotations are
  /// selected: edge + centre alignment, then even-spacing distribution
  /// (which needs three, so those disable below that). Each button defers
  /// to [PdfEditingController.alignSelected].
  Widget _alignmentCluster(
    BuildContext context, {
    Axis axis = Axis.horizontal,
  }) {
    final canDistribute = controller.canDistributeSelected;
    return Flex(direction: axis, mainAxisSize: MainAxisSize.min, children: [
      _alignButton(PdfAlignment.left, Icons.align_horizontal_left,
          pdfL10n(context).tbAlignLeft),
      _alignButton(PdfAlignment.horizontalCenter, Icons.align_horizontal_center,
          pdfL10n(context).tbAlignHorizontalCenters),
      _alignButton(PdfAlignment.right, Icons.align_horizontal_right,
          pdfL10n(context).tbAlignRight),
      _MiniDivider(axis: axis),
      _alignButton(PdfAlignment.top, Icons.align_vertical_top,
          pdfL10n(context).tbAlignTop),
      _alignButton(PdfAlignment.verticalCenter, Icons.align_vertical_center,
          pdfL10n(context).tbAlignVerticalCenters),
      _alignButton(PdfAlignment.bottom, Icons.align_vertical_bottom,
          pdfL10n(context).tbAlignBottom),
      _MiniDivider(axis: axis),
      _alignButton(
          PdfAlignment.distributeHorizontal,
          Icons.horizontal_distribute,
          pdfL10n(context).tbDistributeHorizontally,
          enabled: canDistribute),
      _alignButton(PdfAlignment.distributeVertical, Icons.vertical_distribute,
          pdfL10n(context).tbDistributeVertically,
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
    final strip = _stripFlex([
      _StripLabel(pdfL10n(context).tbElement, axis: _stripAxis),
      IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: pdfL10n(context).tbDeleteElement,
        onPressed: controller.deleteSelectedElement,
      ),
      if (controller.canEditSelectedElementText) ...[
        IconButton(
          key: const ValueKey('pdf-replace-element-text'),
          icon: const Icon(Icons.edit),
          tooltip: pdfL10n(context).tbReplaceText,
          onPressed: () => _editElementText(context),
        ),
        IconButton(
          key: const ValueKey('pdf-style-element-text'),
          icon: const Icon(Icons.format_color_text),
          tooltip: pdfL10n(context).tbEditTextStyle,
          onPressed: () => _editElementTextStyle(context),
        ),
        IconButton(
          key: const ValueKey('pdf-reflow-element-text'),
          icon: const Icon(Icons.wrap_text),
          tooltip: pdfL10n(context).tbReflowParagraph,
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
          tooltip: pdfL10n(context).tbSaveImage,
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
          tooltip: pdfL10n(context).tbReplaceImage,
          onPressed: _replacingElementImage
              ? null
              : () => _replaceElementImage(context),
        ),
    ]);
    return _centeredCard(
      context,
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      scrollDirection: _stripAxis,
      child: strip,
    );
  }

  // ---- inline settings clusters -------------------------------------------

  /// The palette swatches + custom-colour picker + eyedropper. Empty when
  /// [PdfEditingToolbar.showColor] is off.
  List<Widget> _colorCluster(BuildContext context) {
    if (!widget.showColor) return const [];
    final scheme = Theme.of(context).colorScheme;
    // with a restylable selection the swatches show - and change - its
    // colour; otherwise the creation default
    final current = controller.displayColor;
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
                  color: current == color ? scheme.primary : scheme.outline,
                  width: current == color ? 3 : 1,
                ),
              ),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Tooltip(
          message: pdfL10n(context).tbMoreColors,
          child: Material(
            key: const ValueKey('pdf-more-colors'),
            color: Colors.transparent,
            shape: CircleBorder(side: BorderSide(color: scheme.outline)),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
                final picked = await pickEditingColor(context, controller,
                    initial: current);
                if (picked != null) _applyColor(picked);
              },
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Icon(Icons.palette_outlined, color: current, size: 20),
                ),
              ),
            ),
          ),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.colorize),
        tooltip: pdfL10n(context).tbPickColorFromPage,
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
            controller.preferences.strokeWidth)
        : controller.preferences.strokeWidth;
    void set(double w) {
      controller.preferences.strokeWidth = w;
      if (restyling) controller.restyleSelected(strokeWidth: w);
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (final w in presets)
        Tooltip(
          message: pdfL10n(context).tbStrokeWidthPreset(
              w.toStringAsFixed(w == w.roundToDouble() ? 0 : 1)),
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
        controller.preferences.opacity;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Padding(
        padding: EdgeInsetsDirectional.only(end: 2),
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
              if (!restyling) controller.preferences.opacity = v;
            },
            onChangeEnd: (v) {
              controller.preferences.opacity = v;
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
        // a true ratio: typeable down to 0%, never past 100%
        fieldMin: 0,
        fieldMax: 1,
        width: 40,
        display: (v) => '${(v * 100).round()}%',
        parse: _parsePercent,
        onSubmit: (v) {
          controller.preferences.opacity = v;
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
      leading: pdfL10n(context).tbScale,
      value: controller.preferences.measurementScale?.ratioLabel ??
          pdfL10n(context).tbSetEllipsis,
      onTap: () => _setScale(context),
    );
  }

  Widget _takeoffButton(BuildContext context) {
    return _LabeledToolButton(
      key: const ValueKey('pdf-takeoff-totals'),
      icon: Icons.functions,
      label: pdfL10n(context).tbTotals,
      tooltip: pdfL10n(context).tbTakeoffTotals,
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
  /// relevant. A font context renders the trigger as the design's font chip
  /// rather than the gear icon, unless [compactTrigger] requests the mobile
  /// icon-only treatment.
  List<Widget> _tuneTrailing(
    BuildContext context,
    _StyleFields fields, {
    bool compactTrigger = false,
    Axis axis = Axis.horizontal,
  }) {
    if (!widget.showStyle || fields.isEmpty) return const [];
    return [
      if (fields.font) _MiniDivider(axis: axis),
      _StyleMenu(
        controller: controller,
        palette: widget.palette,
        showColor: widget.showColor,
        fields: fields,
        fontChipTrigger: fields.font && !compactTrigger,
        fontPicker: widget.fontPicker,
      ),
    ];
  }

  /// The style controls relevant to [group]'s active tool - see
  /// [_StyleFields]. Drives the tune popup so a rectangle never offers a
  /// font picker, ink never offers line endings, and so on.
  _StyleFields _groupStyleFields(_ToolGroup group) {
    final tool = controller.tool;
    // An armed tool owns exactly which controls it exposes - the per-tool
    // capability booleans that used to live here now live in the tool's
    // [PdfEditToolBehavior].
    if (tool != null && _groupForTool(tool)?.id == group.id) {
      return PdfEditToolBehavior.of(tool).styleFields;
    }
    // No in-group armed tool: the strip is open on its own (Select or Markup,
    // a Draw strip over a selection, or a group opened before its default
    // tool armed). Fall back to the group's resting controls.
    switch (group.id) {
      case 'draw':
        return viewerController.hasSelection
            ? const _StyleFields(opacity: true)
            : const _StyleFields(stroke: true, opacity: true);
      case 'shapes':
        return const _StyleFields(
          stroke: true,
          strokeColor: true,
          opacity: true,
          lineType: true,
          lineScale: true,
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
            // only a rectangle rounds its corners
            cornerRadius: controller.canRoundSelectedCorners,
            // a /Polygon area measurement carries a caption font
            font: controller.canRestyleMeasurementCaption,
            lineType: controller.canSetLineStyleSelected,
            lineScale: controller.canSetLineStyleSelected,
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
            lineScale: controller.canSetLineStyleSelected,
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

  Widget _buildMobile(BuildContext context, {required double width}) {
    final scheme = Theme.of(context).colorScheme;
    final activeChoice = _activeToolChoice;
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
              key: const ValueKey('pdf-undo'),
              icon: const Icon(Icons.undo),
              tooltip: pdfL10n(context).tbUndoShortcut,
              visualDensity: VisualDensity.compact,
              onPressed: controller.canUndo ? controller.undo : null,
            ),
            IconButton(
              key: const ValueKey('pdf-redo'),
              icon: const Icon(Icons.redo),
              tooltip: pdfL10n(context).tbRedoShortcut,
              visualDensity: VisualDensity.compact,
              onPressed: controller.canRedo ? controller.redo : null,
            ),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: _mobileToolSwitcherMaxWidth),
                child: LayoutBuilder(builder: (context, constraints) {
                  // On narrow phones the undo/redo buttons, tool actions, and
                  // Tools handle can leave less than one icon's width here.
                  // Keep the switcher usable by progressively dropping its
                  // label and chevron instead of overflowing.
                  if (constraints.maxWidth < 22) {
                    return const SizedBox.shrink();
                  }
                  final mainWidth = constraints.maxWidth;
                  final horizontalPadding = mainWidth >= 36
                      ? 7.0
                      : ((mainWidth - 22) / 2).clamp(0.0, 7.0).toDouble();
                  final showLabel = !compactToolLabel && mainWidth >= 100;
                  final showChevron = mainWidth >= 54;
                  final recent = _previousVisibleTools;
                  final activeLabel = _activeToolLabel(context, activeChoice);
                  final switchLabel = recent.isEmpty
                      ? '$activeLabel, ${pdfL10n(context).tbTools}'
                      : '$activeLabel, ${pdfL10n(context).propRecentlyUsed}';
                  return Material(
                    key: const ValueKey('pdf-mobile-current-tool-surface'),
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    clipBehavior: Clip.antiAlias,
                    child: Semantics(
                      button: true,
                      label: switchLabel,
                      child: InkWell(
                        key: const ValueKey('pdf-mobile-current-tool'),
                        onTap: () => _openRecentTools(context),
                        child: SizedBox(
                          width: double.infinity,
                          height: 40,
                          child: ExcludeSemantics(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: horizontalPadding),
                              child: Row(children: [
                                Icon(_activeToolIcon(activeChoice),
                                    size: 22, color: scheme.primary),
                                if (showLabel) ...[
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      activeLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ] else
                                  const Spacer(),
                                if (showChevron)
                                  Icon(Icons.expand_less,
                                      size: 17, color: scheme.primary),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          ..._mobileTrailing(context),
          const SizedBox(width: 6),
          _GroupChip.toolsHandle(
            key: const ValueKey('pdf-tools-handle'),
            compact: width < 360,
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
          tooltip: pdfL10n(context)
              .tbDeleteAnnotations(controller.selectedAnnotationSlots.length),
          visualDensity: VisualDensity.compact,
          onPressed: controller.deleteSelected,
        ),
        if (controller.canEditSelectedText)
          IconButton(
            key: const ValueKey('pdf-edit-selected-text'),
            icon: const Icon(Icons.edit),
            tooltip: pdfL10n(context).tbEditAnnotationText,
            visualDensity: VisualDensity.compact,
            onPressed: () => _editSelectedText(context),
          ),
        // the tune popup restyles the selection (stroke/opacity/font/colour) -
        // reachable from the dock, mirroring the desktop selection strip
        ..._tuneTrailing(
          context,
          _selectionStyleFields(),
          compactTrigger: true,
        ),
      ];
    }
    if (controller.selectedElement != null) {
      return [
        IconButton(
          key: const ValueKey('pdf-mobile-delete-element'),
          icon: const Icon(Icons.delete_outline),
          tooltip: pdfL10n(context).tbDeleteElement,
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
            tooltip: pdfL10n(context).tbEditTextStyle,
            visualDensity: VisualDensity.compact,
            onPressed: () => _editElementTextStyle(context),
          ),
          IconButton(
            key: const ValueKey('pdf-reflow-element-text'),
            icon: const Icon(Icons.wrap_text),
            tooltip: pdfL10n(context).tbReflowParagraph,
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
            tooltip: pdfL10n(context).tbSaveImage,
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
            tooltip: pdfL10n(context).tbReplaceImage,
            visualDensity: VisualDensity.compact,
            onPressed: _replacingElementImage
                ? null
                : () => _replaceElementImage(context),
          ),
      ];
    }
    final tune = _mobileTuneTrailing(context);
    if (widget.showColor && controller.toolUsesColor) {
      // The tune popup carries the full palette, so a couple of quick swatches
      // beside it are enough - and dropping the third keeps the whole cluster
      // (swatches + tune) inside the narrow dock without overflowing.
      return [
        ..._mobileSwatches(context, count: tune.isEmpty ? 3 : 2),
        ...tune
      ];
    }
    return tune;
  }

  /// The tune popup trigger for the mobile dock's armed tool, or empty when
  /// no tool is armed or its controls carry nothing to tune. Mirrors the
  /// desktop strip's [_tuneTrailing] so the same stroke/opacity/font sliders
  /// are one tap away on a phone.
  List<Widget> _mobileTuneTrailing(BuildContext context) {
    final group = controller.markupTool != null
        ? _groups.firstWhere((group) => group.id == 'markup')
        : _groupForTool(controller.tool);
    if (group == null) return const [];
    return _tuneTrailing(
      context,
      _groupStyleFields(group),
      compactTrigger: true,
    );
  }

  /// The first [count] palette swatches, sized for the mobile dock.
  List<Widget> _mobileSwatches(BuildContext context, {int count = 3}) {
    final scheme = Theme.of(context).colorScheme;
    final current = controller.displayColor;
    var i = 0;
    return [
      for (final color in widget.palette.take(count))
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
                  color: current == color ? scheme.primary : scheme.outline,
                  width: current == color ? 3 : 1,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  IconData _activeToolIcon(_ToolChoice choice) {
    if (choice.tool == null && choice.markup == null) {
      return Icons.pan_tool_alt;
    }
    for (final group in _groups) {
      for (final entry in group.tools) {
        if (entry.tool == choice.tool && entry.markup == choice.markup) {
          return entry.icon;
        }
      }
    }
    return Icons.near_me;
  }

  String _activeToolLabel(BuildContext context, _ToolChoice choice) {
    final markup = choice.markup;
    if (markup != null) return _markupName(context, markup);
    final tool = choice.tool;
    return tool == null
        ? pdfL10n(context).tbNameHand
        : _toolName(context, tool);
  }

  void _clearMobileTool() {
    if (controller.tool == null && controller.markupTool == null) return;
    setState(() => _openGroupId = null);
    controller.tool = null;
    viewerController.clearSelection();
  }

  /// Opens the compact MRU menu anchored above the active-tool control. With
  /// no history in Hand mode, the same tap opens the full tool sheet so the
  /// control never leads to an empty menu.
  Future<void> _openRecentTools(BuildContext targetContext) async {
    final recent = _previousVisibleTools;
    if (recent.isEmpty &&
        controller.tool == null &&
        controller.markupTool == null) {
      await _openToolSheet(context);
      return;
    }

    final overlay = Overlay.of(targetContext).context.findRenderObject();
    final target = targetContext.findRenderObject();
    if (overlay is! RenderBox || target is! RenderBox || !target.attached) {
      await _openToolSheet(context);
      return;
    }
    final targetRect = Rect.fromPoints(
      overlay.globalToLocal(target.localToGlobal(Offset.zero)),
      overlay.globalToLocal(
        target.localToGlobal(target.size.bottomRight(Offset.zero)),
      ),
    );
    final items = <PopupMenuEntry<Object>>[
      if (controller.tool != null || controller.markupTool != null)
        PopupMenuItem<Object>(
          key: const ValueKey('pdf-recent-tool-clear'),
          value: _clearToolMenuChoice,
          child: Row(children: [
            const Icon(Icons.close, size: 20),
            const SizedBox(width: 12),
            Text(pdfL10n(targetContext).clear),
          ]),
        ),
      if ((controller.tool != null || controller.markupTool != null) &&
          recent.isNotEmpty)
        const PopupMenuDivider(),
      if (recent.isNotEmpty)
        PopupMenuItem<Object>(
          enabled: false,
          height: 32,
          child: Text(
            pdfL10n(targetContext).propRecentlyUsed,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      for (final choice in recent)
        PopupMenuItem<Object>(
          key: ValueKey(choice.markup != null
              ? 'pdf-recent-markup-${choice.markup!.name}'
              : 'pdf-recent-tool-${choice.tool!.name}'),
          value: choice,
          child: Row(children: [
            Icon(_activeToolIcon(choice), size: 20),
            const SizedBox(width: 12),
            Text(_activeToolLabel(targetContext, choice)),
          ]),
        ),
    ];
    final picked = await showMenu<Object>(
      context: targetContext,
      position: RelativeRect.fromRect(
        targetRect,
        Offset.zero & overlay.size,
      ),
      items: items,
    );
    if (!mounted || picked == null) return;
    if (identical(picked, _clearToolMenuChoice)) {
      _clearMobileTool();
      return;
    }
    final choice = picked as _ToolChoice;
    if (choice.markup != null) {
      _chooseMarkup(choice.markup!);
    } else {
      await _armGroupTool(context, choice.tool!);
    }
  }

  /// Opens the mobile tools sheet: group tabs, a tool grid, and the active
  /// tool's settings. Multi-tool tabs only navigate; Select's one-option tab
  /// arms it directly and closes the sheet.
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
                            padding: const EdgeInsetsDirectional.only(end: 7),
                            child: _GroupChip(
                              key: ValueKey('pdf-group-tab-${g.id}'),
                              group: g,
                              active: g.id == tabId,
                              onTap: () {
                                if (g.id == 'select') {
                                  Navigator.of(sheetContext).pop();
                                  _toggleTool(PdfEditTool.select);
                                  return;
                                }
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
                      group.label(context),
                      hint: group.id == 'markup' &&
                              !viewerController.hasSelection &&
                              controller.markupTool == null
                          ? pdfL10n(context).tbSelectTextForMarkup
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
              key: entry.tool == null
                  ? ValueKey('pdf-markup-${entry.markup!.name}')
                  : ValueKey('pdf-tool-${entry.tool!.name}'),
              icon: entry.icon,
              label: entry.markup != null
                  ? _markupName(context, entry.markup!)
                  : _entryLabel(context, entry),
              active: entry.markup != null
                  ? controller.markupTool == entry.markup
                  : controller.tool == entry.tool,
              enabled: true,
              onTap: () async {
                if (entry.markup != null) {
                  _chooseMarkup(entry.markup!);
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
            label: pdfL10n(context).tbTotals,
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
            label: pdfL10n(context).tbColorLabel,
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

  String _entryLabel(BuildContext context, _GroupTool entry) =>
      _toolName(context, entry.tool!);

  /// A tool's tooltip with its keyboard shortcut appended (e.g.
  /// "Rectangle (R)"), so the bindings in [pdfEditToolShortcuts] are
  /// discoverable on hover. Markups and unbound tools keep the plain tip.
  String _entryTip(BuildContext context, _GroupTool entry) {
    final markup = entry.markup;
    if (markup != null) return _markupTip(context, markup);
    final tool = entry.tool!;
    final tip = _toolTip(context, tool);
    final key = pdfEditToolShortcutLabel(tool, shortcuts: widget.toolShortcuts);
    return key == null ? tip : '$tip ($key)';
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

/// A thin divider between dock clusters, perpendicular to the dock [axis].
class _DockDivider extends StatelessWidget {
  const _DockDivider({this.axis = Axis.horizontal});

  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return axis == Axis.horizontal
        ? Container(
            width: 1,
            height: 26,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: color,
          )
        : Container(
            width: 26,
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: color,
          );
  }
}

/// The two mutually exclusive navigation modes, kept in one compact control
/// so they read differently from the editing-tool group chips beside them.
class _NavigationModeGroup extends StatelessWidget {
  const _NavigationModeGroup({
    this.axis = Axis.horizontal,
    required this.handLabel,
    required this.selectLabel,
    required this.handActive,
    required this.selectActive,
    required this.onHand,
    required this.onSelect,
  });

  final Axis axis;
  final String handLabel;
  final String selectLabel;
  final bool handActive;
  final bool selectActive;
  final VoidCallback onHand;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('pdf-navigation-modes'),
      color: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: scheme.outline)),
      clipBehavior: Clip.antiAlias,
      child: Flex(direction: axis, mainAxisSize: MainAxisSize.min, children: [
        _button(
          key: const ValueKey('pdf-mode-hand'),
          icon: Icons.pan_tool_alt,
          label: handLabel,
          active: handActive,
          onPressed: onHand,
          scheme: scheme,
        ),
        axis == Axis.horizontal
            ? Container(width: 1, height: 24, color: scheme.outlineVariant)
            : Container(width: 24, height: 1, color: scheme.outlineVariant),
        _button(
          // Preserve the established key for host and package widget tests.
          key: const ValueKey('pdf-group-select'),
          icon: Icons.near_me,
          label: selectLabel,
          active: selectActive,
          onPressed: onSelect,
          scheme: scheme,
        ),
      ]),
    );
  }

  Widget _button({
    required Key key,
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onPressed,
    required ColorScheme scheme,
  }) {
    return IconButton(
      key: key,
      icon: Icon(icon, size: 19),
      tooltip: label,
      isSelected: active,
      style: IconButton.styleFrom(
        foregroundColor: active ? scheme.primary : scheme.onSurfaceVariant,
        backgroundColor: active
            ? scheme.primary.withValues(alpha: 0.15)
            : Colors.transparent,
        fixedSize: const Size.square(40),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(),
      ),
      onPressed: onPressed,
    );
  }
}

/// The full-height divider between a strip's tools and settings segments.
class _StripDivider extends StatelessWidget {
  const _StripDivider({this.axis = Axis.horizontal});

  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return axis == Axis.horizontal
        ? Container(
            width: 1,
            margin: const EdgeInsets.symmetric(vertical: 8),
            color: color,
          )
        : Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: color,
          );
  }
}

/// A short divider between setting clusters within a strip.
class _MiniDivider extends StatelessWidget {
  const _MiniDivider({this.axis = Axis.horizontal});

  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return axis == Axis.horizontal
        ? Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: color,
          )
        : Container(
            width: 24,
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 6),
            color: color,
          );
  }
}

/// The uppercase group/context label at the left of a contextual strip.
class _StripLabel extends StatelessWidget {
  const _StripLabel(
    this.text, {
    this.hint,
    this.axis = Axis.horizontal,
  });

  final String text;
  final String? hint;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: axis == Axis.horizontal
          ? const EdgeInsetsDirectional.only(end: 8, start: 2)
          : const EdgeInsets.only(bottom: 8, top: 2),
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
    this.vertical = false,
  })  : _toolsHandle = false,
        _compact = false;

  const _GroupChip.toolsHandle({
    super.key,
    required this.onTap,
    bool compact = false,
  })  : group = null,
        active = true,
        _toolsHandle = true,
        _compact = compact,
        vertical = false;

  final _ToolGroup? group;
  final bool active;
  final VoidCallback onTap;
  final bool _toolsHandle;
  final bool _compact;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = active;
    final fg = on ? scheme.primary : scheme.onSurfaceVariant;
    final label =
        _toolsHandle ? pdfL10n(context).tbTools : group!.label(context);
    final icon = _toolsHandle ? Icons.keyboard_arrow_up : group!.icon;
    final chip = Material(
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
          width: vertical ? 40 : null,
          height: 40,
          child: Padding(
            padding: vertical
                ? EdgeInsets.zero
                : _compact
                    ? const EdgeInsets.symmetric(horizontal: 10)
                    : const EdgeInsets.fromLTRB(12, 0, 14, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment:
                  vertical ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                if (vertical)
                  Icon(icon, size: 19, color: fg, semanticLabel: label)
                else if (_toolsHandle && !_compact) ...[
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: fg)),
                  const SizedBox(width: 6),
                  Icon(icon, size: 18, color: fg),
                ] else if (!_toolsHandle) ...[
                  Icon(icon, size: 19, color: fg),
                  const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: fg)),
                ] else
                  Icon(icon, size: 18, color: fg, semanticLabel: label),
              ],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: vertical
          ? const EdgeInsets.symmetric(vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 3),
      child: vertical ? Tooltip(message: label, child: chip) : chip,
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
        label: pdfL10n(context).tbStamp,
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
                        pdfL10n(context).tbStamp,
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
                          child: Text(pdfL10n(context).tbTypeTextEachTime),
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
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                pdfL10n(context).tbNoCustomStamps,
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
                  child: Text(pdfL10n(context).tbManageStamps),
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
              alignment: AlignmentDirectional.centerStart,
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

/// The tune popup's control set. The tool-armed case is owned by
/// [PdfEditToolBehavior.styleFields]; the toolbar still builds one directly
/// from a selected annotation's subtype (see [_selectionStyleFields]).
typedef _StyleFields = PdfToolStyleFields;

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
  double? _draggingCornerRadius;
  double? _draggingScale;
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
    // keep the in-place editor focused for the whole popup session so its
    // selection highlight stays on - both when the popup opens and after each
    // control tap, so the user can see (and keep restyling) the same run
    controller.beginKeepEditingTextFocused();
  }

  void _endTextEditFocusHold() {
    if (!_holdingTextEditFocus) return;
    _holdingTextEditFocus = false;
    controller.endEditingTextFocusHold();
    controller.endKeepEditingTextFocused();
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
    controller.preferences.textFillColor = color; // the new default either way
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
    controller.preferences.shapeFillColor = color; // the new default either way
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
    controller.preferences.textBorderColor = color;
    if (controller.canRestyleSelectedText) {
      controller.restyleSelectedText(
          border: (_rgb(color),),
          // setting a border gives it the current stroke width; clearing
          // one leaves the width field alone
          borderWidth:
              color == null ? null : controller.preferences.strokeWidth);
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
        pickColor: (context, initial) =>
            pickEditingColor(context, controller, initial: initial),
      );

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
                      child: Text(pdfLineEndingLabel(context, ending),
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
                controller.preferences.strokeWidth;
            final opacityValue = _draggingOpacity ??
                annotationStyle?.opacity ??
                controller.preferences.opacity;
            // with a free text selected the rows show its own box style;
            // otherwise the creation defaults
            // line endings: edit a selected /Line or /PolyLine in place,
            // else set the creation defaults while a line tool is armed
            final lineEndingTarget = controller.canSetLineEndings;
            final lineEndings = lineEndingTarget
                ? controller.selectedLineEndings!
                : (
                    controller.preferences.lineStartEnding,
                    controller.preferences.lineEndEnding
                  );
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
                : controller.preferences.textFillColor;
            final borderValue = restyling
                ? (boxStyle?.borderColor != null &&
                        (boxStyle?.borderWidth ?? 0) > 0
                    ? Color(0xFF000000 | boxStyle!.borderColor!)
                    : null)
                : controller.preferences.textBorderColor;
            // shape interior fill: a selected shape shows its own /IC,
            // else the creation default
            final shapeFillValue = controller.canFillSelected
                ? controller.selectedShapeFill
                : controller.preferences.shapeFillColor;
            // shape/cloud/line outline: a selected shape shows its own /C,
            // else the creation default
            final strokeColorValue = controller.displayColor;
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
                      label: pdfL10n(context).tbEraserSize,
                      value: controller.preferences.eraserRadius,
                      min: 2,
                      max: 40,
                      fieldMin: 1,
                      fieldMax: kPdfTypedSizeMax,
                      display: (v) => '${v.round()} pt',
                      parse: _parsePoints,
                      onChanged: (v) => controller.preferences.eraserRadius =
                          v.roundToDouble(),
                    ),
                  if (fields.stroke)
                    _slider(
                      label: pdfL10n(context).tbStrokeWidthLabel,
                      value: strokeValue,
                      min: 0.5,
                      max: 12,
                      fieldMin: 0,
                      fieldMax: kPdfTypedSizeMax,
                      display: (v) => '${v.toStringAsFixed(1)} pt',
                      parse: _parsePoints,
                      onChanged: (v) {
                        setState(() => _draggingStroke = v);
                        if (!restylingAnnotation) {
                          controller.preferences.strokeWidth = v;
                        }
                      },
                      onChangeEnd: (v) {
                        controller.preferences.strokeWidth = v;
                        if (restylingAnnotation) {
                          controller.restyleSelected(strokeWidth: v);
                        }
                        setState(() => _draggingStroke = null);
                      },
                    ),
                  if (fields.cornerRadius)
                    _slider(
                      key: const ValueKey('pdf-corner-radius'),
                      label: pdfL10n(context).tbCornerRadius,
                      // a selected rectangle shows its own radius; otherwise
                      // the creation default while the rectangle tool is armed
                      value: _draggingCornerRadius ??
                          (restylingAnnotation
                              ? controller.selectedCornerRadius
                              : null) ??
                          controller.preferences.cornerRadius,
                      min: 0,
                      max: 40,
                      display: (v) => '${v.round()} pt',
                      parse: _parsePoints,
                      onChanged: (v) {
                        setState(() => _draggingCornerRadius = v);
                        if (!restylingAnnotation) {
                          controller.preferences.cornerRadius =
                              v.roundToDouble();
                        }
                      },
                      onChangeEnd: (v) {
                        controller.preferences.cornerRadius = v.roundToDouble();
                        if (restylingAnnotation) {
                          controller.restyleSelected(
                              cornerRadius: v.roundToDouble());
                        }
                        setState(() => _draggingCornerRadius = null);
                      },
                    ),
                  if (fields.opacity)
                    _slider(
                      label: pdfL10n(context).tbOpacity,
                      value: opacityValue,
                      min: 0.1,
                      max: 1,
                      // opacity is a true ratio: let the field reach 0% but
                      // never past 100%
                      fieldMin: 0,
                      fieldMax: 1,
                      display: (v) => '${(v * 100).round()}%',
                      parse: _parsePercent,
                      onChanged: (v) {
                        setState(() => _draggingOpacity = v);
                        if (!restylingAnnotation) {
                          controller.preferences.opacity = v;
                        }
                      },
                      onChangeEnd: (v) {
                        controller.preferences.opacity = v;
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
                          Expanded(child: Text(pdfL10n(context).tbLineType)),
                          DropdownButton<PdfLineStyle>(
                            key: const ValueKey('pdf-line-type'),
                            isDense: true,
                            value: restylingAnnotation
                                ? (controller.selectedLineStyle ??
                                    controller.preferences.lineStyle)
                                : controller.preferences.lineStyle,
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final style in PdfLineStyle.values)
                                DropdownMenuItem(
                                  value: style,
                                  key: ValueKey('pdf-line-type-${style.name}'),
                                  child:
                                      Text(pdfLineStyleLabel(context, style)),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              controller.preferences.lineStyle = value;
                              if (restylingAnnotation &&
                                  controller.canSetLineStyleSelected) {
                                controller.restyleSelected(lineStyle: value);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  if (fields.lineScale)
                    _slider(
                      key: const ValueKey('pdf-line-scale'),
                      label: pdfL10n(context).tbPatternScale,
                      value: _draggingScale ??
                          (restylingAnnotation
                              ? (controller.selectedLineScale ??
                                  controller.preferences.lineScale)
                              : controller.preferences.lineScale),
                      min: 0.5,
                      max: 4,
                      display: (v) => '${v.toStringAsFixed(1)}×',
                      onChanged: (v) {
                        setState(() => _draggingScale = v);
                        if (!restylingAnnotation) {
                          controller.preferences.lineScale = v;
                        }
                      },
                      onChangeEnd: (v) {
                        controller.preferences.lineScale = v;
                        if (restylingAnnotation &&
                            controller.canSetLineStyleSelected) {
                          controller.restyleSelected(scale: v);
                        }
                        setState(() => _draggingScale = null);
                      },
                    ),
                  if (fields.lineEndings) ...[
                    _lineEndingRow(
                      context: context,
                      label: pdfL10n(context).tbLineStart,
                      keyValue: 'pdf-line-start-ending',
                      atEnd: false,
                      value: lineEndings.$1,
                      onChanged: (ending) {
                        controller.preferences.lineStartEnding = ending;
                        if (controller.canSetLineEndings) {
                          controller.setSelectedLineEndings(start: ending);
                        }
                      },
                    ),
                    _lineEndingRow(
                      context: context,
                      label: pdfL10n(context).tbLineEnd,
                      keyValue: 'pdf-line-end-ending',
                      atEnd: true,
                      value: lineEndings.$2,
                      onChanged: (ending) {
                        controller.preferences.lineEndEnding = ending;
                        if (controller.canSetLineEndings) {
                          controller.setSelectedLineEndings(end: ending);
                        }
                      },
                    ),
                  ],
                  if (fields.strokeColor && widget.showColor)
                    _boxColorRow(
                      context: context,
                      label: pdfL10n(context).tbOutline,
                      keyPrefix: 'pdf-shape-outline',
                      value: strokeColorValue,
                      onChanged: _setStrokeColor,
                      allowNone: false,
                    ),
                  if (fields.shapeFill && widget.showColor)
                    _boxColorRow(
                      context: context,
                      label: pdfL10n(context).tbFill,
                      keyPrefix: 'pdf-shape-fill',
                      value: shapeFillValue,
                      onChanged: _setShapeFill,
                    ),
                  if (fields.font)
                    _slider(
                      label: pdfL10n(context).tbFontSize,
                      value: _draggingFontSize ??
                          selectedStyle?.size ??
                          captionStyle?.size ??
                          controller.preferences.fontSize,
                      min: 8,
                      max: 48,
                      fieldMin: 1,
                      fieldMax: kPdfTypedSizeMax,
                      display: (v) => '${v.round()} pt',
                      parse: _parsePoints,
                      onChanged: (v) {
                        setState(() => _draggingFontSize = v.roundToDouble());
                        if (selectedStyle == null && captionStyle == null) {
                          controller.preferences.fontSize = v.roundToDouble();
                        }
                      },
                      onChangeEnd: (v) {
                        final size = v.roundToDouble();
                        if (controller.restyleEditingTextSelection(
                            size: size)) {
                          controller.preferences.fontSize = size;
                          setState(() => _draggingFontSize = null);
                          return;
                        }
                        if (controller.canRestyleSelectedText) {
                          controller.preferences.fontSize = size;
                          controller.restyleSelectedText(size: size);
                        } else if (controller.canRestyleMeasurementCaption) {
                          // a selected measurement keeps its own caption size;
                          // don't disturb the creation default
                          controller.setSelectedMeasurementCaption(size: size);
                        } else {
                          controller.preferences.fontSize = size;
                        }
                        setState(() => _draggingFontSize = null);
                      },
                    ),
                  if (fields.font) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        SizedBox(
                            width: 86, child: Text(pdfL10n(context).tbFont)),
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
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
                        SizedBox(
                            width: 86, child: Text(pdfL10n(context).tbStyle)),
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
                        SizedBox(
                            width: 86, child: Text(pdfL10n(context).tbAlign)),
                        TextAlignToggles(
                          align: controller.selectedTextAlign ??
                              controller.preferences.textAlign ??
                              PdfTextAlign.left,
                          onChanged: _setTextAlign,
                        ),
                        const Spacer(),
                        // whole-box underline (a per-run underline is set from
                        // the inline editor's style chip)
                        IconButton(
                          key: const ValueKey('pdf-text-underline'),
                          icon: const Icon(Icons.format_underlined, size: 18),
                          tooltip: pdfL10n(context).tbUnderline,
                          isSelected:
                              controller.selectedFreeTextStyle?.underline ??
                                  controller.textUnderline,
                          onPressed: () => controller.setSelectedTextBoxStyle(
                              underline: !(controller
                                      .selectedFreeTextStyle?.underline ??
                                  controller.textUnderline)),
                        ),
                      ]),
                    ),
                    if (captionStyle == null) ...[
                      _slider(
                        key: const ValueKey('pdf-text-line-spacing'),
                        label: pdfL10n(context).tbLineSpacing,
                        value: _draggingLineSpacing ??
                            controller.selectedFreeTextStyle?.lineSpacing ??
                            controller.lineSpacing,
                        min: 0.8,
                        max: 3,
                        fieldMin: 0.1,
                        fieldMax: 100,
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
                        label: pdfL10n(context).tbCharSpacing,
                        value: _draggingCharSpacing ??
                            controller.selectedFreeTextStyle?.charSpacing ??
                            controller.charSpacing,
                        min: -2,
                        max: 10,
                        fieldMin: -kPdfTypedSizeMax,
                        fieldMax: kPdfTypedSizeMax,
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
                        label: pdfL10n(context).tbFontWidth,
                        value: _draggingFontWidth ??
                            controller.selectedFreeTextStyle?.horizontalScale ??
                            controller.fontWidth,
                        min: 50,
                        max: 200,
                        fieldMin: 1,
                        fieldMax: kPdfTypedSizeMax,
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
                      label: pdfL10n(context).tbTextColour,
                      keyPrefix: 'pdf-text-color',
                      value: textValue,
                      onChanged: _setTextColor,
                      allowNone: false,
                    ),
                    _boxColorRow(
                      context: context,
                      label: pdfL10n(context).tbTextFill,
                      keyPrefix: 'pdf-text-fill',
                      value: fillValue,
                      onChanged: _setTextFill,
                    ),
                    _boxColorRow(
                      context: context,
                      label: pdfL10n(context).tbTextBorder,
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

          final tip = widget.fields.eraser
              ? pdfL10n(context).tbEraserSize
              : pdfL10n(context).tbStrokeOpacityFont;
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
    double? fieldMin,
    double? fieldMax,
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
      // or onChanged for sliders that have none (live-only). The typed value
      // may run past the slider's scale (fieldMin/fieldMax) within reason.
      PdfSliderValueField(
        key: key is ValueKey ? ValueKey('${key.value}-input') : null,
        value: value,
        min: min,
        max: max,
        fieldMin: fieldMin,
        fieldMax: fieldMax,
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

  static String _familyLabel(PdfTextFont font) {
    // an embedded/bundled/custom face shows its own name, not the base-14
    // family "Sans" - matching the style popup's font button
    if (font is! PdfStandardFont) {
      return font is PdfEmbeddedFont ? font.displayName : font.resourceName;
    }
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
    // reflect the box's real face (an embedded/bundled font shows its own
    // name) the same way the style popup's font button does, so the chip
    // and popup never disagree
    final font = controller.selectedTextFont ??
        controller.activeFont ??
        style?.font ??
        controller.fontFamily;
    final size = (style?.size ?? controller.preferences.fontSize).round();
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
