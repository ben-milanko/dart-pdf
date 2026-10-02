// How the editor shows things: dialogs, sheets, menus, notices and the
// prompts it asks. Widgets-layer only - the stock (Material) look lives in
// the files the defaults call, so a host presenter can replace any one method
// without the rest changing.

import 'package:flutter/widgets.dart';
import 'package:pdf_document/pdf_document.dart' show PdfPageRange;

import '../dialog.dart';
import '../editing/editing_color_picker.dart' show showPdfColorPicker;
import '../editing/editing_controller.dart'
    show PdfEditingController, PdfLinkTarget;
import '../editing/editing_fonts.dart'
    show PdfFontCatalogEntry, PdfFontChoice, pdfShowStockFontPicker;
import '../editing/editing_link.dart' show showPdfAddLinkDialog;
import '../editing/editing_measure.dart'
    show showPdfCalibrationLengthDialog, showPdfDepthDialog, showPdfScaleDialog;
import '../editing/editing_signature.dart' show showPdfSignatureDialog;
import '../editing/models/color_format.dart';
import '../editing/models/ink_signature.dart';
import '../editing/models/measurement_scale.dart';
import '../editing/models/prompts.dart' show PdfTextPrompt;
import '../editing/text_prompt.dart' show showPdfTextPrompt;
import '../editing/text_style_prompt.dart'
    show
        PdfStyledFontPicker,
        PdfStyledTextEdit,
        PdfStyledTextPrompt,
        defaultStyledTextPalette,
        showPdfStyledTextPrompt;
import '../page_range_dialog.dart' show showPdfPageRangeDialog;
import '../split_dialog.dart' show showPdfSplitDialog;
import 'material_presenter.dart';

/// How the editor presents its UI: dialogs, bottom sheets, popup menus,
/// transient notices, and the prompts it asks (text, colour, font, link,
/// measurement scale, page ranges, signatures, ...).
///
/// Every method has a stock default that reproduces the editor's own
/// (Material) UI. Override the ones you want to change and leave the rest:
///
/// ```dart
/// class MyPresenter extends PdfEditorPresenter {
///   const MyPresenter();
///
///   @override
///   bool notice(BuildContext context, PdfEditorNotice notice) {
///     myToasts.show(notice.message, undo: notice.onUndo);
///     return true;
///   }
/// }
///
/// PdfEditorView(controller: controller, presenter: const MyPresenter());
/// ```
///
/// **Extend, don't implement.** Minor releases add methods here, each with a
/// stock default, so a subclass keeps compiling; an `implements` would not.
///
/// The presenter is found through the nearest [PdfEditorScope]
/// ([PdfEditorPresenter.of]). `PdfEditorView`, `PdfViewer` and `PdfReader`
/// install one from their `presenter` argument; a host can also put a
/// [PdfEditorScope] above them to cover several editors, or its own
/// screens. The stock dialogs carry the scope into their routes, so a prompt
/// a stock dialog opens (the stamp editor's colour picker, the annotation
/// library's rename) goes through the same presenter.
class PdfEditorPresenter {
  /// The stock presenter.
  const PdfEditorPresenter();

  /// The presenter of the nearest [PdfEditorScope] above [context], or the
  /// stock one when there is none. Does not make [context] depend on the
  /// scope - call it from callbacks; use [PdfEditorScope.maybeOf] in build.
  static PdfEditorPresenter of(BuildContext context) =>
      PdfEditorScope.maybeOf(context, listen: false)?.presenter ??
      const PdfEditorPresenter();

  // ---- how ---------------------------------------------------------------

  /// Shows a modal dialog built by [request]'s builder, resolving to the
  /// value it pops with. Every stock dialog and prompt is shown through
  /// this. Default: [showPdfDialog].
  Future<T?> dialog<T>(BuildContext context, PdfDialogRequest<T> request) =>
      showPdfDialog<T>(
        context: context,
        builder: request.builder,
        barrierDismissible: request.barrierDismissible,
      );

