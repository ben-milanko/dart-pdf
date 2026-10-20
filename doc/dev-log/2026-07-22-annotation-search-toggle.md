# Annotation-content search + a search-panel toggle

Document search now scans annotation /Contents (note bodies, free-text
boxes, comments) alongside the page's own extracted text, with a toggle in
the search chrome to turn it on or off. Default on.

## What changed

- `PdfSearchOptions` gained `searchAnnotations` (default `true`) - carried
  through `copyWith`/`==`/`hashCode` like the other flags. All existing
  constructors use named args, so the added field is source-compatible.
- `PdfSearchResult` gained an optional `annotation` (`PdfAnnotation?`) and an
  `isAnnotation` getter. Page-text hits leave it null; annotation hits carry
  the source annotation so the results panel can mark them.
- `_PdfViewerState._searchAllPages` now, per page and when the flag is on,
  walks `page.annotations` and matches each visible annotation's `.contents`
  via the new string-only matcher `_stringMatches` (the literal/regex/
  case/whole-word core of `PdfPageText.findAll`, minus geometry). Each hit
  becomes a `PdfSearchResult` from `_annotationSnippet`, whose synthetic
  `PdfTextMatch` uses the annotation's `/Rect` as a single highlight quad -
  so annotation matches scroll into view and paint like any text match.
  - Skipped: `/Popup` (mirrors its parent markup's /Contents - would
    double-count), and hidden / no-view annotations (`isHidden`/`isNoView`),
    matching the visible-annotation filter used elsewhere.
- Search chrome (`_SearchOptionsBar`, shared by `PdfSearchField` and
  `PdfSearchResultsPanel`) grew a fourth toggle
  (`ValueKey('pdf-search-annotations')`, a comment glyph). The toggle helper
  learned an `iconData` path since this one is an icon, not a text glyph.
  The results-panel tile shows a small comment icon as its leading marker
  for annotation hits.
- Persistence: `PdfEditingPreferences.searchAnnotations` (default `true`,
  key `searchAnnotations`), loaded and seeded into the controller by the
  options bar exactly like the other three toggles.
- l10n: `searchAnnotations` = "Search annotations" (arb + generated en +
  abstract). `flutter gen-l10n` needs the app's `generate` flag, so the
  three generated files are hand-edited to match, as they are checked in.

## Tests

- `search_navigation_test.dart`: a new `buildAnnotationSearchPdf` fixture
  (a /Text note + its /Popup mirror + a /Link). Covers: annotation contents
  found by default, the /Popup not double-counted, page-text vs annotation
  hits told apart via `isAnnotation`, the toggle excluding/restoring
  annotation hits (controller API and the field's toggle button), and a
  stored `searchAnnotations:false` seeding the controller off.
- `editing_preferences_test.dart`: `searchAnnotations` added to the
  round-trip and empty-storage-default assertions.
