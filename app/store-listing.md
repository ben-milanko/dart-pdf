# DartPDF App Store / Play Store listing copy

Accurate to what the app ships today. Character budgets noted per field.
Update this file whenever the live listings change — it is the source of
truth for re-submissions.

> **Localized listings.** The English copy below is translated into every
> language the app ships, laid out per store in a fastlane-compatible tree
> under [`fastlane/metadata/`](fastlane/metadata/) (`ios/<locale>/` and
> `android/<locale>/`, plus per-release "What's New"). Localized marketing
> screenshot captions live in `doc/screenshots/captions/<locale>.json`. When
> you change any field here, mirror it into `en-US` there and re-translate the
> other locales — see [`fastlane/metadata/README.md`](fastlane/metadata/README.md).

> ⚠️ **Apple Guideline 2.3.10 — do not mention other platforms.** The App
> Store description, subtitle, promo text, keywords, and screenshots must
> not reference Android, Windows, Linux, or the web. Version 1.1.0 was
> rejected for exactly this; it was fixed in 1.2.2. The cross-platform
> sentence appears **only** in the Google Play description below. Never
> copy the Play description into App Store Connect.

---

## Apple App Store

**App Name** (≤30): `DartPDF`

**Subtitle** (≤30): `Edit, annotate & sign PDFs` _(26)_

**Promotional text** (≤170, editable without review):
`A PDF editor that runs entirely on your device. Mark up, fill in forms, sign, redact, and rearrange pages. No account, no ads, no uploads.` _(138)_

**Keywords** (≤100, comma-separated, no spaces):
`pdf,editor,annotate,markup,highlight,sign,signature,form,fill,redact,merge,pages,scan,ocr,compare` _(97)_

_(Dropped `document` and `viewer` — too generic to rank for an editor app —
in favor of `ocr` and `compare`, which are real features people search by
name.)_

**Description** (≤4000):

```
DartPDF is a PDF editor that runs entirely on your device.

Open any PDF to mark it up, fill in forms, sign it, redact content, rearrange pages, or edit the text and images on the page. Changes save back to the original file.

Nothing is uploaded. There's no account, no sync, and no ads.

Features:

• Highlight, underline, strikethrough, and freehand ink
• Shapes, arrows, text boxes, notes, and stamps
• Edit existing text and add images
• Redaction that removes the covered text and images from the file, not just from view
• Fill form fields (text, checkboxes, radio buttons, dropdowns), or add your own
• Drawn signatures placed anywhere, plus certificate-backed PAdES digital signatures
• OCR scanned PDFs so text can be selected and searched
• Reorder, delete, and export pages to a new file
• Full-text search, text selection, and links
• Compare two versions side by side
• Open password-protected files

Runs on iPhone, iPad, and Mac. Opens PDFs from the Files app, share sheets, or drag-and-drop. Light and dark themes.
```

**What's New** (write per release, in user-benefit language — no engine
jargon like "retained rendering" or "off-thread processing"):

Current (1.4.1):
`Large drawings and scanned plans now render sharper and stay smooth while you scroll. New: callout annotations with leader lines, and rich-text styling when editing text.`

---

## Google Play

**App name** (≤30): `DartPDF`

**Short description** (≤80):
`Edit, annotate, sign, and fill in PDFs. Everything stays on your device.` _(71)_

**Full description** (≤4000):

```
DartPDF is a PDF editor that runs entirely on your device.

Open any PDF to mark it up, fill in forms, sign it, redact content, rearrange pages, or edit the text and images on the page. Changes save back to the original file.

Nothing is uploaded. There's no account, no sync, and no ads.

Features:

• Highlight, underline, strikethrough, and freehand ink
• Shapes, arrows, text boxes, notes, and stamps
• Edit existing text and add images
• Redaction that removes the covered text and images from the file, not just from view
• Fill form fields (text, checkboxes, radio buttons, dropdowns), or add your own
• Drawn signatures placed anywhere, plus certificate-backed PAdES digital signatures
• OCR scanned PDFs so text can be selected and searched
• Reorder, delete, and export pages to a new file
• Full-text search, text selection, and links
• Compare two versions side by side
• Open password-protected files

Runs on Android, iPhone, iPad, and Mac, plus Windows, Linux, and the web. Opens PDFs from your file manager, share sheets, or drag-and-drop. Light and dark themes.
```

---

## Notes for whoever fills the listing
- Signature wording can distinguish the two shipped flows: drawn signatures
  are movable ink annotations; digital signatures are RSA/X.509 PAdES B-B
  approval signatures. DartPDF validates the cryptographic result but does not
  issue certificates or claim that a signer is trusted by a particular PKI.
- OCR/text-recognition can be advertised, but keep the privacy wording exact:
  native builds download a model once and then run OCR on device; web builds
  download browser model/runtime files and run OCR in the browser. Do not imply
  that OCR goes through a DartPDF server.
- Redaction: "removes from the file" is accurate — applying redactions burns
  them per PDF §12.5.6.23 (covered glyphs and fully-covered images are
  deleted from the content stream, then the whole file is re-serialized so
  the old bytes are gone; a byte search cannot recover them). One honest
  limit: an image only *partially* inside a redaction rect is painted over,
  not stripped — don't claim pixel-level removal *inside* partially-redacted
  images. See `pdf_document/lib/src/redaction.dart`.
- Keep the privacy claims exact. They match `app/PRIVACY.md` (collects nothing, on-device).
