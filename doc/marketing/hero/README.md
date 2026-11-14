# Landing-page hero captures

`site/assets/hero-desktop.webp` and `site/assets/hero-phone.webp` are real
captures of the DartPDF web build showing a signed sample agreement. Nothing
in them is mocked up: the document is a real PDF, and its annotations are
made with `PdfEditor`.

## Rebuild

```bash
python3 doc/marketing/hero/make_doc.py /tmp/hero/agreement.pdf /tmp/hero/geo.json
python3 doc/marketing/hero/sig.py /tmp/hero/sig.json
(cd packages/pdf_document && fvm dart run ../../doc/marketing/hero/annotate_hero.dart \
  /tmp/hero/agreement.pdf /tmp/hero/geo.json "/tmp/hero/Design agreement.pdf" /tmp/hero/sig.json)
(cd app && fvm flutter build web --release) && (cd app/build/web && python3 -m http.server 8765 &)
```

- `make_doc.py` (reportlab) draws the agreement and its AcroForm fields, then
  writes the anchor geometry (`geo.json`) the annotator uses.
- `sig.py` writes the handwritten signature as smoothed Catmull-Rom strokes.
- `annotate_hero.dart` fills the form, adds the highlights, the comment, and
  the ink signature.
- `open.cjs` (Playwright) opens the PDF through the app's file picker and
  takes the screenshot. `OPEN=x,y` is the "Open a PDF" button, in CSS px.
  Set `BOOT=14000` if the app hasn't finished loading when it clicks (the
  default wait is 8 s).

Captures used (cwd `doc/marketing/hero`; the tab title comes from the file
name, so keep it `Design agreement.pdf`):

```bash
OPEN=319,474 PDF="/tmp/hero/Design agreement.pdf" node open.cjs /tmp/hero/desk.png 820 740 2 0 wait:3000 click:133:124 wait:4000
OPEN=195,470 PDF="/tmp/hero/Design agreement.pdf" node open.cjs /tmp/hero/phone.png 390 844 3 1 wait:12000
```

The desktop capture closes the Pages panel (`click:133:124`), so the viewer
fits the page to the window width. The agreement is short enough that the
signature stays above the floating toolbar at that zoom. Export the desktop
capture at 1312 px wide and the phone capture at 585 px wide, as WebP at
quality 86.

The phone is captured at a real phone size (390x844), and the CSS frame adds
the status bar and camera cutout. The agreement has a second page (Schedule
A) so the space under page 1 on the tall screen shows the next page, the way
a real phone would, instead of empty grey. The longer wait gives page 2 time
to render.