  /// Shows a bottom sheet (the compact shell controls, the shortcut editor,
  /// the mobile tool sheet, takeoff totals). Default: a Material modal
  /// bottom sheet.
  Future<T?> sheet<T>(BuildContext context, PdfSheetRequest<T> request) =>
      pdfStockSheet<T>(context, request);

  /// Shows a popup menu at [PdfMenuRequest.anchor] and resolves to the
  /// picked entry's value (null when dismissed). Default: a Material popup
  /// menu that draws each [PdfMenuItem.child] when one is given.
  Future<T?> menu<T>(BuildContext context, PdfMenuRequest<T> request) =>
      pdfStockMenu<T>(context, request);

  /// Shows a transient, non-blocking notice. Returns whether it was shown -
  /// a once-only notice (the XFA form notice) tries again later when it
  /// returns false. Default: a SnackBar on the nearest `ScaffoldMessenger`
  /// (false when there is none).
  bool notice(BuildContext context, PdfEditorNotice notice) =>
      pdfStockNotice(context, notice);

  // ---- prompts ------------------------------------------------------------

  /// Asks for a line (or [PdfTextRequest.multiline] block) of text.
  /// Default: [showPdfTextPrompt].
  Future<String?> text(BuildContext context, PdfTextRequest request) =>
      showPdfTextPrompt(context,
          title: request.title,
          initial: request.initial,
          multiline: request.multiline);

  /// Asks for replacement text plus style overrides (the content tool's
  /// "Edit text and style"). Default: [showPdfStyledTextPrompt].
  Future<PdfStyledTextEdit?> styledText(
          BuildContext context, PdfStyledTextRequest request) =>
      showPdfStyledTextPrompt(context,
          initial: request.initial,
          palette: request.palette,
          pickFont: request.pickFont);

  /// Asks a yes/no question; resolves to true only when confirmed.
  /// Default: a Material alert dialog with Cancel and [PdfConfirmRequest]'s
  /// confirm label.
  Future<bool> confirm(BuildContext context, PdfConfirmRequest request) =>
      pdfStockConfirm(context, request);

  /// Asks for a hyperlink target (a web address or a page). Default:
  /// [showPdfAddLinkDialog].
  Future<PdfLinkTarget?> link(BuildContext context, PdfLinkRequest request) =>
      showPdfAddLinkDialog(context,
          pageCount: request.pageCount,
          currentPage: request.currentPage,
          initialUrl: request.initialUrl);

  /// Asks for a colour. The result is either a picked colour or, when
  /// [PdfColorRequest.allowSampleFromPage] is set, a request to sample one
  /// off the page with the eyedropper (the caller does the sampling and
  /// asks again with the sampled colour as the initial one). Default:
  /// [showPdfColorPicker].
  Future<PdfColorResult?> color(
      BuildContext context, PdfColorRequest request) async {
    var sampling = false;
    final picked = await showPdfColorPicker(
      context,
      initial: request.initial,
      initialFormat: request.format,
      onFormatChanged: request.onFormatChanged,
      recentColors: request.recentColors,
      documentColors: request.documentColors,
      onPickFromPage:
          request.allowSampleFromPage ? () => sampling = true : null,
    );
    if (sampling) return const PdfColorResult.sampleFromPage();
    return picked == null ? null : PdfColorResult.picked(picked);
  }

  /// Asks for a font from [PdfFontRequest.entries], the catalogue the
  /// font menu built (document, standard, bundled and platform fonts, and
  /// "Load font…"). The caller loads and applies the [PdfFontChoice].
  /// Default: the stock searchable font picker dialog.
  Future<PdfFontChoice?> font(BuildContext context, PdfFontRequest request) =>
      pdfShowStockFontPicker(context, request);

  /// Asks which option(s) a choice (combo/list box) form field takes,
  /// resolving to the field's new selection: one export value for a
  /// single-select field, the full set for a multi-select one. Default: a
  /// popup [menu] of the options at [PdfFormChoiceRequest.anchor], where a
  /// pick toggles one option of a multi-select field.
  Future<List<String>?> formChoice(
          BuildContext context, PdfFormChoiceRequest request) =>
      pdfStockFormChoice(this, context, request);

