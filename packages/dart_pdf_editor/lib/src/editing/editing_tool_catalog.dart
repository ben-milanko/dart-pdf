import 'package:flutter/material.dart';

import '../l10n/pdf_l10n.dart';
import 'editing_controller.dart';
import 'editor_commands.dart' show PdfCommand;
import 'tool_shortcuts.dart';
import '../keyboard_availability.dart';

/// One entry in the tool catalogue: an editing [tool], a text [markup]
/// kind, or a host [command], with the icon the dock draws for it.
///
/// The catalogue is the single list behind both the toolbar's dock and any
/// host that needs to enumerate the tools (a command palette, a shortcut
/// sheet) - a tool added here joins every one of them.
class PdfToolEntry {
  const PdfToolEntry.tool(this.tool, this.icon)
      : markup = null,
        command = null;
  const PdfToolEntry.markup(this.markup, this.icon)
      : tool = null,
        command = null;

  /// A host action in a tool group: the dock draws it as a button beside
  /// the stock tools, shows it selected while [PdfCommand.selected] is true,
  /// disables it while [PdfCommand.enabled] is false, and runs
  /// [PdfCommand.invoke] when it is tapped.
  PdfToolEntry.command(PdfCommand this.command)
      : tool = null,
        markup = null,
        icon = command.icon;

  final PdfEditTool? tool;
  final PdfMarkupKind? markup;
  final PdfCommand? command;
  final IconData icon;

  /// The bare, localized name - what the dock's labelled buttons, the
  /// mobile tool tiles and the active-tool caption show.
  String label(BuildContext context) => tool != null
      ? pdfEditToolLabel(context, tool!)
      : markup != null
          ? pdfMarkupLabel(context, markup!)
          : command!.label(context);

  /// The fuller tooltip: a how-to hint where the name alone is too terse,
  /// otherwise the name.
  String tooltip(BuildContext context) => tool != null
      ? pdfEditToolTooltip(context, tool!)
      : markup != null
          ? pdfMarkupTooltip(context, markup!)
          : command!.tooltipOf(context);
}

/// A dock group: a labelled chip that raises a contextual strip of [tools].
///
/// [defaultTool] is armed when the group opens, when arming it is
/// side-effect-free (shapes → rectangle, draw → ink); groups whose first
/// tool has a prerequisite (Measure needs a scale, Insert's signature needs
/// a drawing) leave it null and wait for an explicit tap.
///
/// What a group does beyond listing its tools is data on it: [kind] says
/// which stock group's behaviour it has (the Select navigation cluster, the
/// Markup strip's text-selection hint and style scope, Measure's scale chip
/// and totals, Edit's colour processing, and each one's settings controls),
/// and [labelledTools] whether its strip names its tools. A host group with
/// no [kind] lists its tools and commands with no extra settings.
class PdfToolGroup {
  const PdfToolGroup(
    this.id,
    this.icon,
    this.tools, {
    this.defaultTool,
    PdfEditToolGroup? kind,
    bool? labelledTools,
    this.labelBuilder,
  })  : _kind = kind,
        _labelledTools = labelledTools;

  /// A stable identity, unique among the groups a toolbar shows.
  final String id;
  final IconData icon;
  final List<PdfToolEntry> tools;
  final PdfEditTool? defaultTool;

  final PdfEditToolGroup? _kind;
  final bool? _labelledTools;

  /// Localizes the group's name. Null uses the stock names for the stock
  /// ids, and [id] itself otherwise.
  final String Function(BuildContext context)? labelBuilder;

  /// The stock group whose behaviour this group has, and which
  /// [PdfEditingToolbar.groups] / [PdfEditorFeatures.toolGroups] value
  /// shows or hides it. Defaults to the stock group named [id], if any.
  PdfEditToolGroup? get kind => _kind ?? _stockKinds[id];

  /// Whether the group's strip shows its tools as labelled buttons rather
  /// than bare icons. Defaults to true for the Edit group only - its tools
  /// make destructive document edits and read too cryptically as icons.
  bool get labelledTools => _labelledTools ?? kind == PdfEditToolGroup.edit;

  static final _stockKinds = PdfEditToolGroup.values.asNameMap();

