import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:pdf_document/pdf_document.dart';

import '../l10n/pdf_l10n.dart';
import 'annotation_presentation.dart';
import 'editing_controller.dart';
import 'editing_table.dart';
import 'editing_color_processing.dart';
import 'editing_form_options.dart';
import 'editing_form_style.dart';
import 'text_prompt.dart';
import '../design/editor_presenter.dart';

const _densePopupMenuHeight = 34.0;

TextStyle? _densePopupTextStyle(BuildContext context, {Color? color}) =>
    Theme.of(context).textTheme.labelMedium?.copyWith(
          color: color,
          height: 1.1,
        );

/// What an annotation context menu acts on: the controller and the
/// selection at the moment the menu opened. The right-clicked annotation
/// is always part of the selection (the viewer selects it before the
/// menu shows); a right-click on an already-selected annotation keeps a
/// multi-selection intact, so [annotations] can hold several entries.
class PdfAnnotationMenuRequest {
  PdfAnnotationMenuRequest._(this.controller, this.pageIndex)
      : slots = controller.selectedAnnotationSlots,
        annotations = [
          for (final (page, slot) in controller.selectedAnnotationSlots)
            if (controller.annotationAt(page, slot) case final annotation?)
              annotation
        ];

  final PdfEditingController controller;

  /// The page the menu was opened on (where the right-click landed).
  final int pageIndex;

  /// The selected (page, /Annots slot) pairs, primary last.
  final List<(int page, int slot)> slots;

  /// The selected annotations, in [slots] order.
  final List<PdfAnnotation> annotations;

  /// The primary selected annotation - the one right-clicked, when the
  /// click started a fresh selection.
  PdfAnnotation? get primary => annotations.isEmpty ? null : annotations.last;
}

/// One entry in the annotation context menu. Hosts add their own through
/// [PdfViewer.annotationMenuBuilder]; the stock entries (z-order, delete)
/// are built the same way internally.
class PdfAnnotationMenuItem {
  const PdfAnnotationMenuItem({
    this.key,
    required this.label,
    this.icon,
    this.enabled = true,
    required this.onSelected,
  });

  /// Optional key on the menu row, for tests.
  final Key? key;

  final String label;
  final IconData? icon;
  final bool enabled;

  /// Runs when the entry is picked. The request carries the controller
  /// and the selection the menu was opened on.
  final FutureOr<void> Function(PdfAnnotationMenuRequest request) onSelected;
}

/// Builds the host's extra context-menu entries for the current
/// selection. Returning an empty list adds nothing; the stock entries
/// always come first, with a divider before the custom ones.
typedef PdfAnnotationMenuBuilder = List<PdfAnnotationMenuItem> Function(
    BuildContext context, PdfAnnotationMenuRequest request);

/// What a text-selection context menu acts on: the editing session (null
/// in a plain reader), the page the menu opened on, and the text selection
/// as it stood the moment the menu opened.
///
/// The quads are the ones a text markup would use, so a host entry can
/// build a `/Link`, a `/Highlight`, or its own annotation from the same
/// geometry the stock entries do - see
/// [PdfViewerController.selectionRectsOn], which is where they come from.
class PdfTextMenuRequest {
  const PdfTextMenuRequest({
    required this.controller,
    required this.pageIndex,
    required this.selectedText,
    required this.selectionPages,
    required this.quadsByPage,
    required this.pagePoint,
  });

  /// The editing session behind the viewer, or null in a plain reader -
  /// a host entry that writes to the document must handle both.
  final PdfEditingController? controller;

  /// The page the menu was opened on (where the right-click landed).
  final int pageIndex;

  /// The selected text, empty when the click found no word to select
  /// (the menu still opens for Select all).
  final String selectedText;

  /// Pages the selection touches, in document order; empty without a
  /// selection.
  final List<int> selectionPages;

  /// The selection's rectangles per page, in PDF page coordinates -
  /// ready to use as the quads of a text-markup or `/Link` annotation.
  /// Keyed by the entries of [selectionPages].
  final Map<int, List<PdfRect>> quadsByPage;

  /// Where on [pageIndex] the menu was opened, in PDF page coordinates.
  final (double, double) pagePoint;

  /// Whether the menu opened on a text selection. Host entries that act
  /// on text should disable themselves when this is false.
  bool get hasSelection => selectedText.isNotEmpty;
}

/// One host entry in the text-selection context menu. The stock entries
/// (markup, Copy, Select all) are built internally and always come first.
class PdfTextMenuItem {
  const PdfTextMenuItem({
    this.key,
    required this.label,
    this.icon,
    this.enabled = true,
    required this.onSelected,
  });

  /// Optional key on the menu row, for tests.
  final Key? key;

  final String label;
  final IconData? icon;
  final bool enabled;