  /// Asks for the drawing scale the measurement tools use. Default:
  /// [showPdfScaleDialog].
  Future<PdfMeasurementScale?> measurementScale(
          BuildContext context, PdfMeasurementScaleRequest request) =>
      showPdfScaleDialog(context,
          initial: request.initial, onCalibrate: request.onCalibrate);

  /// Asks for a number a measurement tool needs to finish: the real length
  /// of a calibration segment, or a volume's depth. Default:
  /// [showPdfCalibrationLengthDialog] / [showPdfDepthDialog].
  Future<PdfMeasurementInput?> measurementInput(
      BuildContext context, PdfMeasurementInputRequest request) async {
    switch (request.kind) {
      case PdfMeasurementInputKind.calibrationLength:
        final result = await showPdfCalibrationLengthDialog(context,
            initialUnit: request.unit);
        if (result == null) return null;
        return PdfMeasurementInput(result.$1, unit: result.$2);
      case PdfMeasurementInputKind.depth:
        final depth =
            await showPdfDepthDialog(context, unitLabel: request.unit);
        return depth == null
            ? null
            : PdfMeasurementInput(depth, unit: request.unit);
    }
  }

  /// Asks for an inclusive, 0-based page range. Default:
  /// [showPdfPageRangeDialog].
  Future<({int start, int end})?> pageRange(
          BuildContext context, PdfPageRangeRequest request) =>
      showPdfPageRangeDialog(context,
          pageCount: request.pageCount,
          initialStart: request.initialStart,
          initialEnd: request.initialEnd,
          title: request.title,
          confirmLabel: request.confirmLabel);

  /// Asks for the page ranges to split a document into. Default:
  /// [showPdfSplitDialog].
  Future<List<PdfPageRange>?> splitRanges(
          BuildContext context, PdfSplitRangesRequest request) =>
      showPdfSplitDialog(context, pageCount: request.pageCount);

  /// Asks the user to draw a signature. Default: [showPdfSignatureDialog].
  Future<PdfInkSignature?> signature(
          BuildContext context, PdfSignatureRequest request) =>
      showPdfSignatureDialog(context,
          initialColor: request.initialColor,
          initialStrokeWidth: request.initialStrokeWidth,
          pickColor: request.pickColor);
}

/// Carries a [PdfEditorPresenter] to the editor widgets below it.
///
/// An [InheritedTheme]: [showPdfDialog], popup menus and bottom sheets carry
/// it into their routes, so prompts opened from inside a dialog find it.
/// `PdfEditorView`, `PdfViewer` and `PdfReader` install one from their
/// `presenter` argument; put one above them yourself to share a presenter
/// across editors (or to reach the stock prompts from your own screens).
class PdfEditorScope extends InheritedTheme {
  /// Provides [presenter] to [child].
  const PdfEditorScope({
    super.key,
    required this.presenter,
    required super.child,
  });

  /// The presenter the editor widgets below use.
  final PdfEditorPresenter presenter;

  /// The nearest scope above [context], or null. With [listen] (the
  /// default) [context] rebuilds when the scope's presenter changes.
  static PdfEditorScope? maybeOf(BuildContext context, {bool listen = true}) =>
      listen
          ? context.dependOnInheritedWidgetOfExactType<PdfEditorScope>()
          : context.getInheritedWidgetOfExactType<PdfEditorScope>();

  @override
  Widget wrap(BuildContext context, Widget child) =>
      PdfEditorScope(presenter: presenter, child: child);

  @override
  bool updateShouldNotify(PdfEditorScope oldWidget) =>
      !identical(presenter, oldWidget.presenter);
}

// ---- requests and results -------------------------------------------------

/// What [PdfEditorPresenter.dialog] shows.
@immutable
class PdfDialogRequest<T> {
  /// A dialog built by [builder].
  const PdfDialogRequest({
    required this.builder,
    this.barrierDismissible = true,
  });

