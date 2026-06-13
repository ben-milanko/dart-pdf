import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart' show PdfStandardFont;

import '../pdf_viewer.dart';
import 'editing_color_picker.dart';
import 'editing_controller.dart';
import 'editing_signature.dart';
import 'editing_stamps.dart';
import 'text_prompt.dart';

/// Builds a custom widget inside [PdfEditingToolbar].
typedef PdfEditingToolbarWidgetBuilder = Widget Function(
  BuildContext context,
  PdfEditingController controller,
  PdfViewerController viewerController,
);

/// A ready-made Material toolbar for [PdfEditingController]: text-markup
/// actions for the viewer's current selection, tool toggles, a color
/// palette, undo/redo, selection actions, flatten, and save.
///
/// Place it in a Scaffold's `bottomNavigationBar` (it builds a
/// [BottomAppBar]). Apps wanting different chrome can skip this widget
/// entirely and drive the controller from their own UI, or add focused
/// host actions with [leading] and [trailing].
class PdfEditingToolbar extends StatelessWidget {
  const PdfEditingToolbar({
    super.key,
    required this.controller,
    required this.viewerController,
    this.onSave,
    this.textPrompt = showPdfTextPrompt,
    this.palette = defaultPalette,
    this.tools,
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

  /// The colors offered for new annotations.
  final List<Color> palette;

  /// The tool buttons to show, null meaning all of them. Sub-controls
  /// tied to an armed tool (the stamp picker, the form field-type menu)
  /// follow their tool. Hiding a button doesn't disable the tool — it
  /// can still be armed through the controller.
  final Set<PdfEditTool>? tools;

  /// Whether the text-markup buttons (highlight, underline, strike out,
  /// squiggly — they act on the viewer's text selection) are shown.
  final bool showMarkup;

  /// Whether the undo/redo buttons are shown. The viewer's ⌘Z/⇧⌘Z
  /// shortcuts work either way.
  final bool showUndoRedo;

  /// Whether the color controls — the palette swatches, the "More
  /// colors…" picker, the eyedropper, and the text-box fill/border color
  /// rows in the style popup — are shown. Split from [showStyle] so a
  /// color-locked session can hide the color changer while leaving
  /// stroke/opacity/font editable.
  final bool showColor;

  /// Whether the style popup (the stroke/opacity/font controls) is
  /// shown. Independent of [showColor]: the popup can show its sliders
  /// and font controls with its color rows hidden.
  final bool showStyle;

  /// Whether the flatten-annotations button is shown.
  final bool showFlatten;

  /// Custom widgets shown before the stock toolbar controls. Builders
  /// run inside the toolbar's listenable rebuild, so they can reflect
  /// [controller] or [viewerController] state directly.
  final List<PdfEditingToolbarWidgetBuilder> leading;

  /// Custom widgets shown after the stock toolbar controls.
  ///
  /// Prefer compact controls such as [IconButton]s or popup buttons so
  /// they fit naturally in the toolbar's horizontal scroll row.
  final List<PdfEditingToolbarWidgetBuilder> trailing;

  static const defaultPalette = [
    Color(0xFFE53935), // red
    Color(0xFFFFD100), // marker yellow
    Color(0xFF43A047), // green
    Color(0xFF1E88E5), // blue
    Color(0xFF000000), // black
  ];

  void _markup(PdfMarkupKind kind) {
    // capture before the edit: the document swap clears the selection
    final quadsByPage = {
      for (final page in viewerController.selectionPages)
        page: viewerController.selectionRectsOn(page),
    };
    controller.addMarkup(kind, quadsByPage);
  }

  /// Sets the creation color — and recolors the selected annotations in
  /// place when the whole selection restyles (Ben-comment #11: "change
  /// the style of a selected annotation").
  void _applyColor(Color color) {
    controller.color = color;
    if (controller.canRestyleSelected) controller.restyleSelected(color: color);
  }

  void _toggleTool(PdfEditTool value) {
    controller.tool = controller.tool == value ? null : value;
    if (controller.tool != null) viewerController.clearSelection();
  }

  /// Arms the signature tool, collecting a signature first when none is
  /// saved yet. Tapping again while armed disarms, like any tool.
  Future<void> _toggleSignatureTool(BuildContext context) async {
    if (controller.tool == PdfEditTool.signature) {
      controller.tool = null;
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
    return true;
  }

  Future<void> _editElementText(BuildContext context) async {
    final element = controller.selectedElement;
    if (element == null) return;
    final text = await textPrompt(
      context,
      title: 'Replace text',
      initial: element.text ?? '',
      multiline: false,
    );
    if (text == null || text.isEmpty || text == element.text) return;
    controller.replaceSelectedElementText(text);
  }

  /// Bakes every annotation into its page and reports the result — the
  /// flattened content looks identical to the live annotations, so
  /// without this toast the button appears to do nothing.
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
        action: undoable && controller.canUndo
            ? SnackBarAction(label: 'Undo', onPressed: controller.undo)
            : null,
      ));
  }

