import 'package:flutter/material.dart';

import '../l10n/pdf_l10n.dart';
import 'editing_controller.dart';
import 'tool_shortcuts.dart';
import '../keyboard_availability.dart';

/// One entry in the tool catalogue: an editing [tool] or a text [markup]
/// kind, with the icon the dock draws for it.
///
/// The catalogue is the single list behind both the toolbar's dock and any
/// host that needs to enumerate the tools (a command palette, a shortcut
/// sheet) - a tool added here joins every one of them.
class PdfToolEntry {
  const PdfToolEntry.tool(this.tool, this.icon) : markup = null;
  const PdfToolEntry.markup(this.markup, this.icon) : tool = null;

  final PdfEditTool? tool;
  final PdfMarkupKind? markup;
  final IconData icon;

  /// The bare, localized name - what the dock's labelled buttons, the
  /// mobile tool tiles and the active-tool caption show.
  String label(BuildContext context) => tool != null
      ? pdfEditToolLabel(context, tool!)
      : pdfMarkupLabel(context, markup!);

  /// The fuller tooltip: a how-to hint where the name alone is too terse,
  /// otherwise the name.
  String tooltip(BuildContext context) => tool != null
      ? pdfEditToolTooltip(context, tool!)
      : pdfMarkupTooltip(context, markup!);
}

/// A dock group: a labelled chip that raises a contextual strip of [tools].
///
/// [defaultTool] is armed when the group opens, when arming it is
/// side-effect-free (shapes → rectangle, draw → ink); groups whose first
/// tool has a prerequisite (Measure needs a scale, Insert's signature needs
/// a drawing) leave it null and wait for an explicit tap.
class PdfToolGroup {
  const PdfToolGroup(this.id, this.icon, this.tools, {this.defaultTool});

  final String id;
  final IconData icon;
  final List<PdfToolEntry> tools;
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

/// The seven dock groups, in order. The toolbar filters this by its own
/// `tools`/`showMarkup` settings before display.
const pdfToolGroups = <PdfToolGroup>[
  PdfToolGroup(
      'select',
      Icons.near_me,
      [
        PdfToolEntry.tool(PdfEditTool.select, Icons.near_me),
      ],
      defaultTool: PdfEditTool.select),
  PdfToolGroup('markup', Icons.edit_note, [
    PdfToolEntry.markup(PdfMarkupKind.highlight, Icons.border_color),
    PdfToolEntry.markup(PdfMarkupKind.underline, Icons.format_underlined),
    PdfToolEntry.markup(PdfMarkupKind.strikeOut, Icons.format_strikethrough),
    PdfToolEntry.markup(PdfMarkupKind.squiggly, Icons.gesture),
  ]),
  PdfToolGroup(
      'draw',
      Icons.draw,
      [
        PdfToolEntry.tool(PdfEditTool.ink, Icons.draw),
        PdfToolEntry.tool(PdfEditTool.highlight, Icons.border_color),
        PdfToolEntry.tool(PdfEditTool.eraser, Icons.auto_fix_normal),
      ],
      defaultTool: PdfEditTool.ink),
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
      defaultTool: PdfEditTool.rectangle),
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
      defaultTool: PdfEditTool.freeText),
  PdfToolGroup('measure', Icons.straighten, [
    PdfToolEntry.tool(PdfEditTool.measureDistance, Icons.straighten),
    PdfToolEntry.tool(PdfEditTool.measurePerimeter, Icons.timeline),
    PdfToolEntry.tool(PdfEditTool.measureArea, Icons.crop_din),
    PdfToolEntry.tool(PdfEditTool.measureVolume, Icons.view_in_ar),
    PdfToolEntry.tool(PdfEditTool.measureSlope, Icons.trending_up),
    PdfToolEntry.tool(PdfEditTool.measureAngle, Icons.architecture),
    PdfToolEntry.tool(PdfEditTool.measureArc, Icons.gesture),
  ]),
  PdfToolGroup('edit', Icons.design_services, [
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