  /// Builds the dialog's content (a whole dialog, e.g. an alert dialog).
  /// Pop the route with the result.
  final WidgetBuilder builder;

  /// Whether tapping outside dismisses the dialog (resolving to null).
  final bool barrierDismissible;
}

/// What [PdfEditorPresenter.sheet] shows.
@immutable
class PdfSheetRequest<T> {
  /// A bottom sheet built by [builder].
  const PdfSheetRequest({
    required this.builder,
    this.scrollControlled = false,
    this.maxHeightFactor,
    this.showDragHandle = true,
  });

  /// Builds the sheet's content. Pop the route with the result.
  final WidgetBuilder builder;

  /// Whether the sheet may grow past half the screen's height (its content
  /// scrolls itself).
  final bool scrollControlled;

  /// The sheet's maximum height as a fraction of the screen's, or null for
  /// the presenter's default.
  final double? maxHeightFactor;

  /// Whether the sheet shows a drag handle.
  final bool showDragHandle;
}

/// What [PdfEditorPresenter.menu] shows: [entries] anchored at [anchor].
@immutable
class PdfMenuRequest<T> {
  /// A menu anchored at [anchor], a rectangle in global coordinates (the
  /// control that opened it, or a zero-size rectangle at a pointer).
  const PdfMenuRequest({required this.anchor, required this.entries});

  /// A menu at [globalPosition] (a right-click, say).
  factory PdfMenuRequest.at(Offset globalPosition,
          {required List<PdfMenuEntry<T>> entries}) =>
      PdfMenuRequest(anchor: globalPosition & Size.zero, entries: entries);

  /// Where the menu opens, in global coordinates.
  final Rect anchor;

  /// The rows, in order.
  final List<PdfMenuEntry<T>> entries;
}

/// One row of a [PdfMenuRequest]: a [PdfMenuItem] or a [PdfMenuDivider].
@immutable
abstract class PdfMenuEntry<T> {
  /// Abstract const constructor.
  const PdfMenuEntry();
}

/// A rule between groups of [PdfMenuItem]s.
class PdfMenuDivider<T> extends PdfMenuEntry<T> {
  /// A divider.
  const PdfMenuDivider();
}

/// A pickable (or, while not [enabled], greyed) menu row.
class PdfMenuItem<T> extends PdfMenuEntry<T> {
  /// A row showing [label] (and [icon]) that resolves the menu to [value].
  const PdfMenuItem({
    this.key,
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
    this.checked,
    this.child,
    this.height,
    this.padding,
  });

  /// The row's key - the stock menu puts it on its row (tests find rows by
  /// these `pdf-*` keys).
  final Key? key;

  /// What the menu resolves to when this row is picked. Null for a row that
  /// is not a choice (a section label, an embedded control).
  final T? value;

  /// The row's text.
  final String label;

  /// The row's leading icon, if any.
  final IconData? icon;

  /// Whether the row can be picked.
  final bool enabled;

  /// For a checkable row (a multi-select option), whether it is checked;
  /// null for an ordinary row.
  final bool? checked;

  /// How the stock menu draws this row. Presenters drawing their own menus
  /// use [label], [icon] and [checked] instead - except for a row whose
  /// [value] is null: that is content, not a choice (a section label, or an
  /// embedded control such as the form field text-style popup), so draw its
  /// [child] when there is one.
  final Widget? child;

  /// The stock menu's row height, or null for its default.
  final double? height;

  /// The stock menu's row padding, or null for its default.
  final EdgeInsets? padding;
}

/// What a [PdfEditorNotice] is about.
enum PdfNoticeKind {
  /// Plain information (a hint, a count).
  info,

  /// An action finished (saved to stamps, colours replaced, flattened).
  success,

  /// Something could not be done (invalid input, a failed import).
  error,
}

/// Where the stock presenter puts a notice. Custom presenters may ignore it.
enum PdfNoticePlacement {
  /// Floating, lifted clear of the editor's bottom toolbar dock.
  aboveToolbar,

