# 2026-07-23 — i18n: locale-aware stamp dates

Tiers 1 and 2 shipped 20 UI locales, but the built-in stamp date/time fields
still emitted **hardcoded English**: month abbreviations (`Jan`…`Dec`) and
`AM`/`PM`, baked into `editing_stamps.dart` as `_monthNames` and a literal
`'AM'/'PM'` ternary. A French user placing a `{{date}}` stamp got `Jul` in an
otherwise French UI. This session cashes in the top "Still open" roadmap item —
`DateFormat` for stamp month abbreviations — while leaving the numeric readouts
(zoom %, scale ×) for later.

## What's localized (and what deliberately isn't)

`PdfStampDateFormat.format` / `PdfStampTimeFormat.format` grew an optional
`{String? localeName}`:

- **Spelled-out month names** (`dayMonthNameYear`, `monthNameDayYear`) now come
  from `intl.DateFormat.MMM(localeName)`.
- **AM/PM markers** (the 12-hour time shapes) come from
  `intl.DateFormat('a', localeName)`.
- **Numeric shapes stay ASCII**: `iso` (a fixed technical format, `yyyy-MM-dd`)
  and the `d/M/yyyy` slash forms keep padded ASCII digits regardless of locale,
  as do the 24-hour times. This is deliberate — `iso` is not a localized format,
  and digit **shaping** (Eastern-Arabic/Devanagari numerals) is a separate,
  louder decision than month names, so it's out of scope here.

`localeName == null` keeps the exact bundled-English behavior, so the
no-delegate host path (and every existing widget test that asserts
`'Jul 4, 2026 9:05:06 AM'`) is untouched.

## Where the locale comes from

The stamp text is materialized in `PdfEditingController`
(`_resolvedStampTemplateValues`), which has no `BuildContext`. Added a plain
`PdfEditingController.uiLocale` field (`ui.Locale?`, no `notifyListeners` — it's
an output detail, not observable state). Resolution order:

    uiLocale ?? preferences.locale  →  localeName  →  else English

`uiLocale` is kept fresh by `_EditingPageOverlayState.didChangeDependencies`
(`_controller.uiLocale = Localizations.localeOf(context)`) — the overlay is
always mounted during an editing session and rebuilds when the locale changes,
so the effective UI locale (which may differ from the persisted
`preferences.locale` when that's null/"System default", or under the DevTools
override) wins. `preferences.locale` is the fallback for the brief window before
the overlay mounts. The stamp date-format **picker previews**
(`_StampDateTimeFormatControls`) pass `Localizations.localeOf(context)` directly
since they build with a context in hand.

## Robustness: the `intl` locale-data trap

`DateFormat.MMM('fr')` throws unless `fr`'s date symbols are loaded.
`flutter_localizations` loads them for each locale its delegate resolves, so in
a running app the active locale is always available. A plain unit test that
never registers `flutter_localizations` has **no** symbols loaded, so both
helpers (`_monthAbbr`, `_dayPeriod`) wrap the `intl` call in a `try/catch` and
fall back to the English constant rather than crash a stamp placement. The new
tests call `initializeDateFormatting()` in `setUpAll` to exercise the real
localized path, and one case (`localeName: 'zzz-not-a-locale'`) pins the
fallback.

## Tests

New `localized stamp date/time formatting` group in `editing_stamps_test.dart`
(6 cases): English default preserved; `ja` month name (`7月`) on both name
shapes; numeric shapes stay ASCII under `ja`/`ar`; `ja` AM marker (`午前`) on
12-hour and none on 24-hour; unknown-locale fallback; and the controller
resolving `{{date}}` through `uiLocale`. Full `editing_stamps_test.dart` green
(49). Root `dart analyze --fatal-infos` clean. ARB coverage gate unaffected (57
files) — no message keys were added; this is content formatting, not UI strings.

## Caught up with main: translate the lock/unlock + search-annotations keys

Merging `main` in pulled the lock/unlock (#493) and search-annotations (#495)
features, which had added five English editor keys (`menuLock`, `menuUnlock`,
`searchAnnotations`, `sidebarLockAnnotation`, `sidebarUnlockAnnotation`) to
`_en.arb` **without** translating them into the 19 locales — so the ARB
coverage gate was red on `main` itself (and therefore on this PR's merge
result). Filled in all 19 locales (three distinct strings: "Lock"/"Unlock"
annotation verbs and "Search annotations"), matching each locale's existing
`shellPanelAnnotations` term for "annotation" (e.g. 注释 zh, 註解 zh_Hant, 주석
ko, Anmerkungen de), regenerated gen-l10n, and the gate is green again (57 files
across 3 bundles). These are seed translations for the same community-review
pass as the rest.

## Next (unchanged from tier 2)

`NumberFormat` for the remaining numeric readouts, engine-error→UI-message
mapping, a per-script UI-font smoke test, CJK-glyph embedding into editing
boxes, and community review of the seed translations.
