# Press pitch — Phoronix / OMG! Ubuntu / It's FOSS

One short email. Tailor the first sentence per outlet (angle below), keep the
body identical. Send individually (not a visible group). Best time: once the
Show HN thread has traction, so you can link it as social proof.

## Per-outlet angle (first line)

- **It's FOSS** (Abhishek Prakash / team) — reader-useful, "here's a tool":
  _"I thought It's FOSS readers might like a free, open-source PDF editor that
  actually edits PDFs on Linux, not just annotates them."_
- **OMG! Ubuntu** (Joey Sneddon) — app news, Flatpak availability, screenshots:
  _"There's a new open-source PDF editor available as a signed Flatpak that does
  the full job on Ubuntu — editing page text, forms, redaction, signing."_
- **Phoronix** (Michael Larabel) — technical/engineering angle, cross-platform,
  pure-Dart engine, performance:
  _"A from-scratch PDF engine written in pure Dart (no PDFium/MuPDF) now ships a
  native Linux editor — thought it might interest Phoronix on the engineering
  side."_

## Subject

`Open-source PDF editor for Linux — editing, redaction, and signing, fully local`

## Body

> Hi [name],
>
> [per-outlet first line]
>
> DartPDF is a PDF editor built from scratch in pure Dart — its own parser, font
> engine, renderer, and editor, with no native PDF library underneath. It runs
> natively on Linux (Wayland and X11) and shares a codebase with the
> macOS/Windows/mobile/web builds.
>
> What makes it worth a look for Linux users specifically: the free options here
> mostly view and annotate. DartPDF also edits the text and images already on
> the page, fills and saves forms, does true redaction (covered content is
> removed from the file), adds PAdES and keyless digital signatures, and OCRs
> scans — all on device, with no account and no uploads. It's Apache-2.0.
>
> The recommended Linux install is a signed Flatpak from DartPDF's official
> repository (`dev.milanko.dartpdf`). AppImage and portable builds are also
> available, and it integrates with the desktop as a proper PDF handler.
>
> - Landing page: https://dart-pdf.com/pdf-editor-linux
> - Source: https://github.com/ben-milanko/dart-pdf
> - Show HN discussion: [link once posted]
> - Press kit (screenshots, icon, description): [link — see below]
>
> Happy to answer anything, provide higher-res assets, or walk through the
> engine. No embargo — write whenever suits you.
>
> Thanks,
> Ben

## Press-kit checklist to attach/link

- 3–5 screenshots (the ones in `doc/marketing/app/macos/` work; a Linux/GNOME
  screenshot is better if you can grab one during hardware testing).
- App icon (512px from `app/linux/icons/hicolor/512x512/`).
- One-paragraph description + the feature bullet list (reuse from the landing
  page).
- License (Apache-2.0) and "fully local / no telemetry" line, stated plainly —
  reviewers ask.

## Notes

- Keep it under ~200 words above the links; editors skim.
- No competitor names. If they ask "how's it different from X" in reply, answer
  on capabilities.
- Give each outlet the same facts; don't offer exclusives you can't honour.