  /// Floating at the presenter's default spot.
  floating,

  /// Attached to the bottom edge.
  attached,
}

/// A transient, non-blocking message ([PdfEditorPresenter.notice]).
@immutable
class PdfEditorNotice {
  /// A notice reading [message].
  const PdfEditorNotice(
    this.message, {
    this.kind = PdfNoticeKind.info,
    this.onUndo,
    this.duration,
    this.replaceCurrent = true,
    this.showClose = false,
    this.placement = PdfNoticePlacement.aboveToolbar,
    this.key,
  });

  /// The text to show.
  final String message;

  /// What the notice reports.
  final PdfNoticeKind kind;

  /// Reverts the action the notice reports, when it can be undone; the
  /// notice offers an Undo action that calls it.
  final VoidCallback? onUndo;

  /// How long the notice stays, or null for the presenter's default.
  final Duration? duration;

  /// Whether the notice replaces any notice still showing (rather than
  /// queueing behind it).
  final bool replaceCurrent;

  /// Whether the notice offers an explicit close button (a long notice).
  final bool showClose;

  /// Where the stock presenter shows it.
  final PdfNoticePlacement placement;

  /// A key for the shown notice.
  final Key? key;
}

/// What [PdfEditorPresenter.text] asks for.
@immutable
class PdfTextRequest {
  /// Asks for text under [title], pre-filled with [initial].
  const PdfTextRequest({
    required this.title,
    this.initial = '',
    this.multiline = false,
  });

  /// The prompt's title.
  final String title;

  /// The text the field starts with.
  final String initial;

  /// Whether the answer may span several lines.
  final bool multiline;
}

/// What [PdfEditorPresenter.styledText] asks for.
@immutable
class PdfStyledTextRequest {
  /// Asks for a replacement for [initial] plus its style.
  const PdfStyledTextRequest({
    required this.initial,
    this.palette = defaultStyledTextPalette,
    this.pickFont,
  });

  /// The text being replaced.
  final String initial;

  /// The colours offered for the text.
  final List<Color> palette;

  /// Opens the editor's font menu, when the prompt offers a font choice.
  final PdfStyledFontPicker? pickFont;
}

/// What [PdfEditorPresenter.confirm] asks.
@immutable
class PdfConfirmRequest {
  /// Asks [message] under [title]; [confirmLabel] names the action.
  const PdfConfirmRequest({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.destructive = false,
    this.key,
    this.confirmKey,
  });

  /// The question's title.
  final String title;

  /// The question.
  final String message;

  /// The confirming action's label ("Remove", "Apply").
  final String confirmLabel;

  /// Whether confirming destroys something (presenters may colour it).
  final bool destructive;

  /// A key for the stock dialog.
  final Key? key;

  /// A key for the stock dialog's confirm button.
  final Key? confirmKey;
}

/// What [PdfEditorPresenter.link] asks for.
@immutable
class PdfLinkRequest {
  /// Asks for a link target in a [pageCount]-page document.
  const PdfLinkRequest({
    required this.pageCount,
    required this.currentPage,
    this.initialUrl = '',
  });

  /// The document's page count (bounds a page target).
  final int pageCount;

  /// The zero-based page the link is placed on.
  final int currentPage;

  /// A web address to pre-fill.
  final String initialUrl;
}

/// What [PdfEditorPresenter.color] asks for.
@immutable
class PdfColorRequest {
  /// Asks for a colour, starting from [initial].
  const PdfColorRequest({
    required this.initial,
    this.format = PdfColorFormat.hex,
    this.onFormatChanged,
    this.recentColors = const [],
    this.documentColors = const [],
    this.allowSampleFromPage = false,
  });

  /// The colour the picker starts on.
  final Color initial;

  /// The value-entry format to show.
  final PdfColorFormat format;

  /// Remembers a format change.
  final ValueChanged<PdfColorFormat>? onFormatChanged;

