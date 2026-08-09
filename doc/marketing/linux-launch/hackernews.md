# Show HN

## Title (pick one, ≤ 80 chars, no emoji)

- `Show HN: DartPDF – an open-source PDF editor for Linux that edits page text`
- `Show HN: DartPDF – edit, redact, and sign PDFs on Linux, fully offline`

(First one leads with the differentiator HN cares about: editing the actual
content, not just annotating.)

## URL

https://dart-pdf.com/pdf-editor-linux  (or the GitHub repo — either is fine; the
landing page converts better, the repo signals "it's really open source". If you
post the landing page, put the repo link in the first comment.)

## Body (the first comment you post yourself)

> I've been building DartPDF, a PDF editor written from scratch in pure Dart —
> no PDFium, no MuPDF, no native PDF library underneath. It runs on Linux
> (Wayland and X11), and also macOS/Windows/Android/iOS and the web from the
> same codebase.
>
> The reason I started: on Linux you can *view* a PDF anywhere and *annotate* in
> a few apps, but editing the text that's already on the page, filling a form
> and having it stick, redacting so the data is actually gone, or adding a
> signature another program will verify — having all of that in one free app was
> hard to find. So the parser, font engine, renderer, and editor are all part of
> the project.
>
> What works today on Linux:
> - Edit existing on-page text and images; re-flow a paragraph
> - Fill AcroForms (text/checkbox/radio/dropdown) and save them
> - Redaction that removes the covered text/images from the file
> - Digital signatures: PAdES (B-B/B-T/B-LT/B-LTA) plus Sigstore-style keyless;
>   it validates the crypto but doesn't issue certs or vouch for signer trust
> - OCR for scans, on-device (downloads a model once)
> - Reorder/extract pages, full-text search, compare two versions
>
> Everything runs locally — editing, OCR, and signing. The only network use is
> optional timestamp/revocation checks for signatures and an update check;
> document content never leaves the machine.
>
> It's Apache-2.0. The preferred Linux install is the signed Flatpak from the
> project's own repository; AppImage and portable builds are available too.
> Links are on the page. Happy to go into the rendering pipeline, the
> encryption/signing stack, or why "pure Dart" was worth the pain. Feedback
> welcome.

## Notes for posting

- Post the body as the **first comment**, immediately after submitting, so the
  thread has context.
- Be around for the first 2–3 hours to answer — engagement early is what moves
  it. Technical questions (why pure Dart, how rendering works, signature
  validity) are the ones to answer in depth; that's the HN audience.
- If someone names a specific other tool, respond on capabilities/behaviour, not
  brand — keep your side neutral.
- Confirm the Flatpak one-click link and the fallback downloads are live before
  posting.
