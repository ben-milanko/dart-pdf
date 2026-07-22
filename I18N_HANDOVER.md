# Handover: full internationalization (i18n)

Branch: `feat/i18n` — phase 1 (infrastructure + English extraction) is in
progress. This file is the complete briefing for the agent continuing the
work. Delete it before merging (or keep as you see fit).

## Goal & decisions (agreed with Ben)

Localize the whole product to maximize users. Decisions already made:

1. **Translations must be free**: machine-translate the seed ARB files,
   then community/native review. No paid translation.
2. **`app/` (the shipping DartPDF app) is in scope**, alongside
   `packages/dart_pdf_editor` and the example app.

## The plan (as presented to Ben)

- Stack: `flutter_localizations` + `intl` + ARB + `gen-l10n`, generated
  Dart **checked into git** (required for pub publishing; hosts must not
  need codegen).
- Two localization bundles: the package ships
  `DartPdfEditorLocalizations` (delegate + supportedLocales exported from
  `dart_pdf_editor.dart`); `app/` and `example/` get their own
  `AppLocalizations` and register the package delegate too.
- Engine packages (pdf_cos / pdf_document / pdf_graphics) stay English —
  their exceptions are developer-facing. At the handful of UI spots where
  raw engine errors leak (`progressive_source.dart:238`, open-fail
  dialogs, toasts), map exception types to localized UI messages
  (phase 2).
- Message hygiene: ICU plural/select replaces hand-rolled plurals
  (`'N selected'`, `'N item(s)'`, `forPages()`, `'N matches'`,
  `'N pages'`); typed placeholders + a `@key` description for every
  message (translators depend on them); no sentence concatenation;
  `intl DateFormat` for the 12 hardcoded month abbreviations in
  `editing_stamps.dart` (phase 2); `NumberFormat` for user-visible
  `toStringAsFixed` values (phase 2).
- Locale tiers — tier 1: es, zh-Hans, pt-BR, de, fr, ja, ru, hi, **ar**
  (Arabic in tier 1 deliberately forces the RTL work early); tier 2:
  zh-Hant, ko, it, tr, vi, id, pl, nl, th, uk.
- RTL sweep (phase 2, ~12 files): `EdgeInsets.only(left/right)` →
  `EdgeInsetsDirectional`, `Alignment.topLeft` → `topStart`, etc.;
  `matchTextDirection: true` on undo/redo, `chevron_right`,
  align_horizontal icons. **Exclude page-space geometry** in
  `editing_overlay.dart` / `editing_form_layer.dart` (PDF coordinates
  must not flip). Panel dock sides (`PdfSidebarSide`) stay physical.
- Fonts: UI chrome relies on system fallback (fine on desktop/mobile;
  CanvasKit auto-loads Noto on web) — add a per-script smoke test, don't
  bundle. Bundled editing fonts (DejaVu/Fira/Spectral/Lobster) are
  Latin-only; CJK typed into a text box won't embed — out of scope for
  v1, document the limitation, follow-up is Noto subsets.
- Later phases: app Settings language picker (persisted, default
  system); CI gate that every ARB has 100% key coverage
  (`untranslated-messages-file`); widget tests pumped in de (long
  strings → overflow), ar (RTL), ja (fonts); localize app store
  listings/screenshots (where user count actually moves); redeploy the
  Firebase web demo; Weblate/Crowdin on the ARB files for community
  translation.

## Phase 1 remaining work

Phase 1 extraction is **done** (2026-07-22) — see
`doc/dev-log/2026-07-22-i18n-extraction.md` for the write-up, key counts,
gotchas, and the deferred no-context inventory.

- [x] l10n infra in `packages/dart_pdf_editor` (see "What's done")
- [x] Extract `dart_pdf_editor` strings into the ARB (443 keys total)
- [x] `dart analyze` + `fvm flutter test` green in dart_pdf_editor (the
      one `ghent_render_test` spot-color baseline failure is pre-existing,
      unrelated to i18n)
- [x] `app/`: l10n infra + extract user-facing strings (208 keys) + wire
      `MaterialApp` delegates (`devtools_panel.dart` left English)
- [x] `example/`: l10n infra + extract strings (117 keys) + wire
      `MaterialApp` delegates
- [x] Full verification: root `fvm dart analyze --fatal-infos` + all three
      test suites (package/app/example) green
- [ ] Deferred: the no-context strings that need a context-threading
      refactor (toolbar tool tooltips are the biggest) — full list in the
      2026-07-22 dev-log note.

## What's done (state of this branch)

`packages/dart_pdf_editor` infrastructure, verified green with
`dart analyze lib`:

