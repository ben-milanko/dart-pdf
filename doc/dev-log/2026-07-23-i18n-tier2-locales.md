# 2026-07-23 — i18n tier 2 (zh_Hant, ko, it, tr, vi, id, pl, nl, th, uk)

Tier 1 shipped `[ar, de, en, es, fr, hi, ja, pt, ru, zh]` and left the pipeline
so "the next locale is just drop an ARB, regenerate"
(`2026-07-23-i18n-tier1-locales.md`). This session cashes that in for **the
whole of tier 2** — Traditional Chinese, Korean, Italian, Turkish, Vietnamese,
Indonesian, Polish, Dutch, Thai, and Ukrainian — taking `supportedLocales` from
10 to **20 UI locales**: `[ar, de, en, es, fr, hi, id, it, ja, ko, nl, pl, pt,
ru, th, tr, uk, vi, zh, zh_Hant]`.

## Ten locales × three bundles

Full locale ARBs alongside each `_en.arb` template, in all three bundles
(`packages/dart_pdf_editor/lib/l10n`, `app/lib/l10n`,
`packages/dart_pdf_editor/example/lib/l10n`): 560 / 227 / 120 message keys each,
so 907 strings per locale × 10 = 9070 seed translations. Translation was fanned
out to ten parallel agents, one per locale (each touches its own files, so no
write conflicts), mirroring the tier-1 approach. Each read the English templates
*including* the `@key` descriptions (the translator context) and emitted only
`@@locale` + the translated key/value pairs in template order — gen-l10n reads
placeholder/description metadata from the template only, so the locale ARBs stay
lean.

Preserved verbatim, human text only: ICU `plural`/`select` structure and branch
keywords (`=0`/`=1`/`one`/`other`; the `web`/`windows`/`macos`/`ios`/`android`/
`linux`/`other` platform arms), `{count}`/`{platform}`/`{author}`/… placeholders,
brand and technical nouns (DartPDF, font names, PDF/RSA/ECDSA/PEM/DER/CMS/X.509/
PKCS, RGB/HEX/HSL/CMYK, WebGPU/WASM/Florence-2/dots.ocr), keyboard glyphs
(⌘/⇧/Ctrl/Alt), and `\n`/trailing-space/ellipsis shapes. Polish and Ukrainian
agents expanded every `plural` message with the `few`/`many` branches their
grammar needs (2–4 → few, 5+/genitive → many), all reusing the original
`{count}` — no new placeholders introduced. These are **seed** translations
(machine/LLM now, community review later); every agent flagged its
low-confidence strings for that pass (see below).

## `zh_Hant` ships as the explicit script variant

Tier 1 shipped Simplified Chinese under the base tag `zh` (bare `zh` is
Simplified in Flutter's framework localizations). Traditional Chinese is the
explicit `zh_Hant` variant. gen-l10n **requires a base fallback for any
script-coded locale** — the same rule that made us ship `pt_BR`/`zh_Hans` content
under bare `pt`/`zh` in tier 1. That base (`zh`) now exists, so `zh_Hant` is
accepted. gen-l10n nests the script variant's class inside the base locale's
generated file (`AppLocalizationsZhHant` lives in `app_localizations_zh.dart`,
not a new `_zh_Hant.dart`), so the three `_zh.dart` files show as *modified* while
the other nine locales each add a fresh `_<locale>.dart`. `supportedLocales` gets
`Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')` automatically. The
translation is genuine Taiwan-terminology Traditional (檔案/儲存/尋找/字型/算繪),
not a byte-copy of the Simplified content.

## Everything else was already wired for these locales

Tier 1 left the supporting pieces generic, so tier 2 needed **no** code changes
beyond the ARBs and regenerated Dart:

- **Autonyms** — `app/lib/language_names.dart` already listed all ten tier-2
  languages (한국어, Italiano, Türkçe, Tiếng Việt, Bahasa Indonesia, Polski,
  Nederlands, ไทย, Українська, plus `zh-Hant` → 繁體中文), so the Settings picker
  names them without a table edit.
- **Coverage gate** — `tool/check_arb_coverage.dart` validates all of them; it now
  passes **57 locale files across the 3 bundles** (was 27 after tier 1).
- **`tool/trim_locales.sh`** — discovers locales from the `.arb` filenames, so the
  new languages are trimmable/restorable for free.
- **`MaterialApp` wiring / persisted picker** — `supportedLocales` and the
  delegate are read straight from the generated class; `PdfEditingPreferences.
  locale` round-trips a script+region tag already (the tier-3 `zh-Hans-CN` prefs
  test covers `zh_Hant` too).

## No test changes needed

The tier-1 DevTools-override tests already split cleanly: the unsupported-RTL →
English-fallback seam pins **Hebrew** (`he`, still unshipped, still RTL) and the
shipped-RTL proof pins **Arabic**. Neither assumption changes by adding ten
LTR/base-CJK locales, and nothing enumerates the full `supportedLocales` count.
App suite green (272), example green (54).

## Verification

- `dart analyze --fatal-infos` clean (root).
- `tool/check_arb_coverage.dart` green: 57 locale files across 3 bundles match,
  with the ICU-aware placeholder check.
- App suite green (272); example green (54). Editor suite green apart from the
  **pre-existing** CMYK/softmask `ghent_render_test` baseline failures (identical
  on the base commit, unrelated to strings).

## Low-confidence seed strings (for the community-review pass)

Every agent converged on the same short list of domain terms with no settled
target-language equivalent — worth prioritizing in native review across all ten
locales:

- **Takeoff** (construction quantity takeoff) — left English (id) or glossed
  (計算/估算 zh_Hant, 물량 산출 ko, Metraj tr, Computo it, Przedmiar pl, Обсяг робіт
  uk, Bóc tách vi, การถอดปริมาณ th, Hoeveelheden nl).
- **Redaction / Redact** — many valid renderings (塗黑 vs 密文, 교정 vs 삭제, Karartma,
  Oscuramento, wymazanie, …); pick one per locale.
- **Reflow** — reformat/re-flow verbs vary; confirm against the reflow-view UX.
- **Callout / Squiggly / Cloud polygon** — annotation-type names; check house CAD/
  markup terminology.
- **Shell** (section header) — abstract UI-chrome noun that reads oddly literalized
  in several locales.
- **Single-letter style labels** (`B`/`I` bold/italic, `W`/`H` geometry) — some
  agents localized the initials (G/C, Szer./Wys., R/C), others kept the Latin
  glyphs; confirm which the compact controls expect.
- **Keyless / self-signed / "validity unknown"** signing prose — security wording,
  sensitive to tone; native pass recommended.

## Next

Tier 2 completes the planned locale roadmap. Still deferred from earlier phases:
`DateFormat`/`NumberFormat` for stamp month abbreviations and user-visible numeric
readouts (careful to exclude PDF-syntax number emission); engine-error → localized
UI-message mapping; a per-script UI-font smoke test; CJK-glyph embedding for text
typed into an editing box (bundled editing fonts stay Latin-only); and wiring the
ARBs up to Weblate/Crowdin for community review of these seed translations.
