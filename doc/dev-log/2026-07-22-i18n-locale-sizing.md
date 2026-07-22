# 2026-07-22 — i18n locale sizing: web deferred loading + native prune tool

Follow-up to the phase-1 extraction (`2026-07-22-i18n-extraction.md`, PR #477).
Question from Ben before committing to translating additional languages: can a
host include only the locales it wants, to keep app size down — ideally
following the parent app's i18n config automatically?

## The constraint (why it isn't automatic)

A Flutter dependency that ships its own `LocalizationsDelegate` compiles **every
bundled locale** into the app. The host's `supportedLocales` only drives runtime
resolution and which Material/Cupertino translations load — it does **not**
tree-shake the package's locale classes (the generated delegate's lookup
references all of them). Flutter has no built-in mechanism for a dependency's
bundle to follow the host's locale list. So size control needs an explicit
lever.

## What landed

Three bundles (`packages/dart_pdf_editor`, `app`, `.../example`):

1. **Web deferred loading** — `use-deferred-loading: true` in each `l10n.yaml`.
   gen-l10n now imports each locale `deferred as …` and resolves it via
   `loadLibrary()`, so dart2js splits every locale into its own chunk and the
   browser fetches only the active one. No effect on mobile/desktop AOT.
   English stays **eager**: the `pdfL10n`/`appL10n` fallback wrappers import the
   `_en` class directly, so the same file is both a direct import (wrapper) and
   a deferred import (delegate) — legal in Dart, and it keeps the fallback
   synchronously constructible.

2. **`tool/trim_locales.sh`** — the native-size lever. `trim_locales.sh en es
   fr` regenerates the checked-in gen-l10n output for just those locales (+ the
   English template, always kept), then you `flutter build`, then `--restore`.
   Implementation: for each bundle it moves the unwanted `*_<loc>.arb` out of
   the arb-dir, runs `gen-l10n` (so the delegate + `supportedLocales` come back
   sized to the kept set), restores the ARBs (source of truth never lost), then
   deletes the now-orphaned generated `*_localizations_<loc>.dart` (gen-l10n
   regenerates the delegate but never deletes stale outputs). A `RETURN` trap
   guarantees the ARBs are put back even on failure. `--restore` just re-runs
   gen-l10n across all three bundles; `--list` shows bundled locales.

3. **`doc/i18n.md`** — how lookups/fallback/delegates work, adding
   strings/languages, the two `dart analyze --fatal-infos` traps
   (`Localizations.of` in initState, context across async gaps), and the size
   section: web deferred (auto), `trim_locales.sh` (native), and the host-merge
   alternative for external apps that consume the published package.

## Verified

- gen-l10n with `use-deferred-loading` produces valid deferred imports even
  with the single `en` locale today; `dart analyze --fatal-infos` clean across
  the workspace.
- **Deferred loading makes the delegate load async on every platform**, which
  broke widget tests that boot a localized app and assert on the first frame -
  `WidgetsApp` doesn't build the app subtree until the (now-deferred) delegate
  resolves, so the localized UI (and the example's post-frame demo open) isn't
  there yet. Fixed 5 tests by settling the boot: `app/test/widget_test.dart`
  and `example/test/{tabs,recent_files_menu}_test.dart` use `pumpAndSettle`;
  `example/test/{demo,editing}_test.dart` can't (the opened demo's clock
  overlay runs a periodic timer that never settles), so their `openDemo`
  helper pumps a bounded number of frames until the demo `PdfViewer` appears.
  Package suite is unaffected - its widget tests exercise the English fallback
  (no registered delegate). All three suites green after the fix.
- `trim_locales.sh` end-to-end: created a synthetic `dart_pdf_editor_es.arb`
  (→ 2-locale delegate), ran `trim_locales.sh en`, confirmed the `_es` generated
  class was removed and `supportedLocales` fell back to `[en]` while the `es`
  ARB stayed on disk; `--restore` brought it back. Removed the synthetic locale
  afterwards.

## Cost of deferred loading (why it's a deliberate tradeoff)

On **web** it's a clear win (only the active locale's chunk downloads). On
**native** AOT it gives no size benefit (everything is bundled regardless) and
adds a one-frame delay before localized UI paints, plus the test-settling
requirement above. We enable it anyway (Ben's call) because web is where DartPDF
ships the demo and where download size matters; native size is handled by
`trim_locales.sh`. If the native first-frame delay ever bites, flip
`use-deferred-loading` off in the l10n.yaml files and regenerate - the wrappers
and everything else are unchanged by it. Any NEW widget test that boots a
localized app must settle the async delegate load (see the fixed tests for the
two patterns).

## Gotcha

`--restore` (plain `gen-l10n`) does not delete generated files whose ARB was
*actually removed* — it only regenerates from ARBs present. That's correct for
the trim→build→restore flow (the ARBs are only ever moved, never deleted); a
genuinely deleted locale is a source change and its stale `_loc.dart` must be
removed by hand (or by another `trim_locales.sh` run).