- `pubspec.yaml`: added `flutter_localizations` (sdk), `intl: ^0.20.2`
  (matches the flutter_localizations pin of Flutter 3.44.4), and
  `generate: true` under `flutter:`.
- `l10n.yaml`: arb-dir `lib/l10n`, template `dart_pdf_editor_en.arb`,
  output-class `DartPdfEditorLocalizations`. Do NOT re-add
  `synthetic-package` — deprecated, gen-l10n warns.
- `lib/l10n/dart_pdf_editor_en.arb`: template with `@@locale: en` and the
  first two keys (`cancel`, `ok`) with `@key` descriptions.
- `lib/l10n/dart_pdf_editor_localizations{,_en}.dart`: **generated,
  checked in**. Regenerate after every ARB edit:
  `cd packages/dart_pdf_editor && ~/fvm/versions/3.44.4/bin/flutter gen-l10n`
  (use the fvm binary; `fvm flutter gen-l10n` also works if fvm is set up).
- `lib/src/l10n/pdf_l10n.dart`: the fallback wrapper —
  `pdfL10n(context)` returns the ambient localizations or the English
  instance when the host never registered the delegate. **This is the key
  design**: package widgets work out of the box for existing hosts, and
  the existing widget tests (which find English text via
  `find.text('Cancel')`) keep passing unchanged because the fallback is
  English. Do not migrate test finders in phase 1.
- `lib/dart_pdf_editor.dart`: exports the generated localizations +
  `src/l10n/pdf_l10n.dart`.
- `lib/src/editing/text_prompt.dart`: the exemplar extraction
  (Cancel/OK → `pdfL10n(context).cancel/.ok`).

## Extraction conventions (follow the exemplar)

- Call sites: `pdfL10n(context).someKey` — context is nearly always
  available in build/dialog/snackbar code. Where a string lives in a
  `const` constructor/list, drop the `const` or look up in `build`.
  Where NO context exists (top-level helpers/models), thread the l10n
  through from the caller; if that's too invasive, leave the literal and
  list it in your report.
- Internal imports are relative (repo convention). From
  `lib/src/editing/*.dart` the wrapper is `import '../l10n/pdf_l10n.dart';`.
  Careful with depths: from `lib/src/l10n/` the generated file is
  `../../l10n/...`.
- ARB keys: lowerCamelCase; prefix by area where ambiguous
  (`tooltipRotateLeft`, `menuBringToFront`, `dialogRedactTitle`).
  Every key gets a `@key` entry with a one-line translator description.
- Plurals/selects: ICU now, e.g.
  `"{count, plural, =0{No annotations} one{1 annotation} other{{count} annotations}}"`.
- Keep brand/proper nouns in values ('DartPDF', font names, HEX/RGB/HSL/
  CMYK format labels are names, though the tab labels still want keys).
- Never change behavior — pure string moves + ICU plurals. Don't touch
  tests (English fallback keeps them green).
- After each batch: merge keys into the ARB, run gen-l10n, then
  `dart analyze lib` must be clean.

### Parallel-agent tip (avoiding ARB write conflicts)

Have each extraction agent write its keys to its own JSON fragment (e.g.
`/tmp/arb_fragments/<batch>.json`: `{key, "@key": {...}}` pairs) and edit
only its assigned source files; then merge fragments into the template
(sorted, `@@locale` first) and regenerate once per wave. Flag collisions
where the same key has different values.

## String inventory (from codebase survey)

`packages/dart_pdf_editor/lib` — ≈420–450 strings:

