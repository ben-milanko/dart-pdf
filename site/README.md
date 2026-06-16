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
