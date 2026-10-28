# Edit existing links

Links could be created (2026-07-22-hyperlink-tool.md) but never changed
afterwards: a /Link isn't selectable - a click follows it - so neither the
selection menu nor the properties panel ever saw one. A link baked into an
imported PDF had no way to be re-pointed short of deleting the page content.

## Model (`pdf_document`)

`PdfAnnotationEditing.setLinkUri(page, annotation, uri)` and
`setLinkDestination(page, annotation, PdfExplicitDestination)` rewrite the
link's /A in place (shared `_setLinkAction`). The region, /QuadPoints,
/AP decoration and /NM are untouched - a link's look doesn't depend on its
target. A bare /Dest (what many writers emit instead of /A) is removed:
§12.5.6.5 makes the two mutually exclusive. Non-/Link annotations and an
empty URI throw. Metadata-only change (`visual: false`).

## Controller (`dart_pdf_editor`)

- `linkAnnotationAt(page, x, y)` - topmost editable, visible /Link under a
  point (tests /Rect, like the viewer's click-to-follow).
- `linkTargetAt(page, slot)` - the current target as a `PdfLinkTarget`
  (URI or page), null for launch/remote/named/script actions.
- `editLink(page, slot, target)` - one undoable revision; false when the
  slot isn't an editable link. Remove link reuses `deleteAnnotation`.

## UI

- `showPdfAnnotationMenu(linkTarget: (page, slot))` adds **Edit link…**
  (`pdf-annot-menu-edit-link`) and **Remove link**
  (`pdf-annot-menu-remove-link`) as the first group.
- The viewer passes it from right-click (`_onSecondaryTapUp`, when no
  selectable annotation or text selection claims the click) and from every
  `_showSelectionMenu` path with a page point (touch long-press), via
  `_linkTargetAt`. The host takeover path (`contextMenuEnabled: false`) is
  unchanged.
- The link dialog gained `initialPage` (opens on the page choice) and
  `editing` (title "Edit link"); `PdfLinkRequest` carries both, so a custom
  `PdfEditorPresenter.link` sees them.
- New l10n keys in all 23 ARBs: `menuEditLink`, `menuRemoveLink`,
  `linkEditDialogTitle`.

## Tests

`annotation_editor_test.dart` (link group), `editing_link_test.dart`
(controller + menu/dialog), `select_mode_page_interaction_test.dart`
(right-click a link in the viewer → Edit link → saved).
