# 2026-07-23 — Marketing site full localization (19 locales)

Localized the static marketing site under `site/` (`index.html`, `privacy.html`,
`support.html`, `sdk.html`) into the same 19 non-English locales the app ships:
ar, de, es, fr, hi, id, it, ja, ko, nl, pl, pt, ru, th, tr, uk, vi, zh, zh-Hant.
English stays the source of truth and renders natively (no JS, no fetch).

## Approach — client-side, no build step

Kept the site's "single self-contained static page, no build step" ethos:

- `site/i18n/en.json` — flat key → English catalog (~200 keys) spanning all four
  pages; source of truth **and** runtime fallback.
- `site/i18n/<locale>.json` — one file per locale, same key set.
- `site/i18n.js` — detects locale (`?lang=` override → `localStorage` →
  `navigator.languages` → `en`), lazy-fetches the locale JSON, applies it over
  the DOM, sets `<html lang>` + `dir` (RTL for `ar`), injects a language
  `<select>` into `[data-i18n-switcher]`, and persists the choice. Loaded on
  every page with `<script src="/i18n.js" defer>`.

Markup contract added to the HTML: `data-i18n` (textContent), `data-i18n-html`
(innerHTML, for values with inline `<a>`/`<strong>`/`<code>`), and
`data-i18n-attr="attr:key;…"` (title/description meta, `alt`, `aria-label`).
Elements that mix an SVG icon with text got the text wrapped in a
`<span data-i18n>` so the icon survives.

Chose client-side over per-locale static files to avoid 76 duplicated HTML files
with no build step to keep them in sync; English remains crawlable as the
default render. `?lang=<locale>` gives shareable localized links.

## Translation generation

Drove 19 parallel translation sub-agents (one per locale), each reading
`en.json` and writing its own `<locale>.json` (no write contention). Rules:
preserve HTML tags/attributes, URLs, emails, code identifiers, brand/technical
proper nouns, numbers/units/filenames; translate visible text only; keep the
`←` in `back_arrow`; keep the date in `pp_updated`.

## Gotchas

- The pt-BR agent rendered "redact/redaction" as *refinar/refinamento* (refine).
  Corrected to *censura/censurar* (the Adobe Acrobat pt-BR term) across
  `featRedact*`, `sdkFeatRedact*`, and the meta/FAQ mentions.
- A few values are intentionally identical to English (`dlLinux_meta` =
  "AppImage · 64-bit", `foot_sdk` = "Flutter PDF SDK") — proper nouns/format
  names.
- Headless `--lang=` does not set `navigator.languages`; the `?lang=` override
  (also a real feature) made browser verification deterministic.

## Verification

- `site/i18n/_validate.py` — key parity + HTML-tag integrity for all 19 locales
  (dev-only, excluded from Firebase deploy via `firebase.json` ignore).
- Headless Chromium render of all four pages in de/ar/zh-Hant/fr/ja/ru: correct
  `<html lang>`/`dir`, localized nav/headings/table cells, `<span class="hl">`
  and inline links preserved, meta `content` localized, switcher injected.

## Follow-ups (not done)

- Native/community review of machine translations (Weblate/Crowdin on the JSON).
- Optional `hreflang`/`?lang=` alternates in `sitemap.xml` if per-locale SEO is
  wanted later.
