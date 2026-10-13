# iOS "Paste" bubble covered the free-text style chip

Reported from Brave on iPhone: in a new free-text box, tapping the caret
brings up the selection menu ("Paste"). It sat right on top of the inline
style chip (font / A- / A+ / U / colour), hiding the font and size buttons.

## Why

The viewer turns the browser context menu off (`_suppressBrowserContextMenu`),
and the in-page editor asks for Flutter's own toolbar (`systemMenu: false`),
so iOS web draws `CupertinoTextSelectionToolbar`. That toolbar sits just
above `contextMenuAnchors.primaryAnchor`, which is the top of the selection.
`_buildInlineTextStyleChip` puts the chip 10px above the box. Both end up in
the same band.

## Fix

- `pdfStockTextContextMenu(anchors:)` lets an editor pass its own anchors
  (it now builds `AdaptiveTextSelectionToolbar.buttonItems`, which is what
  `.editableText` does under the hood).
- `pdfTextMenuAnchorsClearOf(anchors, avoid)` (editing_text_menu.dart) moves
  the primary anchor to the chip's top when the chip is in the bar's band
  above, and moves the secondary anchor to the chip's bottom when the chip
  sits below the box. Anchors that are already clear are returned as-is.
- The free-text editor passes the chip's global rect, read off a GlobalKey
  on the chip's Listener. That rect goes through the chip's
  `Transform.scale`, so it's in the same screen space as the anchors.
  `pdfPlacedTextSelectionMenu` still applies its zoom correction afterwards.

Test: `the iOS selection menu doesn't cover the inline style chip` in
editing_text_edit_test.dart. It fails before the fix: menu
(221,194)-(508,245) on top of chip (259,193)-(499,241).

The form layer's editor has no chip, so it isn't changed.
