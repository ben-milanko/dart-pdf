import 'package:flutter/material.dart';

/// Margin that floats a [SnackBar] clear of the editor's bottom chrome —
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
/// the bottom-right corner so it never covers the page; on narrow windows
/// it spans the width with a 16px gutter.
EdgeInsets pdfFloatingToastMargin(BuildContext context, {double pill = 360}) {
  final size = MediaQuery.sizeOf(context);
  // The dock sits at the bottom; lift the toast above it AND above the
  // device's bottom safe-area inset, which the dock pads itself out by.
  final bottom = 96.0 + MediaQuery.paddingOf(context).bottom;
  if (size.width >= 600) {
    return EdgeInsets.only(left: size.width - pill - 24, right: 24, bottom: bottom);
  }
  return EdgeInsets.fromLTRB(16, 0, 16, bottom);
}
