# Redaction removes what it covers everywhere, not just page text (#1255)

The report: a synthetic PDF with a fake SSN in a dozen places, every one
boxed and burned. Page text went, but image, form-field, Form XObject,
metadata, bookmark and attachment copies were still in the saved file. This
session fixed those, then ran two adversarial review rounds against the
burn. Every confirmed bypass has a regression test, and each one fails on
the code before its fix.

Code: `packages/pdf_document/lib/src/redaction.dart` (document level:
annotations, fields, scrubbing, purge, compaction) and the new part file
`redaction_burn.dart` (content-stream surgery, `_RedactionBurn`).

## Design rule

**Removing too much beats leaking.** Where something's geometry can't be
known exactly, it is judged by a deliberately generous bound and removed
whole when that bound touches a region. Errors fail closed: either the
burn throws and nothing is saved, or the thing that errored is dropped.
They never keep content.

## What the burn covers now

- **Text**: exact per-glyph splitting for simple fonts (with /Widths, or an
  exact base-14 name; `_RedFont._standardFont`) and Identity-H composites.
  - A glyph is tested along four lines through its body (0.1/0.3/0.5/0.7
    em, still clear of the next line on ordinary leading, #1162). The test
    spans its advance clamped to 0.25..1 em, because outlines sit near the
    origin whatever /Widths says. A Type 3 glyph is tested over the union
    of its `d1`/FontBBox boxes.
  - Unknown metrics (missing font, embedded or non-Identity CMap, vertical
    writing, widthless non-base-14) go through `_showConservatively`. The
    bound is every code an em plus |Tc|+|Tw| wide, in any direction, and
    the result leaves `_slack` set, so later shows in the same line stay
    conservative until a positioning operator.
  - `gs /Font` sets the font. Forms inherit the invoker's font **object**.
- **Paths**: a subpath goes when any point it names, or any sample along
  its curves (≤2pt apart), lies inside a region. A straight edge merely
  crossing a box (a table rule, a background) stays. Clips are kept. A
  subpath painted with a picture-carrying pattern (tiling, or a shading
  with a sampled/PostScript function or a mesh) goes when its bounds touch
  a region.
- **Form XObjects** are always burned, recursively. Their /BBox clips the
  drawing, not text extraction. Names resolve through the invoker's
  resources the way viewers resolve them (`_lookup`). Soft-mask groups in
  ExtGStates are burned the same way. Nesting is bounded by
  `_RedactionSession.maxFormBurns`.
- **Images**: covered pixels are cleared, along with the matching /SMask
  and /Mask pixels, and the image is re-encoded with Flate. JPX, CMYK or
  rotated JPEGs and unknown colour spaces are dropped whole. Copies keep
  only whitelisted keys (`_imageKeys`/`_formKeys`), so /Alternates, /OPI
  and private keys don't carry the original. Inline images that touch a
  box are dropped.
- **`sh`** with a picture-carrying shading and no /BBox (or one that
  touches a box) goes.
- **Marked content**: /ActualText, /Alt and /E are stripped from every
  enclosing BDC, inline or named (`/Properties`). The /MCIDs are recorded,
  and the owning structure elements and their ancestors lose theirs
  through the /ParentTree (`_stripStructTextOfRemoved`).

## Annotations and forms

Anything whose /Rect touches a box is removed, along with its popups and
/IRT replies. A popup under a box takes its owner, since it shows the
owner's /Contents. A widget takes its field once the field has no other
*shown* widget: listed on a page, not Hidden/NoView, with an area. The
whole subtree is purged and /XFA is dropped.

## Getting it out of the file

`_compactedSave(purged)` drops purged objects even where they are still
referenced: the reference leaves its array or dictionary, and a struct
/OBJR pointing at one goes too. This is how removed annotations leave the
/AcroForm tree, popups and the structure tree. Retired resources are
purged unless `_usedResourceNumbers` finds them still drawn somewhere: it
follows Do/scn/sh/gs/Tf/BDC through forms, tiling patterns, soft masks,
Type 3 glyphs and annotation appearances, with invoker fallback. Replaced
content streams are purged unless a page still shows them. A pattern no
kept paint uses also has its `scn` blanked, so the stream stops naming it.

## Hidden copies

`_RedactionScrubber` turns every removed span, and each 4+ character word
of it (on word boundaries), into a case-insensitive pattern that ignores
whitespace. It scrubs document info, XMP, bookmark titles and URIs,
struct-tree alternate text, and attachments (an entry that mentions the
text is dropped). `burnRedactions(removeHiddenInformation: true)`, the
default behind `applyRedactions`, also drops metadata (keeping Producer
and the dates), embedded files, document JavaScript and page /AA. Page
/Thumb and /PieceInfo always go on burned pages.

## Tests

- `test/redaction_hidden_content_test.dart`: the issue's experiment, with
  13 markers in one file and controls that must survive.
- `test/redaction_bypass_test.dart`: one test per review finding. Each
  asserts its marker is in the fixture first, so none can pass vacuously.
