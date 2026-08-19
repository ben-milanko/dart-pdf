import 'package:flutter/material.dart';

/// Places a text field's selection toolbar - the long-press copy/paste
/// menu - where the framework computed it, even when the field lives
/// inside the viewer's zoom transform.
///
/// Flutter shows that toolbar through a [CompositedTransformFollower]
/// linked to the field, with the field's global origin subtracted again as
/// the follower's offset (`_SelectionToolbarWrapper` in the framework's
/// `text_selection.dart`). The menu itself lays out in *screen*
/// coordinates - around anchors taken from the same field - so the two
/// cancel and it lands where it was measured. That cancellation only holds
/// while the field's transform to the screen is a pure translation.
///
/// Above 100% zoom it isn't: the page (and every editor over it) sits
/// under the viewer's `InteractiveViewer` scale `s`, so the follower maps
/// the menu's origin to `(1 - s) * fieldOrigin` instead of `Offset.zero`.
/// The menu is drawn `s` times too large and displaced by the *whole
/// distance from the screen origin to the field*, scaled - hundreds of
/// pixels on a phone, i.e. entirely off-screen. The long press works; its
/// menu is just somewhere nobody can see, which reads as "holding the text
/// box does nothing".
///
/// Wrapping the menu in the inverse of the field's transform, taken about
/// the field's own origin, cancels the follower exactly - at any scale or
/// rotation, and as the identity when the field is unscaled (so an
/// unzoomed page keeps the framework's own placement, untouched).
///
/// Residual: the follower is linked to the field's inner scroll viewport,
/// not to the box measured here, so a field scrolled inside itself is off
/// by its own scroll offset (times the zoom). Our in-page editors are
/// sized to their content and don't scroll.
Widget pdfPlacedTextSelectionMenu(
    EditableTextState editableTextState, Widget menu) {
  final box = editableTextState.context.findRenderObject() as RenderBox?;
  if (box == null || !box.attached || !box.hasSize) return menu;
  final toGlobal = box.getTransformTo(null);
  final inverse = Matrix4.tryInvert(toGlobal);
  if (inverse == null) return menu;
  final origin = box.localToGlobal(Offset.zero);
  final correction = Matrix4.translationValues(origin.dx, origin.dy, 0)
    ..multiply(inverse);
  if (_isIdentity(correction)) return menu;
  return Transform(transform: correction, child: menu);
}

/// Wraps an in-page [TextField] so Flutter's Apple-platform caret nudge
/// stays constant in *screen* space.
///
/// Material and Cupertino text fields shift the caret two device pixels
/// left on iOS and macOS (`-2 / devicePixelRatio`), and [RenderEditable]
/// snaps the caret to the device pixel grid with the same ratio. Both are
/// measured against the untransformed screen, so an editor living inside
/// the viewer's zoom transform has them multiplied by the zoom: the caret
/// drifts off the glyphs, by more the deeper you go. Feeding the subtree a
/// device pixel ratio scaled by the same zoom ([chromeScale] is its
/// inverse) cancels both, leaving the two physical pixels Flutter intends.
///
/// The identity off Apple platforms, and whenever the zoom is unusable.
Widget pdfZoomAwareCaret(BuildContext context,
    {required double chromeScale, required Widget child}) {
  final platform = Theme.of(context).platform;
  if (platform != TargetPlatform.iOS && platform != TargetPlatform.macOS) {
    return child;
  }
  if (!chromeScale.isFinite || chromeScale <= 0) return child;
  final media = MediaQuery.of(context);
  return MediaQuery(
    data: media.copyWith(devicePixelRatio: media.devicePixelRatio / chromeScale),
    child: child,
  );
}

/// The gutter [RenderEditable] reserves at the end of every editable line
/// for the caret: its one-pixel `_kCaretGap` plus the cursor width.
///
/// It comes out of the width the text is laid out and aligned in, so
/// centred text sits half a gutter - and right-aligned text a whole one -
/// to the left of the field. That is a constant in *layout* pixels, which
/// the viewer transform magnifies into a visible gap: at 24x it drags a
/// centred line about 13 screen pixels off the glyphs the page shows,
/// which is what leaves an inline caret looking detached from both ends of
/// centred free text at deep zoom (#692). In-page editors hand it back out
/// of their trailing content padding, so the band the text aligns inside
/// is the appearance's own text area at any zoom.
double pdfCaretGutter(double chromeScale) => 1.0 + 2 * chromeScale;

/// [Matrix4.isIdentity] is exact; the correction is a product of two
/// float matrices, so an unscaled field lands a hair off it.
bool _isIdentity(Matrix4 matrix) {
  final identity = Matrix4.identity().storage;
  final storage = matrix.storage;
  for (var i = 0; i < 16; i++) {
    if ((storage[i] - identity[i]).abs() > 1e-6) return false;
  }
  return true;
}
