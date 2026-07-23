# 2026-07-22 — i18n phase 2: no-context string refactors (editor package)

Follows the phase-1 extraction (`2026-07-22-i18n-extraction.md`, PR #477)
and the locale-sizing work (`2026-07-22-i18n-locale-sizing.md`, PR #483).
Phase 1 left a "deferred — no-context strings" inventory: user-facing
English that lives in `static`/`const` data, enum getters, or top-level
helpers with no `BuildContext` at the point the text is produced. This
session clears that inventory for the `dart_pdf_editor` package.

## The pattern

Every one of these was a literal produced where no context was in scope.
The fix is always the same shape the handover called for: **the enum /
subtype / id is the stable key; the visible string is resolved from the
localizations at the consumer** (which does have a context). Two concrete
moves:

- Model→label helpers that are shared across consumers were centralized in
  `annotation_presentation.dart` (already the Flutter-presentation layer)
  as context-taking functions, so the same mapping is translated once and
  reused: `pdfAnnotationLabel(context, subtype)` (now takes context),
  `pdfLineStyleLabel(context, style)`, `pdfMeasurementKindLabel(context,
  kind)`, `pdfLineEndingLabel(context, ending)`. The pure models
  (`PdfLineStyle`, `PdfMeasurementKind`, `PdfLineEnding`) stay unchanged in
  their engine/enum homes — no Flutter dependency added there.
- Per-file statics/getters were made instance methods (so they can use the
  `State`'s own `context`) or given a `BuildContext` parameter threaded
  from the build-time call site.

## What landed (107 new ARB keys)

- **`editing_toolbar.dart`** (the big one, most-visible remaining English —
  every tool tooltip and dock-group label). The `static const _groups`
  list dropped its `label`/`tip` **literals** entirely: `_ToolGroup` now
  carries only `(id, icon, tools)` and `_GroupTool` only `(tool|markup,
  icon)`. Names/tips are resolved from the enum via `_toolName`/`_toolTip`/
  `_markupName`/`_markupTip`, and the group name via a `_ToolGroup.label(
  context)` method (put on the class so the separate `_GroupChip` widget
  can call it too). This also **deleted the string-splitting hacks** —
  `_activeToolLabel` used to parse the tip's leading clause before `" -"`,
  and the mobile sheet stripped `" selection"` off markup tips; both are
  gone, replaced by direct name lookups. The toolbar's duplicate
  `_endingLabel` was removed in favour of the shared
  `pdfLineEndingLabel` (reuses the `propLineEnding*` keys the Properties
  panel already localized in phase 1), and the line-style dropdown now
  calls `pdfLineStyleLabel`. `calibrate` (a tool not in `_groups`) maps to
  the existing `measCalibrate` key.
- **`editing_sidebar.dart`**: `_fieldLabel`, `_actionLabel`, `_stateChip`
  de-`static`'d to instance methods; `_title`'s `'Callout'` and the
  annotation-label call now localized. `_actionLabel`'s `'Page N'` became
  an ICU key with an `int` placeholder (`sbarActionPage`).
- **`editing_takeoff.dart`**: `_kindLabel` deleted; the panel calls the
  shared `pdfMeasurementKindLabel`.
- **`editing_panel.dart`**: `PdfDockablePanel` dropped its stored `label`
  literal for a `label(context)` method reusing the shell's `shellPanel*`
  keys (Pages/Search results/Bookmarks/Annotations/Properties). Both
  consumers (the drag chip and `shell_chrome.dart`'s dock tab) updated.
- **`editing_stamps.dart`**: `_timePreview` (`24 hr`/`12 hr`), `_caption`
  (`Custom stamp` fallback), `_fontLabel` (`Bold`/`Italic` — the family
  names stay as proper nouns), `_fieldLabel` (Date/Time/Date & time/
  Username). The `_monthNames` array and the AM/PM in `format()` are
  **left** — that output is stamped into document content and belongs with
  the separate `DateFormat`/`NumberFormat` follow-up.
- **`annotation_presentation.dart`**: `pdfAnnotationLabel` now maps a
  fuller set of subtypes (it previously returned most raw), still falling
  back to the raw subtype for anything unknown. Two English strings
  changed as a side effect: `FileAttachment` → "File attachment" (was the
  raw camelCase) and `Redact` → "Redaction".

Every new key carries a `@key` translator description and typed
placeholders where relevant. English values were kept byte-identical to
the previous literals (except the two annotation labels above), so the
English-fallback path — and the existing widget tests that find UI by
English text — are unaffected.

## Verification

- `dart analyze --fatal-infos` clean across the whole workspace.
- `dart_pdf_editor` `flutter test` green.
- The English `.arb` grew from 443 → 550 keys; `gen-l10n` regenerated.

## Still deferred (unchanged from the phase-1 inventory)

- **App/example strings**: `settings_screen.dart` default subtitle/
  instructions, `ocr_status.dart` `OcrJobStatus.label`, the `XTypeGroup`
  file-picker labels, and the `digital_signature.dart` model's
  `FormatException` messages (a **pure** model — localize at the app's
  `error.message` display site in `app/lib/digital_signature.dart:449`,
  with app-ARB keys). These live in the separate app/example ARBs and are
  their own change.
- **`DateFormat`/`NumberFormat`** for the stamp month abbreviations and
  user-visible `toStringAsFixed` values.
- The RTL sweep, the Settings language picker, the machine-translated seed
  ARBs + tier-1/2 locales, and the per-locale CI coverage gate.
