import 'package:flutter/material.dart';
import 'package:pdf_document/pdf_document.dart' show PdfAcroForm;

import '../l10n/pdf_l10n.dart';
import '../toast.dart';
import 'editing_controller.dart';

/// Controllers whose dynamic-XFA notice has already been shown. Keyed by
/// controller so switching tabs, remounting the viewer, or a later revision
/// of the same session never repeats it.
final Expando<bool> _xfaNoticeShown = Expando<bool>('pdfXfaNoticeShown');

/// Whether [controller]'s form is a dynamic XFA form
/// ([PdfAcroForm.isDynamicXfa]) that nobody has been told about yet.
bool pdfXfaNoticePending(PdfEditingController controller) =>
    _xfaNoticeShown[controller] != true &&
    (controller.acroForm?.isDynamicXfa ?? false);

/// Shows a one-time, non-blocking toast explaining that [controller]'s form
/// is XFA-only, so its fields don't appear and can't be filled here -
/// instead of the form silently showing no fields. No-op when the form is
/// not dynamic XFA, the notice was already shown for this controller, or
/// there is no [ScaffoldMessenger] to show it in.
///
/// A hybrid form (XFA plus AcroForm fields) gets no notice: its AcroForm
/// fields fill normally, and filling drops the stale XFA copy.
void showPdfXfaNoticeIfNeeded(
  BuildContext context,
  PdfEditingController controller,
) {
  if (!pdfXfaNoticePending(controller)) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  _xfaNoticeShown[controller] = true;
  messenger.showSnackBar(SnackBar(
    key: const ValueKey('pdf-xfa-form-notice'),
    content: Text(pdfL10n(context).formXfaUnsupportedNotice),
    behavior: SnackBarBehavior.floating,
    margin: pdfFloatingToastMargin(context),
    duration: const Duration(seconds: 10),
    showCloseIcon: true,
  ));
}
