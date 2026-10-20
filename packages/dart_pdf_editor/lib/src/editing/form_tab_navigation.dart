import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:pdf_document/pdf_document.dart';

import 'editing_controller.dart';

/// A Tab / Shift+Tab move handed from one page's form layer to the page
/// that holds the target field. Each page mounts its own
/// [FormInteractionLayer], and the target page may not even be built yet
/// when the move starts (it scrolls in), so the move is posted here and the
/// target layer picks it up - immediately if mounted, on mount otherwise.
@immutable
class PdfFormTabRequest {
  const PdfFormTabRequest({
    required this.pageIndex,
    required this.fieldName,
    required this.widgetIndex,
    required this.revisionId,
    required this.revealed,
  });

  final int pageIndex;
  final String fieldName;
  final int widgetIndex;

  /// The controller revision the move was computed for; a request that
  /// outlived its revision is dropped rather than acted on.
  final int revisionId;

  /// Completes once the viewer has scrolled the field into view - a choice
  /// menu waits for it so it anchors where the field ends up.
  final Future<void> revealed;
}

/// A fill gesture on a form field (the form tool's double-tap) handed to
/// the field's page's [FormInteractionLayer], so a field fills through one
/// component whichever tool is armed: the same inline editor, keystroke
/// filtering and validation, choice menu and image picker.
@immutable
class PdfFormFillRequest {
  const PdfFormFillRequest({
    required this.pageIndex,
    required this.fieldName,
    required this.widgetIndex,
    required this.revisionId,
    this.anchor,
  });

  final int pageIndex;
  final String fieldName;
  final int widgetIndex;

  /// The controller revision the gesture hit; a stale request is dropped.
  final int revisionId;

  /// Where a choice field's menu opens, in global coordinates (the tap);
  /// null anchors it under the field.
  final Offset? anchor;
}

class _FormTabState {
  final request = ValueNotifier<PdfFormTabRequest?>(null);
  final fill = ValueNotifier<PdfFormFillRequest?>(null);
  PdfFormTabOrder? order;
  int? orderRevision;
}

final _states = Expando<_FormTabState>('pdf-form-tab');

_FormTabState _state(PdfEditingController controller) =>
    _states[controller] ??= _FormTabState();

/// The pending Tab move for [controller]'s form layers.
ValueNotifier<PdfFormTabRequest?> pdfFormTabRequests(
        PdfEditingController controller) =>
    _state(controller).request;

/// The pending fill gesture for [controller]'s form layers.
ValueNotifier<PdfFormFillRequest?> pdfFormFillRequests(
        PdfEditingController controller) =>
    _state(controller).fill;

/// [controller]'s form traversal order, built once per revision.
PdfFormTabOrder pdfFormTabOrderOf(PdfEditingController controller) {
  final state = _state(controller);
  final revision = controller.revisionId;
  final cached = state.order;
  if (cached != null && state.orderRevision == revision) return cached;
  state.orderRevision = revision;
  return state.order = PdfFormTabOrder.of(
    controller.document,
    form: controller.acroForm,
  );
}
