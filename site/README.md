# DartPDF landing page

The marketing landing page for the **DartPDF** app. It is a single self-contained
static site (HTML + CSS, no build step). Generated from
[`doc/landing-prompt.md`](../doc/landing-prompt.md) via Claude Design and wired
up against the real product facts.

## Files

- `index.html` is the landing page (hero, features, privacy band, download,
  developers, footer). Self-contained: only external dependency is the Manrope
  web font from Google Fonts.
- `sdk.html` serves the canonical `/flutter-pdf-editor` developer landing page.
  Firebase permanently redirects the old `/sdk` URL to it.
- `guides/add-pdf-editing-to-flutter.html` is the answer-first integration
  tutorial served at `/guides/add-pdf-editing-to-flutter`.
- `guides/pdf-forms-and-signatures.html` answers "does it support fillable
  AcroForm fields and signatures?" at `/guides/pdf-forms-and-signatures`
  (English-only, like the integration guide).
- `privacy.html` is the privacy policy, mirroring `app/PRIVACY.md`. This is the
  URL to use for the App Store / Play Store "privacy policy" listing field.
- `404.html` is the not-found page. Firebase Hosting serves it automatically
  (with a 404 status) for any URL that doesn't match a file. Because it can be
  served at *any* path depth, every link on it is root-absolute (`/support`,
  not `support.html`), and it is `noindex` and kept out of `sitemap.xml`.
- `assets/editor-screenshot.png` is the hero screenshot of the editor.
- `assets/promo-{app,sdk}.{webm,mp4}` + `-poster.webp` are the promo videos below the
  hero (app cut on the homepage, library cut on the SDK page), built from
  `doc/marketing/motion/`. `promo-video.js` plays them only while on screen and
  not at all under `prefers-reduced-motion`; each page carries a `VideoObject`
  JSON-LD block for them.
- `firebase.json` / `.firebaserc` are the Firebase Hosting config.

## Localization (i18n)

The marketing, support, and SDK overview pages are translated into the same 19
non-English locales the DartPDF app ships (ar, de, es, fr, hi, id, it, ja, ko,
nl, pl, pt, ru, th, tr, uk, vi, zh, zh-Hant), with English as the source. The
developer integration guide is English-only. The localized pages use a
lightweight client-side system — no build step, no framework:

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

## Search indexing

Use the extensionless, non-trailing-slash URLs on `https://dart-pdf.com`
in page canonicals, internal links, and `sitemap.xml`. Hosting redirects
`.html` and trailing-slash variants; `/sdk`, `/sdk/`, and `/sdk.html`
redirect directly to `/flutter-pdf-editor`. The `www` host declares the
apex URLs as canonical.

Every indexable page must be reachable through HTML links from the home
page, including English-only guides. `tool/site/seo.py` discovers pages from
their canonical tags and generates `sitemap.xml`, using each HTML file's
latest Git commit date for `lastmod`. New pages join the sitemap automatically;
unrelated commits and redeploys do not advance existing page dates. Generation
requires full Git history and committed HTML sources.

The **Deploy Site** workflow runs these checks on pull requests and before
deploying main: canonical routes, title/description/H1, internal links,
homepage reachability, robots rules, and direct redirects for URL variants.
It regenerates the sitemap for every deployment and then checks the live
domain's HTTP statuses, canonical/robots tags, sitemap, links, redirects, and
real 404 responses. Failed live checks fail the deployment workflow and are
reported in GitHub Actions.
The source checker supports the site's exact/simple-glob Hosting rules and
literal-prefix robots rules; unsupported patterns fail explicitly and require
extending the checker before deployment.

Run locally from the repository root:

```sh
python3 -m unittest discover -s tool/site -p 'test_*.py'
python3 tool/site/seo.py --write-sitemap
python3 tool/site/seo.py --live
```

In Search Console, redirect URLs and alternate pages with proper canonical
tags are expected exclusions. For a canonical page marked **Discovered –
currently not indexed**, inspect its live URL and request indexing; a
successful request queues a crawl and does not confirm indexing.

## Local preview

Any static server works, e.g.:

```sh
cd site && python3 -m http.server 8000   # → http://localhost:8000
```

## Deploy

Hosted on the existing **`dart-pdf-demo`** Firebase project. Four sites now
live under that project:

| Site | `.web.app` | Custom domain | Serves |
|---|---|---|---|
| `dart-pdf-demo` | `dart-pdf-demo.web.app` | none | the SDK demo (`packages/dart_pdf_editor/example`) |
| `dartpdf` | `dartpdf.web.app` | `dart-pdf.com`, `www.dart-pdf.com` | this landing page (`site/`) |
| `dartpdf-app` | `dartpdf-app.web.app` | `app.dart-pdf.com` | the DartPDF web app (`app/`, `flutter build web`) |
| `dartpdf-flatpak` | `dartpdf-flatpak.web.app` | none | the signed Flatpak repository (`flatpak-hosting/`) |

Deploy the landing page:

```sh
python3 tool/site/seo.py --write-sitemap # from the repository root, after committing HTML edits
cd site
firebase deploy --only hosting:dartpdf --project dart-pdf-demo
```

Deploy the web app (after `cd app && fvm flutter build web --release`):

```sh
cd app
firebase deploy --only hosting:dartpdf-app --project dart-pdf-demo
```

The Flatpak repository is published by
`.github/workflows/publish-flatpak.yml`; do not deploy `flatpak-hosting/`
from an empty `public/` directory. See
[`flatpak-hosting/README.md`](../flatpak-hosting/README.md).

Custom domains were wired via the Firebase Hosting `customDomains` REST API
against Namecheap DNS (apex A `199.36.158.100` + `hosting-site=dartpdf` TXT;
`www`/`app` CNAMEs).

> The App Store / Play Store **privacy policy URL** is `https://dart-pdf.com/privacy`.