  /// Recently used colours, newest first.
  final List<Color> recentColors;

  /// Colours already used in the document.
  final List<Color> documentColors;

  /// Whether the picker may answer [PdfColorResult.sampleFromPage] - the
  /// page is reachable (the picker is not nested in another modal).
  final bool allowSampleFromPage;
}

/// The answer to a [PdfColorRequest]: a picked [color], or a request to
/// sample one off the page.
@immutable
class PdfColorResult {
  /// The user chose [color].
  const PdfColorResult.picked(Color this.color);

  /// The user wants the eyedropper: the caller samples a page colour and
  /// asks again with it.
  const PdfColorResult.sampleFromPage() : color = null;

  /// The picked colour; null for [PdfColorResult.sampleFromPage].
  final Color? color;

  /// Whether this asks for the eyedropper.
  bool get samplesFromPage => color == null;
}

/// What [PdfEditorPresenter.font] asks for: one of [entries] (or [recent]).
@immutable
class PdfFontRequest {
  /// Asks for one of [entries].
  const PdfFontRequest({required this.entries, this.recent = const []});

  /// The catalogue, in order, grouped by [PdfFontCatalogEntry.section].
  final List<PdfFontCatalogEntry> entries;

  /// Recently picked entries (copies of catalogue entries), newest first.
  final List<PdfFontCatalogEntry> recent;
}

/// What [PdfEditorPresenter.formChoice] asks for.
@immutable
class PdfFormChoiceRequest {
  /// Asks for the selection of the choice field [fieldName].
  const PdfFormChoiceRequest({
    required this.fieldName,
    required this.options,
    required this.anchor,
    this.multiSelect = false,
    this.selected = const {},
    this.compact = true,
    this.optionKeyPrefix = 'pdf-form-option-',
  });

  /// The field's fully qualified name.
  final String fieldName;

  /// The options as `(export value, display text)`.
  final List<(String, String)> options;

  /// Where the choice opens, in global coordinates.
  final Rect anchor;

  /// Whether several options may be selected.
  final bool multiSelect;

  /// The export values selected now.
  final Set<String> selected;

  /// Whether the stock menu uses compact rows.
  final bool compact;

  /// The stock menu keys each option row `'$optionKeyPrefix$export'`.
  final String optionKeyPrefix;
}

/// What [PdfEditorPresenter.measurementScale] asks for.
@immutable
class PdfMeasurementScaleRequest {
  /// Asks for a scale, pre-filled from [initial].
  const PdfMeasurementScaleRequest({this.initial, this.onCalibrate});

  /// The scale in use, if any.
  final PdfMeasurementScale? initial;

  /// Offered as "Calibrate": the presenter dismisses its prompt (resolving
  /// to null) and calls this to measure a known length on the page instead.
  final VoidCallback? onCalibrate;
}

/// Which number a [PdfMeasurementInputRequest] asks for.
enum PdfMeasurementInputKind {
  /// The real-world length of the calibration segment just drawn, and its
  /// unit.
  calibrationLength,

  /// The depth of a volume measurement, in the scale's unit.
  depth,
}

/// What [PdfEditorPresenter.measurementInput] asks for.
@immutable
class PdfMeasurementInputRequest {
  /// Asks for the [kind] of number.
  const PdfMeasurementInputRequest({required this.kind, this.unit});

  /// Which number.
  final PdfMeasurementInputKind kind;

  /// For a calibration length, the unit to pre-select; for a depth, the
  /// unit it is in.
  final String? unit;
}

/// The answer to a [PdfMeasurementInputRequest].
@immutable
class PdfMeasurementInput {
  /// [value] in [unit].
  const PdfMeasurementInput(this.value, {this.unit});

  /// The number entered.
  final double value;

  /// Its unit label (the chosen unit for a calibration length).
  final String? unit;
}

/// What [PdfEditorPresenter.pageRange] asks for.
@immutable
class PdfPageRangeRequest {
  /// Asks for a range within [pageCount] pages.
  const PdfPageRangeRequest({
    required this.pageCount,
    this.initialStart,
    this.initialEnd,
    this.title,
    this.confirmLabel,
  });