  /// Runs when the entry is picked, with the request the menu was built
  /// from - the selection it names is the one the user right-clicked,
  /// even if the viewer's live selection has moved on since.
  final FutureOr<void> Function(PdfTextMenuRequest request) onSelected;
}

/// Builds the host's extra entries for the text-selection context menu -
/// the [PdfAnnotationMenuBuilder] of the text menu. Returning an empty
/// list adds nothing; the stock entries always come first, with a divider
/// before the custom ones.
///
/// Called every time the menu opens, including when nothing is selected
/// (a right-click that found no word, where only Select all is live), so
/// entries that need text should key off [PdfTextMenuRequest.hasSelection]
/// rather than assume one.
typedef PdfTextMenuBuilder = List<PdfTextMenuItem> Function(
    BuildContext context, PdfTextMenuRequest request);

/// Rewrites a context menu's rows: receives the [stock] rows - the stock
/// entries, then any [PdfAnnotationMenuBuilder] additions, with dividers -
/// and returns the rows to show. Drop, reorder or add rows; find stock ones
/// by [PdfMenuEntry.id] (`pdf-annot-menu-delete`, ...) and build new ones
/// with [pdfAnnotationMenuEntry]:
///
/// ```dart
/// annotationMenuEntries: (context, request, stock) => [
///   ...stock.where((e) => e.id != 'pdf-annot-menu-flatten'),
///   const PdfMenuDivider(),
///   pdfAnnotationMenuEntry(PdfAnnotationMenuItem(
///       label: 'Share', onSelected: (request) => share(request.primary))),
/// ],
/// ```
///
/// Returning an empty list keeps the menu from opening.
typedef PdfAnnotationMenuEntriesBuilder
    = List<PdfMenuEntry<PdfAnnotationMenuItem>> Function(
        BuildContext context,
        PdfAnnotationMenuRequest request,
        List<PdfMenuEntry<PdfAnnotationMenuItem>> stock);

/// [PdfAnnotationMenuEntriesBuilder] for the text-selection context menu;
/// build new rows with [pdfTextMenuEntry]. Stock ids are `pdf-text-menu-*`
/// (`edit`, `copy`, `markup`, `link`, `select-all`), in the touch selection
/// chip's order; `markup` opens the `highlight`, `underline`, `strikeout`
/// and `squiggly` rows as a second menu, so they are not in [stock].
typedef PdfTextMenuEntriesBuilder
    = List<PdfMenuEntry<PdfTextMenuItem>> Function(BuildContext context,
        PdfTextMenuRequest request, List<PdfMenuEntry<PdfTextMenuItem>> stock);

/// What the form tool's field context menu acts on.
class PdfFormFieldMenuRequest {
  /// The menu for [fieldName] in [controller]'s form.
  const PdfFormFieldMenuRequest({
    required this.controller,
    required this.fieldName,
    this.widgetIndex,
  });

  /// The editing session.
  final PdfEditingController controller;

  /// The field's fully qualified name.
  final String fieldName;

  /// The field widget the menu opened on (a radio button), when known.
  final int? widgetIndex;
}

/// [PdfAnnotationMenuEntriesBuilder] for the form tool's field menu. Stock
/// ids are `pdf-form-menu-*` (`edit`, `style`, `options`, `add-radio`,
/// `rename`, `text`, `checkbox`, `button`, `radio`, `combo`, `list`,
/// `signature`, `delete`, `flatten`).
typedef PdfFormFieldMenuEntriesBuilder
    = List<PdfMenuEntry<PdfAnnotationMenuItem>> Function(
        BuildContext context,
        PdfFormFieldMenuRequest request,
        List<PdfMenuEntry<PdfAnnotationMenuItem>> stock);

/// A row for an annotation or form-field context menu, drawn like the stock
/// rows (dense, a 16px icon) - for [PdfAnnotationMenuEntriesBuilder]s.
PdfMenuItem<PdfAnnotationMenuItem> pdfAnnotationMenuEntry(
        PdfAnnotationMenuItem item) =>
    _menuRow(item);

