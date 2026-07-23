# DartPDF landing page

The marketing landing page for the **DartPDF** app. It is a single self-contained
static site (HTML + CSS, no build step). Generated from
[`doc/landing-prompt.md`](../doc/landing-prompt.md) via Claude Design and wired
up against the real product facts.

## Files

- `index.html` is the landing page (hero, features, privacy band, download,
  developers, footer). Self-contained: only external dependency is the Manrope
  web font from Google Fonts.
- `privacy.html` is the privacy policy, mirroring `app/PRIVACY.md`. This is the
  URL to use for the App Store / Play Store "privacy policy" listing field.
- `assets/editor-screenshot.png` is the hero screenshot of the editor.
- `firebase.json` / `.firebaserc` are the Firebase Hosting config.

## Localization (i18n)

The site is translated into the same 19 non-English locales the DartPDF app
ships (ar, de, es, fr, hi, id, it, ja, ko, nl, pl, pt, ru, th, tr, uk, vi, zh,
zh-Hant), with English as the source. It uses a lightweight client-side system —
no build step, no framework:

- `i18n/en.json` is the **source of truth**: a flat map of key → English
  string covering every page. It is also the runtime fallback.
- `i18n/<locale>.json` holds each translation with the same keys.
- `i18n.js` (included on every page via `<script src="/i18n.js" defer>`) detects
  the locale (`?lang=` override → saved choice → `navigator.languages` →
  English), lazily fetches the locale JSON, applies it over the DOM, sets
  `<html lang>`/`dir` (RTL for Arabic), and injects the language `<select>` into
  the `[data-i18n-switcher]` slot in the nav. English pages render with **zero
  fetches** because the English text is native in the HTML.

Markup contract in the HTML:

| Attribute | Effect |
|---|---|
| `data-i18n="key"` | sets `textContent` |
| `data-i18n-html="key"` | sets `innerHTML` (values with inline `<a>`/`<strong>`/`<code>`) |
| `data-i18n-attr="content:key;alt:key2"` | sets the named attribute(s) |

### Editing / adding strings

1. Add or change the English key in `i18n/en.json` and the matching
   `data-i18n*` marker in the HTML.
2. Add the same key to every `i18n/<locale>.json`.
3. Run the parity + tag-integrity check: `python3 i18n/_validate.py`
   (verifies every locale has the exact key set and that HTML values keep the
   same tags as English). `_validate.py` is dev-only and excluded from deploys.

Share a localized link directly with `?lang=<locale>`, e.g.
`https://dart-pdf.com/?lang=ja`.

## Local preview

Any static server works, e.g.:

```sh
cd site && python3 -m http.server 8000   # → http://localhost:8000
```

## Deploy

Hosted on the existing **`dart-pdf-demo`** Firebase project. Three sites now
live under that project:

| Site | `.web.app` | Custom domain | Serves |
|---|---|---|---|
| `dart-pdf-demo` | `dart-pdf-demo.web.app` | none | the SDK demo (`packages/dart_pdf_editor/example`) |
| `dartpdf` | `dartpdf.web.app` | `dart-pdf.com`, `www.dart-pdf.com` | this landing page (`site/`) |
| `dartpdf-app` | `dartpdf-app.web.app` | `app.dart-pdf.com` | the DartPDF web app (`app/`, `flutter build web`) |

Deploy the landing page:

```sh
cd site
firebase deploy --only hosting:dartpdf --project dart-pdf-demo
```

Deploy the web app (after `cd app && fvm flutter build web --release`):

```sh
cd app
firebase deploy --only hosting:dartpdf-app --project dart-pdf-demo
```

Custom domains were wired via the Firebase Hosting `customDomains` REST API
against Namecheap DNS (apex A `199.36.158.100` + `hosting-site=dartpdf` TXT;
`www`/`app` CNAMEs).

> The App Store / Play Store **privacy policy URL** is `https://dart-pdf.com/privacy`.