  Future<void> _editSelectedText(BuildContext context) async {
    final annotation = controller.selectedAnnotation;
    if (annotation == null) return;
    final text = await textPrompt(
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
      child: BottomAppBar(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ListenableBuilder(
          listenable: Listenable.merge([controller, viewerController]),
          builder: (context, _) {
            final hasTextSelection = viewerController.hasSelection;
            final selected = controller.selectedAnnotation;

            bool shows(PdfEditTool value) => tools?.contains(value) ?? true;

            Widget toolButton(PdfEditTool value, IconData icon, String tip) =>
                !shows(value)
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: Icon(icon),
                        tooltip: tip,
                        isSelected: controller.tool == value,
                        onPressed: () => _toggleTool(value),
                      );

            Widget markupButton(
                    PdfMarkupKind kind, IconData icon, String tip) =>
                IconButton(
                  icon: Icon(icon),
                  tooltip: tip,
                  onPressed: hasTextSelection ? () => _markup(kind) : null,
                );

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final builder in leading)
                  builder(context, controller, viewerController),
                if (leading.isNotEmpty) const VerticalDivider(width: 16),
                if (showUndoRedo) ...[
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
                  const VerticalDivider(width: 16),
                ],
                if (showMarkup) ...[
                  markupButton(PdfMarkupKind.highlight, Icons.border_color,
                      'Highlight selection'),
                  markupButton(PdfMarkupKind.underline, Icons.format_underlined,
                      'Underline selection'),
                  markupButton(PdfMarkupKind.strikeOut,
                      Icons.format_strikethrough, 'Strike out selection'),
                  markupButton(PdfMarkupKind.squiggly, Icons.gesture,
                      'Squiggly-underline selection'),
                  const VerticalDivider(width: 16),
                ],
                toolButton(PdfEditTool.select, Icons.near_me, 'Select'),
                if (selected != null) ...[
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: switch (
                        controller.selectedAnnotationSlots.length) {
                      1 => 'Delete annotation',
                      final n => 'Delete $n annotations',
                    },
                    onPressed: controller.deleteSelected,
                  ),
                  if (controller.canEditSelectedText)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit annotation text',
                      onPressed: () => _editSelectedText(context),
                    ),
                ],
                toolButton(PdfEditTool.ink, Icons.draw, 'Draw'),
                // pointless without a touchscreen: it only governs what
                // touch pointers do
                if ((controller.tool == PdfEditTool.ink ||
                        controller.tool == PdfEditTool.eraser) &&
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
                // with auto-commit (the default) strokes land on their own
                // and undo covers regret — confirm buttons are manual-mode
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
                // the Material icon font ships no true eraser glyph; the
                // magic-wand outline is the closest stand-in
                toolButton(PdfEditTool.eraser, Icons.auto_fix_normal,
                    'Erase ink strokes'),
                toolButton(PdfEditTool.rectangle, Icons.rectangle_outlined,
                    'Rectangle'),
                toolButton(
                    PdfEditTool.ellipse, Icons.circle_outlined, 'Ellipse'),
                toolButton(PdfEditTool.line, Icons.horizontal_rule, 'Line'),
                toolButton(PdfEditTool.arrow, Icons.arrow_right_alt, 'Arrow'),
                toolButton(PdfEditTool.polyline, Icons.timeline, 'Polyline'),
                toolButton(
                    PdfEditTool.polygon, Icons.change_history, 'Polygon'),
                toolButton(PdfEditTool.freeText, Icons.text_fields, 'Text box'),
                toolButton(
                    PdfEditTool.note, Icons.sticky_note_2_outlined, 'Note'),
                toolButton(PdfEditTool.stamp, Icons.approval, 'Stamp'),
                if (controller.tool == PdfEditTool.stamp)
                  IconButton(
                    icon: const Icon(Icons.style),
                    tooltip: 'Custom stamps…',
                    isSelected: controller.activeStamp != null,
                    onPressed: () =>
                        showPdfStampPicker(context, controller: controller),
                  ),
                if (shows(PdfEditTool.signature))
                  IconButton(
                    icon: const Icon(Icons.history_edu),
                    tooltip: 'Signature — tap a page to place it',
                    isSelected: controller.tool == PdfEditTool.signature,
                    onPressed: () => _toggleSignatureTool(context),
                  ),
                if (controller.tool == PdfEditTool.signature)
                  IconButton(
                    icon: const Icon(Icons.restart_alt),
                    tooltip: 'Draw a new signature…',
                    onPressed: () => _drawSignature(context),
                  ),
                toolButton(PdfEditTool.content, Icons.format_shapes,
                    'Edit page content'),
                toolButton(PdfEditTool.form, Icons.ballot_outlined,
                    'Form fields — tap to fill, drag to add'),
                if (controller.tool == PdfEditTool.form) ...[
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
                    onPressed: controller.acroForm == null
                        ? null
                        : () => _flattenForm(context),
                  ),
                ],
                if (controller.selectedElement != null) ...[
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
                ],
                if (showColor || showStyle)
                  const VerticalDivider(width: 16),
                if (showColor) ...[
                  for (final color in palette)
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
                              // theme outline: visible on light and dark chrome
                              color: controller.color == color
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outline,
                              width: controller.color == color ? 3 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(Icons.palette, color: controller.color),
                    tooltip: 'More colors…',
                    onPressed: () async {
                      final picked = await showPdfColorPicker(context,
                          initial: controller.color,
                          initialFormat:
                              controller.preferences.colorPickerFormat,
                          onFormatChanged: (format) => controller
                              .preferences.colorPickerFormat = format);
                      if (picked != null) _applyColor(picked);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.colorize),
                    tooltip: 'Pick a color from the page',
                    isSelected: controller.isPickingColor,
                    onPressed: () => controller.isPickingColor
                        ? controller.cancelColorPick()
                        : controller.startColorPick(),
                  ),
                ],
                if (showStyle)
                  _StyleMenu(
                    controller: controller,
                    palette: palette,
                    showColor: showColor,
                  ),
                if (showFlatten || onSave != null)
                  const VerticalDivider(width: 16),
                if (showFlatten)
                  IconButton(
                    icon: const Icon(Icons.layers),
                    tooltip: 'Flatten annotations into the pages',
                    onPressed: () => _flatten(context),
                  ),
                if (onSave != null)
                  IconButton(
                    icon: const Icon(Icons.save_alt),
                    tooltip: 'Save… (⌘S / Ctrl+S)',
                    onPressed: () => onSave!(controller.bytes),
                  ),
                if (trailing.isNotEmpty) ...[
                  const VerticalDivider(width: 16),
                  for (final builder in trailing)
                    builder(context, controller, viewerController),
                ],
              ]),
            );
          },
        ),
      ),
    );
  }
}