/// A row for the text-selection context menu, drawn like the stock rows -
/// for [PdfTextMenuEntriesBuilder]s.
PdfMenuItem<PdfTextMenuItem> pdfTextMenuEntry(PdfTextMenuItem item) =>
    PdfMenuItem<PdfTextMenuItem>(
      key: item.key,
      value: item,
      label: item.label,
      icon: item.icon,
      enabled: item.enabled,
      child: Row(
        children: [
          if (item.icon != null) ...[
            Builder(
              builder: (context) => Icon(item.icon,
                  size: 18,
                  color: item.enabled ? null : Theme.of(context).disabledColor),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(child: Text(item.label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );

/// Shows the annotation context menu at [position] (global coordinates)
/// for [controller]'s current selection: copy/cut/apply-to-pages/paste,
/// group/ungroup, bring to front, send to back, add/remove node (a single /PolyLine or
/// /Polygon, when [pagePoint] is known), delete, then whatever
/// [customActions] adds. Resolves when the menu closes, after the picked
/// action ran.
///
/// [pagePoint] is where on the page the menu was opened (page space) -
/// Paste centers the clipboard there; without it the paste falls back
/// to [PdfEditingController.pasteAnnotations]' cascade. With nothing
/// selected - the empty-area right-click or long-press - the menu offers
/// page actions instead: Paste when the clipboard has content, and, when
/// [pagePoint] is known, Add note here plus Select all (when
/// [onSelectAllText] is given). [entriesBuilder] rewrites the rows last (see
/// [PdfAnnotationMenuEntriesBuilder]).
/// [onSaveImage] adds Save as image for one selected vector snapshot.
/// [linkTarget] names a /Link under the press (page, /Annots slot - see
/// [PdfEditingController.linkAnnotationAt]); it adds Edit link and Remove
/// link, since a link can't be selected (a click follows it).
Future<void> showPdfAnnotationMenu({
  required BuildContext context,
  required Offset position,
  required PdfEditingController controller,
  required int pageIndex,
  PdfAnnotationMenuBuilder? customActions,
  PdfAnnotationMenuEntriesBuilder? entriesBuilder,
  PdfTextPrompt textPrompt = pdfPresentTextPrompt,
  // When supplied, the host can read a system clipboard on the user's Paste
  // action. No clipboard permissions are requested merely to open the menu.
  VoidCallback? onPaste,
  (double, double)? pagePoint,
  (int page, int slot)? unlockTarget,
  PdfSelectedContentImageHandler? onSaveImage,
  VoidCallback? onSelectAllText,
  (int page, int slot)? linkTarget,
}) async {
  final request = PdfAnnotationMenuRequest._(controller, pageIndex);
  // a captured snapshot pastes back as vector graphics; otherwise the
  // annotation clipboard (the most recent copy wins)
  final canPasteSnapshot = controller.hasSnapshotClipboard;
  final canPaste =
      onPaste != null || canPasteSnapshot || controller.hasAnnotationClipboard;
  final hasSelection = request.annotations.isNotEmpty;
  // A locked annotation can't be selected, so a right-click on one opens
  // an Unlock-only menu instead ([unlockTarget]); it stands alone from the
  // selection/paste entries.
  //
  // A press on empty page area always has somewhere to go: the page actions
  // below. Without them a long-press there looked like it did nothing.
  final onEmptyPage =
      !hasSelection && unlockTarget == null && pagePoint != null;
  if (!hasSelection &&
      !canPaste &&
      !onEmptyPage &&
      unlockTarget == null &&
      linkTarget == null) {
    return;
  }

  // The stock entries are grouped so [_menuRowsWithDividers] can rule off
  // each cluster: unlock, clipboard, z-order arrange, node editing,
  // recolour, then the destructive lock/delete. Empty groups drop out and
  // no divider is drawn for them, so a small selection still reads as a
  // tight menu.
  final unlock = <PdfAnnotationMenuItem>[
    if (unlockTarget != null)
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-unlock'),
        label: pdfL10n(context).menuUnlock,
        icon: Icons.lock_open_outlined,
        onSelected: (request) => request.controller
            .setAnnotationLocked(unlockTarget.$1, unlockTarget.$2, false),
      ),
  ];
  final link = <PdfAnnotationMenuItem>[
    if (linkTarget != null) ...[
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-edit-link'),
        label: pdfL10n(context).menuEditLink,
        icon: Icons.edit_outlined,
        onSelected: (request) async {
          final (linkPage, slot) = linkTarget;
          final current = request.controller.linkTargetAt(linkPage, slot);
          final target = await PdfEditorPresenter.of(context).link(
              context,
              PdfLinkRequest(
                pageCount: request.controller.document.pageCount,
                currentPage: linkPage,
                initialUrl: current?.uri ?? '',
                initialPage: current?.page,
                editing: true,
              ));
          if (target == null) return;
          request.controller.editLink(linkPage, slot, target);
        },
      ),
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-remove-link'),
        label: pdfL10n(context).menuRemoveLink,
        icon: Icons.link_off,
        onSelected: (request) =>
            request.controller.deleteAnnotation(linkTarget.$1, linkTarget.$2),
      ),
    ],
  ];
  final selectedTable = controller.selectedAnnotation?.table;
  final clipboard = <PdfAnnotationMenuItem>[
    if (hasSelection &&
        selectedTable != null &&
        controller.selectedAnnotationSlots.length == 1)
      PdfAnnotationMenuItem(
          key: const ValueKey('pdf-annot-menu-edit-table'),
          label: pdfL10n(context).tableEdit,
          icon: Icons.table_chart_outlined,
          enabled:
              controller.isAnnotationEditable(controller.selectedAnnotation!) &&
                  !controller.selectedAnnotation!.isLockedContents,
          onSelected: (request) => showPdfTableEditor(context,
              controller: controller,
              pageIndex: request.slots.single.$1,
              annotationSlot: request.slots.single.$2)),
    if (hasSelection &&
        selectedTable != null &&
        controller.selectedAnnotationSlots.length == 1)
      PdfAnnotationMenuItem(
          key: const ValueKey('pdf-annot-menu-copy-table-cells'),
          label: '${pdfL10n(context).copy} (Excel)',
          icon: Icons.copy,
          onSelected: (_) =>
              controller.copyTableCellsText(selectedTable.toTsv())),
    if (onEmptyPage)
      PdfAnnotationMenuItem(
          key: const ValueKey('pdf-annot-menu-insert-table'),
          label: pdfL10n(context).table,
          icon: Icons.table_chart_outlined,
          onSelected: (_) => showPdfTableEditor(context,
              controller: controller,
              pageIndex: pageIndex,
              position: pagePoint)),
    if (hasSelection) ...[
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-copy'),
        label: pdfL10n(context).copy,
        icon: Icons.copy,
        onSelected: (request) => request.controller.copySelectedAnnotations(),
      ),
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-cut'),
        label: pdfL10n(context).cut,
        icon: Icons.cut,
        onSelected: (request) => request.controller.cutSelectedAnnotations(),
      ),
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-apply-pages'),
        label: pdfL10n(context).menuApplyToPages,
        icon: Icons.copy_all_outlined,
        onSelected: (request) async {
          final pageCount = request.controller.document.pageCount;
          final range = await PdfEditorPresenter.of(context).pageRange(
            context,
            PdfPageRangeRequest(
              pageCount: pageCount,
              title: pdfL10n(context)
                  .menuApplyAnnotationsToPagesTitle(request.annotations.length),
              confirmLabel: pdfL10n(context).apply,
            ),
          );
          if (range == null) return;
          request.controller.applySelectedAnnotationsToPages(
            Iterable<int>.generate(
              range.end - range.start + 1,
              (i) => range.start + i,
            ),
          );
        },
      ),
    ],
    // Paste rides the selection/clipboard menu; it stays out of the
    // standalone Unlock menu (no selection, no clipboard).
    if (canPaste || hasSelection)
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-paste'),
        label: pdfL10n(context).paste,
        icon: Icons.paste,
        enabled: canPaste,
        onSelected: (request) {
          if (onPaste != null) {
            onPaste();
          } else if (canPasteSnapshot) {
            request.controller.pasteSnapshot(pageIndex, at: pagePoint);
          } else {
            request.controller.pasteAnnotations(pageIndex, at: pagePoint);
          }
        },
      ),
  ];
  final notePoint = onEmptyPage ? pagePoint : null;
  final page = <PdfAnnotationMenuItem>[
    if (notePoint != null) ...[
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-add-note'),
        label: pdfL10n(context).menuAddNoteHere,
        icon: Icons.sticky_note_2_outlined,
        onSelected: (request) async {
          final text = await textPrompt(context,
              title: pdfL10n(context).overlayNote, multiline: true);
          if (text == null || text.isEmpty) return;
          request.controller
              .addNote(pageIndex, notePoint.$1, notePoint.$2, text);
        },
      ),
      if (onSelectAllText != null)
        PdfAnnotationMenuItem(
          key: const ValueKey('pdf-annot-menu-select-all-text'),
          label: pdfL10n(context).viewerSelectAll,
          icon: Icons.select_all,
          onSelected: (_) => onSelectAllText(),
        ),
    ],
  ];
  final arrange = <PdfAnnotationMenuItem>[
    if (hasSelection) ...[
      if (request.slots.length > 1)
        PdfAnnotationMenuItem(
          key: const ValueKey('pdf-annot-menu-group'),
          label: pdfL10n(context).menuGroup,
          icon: Icons.group_work_outlined,
          enabled: controller.canGroupSelectedAnnotations,
          onSelected: (request) =>
              request.controller.groupSelectedAnnotations(),
        ),
      if (controller.canUngroupSelectedAnnotations)
        PdfAnnotationMenuItem(
          key: const ValueKey('pdf-annot-menu-ungroup'),
          label: pdfL10n(context).menuUngroup,
          icon: Icons.workspaces_outline,
          onSelected: (request) =>
              request.controller.ungroupSelectedAnnotations(),
        ),
      if (request.slots.length > 1 && controller.canRotateSelected)
        for (final mode in PdfAnnotationRotationMode.values)
          PdfAnnotationMenuItem(
            key: ValueKey('pdf-annot-menu-rotate-${mode.name}'),
            label: mode == PdfAnnotationRotationMode.selectionCenter
                ? pdfL10n(context).menuRotateSelection
                : pdfL10n(context).menuRotateEach,
            icon: Icons.rotate_right,
            onSelected: (request) async {
              final value = await textPrompt(context,
                  title: pdfL10n(context).rotationAngleTitle,
                  initial: '90',
                  multiline: false);
              final degrees = double.tryParse(value?.trim() ?? '');
              if (degrees != null && degrees.isFinite) {
                request.controller.rotateSelected(degrees, mode: mode);
              }
            },
          ),
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-front'),
        label: pdfL10n(context).menuBringToFront,
        icon: Icons.flip_to_front,
        enabled: controller.canBringSelectedToFront,
        onSelected: (request) => request.controller.bringSelectedToFront(),
      ),
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-back'),
        label: pdfL10n(context).menuSendToBack,
        icon: Icons.flip_to_back,
        enabled: controller.canSendSelectedToBack,
        onSelected: (request) => request.controller.sendSelectedToBack(),
      ),
    ],
  ];
  final nodes = <PdfAnnotationMenuItem>[
    // A right-click on a /PolyLine or /Polygon can grow or drop a vertex
    // at the click point. Needs the page point the menu opened on; the
    // selection-chip "More" path (no point) hides these.
    if (hasSelection &&
        pagePoint != null &&
        controller.canAddSelectedVertex) ...[
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-add-node'),
        label: pdfL10n(context).menuAddNode,
        icon: Icons.add_location_alt_outlined,
        onSelected: (request) =>
            request.controller.addSelectedVertexAt(pagePoint),
      ),
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-remove-node'),
        label: pdfL10n(context).menuRemoveNode,
        icon: Icons.wrong_location_outlined,
        enabled: controller.canRemoveSelectedVertex,
        onSelected: (request) =>
            request.controller.removeSelectedVertexNear(pagePoint),
      ),
    ],
    // A measurement takes the value the drawing says, typed over the one
    // the scale computes; a blank answer goes back to the computed value.
    if (hasSelection && controller.canEditSelectedMeasurementValue)
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-measurement-value'),
        label: pdfL10n(context).menuEditMeasurementValue,
        icon: Icons.edit_note,
        onSelected: (request) async {
          final value = await textPrompt(
            context,
            title: pdfL10n(context).measCustomValueTitle,
            initial: request.controller.selectedMeasurementValue ?? '',
            multiline: false,
          );
          if (value != null) {
            request.controller.setSelectedMeasurementValue(value);
          }
        },
      ),
    // A callout grows another arrow from the same box (aimed just off the
    // box, ready to drag by its tip) or drops the one nearest the click -
    // the last one when the menu has no click point. One always stays.
    if (hasSelection && controller.canAddSelectedCalloutLeader) ...[
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-add-leader'),
        label: pdfL10n(context).menuAddLeader,
        icon: Icons.call_made,
        onSelected: (request) => request.controller.addSelectedCalloutLeader(),
      ),
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-remove-leader'),
        label: pdfL10n(context).menuRemoveLeader,
        icon: Icons.remove_circle_outline,
        enabled: controller.canRemoveSelectedCalloutLeader,
        onSelected: (request) => request.controller.removeSelectedCalloutLeader(
            pagePoint == null
                ? null
                : request.controller.selectedCalloutLeaderNear(pagePoint)),
      ),
    ],
  ];
  final recolor = <PdfAnnotationMenuItem>[
    if (hasSelection && controller.canCropSelected)
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-crop-snapshot'),
        label: pdfL10n(context).tbCropImage,
        icon: Icons.crop,
        onSelected: (request) => request.controller.beginImageCrop(),
      ),
    if (hasSelection && controller.canRecolorSnapshotSelected)
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-recolor-snapshot'),
        label: pdfL10n(context).menuRecolour,
        icon: Icons.palette_outlined,
        onSelected: (request) async {
          await showPdfColorProcessingDialog(
            context,
            controller: request.controller,
            preferences: request.controller.preferences,
            annotationSlots: request.slots,
          );
        },
      ),
    // A pasted snapshot is vector, so it saves as a fresh render at print
    // resolution rather than as the pixels on screen.
    if (hasSelection &&
        onSaveImage != null &&
        controller.canExportSelectedSnapshotImage)
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-save-snapshot-image'),
        label: pdfL10n(context).menuSaveAsImage,
        icon: Icons.download_outlined,
        onSelected: (request) async {
          final image = await request.controller.exportSelectedSnapshotImage();
          if (image == null || !context.mounted) return;
          await onSaveImage(context, image);
        },
      ),
    if (hasSelection && controller.canApplySelectedStyleAsDefault)
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-set-default'),
        label: pdfL10n(context).menuSetAsDefaultStyle,
        icon: Icons.brush_outlined,
        onSelected: (request) =>
            request.controller.applySelectedStyleAsDefault(),
      ),
    // A stamp on the page goes back into the stamp collection, so a design
    // that arrived in a document can be reused like one made in the editor.
    if (hasSelection && controller.canSaveSelectedAsCustomStamp)
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-save-stamp'),
        label: pdfL10n(context).menuSaveToStamps,
        icon: Icons.approval_outlined,
        onSelected: (request) {
          final saved = request.controller.saveSelectedAsCustomStamp();
          if (saved == null || !context.mounted) return;
          PdfEditorPresenter.of(context).notice(
              context,
              PdfEditorNotice(pdfL10n(context).stampSavedToCollection,
                  kind: PdfNoticeKind.success,
                  placement: PdfNoticePlacement.floating));
        },
      ),
    if (hasSelection && controller.canSaveSelectedAnnotation)
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-save-library'),
        label: pdfL10n(context).annotationLibrarySave,
        icon: Icons.collections_bookmark_outlined,
        onSelected: (request) async {
          final annotation = request.primary;
          if (annotation == null) return;
          final name = await textPrompt(
            context,
            title: pdfL10n(context).annotationLibrarySaveTitle,
            initial: pdfAnnotationLabel(context, annotation.subtype),
            multiline: false,
          );
          if (name != null) request.controller.saveSelectedAnnotation(name);
        },
      ),
  ];
  final destructive = <PdfAnnotationMenuItem>[
    if (hasSelection) ...[
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-flatten'),
        label: pdfL10n(context).tbFlattenLabel,
        icon: Icons.layers_clear_outlined,
        enabled: controller.canFlattenSelectedAnnotations,
        onSelected: (request) =>
            request.controller.flattenSelectedAnnotations(),
      ),
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-lock'),
        label: pdfL10n(context).menuLock,
        icon: Icons.lock_outline,
        enabled: controller.canLockSelected,
        onSelected: (request) => request.controller.lockSelectedAnnotations(),
      ),
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-annot-menu-delete'),
        label: pdfL10n(context).delete,
        icon: Icons.delete_outline,
        enabled: true,
        onSelected: (request) => request.controller.deleteSelected(),
      ),
    ],
  ];
  final custom =
      customActions?.call(context, request) ?? const <PdfAnnotationMenuItem>[];

  var entries = _menuRowsWithDividers([
    unlock,
    link,
    clipboard,
    page,
    arrange,
    nodes,
    recolor,
    destructive,
    custom
  ]);
  if (entriesBuilder != null) {
    entries = entriesBuilder(context, request, entries);
    if (entries.isEmpty) return;
  }
  final picked = await PdfEditorPresenter.of(context).menu(
    context,
    PdfMenuRequest<PdfAnnotationMenuItem>.at(position, entries: entries),
  );
  await picked?.onSelected(request);
}