  /// The localized group name (the stable [id] is the translation key).
  String label(BuildContext context) {
    final builder = labelBuilder;
    if (builder != null) return builder(context);
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

/// The seven dock groups, in order. The toolbar filters this by its own
/// `tools`/`showMarkup` settings before display.
const pdfToolGroups = <PdfToolGroup>[
  PdfToolGroup(
      'select',
      Icons.near_me,
      [
        PdfToolEntry.tool(PdfEditTool.select, Icons.near_me),
      ],
      defaultTool: PdfEditTool.select,
      kind: PdfEditToolGroup.select),
  PdfToolGroup(
      'markup',
      Icons.edit_note,
      [
        PdfToolEntry.markup(PdfMarkupKind.highlight, Icons.border_color),
        PdfToolEntry.markup(PdfMarkupKind.underline, Icons.format_underlined),
        PdfToolEntry.markup(
            PdfMarkupKind.strikeOut, Icons.format_strikethrough),
        PdfToolEntry.markup(PdfMarkupKind.squiggly, Icons.gesture),
      ],
      kind: PdfEditToolGroup.markup),
  PdfToolGroup(
      'draw',
      Icons.draw,
      [
        PdfToolEntry.tool(PdfEditTool.ink, Icons.draw),
        PdfToolEntry.tool(PdfEditTool.highlight, Icons.border_color),
        PdfToolEntry.tool(PdfEditTool.eraser, Icons.auto_fix_normal),
      ],
      defaultTool: PdfEditTool.ink,
      kind: PdfEditToolGroup.draw),
  PdfToolGroup(
      'shapes',
      Icons.rectangle_outlined,
      [
        PdfToolEntry.tool(PdfEditTool.rectangle, Icons.rectangle_outlined),
        PdfToolEntry.tool(PdfEditTool.ellipse, Icons.circle_outlined),
        PdfToolEntry.tool(PdfEditTool.line, Icons.horizontal_rule),
        PdfToolEntry.tool(PdfEditTool.arrow, Icons.arrow_right_alt),
        PdfToolEntry.tool(PdfEditTool.polyline, Icons.timeline),
        PdfToolEntry.tool(PdfEditTool.polygon, Icons.change_history),
        PdfToolEntry.tool(PdfEditTool.cloudPolygon, Icons.cloud_outlined),
      ],
      defaultTool: PdfEditTool.rectangle,
      kind: PdfEditToolGroup.shapes),
  PdfToolGroup(
      'insert',
      Icons.text_fields,
      [
        PdfToolEntry.tool(PdfEditTool.freeText, Icons.text_fields),
        PdfToolEntry.tool(PdfEditTool.callout, Icons.chat_bubble_outline),
        PdfToolEntry.tool(PdfEditTool.note, Icons.sticky_note_2_outlined),
        PdfToolEntry.tool(PdfEditTool.stamp, Icons.approval),
        PdfToolEntry.tool(PdfEditTool.count, Icons.task_alt),
        PdfToolEntry.tool(PdfEditTool.image, Icons.image_outlined),
        PdfToolEntry.tool(PdfEditTool.signature, Icons.history_edu),
        PdfToolEntry.tool(PdfEditTool.signatureBox, Icons.draw_outlined),
      ],
      defaultTool: PdfEditTool.freeText,
      kind: PdfEditToolGroup.insert),
  PdfToolGroup(
      'measure',
      Icons.straighten,
      [
        PdfToolEntry.tool(PdfEditTool.measureDistance, Icons.straighten),
        PdfToolEntry.tool(PdfEditTool.measurePerimeter, Icons.timeline),
        PdfToolEntry.tool(PdfEditTool.measureArea, Icons.crop_din),
        PdfToolEntry.tool(PdfEditTool.measureVolume, Icons.view_in_ar),
        PdfToolEntry.tool(PdfEditTool.measureSlope, Icons.trending_up),
        PdfToolEntry.tool(PdfEditTool.measureAngle, Icons.architecture),
        PdfToolEntry.tool(PdfEditTool.measureArc, Icons.gesture),
      ],
      kind: PdfEditToolGroup.measure),
  PdfToolGroup(
      'edit',
      Icons.design_services,
      kind: PdfEditToolGroup.edit,
      labelledTools: true,
      [
        PdfToolEntry.tool(PdfEditTool.content, Icons.format_shapes),
        PdfToolEntry.tool(PdfEditTool.contentDelete, Icons.content_cut),
        PdfToolEntry.tool(PdfEditTool.form, Icons.ballot_outlined),
        PdfToolEntry.tool(PdfEditTool.link, Icons.link),
        PdfToolEntry.tool(PdfEditTool.redact, Icons.gradient),
        PdfToolEntry.tool(PdfEditTool.snapshot, Icons.crop),
      ]),
];

/// Every catalogue entry, flattened, paired with the group it belongs to -
/// what a command palette or a shortcut sheet enumerates.
///
/// Pass [tools] to keep only the editing tools a host offers (the same
/// filter `PdfEditingToolbar.tools` applies), and [markup] false to drop the
/// text-markup kinds.
List<({PdfToolGroup group, PdfToolEntry entry})> pdfToolCatalog({
  Set<PdfEditTool>? tools,
  bool markup = true,
}) =>
    [
      for (final group in pdfToolGroups)
        for (final entry in group.tools)
          if (entry.markup != null
              ? markup
              : tools == null || tools.contains(entry.tool))
            (group: group, entry: entry),
    ];

/// The bare, localized name of [tool]. The enum is the key.
String pdfEditToolLabel(BuildContext context, PdfEditTool tool) {
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
    PdfEditTool.contentDelete => l.tbToolContentDelete,
    PdfEditTool.form => l.tbToolForm,
    PdfEditTool.link => l.toolLink,
    PdfEditTool.redact => l.tbToolRedact,
    PdfEditTool.snapshot => l.tbToolSnapshot,
    PdfEditTool.signatureBox => l.tbNameDigitalSignature,
  };
}

/// The full tooltip for [tool]. Tools whose tip is just their name fall
/// through to [pdfEditToolLabel]; the rest carry a fuller how-to hint.
String pdfEditToolTooltip(BuildContext context, PdfEditTool tool) {
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
    PdfEditTool.contentDelete => l.tbTipContentDelete,
    PdfEditTool.form => l.tbTipForm,
    PdfEditTool.redact => l.tbTipRedact,
    PdfEditTool.snapshot => l.tbTipSnapshot,
    _ => pdfEditToolLabel(context, tool),
  };
}

