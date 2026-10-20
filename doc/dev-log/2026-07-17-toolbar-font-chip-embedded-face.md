# Toolbar font chip vs. tune popup: show the real face

## Symptom

For a free-text box drawn in an embedded font (a bundled/custom/platform
face, e.g. "Arial"), the toolbar's font chip read "Sans" while the tune
(style) popup's font button read the box's real family. The two disagreed
on what was, in fact, the same font.

## Cause

The two widgets resolved "current font" differently.

- The tune popup's `PdfFontMenuButton` (`editing_toolbar.dart`, the `fields.font`
  block) passes `currentFont: controller.selectedTextFont ?? captionStyle?.font
  ?? controller.activeFont ?? controller.fontFamily`. `selectedTextFont`
  recovers the *actual* embedded face from the box's appearance (see its
  doc-comment in `editing_controller.dart`), so it shows "Arial".
- `_FontChip` used `controller.selectedTextStyle?.font ?? controller.fontFamily`.
  `selectedTextStyle` only parses a base-14 `PdfStandardFont` out of the flat
  /DA, so any embedded face collapsed to its nearest standard family label
  ("Sans"/"Serif"/"Mono").

## Fix

`_FontChip` now resolves the same way the popup does:

```dart
final font = controller.selectedTextFont ??
    controller.activeFont ??
    style?.font ??
    controller.fontFamily;
```

and `_familyLabel` was widened from `PdfStandardFont` to `PdfTextFont`: an
embedded font reports `familyName`, a custom `PdfTextFont` reports
`resourceName`, and a standard family keeps the existing " B"/" I"/" BI"
suffix. `PdfEmbeddedFont` was added to the pdf_document import list.

The chip's size still comes from `selectedTextStyle?.size ??
preferences.fontSize` - only the family label needed the real-face fix.

## Test

`editing_text_edit_test.dart` › "the toolbar font chip shows the embedded
face, not Sans": embeds DejaVu into a box, selects it, and asserts the chip
carries the embedded family name and not "Sans".
