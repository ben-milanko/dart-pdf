# 2026-07-22 — i18n phase 1: string extraction (package + app + example)

Builds on the l10n infrastructure landed on `feat/i18n`
(`2026-07-21`, commit 4d4656b): `flutter_localizations` + `intl` + ARB +
`gen-l10n`, generated Dart checked in, and the `pdfL10n()`/`appL10n()`
English-fallback wrappers so hosts and widget tests keep working without
registering a delegate. See `I18N_HANDOVER.md` for the original plan.

## What landed

- **app/ and example/ l10n infrastructure** mirroring the package:
  `generate: true` + `flutter_localizations`/`intl` in each pubspec, an
  `l10n.yaml`, an `appL10n(context)` fallback wrapper, the generated
  `AppLocalizations` bundle (checked in), and `MaterialApp` delegates
  (`AppLocalizations` + `DartPdfEditorLocalizations` + the global
  Material/Widgets/Cupertino delegates). The app's splash `MaterialApp`
  (main.dart) and the real one (app.dart) both carry the delegates.
- **20 shared common keys** (`cancel`/`ok`/`delete`/`apply`/`close`/`save`/
  `edit`/`rename`/`add`/`remove`/`reset`/`clear`/`copy`/`cut`/`paste`/
  `undo`/`redo`/`done`/`none`) seeded into all three ARBs so extraction
  reuses them instead of duplicating.
- **~700 strings extracted** into `pdfL10n(context).<key>` /
  `appL10n(context).<key>` across ~30 package files + app + example:
  - `dart_pdf_editor` ARB: **443 keys** (from 19)
  - app ARB: **208 keys** (from 19)
  - example ARB: **117 keys** (from 19)
- **ICU plural/select** replaced hand-rolled plurals and verb+count
  concatenation everywhere they appeared: `'N selected'`, `'N item(s)'`,
  `'N matches'`, `'N pages'`, `'N annotations'`, the thumbnail
  `forPages(verb)` helper (now one ICU key per verb —
  `thumbDuplicatePages`/`thumbCopyPages`/… passing `targets.length`),
  redaction/compare/search counts, OCR span counts, update-available
  wording, dropped-PDF this/these/its/their, etc. Every key carries a
  `@key` translator description and typed `placeholders`.
- Keys are namespaced by area (`tb*`, `prop*`, `stamp*`/`menu*`/`meas*`,
  `thumb*`/`sidebar*`/`bookmark*`/`takeoff*`, `color*`/`overlay*`/`panel*`,
  `shell*`/`viewer*`/`reflow*`, `search*`/`compare*`/`signId*`/…; app
  `editor*`/`appSig*`/`settings*`/…; example `ex*`/`feedback*`/`scrollDemo*`).

## How it was done

Parallel extraction: one subagent per file group, each editing only its
files and emitting an ARB fragment JSON to a scratch dir; a central
collision-detecting merge (`scratchpad/merge_arb.py`) folded the fragments
into each template ARB, then `gen-l10n` regenerated the bundles. No key
collisions across agents (the per-area prefixes + shared common keys made
the merge clean).

## Gotchas hit

- **`Localizations.of` in `initState`** — the example's `_ViewerScreenState`
  auto-opens a demo document in `initState`, and localizing its tab title
  made `appL10n(context)` run before the first build → `_LocalizationsScope`
  assertion, which cascaded into 24 test failures. Fixed by deferring the
  initial auto-open to a post-frame callback (context-dependent init belongs
  after first build). This is the pattern to watch for any other
  initState/constructor string.
- **`BuildContext` across async gaps** — `dart analyze --fatal-infos`
  (what CI runs) flags `appL10n(context)`/`pdfL10n(context)` used after an
  `await`. Fixed by capturing `final l10n = ...(context);` before the gap
  and using `l10n.*` in the post-await toasts/catches.
- **`AppVersion` into a String placeholder** — the update-banner keys take
  a `String` version; the original used string interpolation
  (`'$version'`). Pass `version.toString()`.
- The single `ghent_render_test.dart` `GWG030_Gray_K_black_OP_X1.pdf`
  baseline failure is **pre-existing** (fails identically on the base
  commit) — a spot-color render diff, unrelated to i18n.

## Deferred — no-context strings (phase 2)

These user-facing strings live in `static`/const data, enum getters, or
top-level helpers with no `BuildContext` at the point the text is produced;
localizing them needs a small refactor to thread context to the build/call
site (turn the literal into a stable key resolved via `pdfL10n(context)` at
the consumer). Listed so phase 2 can pick them up:

- **`editing_toolbar.dart`** (biggest): the `static const _groups` list —
  tool-group labels (Select/Markup/Draw/Shapes/Insert/Measure/Edit) and
  ~35 tool tooltips; plus `_selectedFormEditAction`, `_activeToolLabel`,
  `_endingLabel`. These are the most visible remaining English (every tool
  tooltip). The fix: give `_ToolGroup`/`_GroupTool` a key instead of a
  literal and resolve at the build sites (they all have context).
- **`editing_sidebar.dart`**: `_fieldLabel`, `_actionLabel`, `_title`
  ('Callout'), `_stateChip` (review-state names).
- **`editing_takeoff.dart`**: `_kindLabel` (measurement-kind names).
- **`line_style.dart`**: `PdfLineStyle.label` (Solid/Dashed/Dotted/Dash-dot).
- **`annotation_presentation.dart`**: `pdfAnnotationLabel` (subtype names).
- **`editing_panel.dart`**: `PdfDockablePanel` enum labels (Pages/Search
  results/Bookmarks/Annotations/Properties). NB the shell chrome already
  has `shellPanel*` keys for the same words — reuse those.
- **`editing_stamps.dart`**: `_timePreview` (24 hr/12 hr), `_caption`
  ('Custom stamp'), `_fontLabel` (Bold/Italic), `_fieldLabel` (Date/Time/
  Date & time/Username); the 12 month abbreviations want `intl DateFormat`;
  default stamp content 'APPROVED'/'TEXT' is document content, leave.
- **`digital_signature.dart` (package)**: user-visible `FormatException`
  messages thrown from a pure model — localize at the catch/display site.
- **app**: `settings_screen.dart` `_defaultAppSubtitle`/`_defaultAppInstructions`
  getters; `ocr_status.dart` `OcrJobStatus.label`; `XTypeGroup` file-picker
  labels (app + example); a couple of function-default params
  (`showPdfPageRangeDialog` title/label, `search_panel` 'Search' hint,
  `text_style_prompt` 'Keep').

## Still open (from the original plan)

Phase 2: engine-error→UI-message mapping (`progressive_source.dart`'s
`'Could not open document: $error'` kept as-is), `DateFormat`/`NumberFormat`
for month abbreviations and `toStringAsFixed` values, the RTL sweep, the
Settings language picker, the machine-translated seed ARBs + tier-1/2
locales, the per-locale CI coverage gate, and the no-context refactors above.
