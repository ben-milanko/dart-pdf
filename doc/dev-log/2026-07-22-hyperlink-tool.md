# Hyperlink tool (add /Link annotations to text)

Added a tool for authoring hyperlinks - external (URI) and internal
("link within the document", a /GoTo destination) - spanning the model
layer and the editor UI.

## Model layer (`pdf_document`)

`PdfAnnotationEditing` (annotation_editor.dart) gained three creators,
mirroring the text-markup creators' `List<PdfRect> quads` shape so a text
selection's per-line quads become one link:

- `addLinkToUri(page, quads, uri:)` - a /Link with `/A << /S /URI >>`.
- `addLinkToDestination(page, quads, destination:)` - a /Link with
  `/A << /S /GoTo /D [pageRef /Fit …] >>` built from a
  `PdfExplicitDestination` (the write-side destination value that
  `PdfOutlineEditing` already used for bookmarks).
- `addLinkToPage(page, quads, targetPage:)` - the fit-the-whole-page
  shortcut.

Shared internals (`_addLink`): `/Rect` is the quads' bounding box, every
quad is written to `/QuadPoints` (so a multi-line link is only clickable
over the glyphs), and `/Border` is `[0 0 0]` - the convention for
suppressing the ugly default link rectangle - unless a visible border is
asked for. A link is **invisible by default** (linking existing text
needs no ink); `underlineColor` draws a hyperlink underline and
`borderColor` strokes a box, either baked into an `/AP` so the decoration
shows in every viewer. Reading already worked: `PdfLinkAnnotation` +
`PdfAction.parse` surface `/A` and a bare `/Dest`.

Gotcha: `_pageReference` exists on **two** extensions (`PdfOutlineEditing`
and `PdfTaggingAndArchival`), so calling it from a third extension is an
`ambiguous_extension_member_access` error. Added a local
`_linkPageReference` twin rather than disambiguate with an override.

## Editor UI (`dart_pdf_editor`)

- `PdfEditTool.link`: a box-drag tool (registered as a `_SimpleTool`,
  routed through the overlay's box arm + `_commitRect` like redact /
  signatureBox). On release it opens the Add-link dialog, then
  `PdfEditingController.addLink`.
- `PdfLinkTarget` (uri / page / destination) + controller `addLink` /
  `addLinkToSelection`. Box links default to a visible **border**;
  selection links default to an **underline**. A negative decoration
  colour clears it (invisible region).
- `showPdfAddLinkDialog` (editing_link.dart): a `SegmentedButton`
  (Web address / Page in document) over a URL or page-number field.
  Injectable as `EditingPageOverlay.linkPrompt` (typedef `PdfLinkPrompt`),
  defaulting to the dialog so the tool works out of the box.
- Text-selection "Add link" wired into both the touch chip
  (`_PageTextSelection.onAddLink`) and the desktop context menu
  (`_TextMenuAction.addLink`) - the primary "add a hyperlink to selected
  text" path.
- Toolbar: a Link entry in the Edit dock. New l10n strings in the `en`
  ARB (`linkDialogTitle`, `linkKindWeb/Page`, `linkUrlLabel`,
  `linkPageLabel`, `toolLink`, `textSelectionAddLink`), regenerated with
  `flutter gen-l10n`.

## Formatting caveat

The repo's committed sources are in the **old** dart-format style, and CI
gates on `dart analyze --fatal-infos` (not a format check). Running
`dart format` under fvm 3.44.4 rewrites whole files in the new "tall"
style and can even split a one-line `if` into a braced-less two-liner that
trips `curly_braces_in_flow_control_structures` (a fatal info). Keep edits
surgical - do **not** `dart format` these files wholesale.

## Tests

- `annotation_editor_test.dart`: URI/GoTo/XYZ round-trips, multi-quad
  `/QuadPoints`, default-invisible vs underline/border decoration, empty
  URI rejected, print flag.
- `editing_link_test.dart`: controller `addLink` / `addLinkToSelection`
  (border vs underline defaults, negative-colour suppression, empty-quad
  no-op) and the Add-link dialog widget (web + page modes).