/// Shows the form tool's field context menu at [position] (global
/// coordinates) for the field named [fieldName]: rename, convert to the
/// other creatable kinds, delete, and flatten the whole form, rewritten by
/// [entriesBuilder] when given. Resolves when the menu closes, after the
/// picked action ran.
Future<void> showPdfFormFieldMenu({
  required BuildContext context,
  required Offset position,
  required PdfEditingController controller,
  required String fieldName,
  int? widgetIndex,
  PdfTextPrompt textPrompt = pdfPresentTextPrompt,
  PdfFontPicker? fontPicker,
  PdfFormImagePicker? formImagePicker,
  PdfFormFieldMenuEntriesBuilder? entriesBuilder,
}) async {
  final field = controller.acroForm?.fieldNamed(fieldName);
  if (field == null) return;
  final type = field.type;
  // a signed signature is never retyped (PdfEditor.changeFieldType)
  final signed = type == PdfFieldType.signature &&
      controller.signatureByFieldName.containsKey(fieldName);
  bool convertsTo(PdfFormFieldKind kind) => !signed && kind.fieldType != type;

  PdfAnnotationMenuItem? editItem() {
    final enabled = !field.isReadOnly;
    switch (type) {
      case PdfFieldType.text:
        return PdfAnnotationMenuItem(
          key: const ValueKey('pdf-form-menu-edit'),
          label: pdfL10n(context).menuEditValue,
          icon: Icons.edit_outlined,
          enabled: enabled,
          onSelected: (_) async {
            final value = await textPrompt(context,
                title: pdfL10n(context).menuFieldValue,
                initial: field.isPassword ? '' : field.value ?? '');
            if (value != null) controller.setFormFieldText(fieldName, value);
          },
        );
      case PdfFieldType.checkBox:
        return PdfAnnotationMenuItem(
          key: const ValueKey('pdf-form-menu-edit'),
          label: field.isChecked
              ? pdfL10n(context).menuClearCheck
              : pdfL10n(context).menuCheck,
          icon: field.isChecked
              ? Icons.check_box_outline_blank
              : Icons.check_box_outlined,
          enabled: enabled,
          onSelected: (_) => controller.toggleFormCheckBox(fieldName),
        );
      case PdfFieldType.radioGroup:
        final state =
            widgetIndex == null ? null : field.widgetOnState(widgetIndex);
        return PdfAnnotationMenuItem(
          key: const ValueKey('pdf-form-menu-edit'),
          label: pdfL10n(context).menuSelectOption,
          icon: Icons.radio_button_checked,
          enabled: enabled && state != null && field.value != state,
          onSelected: (_) {
            if (state != null) controller.setFormRadioValue(fieldName, state);
          },
        );
      case PdfFieldType.comboBox || PdfFieldType.listBox:
        return PdfAnnotationMenuItem(
          key: const ValueKey('pdf-form-menu-edit'),
          label: pdfL10n(context).menuChooseValue,
          icon: Icons.list_alt_outlined,
          enabled: enabled && field.options.isNotEmpty,
          onSelected: (_) async {
            final values = await PdfEditorPresenter.of(context).formChoice(
              context,
              PdfFormChoiceRequest(
                fieldName: fieldName,
                options: field.options,
                anchor: position & Size.zero,
                multiSelect: field.isMultiSelect,
                selected: field.values.toSet(),
                optionKeyPrefix: 'pdf-form-edit-option-',
              ),
            );
            if (values != null) {
              pdfApplyFormChoice(controller, fieldName, values);
            }
          },
        );
      case PdfFieldType.pushButton:
        return PdfAnnotationMenuItem(
          key: const ValueKey('pdf-form-menu-edit'),
          label: pdfL10n(context).menuSetImage,
          icon: Icons.image_outlined,
          enabled: enabled && formImagePicker != null,
          onSelected: (_) async {
            final picker = formImagePicker;
            if (picker == null) return;
            final fresh = controller.acroForm?.fieldNamed(fieldName);
            if (fresh == null) return;
            final bytes = await picker(context, fresh);
            if (bytes != null) {
              await controller.setFormButtonImageAsync(fieldName, bytes);
            }
          },
        );
      case PdfFieldType.signature || PdfFieldType.unknown:
        return null;
    }
  }

  // Grouped so [_menuRowsWithDividers] rules off value edits, the
  // rename/convert structure changes, and the destructive delete/flatten.
  final edit = <PdfAnnotationMenuItem>[
    if (editItem() case final item?) item,
    if (type == PdfFieldType.text ||
        type == PdfFieldType.comboBox ||
        type == PdfFieldType.listBox)
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-form-menu-style'),
        label: pdfL10n(context).menuTextStyle,
        icon: Icons.text_format,
        onSelected: (_) async {
          if (!controller.selectFormFieldByName(fieldName)) return;
          if (!context.mounted) return;
          await showPdfFormTextStylePopup(
            context: context,
            position: position,
            controller: controller,
            fontPicker: fontPicker,
          );
        },
      ),
    if (type == PdfFieldType.comboBox || type == PdfFieldType.listBox)
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-form-menu-options'),
        label: pdfL10n(context).menuEditOptions,
        icon: Icons.format_list_bulleted,
        onSelected: (_) => showPdfFormOptionsDialog(
          context: context,
          controller: controller,
          fieldName: fieldName,
        ),
      ),
    if (type == PdfFieldType.radioGroup)
      PdfAnnotationMenuItem(
        key: const ValueKey('pdf-form-menu-add-radio'),
        label: pdfL10n(context).menuAddRadioButton,
        icon: Icons.add_circle_outline,
        onSelected: (_) => controller.addFormRadioButton(fieldName),
      ),
  ];
  final structure = <PdfAnnotationMenuItem>[
    PdfAnnotationMenuItem(
      key: const ValueKey('pdf-form-menu-rename'),
      label: pdfL10n(context).menuRename,
      icon: Icons.drive_file_rename_outline,
      onSelected: (_) async {
        final newName = await textPrompt(context,
            title: pdfL10n(context).menuFieldName, initial: fieldName);
        if (newName == null || newName.isEmpty || newName == fieldName) {
          return;
        }
        controller.renameFormField(fieldName, newName);
      },
    ),
    PdfAnnotationMenuItem(
      key: const ValueKey('pdf-form-menu-text'),
      label: pdfL10n(context).menuConvertToTextField,
      icon: Icons.text_fields,
      enabled: convertsTo(PdfFormFieldKind.text),
      onSelected: (_) =>
          controller.changeFormFieldKind(fieldName, PdfFormFieldKind.text),
    ),
    PdfAnnotationMenuItem(
      key: const ValueKey('pdf-form-menu-checkbox'),
      label: pdfL10n(context).menuConvertToCheckBox,
      icon: Icons.check_box_outlined,
      enabled: convertsTo(PdfFormFieldKind.checkBox),
      onSelected: (_) =>
          controller.changeFormFieldKind(fieldName, PdfFormFieldKind.checkBox),
    ),
    PdfAnnotationMenuItem(
      key: const ValueKey('pdf-form-menu-button'),
      label: pdfL10n(context).menuConvertToImageButton,
      icon: Icons.smart_button,
      enabled: convertsTo(PdfFormFieldKind.pushButton),
      onSelected: (_) => controller.changeFormFieldKind(
          fieldName, PdfFormFieldKind.pushButton),
    ),
    for (final (kind, key, label, icon) in [
      (
        PdfFormFieldKind.radioGroup,
        'radio',
        pdfL10n(context).menuConvertToRadioGroup,
        Icons.radio_button_checked,
      ),
      (
        PdfFormFieldKind.comboBox,
        'combo',
        pdfL10n(context).menuConvertToComboBox,
        Icons.arrow_drop_down_circle_outlined,
      ),
      (
        PdfFormFieldKind.listBox,
        'list',
        pdfL10n(context).menuConvertToListBox,
        Icons.list_alt,
      ),
      (
        PdfFormFieldKind.signature,
        'signature',
        pdfL10n(context).menuConvertToSignatureField,
        Icons.draw_outlined,
      ),
    ])
      PdfAnnotationMenuItem(
        key: ValueKey('pdf-form-menu-$key'),
        label: label,
        icon: icon,
        enabled: convertsTo(kind),
        onSelected: (_) => controller.changeFormFieldKind(fieldName, kind),
      ),
  ];
  final destructive = <PdfAnnotationMenuItem>[
    PdfAnnotationMenuItem(
      key: const ValueKey('pdf-form-menu-delete'),
      label: pdfL10n(context).menuDeleteField,
      icon: Icons.delete_outline,
      onSelected: (_) => controller.removeFormField(fieldName),
    ),
    PdfAnnotationMenuItem(
      key: const ValueKey('pdf-form-menu-flatten'),
      label: pdfL10n(context).menuFlattenForm,
      icon: Icons.layers_clear_outlined,
      onSelected: (_) => controller.flattenFormFields(),
    ),
  ];

  var entries = _menuRowsWithDividers([edit, structure, destructive]);
  if (entriesBuilder != null) {
    entries = entriesBuilder(
        context,
        PdfFormFieldMenuRequest(
            controller: controller,
            fieldName: fieldName,
            widgetIndex: widgetIndex),
        entries);
    if (entries.isEmpty) return;
  }
  final picked = await PdfEditorPresenter.of(context).menu(
    context,
    PdfMenuRequest<PdfAnnotationMenuItem>.at(position, entries: entries),
  );
  // the request param is unused by these closures; reuse the row type
  // so the menu plumbing stays shared with the annotation menu
  await picked?.onSelected(PdfAnnotationMenuRequest._(controller, -1));
}