  /// The document's page count.
  final int pageCount;

  /// The 0-based first page to pre-fill.
  final int? initialStart;

  /// The 0-based last page to pre-fill.
  final int? initialEnd;

  /// The prompt's title (defaults to "Export pages").
  final String? title;

  /// The confirming action's label (defaults to "Export").
  final String? confirmLabel;
}

/// What [PdfEditorPresenter.splitRanges] asks for.
@immutable
class PdfSplitRangesRequest {
  /// Asks how to split a [pageCount]-page document.
  const PdfSplitRangesRequest({required this.pageCount});

  /// The document's page count.
  final int pageCount;
}

/// What [PdfEditorPresenter.signature] asks for.
@immutable
class PdfSignatureRequest {
  /// Asks for a drawn signature.
  const PdfSignatureRequest({
    this.initialColor,
    this.initialStrokeWidth = PdfInkSignature.defaultStrokeWidth,
    this.pickColor,
  });

  /// The ink to start with.
  final Color? initialColor;

  /// The pen width to start with.
  final double initialStrokeWidth;

  /// Picks an arbitrary ink colour; null asks the presenter's [color].
  final PdfSignatureColorPicker? pickColor;
}

// ---- helpers --------------------------------------------------------------
// pdfPresentDialog, pdfPresentColor, pdfApplyFormChoice and
// pdfInstallPresenter are the editor's own plumbing (hidden from the
// library export); the pdfPresent*Prompt adapters are public - they are the
// default values of the older prompt parameters.

/// Shows [builder]'s dialog through the nearest presenter.
Future<T?> pdfPresentDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) =>
    PdfEditorPresenter.of(context).dialog<T>(
        context,
        PdfDialogRequest<T>(
            builder: builder, barrierDismissible: barrierDismissible));

/// Asks the nearest presenter for a colour that cannot be sampled from the
/// page, unwrapping the result.
Future<Color?> pdfPresentColor(
    BuildContext context, PdfColorRequest request) async {
  final result = await PdfEditorPresenter.of(context).color(context, request);
  return result?.color;
}

/// Applies a [PdfEditorPresenter.formChoice] answer: one value for a
/// single-select field, the whole selection for a multi-select one.
void pdfApplyFormChoice(
    PdfEditingController controller, String name, List<String> values) {
  final field = controller.acroForm?.fieldNamed(name);
  if (field == null || !field.isMultiSelect) {
    if (values.isNotEmpty) controller.setFormChoiceValue(name, values.first);
    return;
  }
  controller.setFormChoiceValues(name, values);
}

/// A [PdfTextPrompt] that asks the nearest [PdfEditorPresenter] - the
/// default wherever the editor takes a text prompt.
Future<String?> pdfPresentTextPrompt(
  BuildContext context, {
  required String title,
  String initial = '',
  bool multiline = false,
}) =>
    PdfEditorPresenter.of(context).text(context,
        PdfTextRequest(title: title, initial: initial, multiline: multiline));

/// A [PdfStyledTextPrompt] that asks the nearest [PdfEditorPresenter].
Future<PdfStyledTextEdit?> pdfPresentStyledTextPrompt(
  BuildContext context, {
  required String initial,
  List<Color> palette = defaultStyledTextPalette,
  PdfStyledFontPicker? pickFont,
}) =>
    PdfEditorPresenter.of(context).styledText(
        context,
        PdfStyledTextRequest(
            initial: initial, palette: palette, pickFont: pickFont));

/// A `PdfLinkPrompt` that asks the nearest [PdfEditorPresenter].
Future<PdfLinkTarget?> pdfPresentLinkPrompt(
  BuildContext context, {
  required int pageCount,
  required int currentPage,
  String initialUrl = '',
}) =>
    PdfEditorPresenter.of(context).link(
        context,
        PdfLinkRequest(
            pageCount: pageCount,
            currentPage: currentPage,
            initialUrl: initialUrl));

