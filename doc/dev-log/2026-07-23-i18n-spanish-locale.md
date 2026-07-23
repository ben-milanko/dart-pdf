# 2026-07-23 — i18n phase 3: the first shipped locale (Spanish), a language picker, and an ARB coverage gate

Phase 1 extracted ~900 English strings across the three bundles; phase 2 did the
RTL sweep and a DevTools-only locale override
(`2026-07-23-i18n-rtl-sweep.md`). This session makes i18n *real*: **Spanish (es)
is fully translated and shipping**, the app grows a persisted Settings language
picker, and CI gains a per-locale coverage gate. Everything is wired so the next
locale is just "drop an ARB, regenerate".

## Spanish translation — all three bundles

Full `es` ARBs alongside each `_en.arb` template:

- `packages/dart_pdf_editor/lib/l10n/dart_pdf_editor_es.arb` (560 keys)
- `app/lib/l10n/app_es.arb` (227 keys — includes the two new picker keys below)
- `packages/dart_pdf_editor/example/lib/l10n/app_es.arb` (120 keys)

Translation was fanned out to three parallel agents, one per bundle (they touch
disjoint files, so no write conflicts). Each read the English template
*including* the `@key` descriptions — the translator context that makes a bare
toolbar tooltip unambiguous — and emitted only `@@locale` + the translated
key/value pairs (gen-l10n reads placeholder/description metadata from the
template only, so the locale ARBs stay lean). ICU plural/select structure,
placeholder names (`{count}`, `{platform}`, …), select branch keywords
(`web`/`windows`/…), brand nouns (DartPDF, font names, RSA/PEM/DER, HEX/RGB/…),
and ellipsis/`\n`/unit shapes were all preserved; only human text was
translated. Terminology was kept consistent per bundle (Eliminar=delete,
Guardar=save, Anotación, Marcador=bookmark, Sello=stamp, Aplanar=flatten, …).

After the fragments landed, one `flutter gen-l10n` per bundle regenerated the
checked-in Dart. `AppLocalizations.supportedLocales` is now `[en, es]`
automatically — nothing hand-edits the supported list.

## Persisted locale preference + `MaterialApp` wiring

`PdfEditingPreferences` gains a `Locale? locale` (null = "System default"),
persisted by BCP-47 tag via `toLanguageTag()` and read back through a small
`_parseLocaleTag` that recovers script (4-letter subtag) and region (2-letter /
3-digit) — so `pt-BR` and `zh-Hans` round-trip, not just bare `es`. It lives in
the editor package's prefs (next to `themeMode`) because that's the object the
app already threads to its `MaterialApp`.

`app.dart` now sets `MaterialApp.locale: _prefs.locale`. The existing
`localeListResolutionCallback` is unchanged in spirit: the **DevTools override
still wins** (RTL testing), then the resolution falls to the callback over
either the Settings locale (when set) or the full platform list. So three levers
stack cleanly: DevTools override > Settings pref > platform.

## Settings language picker

A "Language" dropdown in the app Settings dialog (`settings_screen.dart`,
`_LanguagePicker`), between the theme control and Recent files. "System default"
(value null) leads, then every `AppLocalizations.supportedLocales` entry shown by
its **native name** (autonym) so a user finds their language regardless of the
current UI language. The autonyms live in `app/lib/language_names.dart`, keyed by
BCP-47 tag then bare code, and cover the whole planned tier-1/2 set (not just
en/es) so a future ARB gets a proper name for free; anything unlisted falls back
to its tag. Two new ARB keys: `settingsLanguage`, `settingsLanguageSystem`.

## ARB coverage gate (CI)

`tool/check_arb_coverage.dart` (new CI step, next to the lockstep check) compares
every `<prefix>_<locale>.arb` against its `_en.arb` template across all three
bundles and fails on: missing keys, extra keys, a mislabeled `@@locale`, or a
translation using an interpolation placeholder the template never declared
(`{cont}` for `{count}`). **Why it matters:** gen-l10n silently falls back to
English for *missing* keys, so a half-translated locale otherwise ships looking
finished. ICU selector forms are left to gen-l10n's own structural validation;
the gate only guards key coverage + stray interpolations. Negative-tested (drop a
key / add a stray `{x}` → non-zero exit) before wiring it in.

## Tests

- `editing_preferences_test.dart`: `locale` added to the big round-trip, plus a
  dedicated test that a script+region tag (`zh-Hans-CN`) round-trips and that
  clearing to null removes the stored value.
- `settings_menu_test.dart`: the picker writes `Locale('es')` to prefs when
  "Español" is chosen.
- `spanish_locale_test.dart` (**new file, on purpose** — see the gotcha):
  forcing `es` renders the shipped Spanish empty-state button ("Abrir un PDF"),
  proving supportedLocales + the generated delegate + the app ARB are wired end
  to end.

### Gotchas hit

- **Deferred-loaded locale + widget tests.** The `es` localization is a deferred
  library (web chunking, `use-deferred-loading: true`). Once *any* localized app
  has booted earlier in the same test isolate, a second boot into `es` **never
  finishes loading the deferred library** — `pumpAndSettle`, `runAsync`, and
  bounded frame-pumping all leave `SCAFFOLDS: 0`. The fix is to keep the es
  render test **alone in its own file** (fresh isolate → its boot is the first).
  Documented in `doc/i18n.md`.
- **Picker pushed a pre-existing test off-screen.** Adding the ~72px Language
  dropdown to the top of the Settings dialog shifted the default-app tile below
  the fold on the smaller mobile `TargetPlatformVariant`s (their per-platform
  subtitle text is longer), so `tester.tap` by key hit an off-screen coordinate
  and the instructions dialog never opened — failing only android/ios/fuchsia.
  Fix: `tester.ensureVisible(tile)` before the tap, which is the correct thing
  regardless.
- **SharedPreferences mock caching.** First attempt at the es render test set
  `setMockInitialValues({...locale: es})` and booted the real app expecting its
  internal prefs to read it — but the mock's `SharedPreferences` singleton is
  cached process-wide, so a prior test's `getInstance()` had already frozen an
  empty store. Switched the widget-level check to the deterministic DevTools
  override and left the persistence proof to the (shared-cache-friendly) prefs
  unit test.

## Verification

- `dart analyze --fatal-infos` clean (root).
- `tool/check_arb_coverage.dart` green: 3 locale files across 3 bundles match.
- App suite green (271); editor + example suites green apart from the
  **pre-existing** CMYK/softmask `ghent_render_test` baseline failures (unrelated
  to strings).

## Next

`DateFormat`/`NumberFormat` (stamp months, numeric readouts); the remaining
tier-1/2 locales (each is now just an ARB drop + regenerate — picker and gate
follow automatically); engine-error→UI-message mapping.