/// The bare, localized name of a text-markup kind.
String pdfMarkupLabel(BuildContext context, PdfMarkupKind markup) {
  final l = pdfL10n(context);
  return switch (markup) {
    PdfMarkupKind.highlight => l.tbMarkupHighlight,
    PdfMarkupKind.underline => l.tbMarkupUnderline,
    PdfMarkupKind.strikeOut => l.tbMarkupStrikeOut,
    PdfMarkupKind.squiggly => l.tbMarkupSquiggly,
  };
}

/// The full tooltip for a text-markup kind.
String pdfMarkupTooltip(BuildContext context, PdfMarkupKind markup) {
  final l = pdfL10n(context);
  return switch (markup) {
    PdfMarkupKind.highlight => l.tbMarkupHighlightTip,
    PdfMarkupKind.underline => l.tbMarkupUnderlineTip,
    PdfMarkupKind.strikeOut => l.tbMarkupStrikeOutTip,
    PdfMarkupKind.squiggly => l.tbMarkupSquigglyTip,
  };
}

/// [tooltip] with the tool's keyboard shortcut appended (e.g.
/// "Rectangle (R)"), so the bindings in [pdfEditToolShortcuts] are
/// discoverable on hover. Unbound tools keep the plain tip.
String pdfEditToolTooltipWithShortcut(
  BuildContext context,
  PdfEditTool tool, {
  Map<PdfEditTool, PdfToolShortcut> shortcuts = pdfEditToolShortcuts,
}) {
  final tip = pdfEditToolTooltip(context, tool);
  if (!PdfKeyboardAvailability.of(context)) return tip;
  final key = pdfEditToolShortcutLabel(tool, shortcuts: shortcuts);
  return key == null ? tip : '$tip ($key)';
}
