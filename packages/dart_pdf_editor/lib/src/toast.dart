import 'package:flutter/widgets.dart';

import 'design/editor_theme.dart';
import 'design/fold.dart';

/// Margin that floats a [SnackBar] clear of the editor's bottom chrome -
/// the floating editing toolbar dock (and any device safe-area inset
/// beneath it, e.g. a home indicator). Use it with
/// [SnackBarBehavior.floating] so toasts never hide behind the dock:
///
/// ```dart
/// ScaffoldMessenger.of(context).showSnackBar(SnackBar(
///   content: const Text('Saved'),
///   behavior: SnackBarBehavior.floating,
///   margin: pdfFloatingToastMargin(context),
/// ));
/// ```
///
/// On wide windows (≥600px) the toast is a compact [pill]-wide bubble in
/// the bottom trailing corner (bottom-right in LTR, bottom-left in RTL) so it
/// never covers the page; on narrow windows it spans the width with a 16px
/// gutter. On a foldable held half open the toast stays on the trailing pane
/// instead of crossing the crease.
EdgeInsetsGeometry pdfFloatingToastMargin(BuildContext context,
    {double pill = 360}) {
  final size = MediaQuery.sizeOf(context);
  // The dock sits at the bottom; lift the toast above it AND above the
  // device's bottom safe-area inset, which the dock pads itself out by.
  final bottom = PdfEditorThemeData.of(context).toastLift! +
      MediaQuery.paddingOf(context).bottom;
  // A foldable held open like a book: keep the toast on the trailing pane
  // rather than across the crease. [crease] is how far the trailing pane's
  // inner edge sits from the leading edge of the window.
  final fold = pdfSeparatingFoldOf(context);
  double crease = 0;
  if (fold != null && fold.direction == Axis.horizontal) {
    crease = Directionality.maybeOf(context) == TextDirection.rtl
        ? size.width - fold.bounds.left
        : fold.bounds.right;
  }
  if (size.width >= 600) {
    // Directional so the pill hugs the trailing edge (bottom-right in LTR,
    // bottom-left in RTL) instead of always the physical right.
    final start = size.width - pill - 24;
    return EdgeInsetsDirectional.only(
        start: crease > 0 && start < crease + 24 ? crease + 24 : start,
        end: 24,
        bottom: bottom);
  }
  if (crease > 0) {
    return EdgeInsetsDirectional.fromSTEB(crease + 16, 0, 16, bottom);
  }
  return EdgeInsets.fromLTRB(16, 0, 16, bottom);
}