/// The style popup: sliders for stroke width, opacity, and font size,
/// the font family for free text, and the text box's fill and border
/// colors. With a free-text annotation selected, the text controls show
/// — and change — that annotation's style; otherwise they set the style
/// new text is created with.
class _StyleMenu extends StatefulWidget {
  const _StyleMenu({
    required this.controller,
    required this.palette,
    this.showColor = true,
  });

  final PdfEditingController controller;

  /// The colors offered as fill/border swatches (the toolbar's palette).
  final List<Color> palette;

  /// Whether the text-box fill/border color rows are shown. The
  /// stroke/opacity/font controls show regardless — this only hides the
  /// color rows so a color-locked session keeps the sliders.
  final bool showColor;

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

  void _setFontFamily(PdfStandardFont font) {
    controller.fontFamily = font; // the new default either way
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

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        // the menu lives in its own overlay, outside the toolbar's
        // ListenableBuilder — it needs its own listener to track sliders
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final selectedStyle = controller.selectedTextStyle;
            // with a restylable selection the stroke/opacity sliders
            // show — and change — its style; otherwise the defaults
            final restylingAnnotation = controller.canRestyleSelected;
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
            return Container(
              width: 300,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  if (controller.tool == PdfEditTool.eraser)
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
                  if (!restylingAnnotation)
                    SwitchListTile(
                      key: const ValueKey('pdf-dashed-stroke'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Dashed line'),
                      value: controller.dashedStroke,
                      onChanged: (value) => controller.dashedStroke = value,
                    ),
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
                      if (controller.canRestyleSelectedText) {
                        controller.restyleSelectedText(size: size);
                      }
                      setState(() => _draggingFontSize = null);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      const SizedBox(width: 86, child: Text('Font')),
                      Expanded(
                        child: SegmentedButton<PdfStandardFont>(
                          segments: const [
                            ButtonSegment(
                                value: PdfStandardFont.helvetica,
                                label: Text('Sans')),
                            ButtonSegment(
                                value: PdfStandardFont.times,
                                label: Text('Serif')),
                            ButtonSegment(
                                value: PdfStandardFont.courier,
                                label: Text('Mono')),
                          ],
                          selected: {
                            selectedStyle?.font ?? controller.fontFamily
                          },
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            padding: WidgetStatePropertyAll(
                                EdgeInsets.symmetric(horizontal: 8)),
                          ),
                          onSelectionChanged: (selection) =>
                              _setFontFamily(selection.single),
                        ),
                      ),
                    ]),
                  ),
                  if (widget.showColor) ...[
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
      builder: (context, menu, _) => IconButton(
        icon: const Icon(Icons.tune),
        tooltip: 'Stroke, opacity, font',
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
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
