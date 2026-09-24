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

class _FormTabState {
  final request = ValueNotifier<PdfFormTabRequest?>(null);
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
