# Find to redact (#1160)

**Ask:** redacting is mostly names, so marking them one drag at a time is
slow. In redact mode, offer find/search (with optional regex) that marks the
hits for review and later redaction.

**Shape:** it reuses the search the viewer already has. Search, regex,
whole-word and match-case already lived in `PdfViewerController.search`
and `PdfSearchResultsPanel`, and the burn was already a separate phase
(`applyRedactions`), so the feature is a third panel section next to
replace:

- `PdfEditingController.markMatchesForRedaction(Iterable<PdfTextMatch>)`
  adds **one /Redact per hit** (fill black) in one `apply`, so one undo step.
  One mark per hit, not one per page, keeps the review step usable: a
  false positive is a single mark to delete on the page before burning. A
  hit whose runs all sit inside an existing /Redact /Rect (±0.5pt) is
  skipped, and so is an overlapping hit earlier in the same batch, so "Mark
  all" twice adds nothing and makes no empty revision. The rects are the
  match's per-run AABBs (`PdfTextMatch.rects`), the same geometry replace
  pins runs with. For rotated text that over-covers, which is the safe
  direction for a redaction.
  `isMarkedForRedaction(match)` is the same coverage test, for the panel.
- `PdfSearchResultsPanel(editing:)` gets a redact toggle (`Icons.gradient`,
  the redact tool's icon), `pdf-search-redact-toggle`. It expands
  `_RedactBar` with **Mark** (`pdf-search-redact-one`: the current hit, then
  step to the next, which is how a reviewer walks the list) and **Mark all**
  (`pdf-search-redact-all`: every page-text hit). Annotation /Contents hits
  have no page text under them, so they are filtered out. While the section
  is open, a marked hit shows a trailing glyph
  (`pdf-search-result-marked-N`). Expansion is
  `PdfEditingPreferences.searchRedactExpanded`, persisted like
  `searchReplaceExpanded`.
- Every revision clears the viewer's search (`_controller.clearSearch()` in
  the revision swap paths), so after marking the bar waits for
  `endOfFrame` and re-runs the query, the same as `_ReplaceBar._refresh`.
  Marking does not change the text, so result indices still line up and
  "Mark" can land on `index + 1`.
- Entry point from the tool: `PdfEditingToolbar.onFindToRedact` shows a
  "Find text to redact" button (`pdf-find-to-redact`, `Icons.manage_search`)
  in the redact strip beside Apply. `PdfEditorView` wires it only when
  `features.search && features.searchResultsPanel`. It sets
  `searchRedactExpanded` and `showSearchResultsPanel`. A standalone toolbar
  with no panel gets no button.

Six new strings (`searchRedact*`, `tbFindToRedact`), translated for every
locale. The English regions were synced with `tool/sync_english_locales.dart`.

Tests: `packages/dart_pdf_editor/test/search_redact_test.dart`. It covers the
controller API (one mark per hit, dedupe, multi-page, a burn that removes the
matched text, and ignoring a degenerate hit), the panel (collapsed by default,
persisted, Mark all, a regex pass over phone numbers burned end to end, Mark
stepping forward), and the toolbar entry point with and without a panel.