/// Flattens [groups] of menu items into menu entries, dropping empty
/// groups and ruling a [PdfMenuDivider] between the ones that survive.
/// Large menus read as labelled clusters; a menu that collapses to a
/// single group draws no divider at all.
List<PdfMenuEntry<PdfAnnotationMenuItem>> _menuRowsWithDividers(
    List<List<PdfAnnotationMenuItem>> groups) {
  final entries = <PdfMenuEntry<PdfAnnotationMenuItem>>[];
  for (final group in groups) {
    if (group.isEmpty) continue;
    if (entries.isNotEmpty) entries.add(const PdfMenuDivider());
    for (final item in group) {
      entries.add(_menuRow(item));
    }
  }
  return entries;
}

PdfMenuItem<PdfAnnotationMenuItem> _menuRow(PdfAnnotationMenuItem item) =>
    PdfMenuItem<PdfAnnotationMenuItem>(
      key: item.key,
      value: item,
      label: item.label,
      icon: item.icon,
      enabled: item.enabled,
      height: _densePopupMenuHeight,
      child: Builder(
        builder: (context) {
          final disabledColor = Theme.of(context).disabledColor;
          final color = item.enabled ? null : disabledColor;
          return Row(
            children: [
              if (item.icon != null) ...[
                // PopupMenuItem dims only text when disabled; match it
                Icon(item.icon, size: 16, color: color),
                const SizedBox(width: 8),
              ],
              // flexible: long labels ellipsize at the popup's width cap
              // instead of overflowing
              Flexible(
                child: Text(
                  item.label,
                  overflow: TextOverflow.ellipsis,
                  style: _densePopupTextStyle(context, color: color),
                ),
              ),
            ],
          );
        },
      ),
    );
