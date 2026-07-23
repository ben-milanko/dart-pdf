# 2026-07-23 — i18n phase 4: the rest of tier 1 (de, fr, pt, ru, ja, zh, hi, ar)

Phase 3 shipped the first real locale (Spanish) plus the picker, the persisted
preference, and the ARB coverage gate, and left the pipeline so "the next locale
is just drop an ARB, regenerate" (`2026-07-23-i18n-spanish-locale.md`). This
session cashes that in: **the whole of tier 1 now ships** — German, French,
Portuguese, Russian, Japanese, Simplified Chinese, Hindi, and Arabic — taking
`supportedLocales` from `[en, es]` to `[ar, de, en, es, fr, hi, ja, pt, ru, zh]`.
Arabic makes the phase-2 RTL sweep real: it's the first shipped right-to-left
locale.

## Eight locales × three bundles

Full locale ARBs alongside each `_en.arb` template, in all three bundles
(`packages/dart_pdf_editor/lib/l10n`, `app/lib/l10n`,
`packages/dart_pdf_editor/example/lib/l10n`): 560 / 227 / 120 message keys each.
Translation was fanned out to eight parallel agents, one per locale (each touches
its own files, so no write conflicts), mirroring the phase-3 Spanish approach.
Each read the English templates *including* the `@key` descriptions (the
translator context) and emitted only `@@locale` + the translated key/value pairs
in template order — gen-l10n reads placeholder/description metadata from the
template only, so the locale ARBs stay lean.

Preserved verbatim, human text only: ICU `plural`/`select` structure and branch
keywords (`=0`/`=1`/`one`/`other`; the `web`/`windows`/`macos`/`ios`/`android`/
`linux`/`other` platform arms), `{count}`/`{platform}`/… placeholders, brand and
technical nouns (DartPDF, font names, PDF/RSA/ECDSA/PEM/DER/CMS, RGB/HEX/HSL/
CMYK), and `\n`/trailing-space/ellipsis shapes. Russian and Arabic agents added
their language's extra plural categories (`few`/`many`, `two`) where grammar
needs them while keeping the template's existing branches. Per-locale terminology
was kept consistent across the three bundles (e.g. de Löschen/Speichern/
Lesezeichen/Stempel; ar حذف/حفظ/إشارة مرجعية/ختم). These are **seed** translations
— the plan (see `I18N_HANDOVER.md`) is machine/LLM seed now, community review
later; every agent flagged its low-confidence strings (mostly domain terms like
"Takeoff", "Redaction", "Reflow", and single-letter style-button labels) for that
pass.

## `pt_BR`/`zh_Hans` ship under their base tags `pt`/`zh`

The roadmap tiers list `pt-BR` and `zh-Hans`, but **gen-l10n refuses a
script/region-coded locale unless the base locale exists as a fallback**:

```
Arb file for a fallback, pt, does not exist, even though the following
locale(s) exist: [pt_BR]. When locales specify a script code or country code,
a base locale ... should exist as the fallback.
```

Shipping `pt_BR` + a duplicate `pt` fallback (or `zh_Hans` + `zh`) would be two
identical files with no added value — we only have one Portuguese and one Chinese
translation. So each ships under its **base** tag: the Brazilian Portuguese
content as `pt`, the Simplified Chinese content as `zh`. This matches Flutter's
own framework localizations, where bare `pt` **is** Brazilian and bare `zh`
**is** Simplified (the explicit variants are `pt_PT`/`zh_Hant`) — so our locale
resolves in lockstep with the Material/Cupertino/Widgets globals the app already
registers, and it covers the widest audience (a bare-`pt` or bare-`zh` device
resolves to it). The content is unchanged; only the BCP-47 tag differs. The
picker autonyms (`pt` → Português, `zh` → 中文) were already in
`app/lib/language_names.dart`, so no table change. When a real `zh_Hant` /
`pt_PT` lands later it takes precedence for those users automatically.

## Coverage-gate fix: ICU branch bodies aren't placeholders

Running `tool/check_arb_coverage.dart` on the new ARBs surfaced a **bug in the
gate itself**, not a translation error. The gate flagged German
`tbSelectionCount`:

```
key "tbSelectionCount" uses undeclared placeholder(s): {Auswahl}
```

The message is `{count, plural, =1{Selection} other{{count} selected}}`. The old
placeholder scan was a flat `\{(\w+)\}` regex, which reads the ICU **branch body**
`{Selection}` as an interpolation. English "Selection" is in the template so it's
allowed; German correctly translates that branch to "Auswahl", which the regex
then flags as a stray placeholder. Spanish only slipped through in phase 3 by
luck — "Selección" has a non-ASCII char, so `\w+` never matched it. Any
single-word ICU branch translated into a Latin-script locale would trip this.

Fix: `_placeholders` now walks the ICU structure (`_scanMessage`/`_scanBranches`
with a brace matcher) — it records the plural/select **argument** variable and
genuine `{name}` interpolations (including re-references like the `{count}` inside
the `other` branch), but treats a branch body's own delimiting braces as literal
text. So `{Selection}`/`{Auswahl}` are no longer placeholders, while a real typo
*inside* a branch (`{cont}` for `{count}`) or a stray `{foo}` in plain text is
still caught — both re-verified with negative probes. The gate passes on all 27
locale files across the three bundles.

## Test update: Arabic is a shipped locale now

`app/test/widget_test.dart`'s "a DevTools locale override forces the app onto
that locale" assumed forcing `ar` flips RTL **and** falls back to English (no ar
ARB). Both halves changed: ar now translates. Split into two tests:

- The unsupported-RTL-locale → English-fallback + RTL seam moves to **Hebrew**
  (`he`, still unshipped, still RTL) — same assertion, still valid.
- A new test forces `ar` and asserts both RTL **and** the Arabic empty-state
  button (`فتح ملف PDF`), the end-to-end proof that supportedLocales + the
  generated delegate + the app's ar ARB are wired for the first RTL locale.

## Verification

- `dart analyze --fatal-infos` clean (root).
- `tool/check_arb_coverage.dart` green: 27 locale files across 3 bundles match,
  with the ICU-aware placeholder check (positive + two negative probes).
- App suite green (272); example green (54). Editor suite green apart from the
  **pre-existing** CMYK/softmask `ghent_render_test` baseline failures (identical
  on the base commit, unrelated to strings).

## Next

Tier 2 (`zh_Hant`, ko, it, tr, vi, id, pl, nl, th, uk) — same drop-an-ARB +
regenerate; `zh_Hant` and any `pt_PT` now have their base fallback in place.
Still deferred from earlier phases: `DateFormat`/`NumberFormat` for stamp month
abbreviations and user-visible numeric readouts (careful to exclude PDF-syntax
number emission); engine-error → localized-UI-message mapping; a per-script font
smoke test; community review (Weblate/Crowdin) of these seed translations.