| File | ~Count | Notes |
|---|---|---|
| `src/editing/editing_toolbar.dart` | 150 | ~52 tooltips, tool/group labels, style-menu labels, dialogs ('Apply redactions?'), ~8 SnackBars; biggest file, give it its own agent |
| `src/editing/editing_properties.dart` | 35 | section headers, control labels, 'Varies', 8 line-ending names |
| `src/editing/editing_stamps.dart` | 30 | incl. 12 month abbreviations + defaults 'APPROVED'/'TEXT' (content placeholders) |
| `src/editing/editing_menu.dart` | 25 | annotation + form context menus |
| `src/editing/editing_thumbnails.dart` | 25 | `forPages()` plural helper → ICU |
| `src/shell_chrome.dart` | 30 | shell header, settings, keyboard shortcuts |
| `src/editing/editing_sidebar.dart` | 22 | review states, 'N selected', 'by {author}' |
| `src/editing/editing_color_processing.dart` | 17 | |
| `src/editing/editing_bookmarks.dart` | 16 | |
| `src/editing/editing_measure.dart` | 15 | unit symbols ft/in/… stay as-is (symbols) |
| `src/editing/editing_takeoff.dart` | 15 | 'N item(s)' → ICU |
| `src/editing/editing_form_style.dart` | 14 | |
| `src/pdf_viewer.dart` | 14 | selection menus + 4 toasts |
| `src/editing/editing_fonts.dart` | 12 | font names are proper nouns |
| `src/editing/editing_overlay.dart` | 11 | chip/inline-editor tooltips, prompt titles |
| `src/comparison/comparison_view.dart` | 10 | |
| `src/search_panel.dart` | 10 | |
| `src/editing/create_signing_identity_dialog.dart` | 9 | |
| `src/pdf_editor_view.dart` | 14 | |
| `src/pdf_reader.dart` | 8 | |
| `src/editing/text_style_prompt.dart` | 8 | |
| `src/editing/editing_font_controls.dart` | 8 | |
| `src/editing/editing_color_picker.dart` | 8 | |
| `src/editing/editing_panel.dart` | 7 | |
| `src/page_range_dialog.dart` | 6 | |
| `src/pdf_reflow_view.dart` | 6 | |
| `src/editing/annotation_presentation.dart` | 6 | subtype display names |
| `src/editing/digital_signature.dart` | 5 | user-visible FormatExceptions |
| `src/editing/editing_signature.dart` | 4 | |
| `src/editing/line_style.dart` | 4 | |
| `src/editing/text_prompt.dart` | 2 | **done** (exemplar) |
| `src/editing/editing_value_field.dart` | 1 | 'Varies' |
| `src/progressive_source.dart` | 1 | 'Could not open document: $error' — phase-2 error mapping, leave the interpolation shape |
| `src/page_number_field.dart`, `src/toast.dart` | 0 | nothing to do |

`app/lib` — ≈150 user-facing (extract these; skip `devtools_panel.dart`):
`editor_screen.dart` ~114 (update banner, tab menu, 'Discard changes?',
app menu, 'Open Recent'), `digital_signature.dart` ~68 (signing flow),
`settings_screen.dart` ~34, `ocr_native.dart`/`ocr_web.dart` ~13 each,
`welcome_screen.dart` ~4, `new_document.dart` ~5, `image_export.dart`,
`print_progress_dialog.dart`, `app.dart`, `main.dart` ~2 each.

`example/lib` — ≈75–80: `main.dart` ~65 (app-bar menus, tab strip,
toasts, export/URL/OCR dialogs, worker picker), `feedback.dart` ~7,
`scroll_indicator_demo.dart` ~6. `demo_document.dart` English is baked
into the generated demo PDF = document content, leave it.

## app/ and example/ infra (mirror the package)

- pubspec: add `flutter_localizations` (sdk) + `intl: ^0.20.2`,
  `generate: true` under `flutter:`.
- `l10n.yaml`: arb-dir `lib/l10n`, template `app_en.arb`, output-class
  `AppLocalizations` (no synthetic-package line).
- Same fallback helper (`appL10n(context)` in
  `lib/src/l10n/app_l10n.dart`) so their widget tests stay green without
  registering delegates.
- Wire each `MaterialApp`: `localizationsDelegates: [
  ...AppLocalizations.localizationsDelegates,
  ...DartPdfEditorLocalizations.localizationsDelegates,
  GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate]`,
  `supportedLocales: AppLocalizations.supportedLocales` (en only in
  phase 1).

## Verification commands

- `cd packages/dart_pdf_editor && ~/fvm/versions/3.44.4/bin/dart analyze`
  and `~/fvm/versions/3.44.4/bin/flutter test`
- Root: `~/fvm/versions/3.44.4/bin/flutter pub get` (workspace), then the
  same analyze/test in `app/` and `packages/dart_pdf_editor/example/`.
- The four corpus suites are rendering-only and shouldn't be affected;
  run them only if something non-string changed (see AGENTS.md).

## Gotchas already hit

- `synthetic-package` is removed/deprecated in Flutter 3.44's gen-l10n —
  omit it; generation writes into `lib/l10n` directly.
- gen-l10n refuses unless `generate: true` is in the pubspec's
  `flutter:` section.
- The generated base file imports but does NOT re-export
  `dart_pdf_editor_localizations_en.dart` — the fallback wrapper imports
  both files.
- `Localizations.of<T>(context, T)` (nullable, safe) is what the wrapper
  uses; don't use the generated `of()` — it force-unwraps when
  `nullable-getter: false` and would break the no-delegate fallback.
