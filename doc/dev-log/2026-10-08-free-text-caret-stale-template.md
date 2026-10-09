# Free-text caret floating above its line (stale caret template)

**Symptom.** In the inline free-text editor, the caret at the end of the
text sat a line fragment too high: its bottom stopped short of the last
line's baseline, and its top touched the line above.

**Cause (a Flutter quirk).** `TextPainter` places an end-of-text caret
using a cached one-line *layout template*:
`_endOfTextCaretMetrics.shift(-template.baseline)`. That template is rebuilt
only when the root `TextSpan.style`, `textDirection` or `textScaler`
changes. The `strutStyle` setter does **not** drop it. The editor pins line
height with `StrutStyle(fontSize: maxStyleSize * scale, forceStrutHeight:
true)`, but its root style was sized `_textEditSize`. So once a run's size
changed (strut changes, root style does not), the template kept the old
strut's baseline. Example: a run is enlarged, something rebuilds the
template (a whole-box recolour, zoom), then the run is shrunk back or
deleted. The template baseline is now too large, so the caret moves up by
the difference.

**Fix.** `editing_overlay.dart`: the field's root style now uses
`maxStyleSize` for its size, the same number the strut uses. Any strut
change is therefore also a root-style change, and Flutter rebuilds the
template. Unstyled gaps in `_RichTextEditingController.buildTextSpan` now
carry `defaultStyle.size` themselves, so typed text keeps the typing
default's size. Without per-run styles, `maxStyleSize == defaultStyle.size
== _textEditSize`, so nothing changes visually.

**Test.** `editing_text_edit_test.dart`, "the end-of-text caret stays on
its line after a run is resized back". It fails without the fix (caret top
4.6 px above the line box).