/// Installs the presenter a root editor widget was given: [presenter] (or
/// the inherited one), with [textPrompt]/[styledTextPrompt] - the older
/// per-widget prompt parameters - taking precedence for this subtree. Always
/// wraps, so the tree's shape does not change with the arguments.
Widget pdfInstallPresenter(
  BuildContext context, {
  PdfEditorPresenter? presenter,
  PdfTextPrompt? textPrompt,
  PdfStyledTextPrompt? styledTextPrompt,
  required Widget child,
}) {
  var effective = presenter ??
      PdfEditorScope.maybeOf(context)?.presenter ??
      const PdfEditorPresenter();
  if (textPrompt != null || styledTextPrompt != null) {
    effective = _PromptOverridePresenter(effective,
        textPrompt: textPrompt, styledTextPrompt: styledTextPrompt);
  }
  return PdfEditorScope(presenter: effective, child: child);
}

/// [base], except that [textPrompt]/[styledTextPrompt] answer the text
/// prompts. Forwards every method so [base]'s overrides keep working.
class _PromptOverridePresenter extends PdfEditorPresenter {
  const _PromptOverridePresenter(this.base,
      {this.textPrompt, this.styledTextPrompt});

  final PdfEditorPresenter base;
  final PdfTextPrompt? textPrompt;
  final PdfStyledTextPrompt? styledTextPrompt;

  @override
  Future<String?> text(BuildContext context, PdfTextRequest request) {
    final prompt = textPrompt;
    if (prompt == null) return base.text(context, request);
    return prompt(context,
        title: request.title,
        initial: request.initial,
        multiline: request.multiline);
  }

  @override
  Future<PdfStyledTextEdit?> styledText(
      BuildContext context, PdfStyledTextRequest request) {
    final prompt = styledTextPrompt;
    if (prompt == null) return base.styledText(context, request);
    return prompt(context,
        initial: request.initial,
        palette: request.palette,
        pickFont: request.pickFont);
  }

  @override
  Future<T?> dialog<T>(BuildContext context, PdfDialogRequest<T> request) =>
      base.dialog<T>(context, request);

  @override
  Future<T?> sheet<T>(BuildContext context, PdfSheetRequest<T> request) =>
      base.sheet<T>(context, request);

  @override
  Future<T?> menu<T>(BuildContext context, PdfMenuRequest<T> request) =>
      base.menu<T>(context, request);

  @override
  bool notice(BuildContext context, PdfEditorNotice notice) =>
      base.notice(context, notice);

  @override
  Future<bool> confirm(BuildContext context, PdfConfirmRequest request) =>
      base.confirm(context, request);

  @override
  Future<PdfLinkTarget?> link(BuildContext context, PdfLinkRequest request) =>
      base.link(context, request);

  @override
  Future<PdfColorResult?> color(
          BuildContext context, PdfColorRequest request) =>
      base.color(context, request);

  @override
  Future<PdfFontChoice?> font(BuildContext context, PdfFontRequest request) =>
      base.font(context, request);

  @override
  Future<List<String>?> formChoice(
          BuildContext context, PdfFormChoiceRequest request) =>
      base.formChoice(context, request);

  @override
  Future<PdfMeasurementScale?> measurementScale(
          BuildContext context, PdfMeasurementScaleRequest request) =>
      base.measurementScale(context, request);

  @override
  Future<PdfMeasurementInput?> measurementInput(
          BuildContext context, PdfMeasurementInputRequest request) =>
      base.measurementInput(context, request);

  @override
  Future<({int start, int end})?> pageRange(
          BuildContext context, PdfPageRangeRequest request) =>
      base.pageRange(context, request);

  @override
  Future<List<PdfPageRange>?> splitRanges(
          BuildContext context, PdfSplitRangesRequest request) =>
      base.splitRanges(context, request);

  @override
  Future<PdfInkSignature?> signature(
          BuildContext context, PdfSignatureRequest request) =>
      base.signature(context, request);
}
