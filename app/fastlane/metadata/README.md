# Localized store metadata

The full **DartPDF** app-store presence — every listing field and the
per-release "What's New" — for both stores, in every language the app ships
(see `app/lib/l10n/`). The English source of truth for the copy is
[`../../store-listing.md`](../../store-listing.md); the files here are its
localization, one folder per store language.

The layout follows the **fastlane** `supply` (Play) / `deliver` (App Store)
convention, so the trees upload as-is with `fastlane supply` /
`fastlane deliver`, or can be read field-by-field by the custom release tooling
described in [`../../RELEASING.md`](../../RELEASING.md) (App Store Connect
`appStoreVersionLocalizations`, Play `listings`/`releaseNotes`).

```
metadata/
  ios/<apple-locale>/            App Store Connect
    name.txt              (≤30)  app name
    subtitle.txt          (≤30)
    promotional_text.txt  (≤170) editable without review
    keywords.txt          (≤100) comma-separated, no spaces
    description.txt       (≤4000)
    release_notes.txt     (≤4000) "What's New" for the current version
  android/<play-locale>/         Play Console
    title.txt             (≤30)
    short_description.txt  (≤80)
    full_description.txt   (≤4000)
    changelogs/
      <versionCode>.txt    (≤500) "What's New" (19 = 2.1.0+19)
```

## Languages & store locale codes

The app's locale → the code each store expects. Apple and Play spell several
locales differently; the folder names below are what each console accepts.

| App locale | Language | App Store (`ios/`) | Play (`android/`) |
|---|---|---|---|
| en       | English (source)      | en-US   | en-US |
| ar       | Arabic                | ar-SA   | ar    |
| de       | German                | de-DE   | de-DE |
| es       | Spanish               | es-ES   | es-ES |
| fr       | French                | fr-FR   | fr-FR |
| hi       | Hindi                 | hi      | hi-IN |
| id       | Indonesian            | id      | id    |
| it       | Italian               | it      | it-IT |
| ja       | Japanese              | ja      | ja-JP |
| ko       | Korean                | ko      | ko-KR |
| nl       | Dutch                 | nl-NL   | nl-NL |
| pl       | Polish                | pl      | pl-PL |
| pt       | Portuguese (Brazil)   | pt-BR   | pt-BR |
| ru       | Russian               | ru      | ru-RU |
| th       | Thai                  | th      | th    |
| tr       | Turkish               | tr      | tr-TR |
| uk       | Ukrainian             | uk      | uk    |
| vi       | Vietnamese            | vi      | vi    |
| zh       | Chinese (Simplified)  | zh-Hans | zh-CN |
| zh_Hant  | Chinese (Traditional) | zh-Hant | zh-TW |

## Rules that shaped the copy

- **Apple Guideline 2.3.10 — no other-platform names.** The App Store
  `description`/`subtitle`/`promotional_text`/`keywords` never mention Android,
  Windows, Linux, or the web (v1.1.0 was rejected for this). The cross-platform
  sentence lives **only** in the Play `full_description`. This holds in every
  language, not just English.
- **Brand names are not translated:** `DartPDF`, `PAdES`. `OCR` stays literal
  unless a language has a conventional localized term.
- **Terminology matches the app UI.** Feature words (annotate, redact, sign,
  form, stamp, compare…) reuse the wording already in the app's ARB
  translations (`app/lib/l10n/`, `packages/dart_pdf_editor/lib/l10n/`).
- **Character limits are per store field**, counted in characters. The capped
  fields (subtitle, promotional text, keywords, short description, changelog)
  are kept within budget in every locale.

## Keeping it current

1. Edit the English source in [`../../store-listing.md`](../../store-listing.md)
   and the matching `en-US` files here.
2. For a new release, add `android/<locale>/changelogs/<versionCode>.txt` and
   refresh each `ios/<locale>/release_notes.txt` from
   [`../../release-notes/`](../../release-notes/). Version code = the `+build`
   in `app/pubspec.yaml`.
3. Re-translate the changed fields across the locale folders (the app ARB files
   are the terminology reference).

The screenshot/marketing text is localized separately — see
[`doc/screenshots/README.md`](../../../doc/screenshots/README.md) and
`doc/screenshots/captions/<locale>.json`.
