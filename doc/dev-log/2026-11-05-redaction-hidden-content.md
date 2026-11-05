# Redaction removes what it covers everywhere, not just page text (#1255)

The report: a synthetic PDF with a fake SSN in a dozen places, every one
boxed and burned. Page text went, but image, form-field, Form XObject,
metadata, bookmark and attachment copies were still in the saved file. This
session fixed those, then ran two adversarial review rounds against the
burn (20, then 14 confirmed bypasses), then third and fourth verification
rounds (21 and 14 failures). Every confirmed bypass has a regression test, and each one fails on
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

## Round 2: making viewers and the burn agree

The second review was about *disagreement*. The burn modelled a malformed
operator one way while viewers read it another, so the burn kept what
they show under the box.

- **Canonical operators** (`_canonical`, `_arity`). Every interpreted
  operator is rewritten with exactly the operands the burn read: the
  *last* n, as poppler and pdf.js take them. An operator with too few or
  mistyped operands is dropped, as viewers drop it. Over-long `cm`/`Td`,
  two-string `Tj` and two-name `Do` can no longer be read two ways.
- **Inline images** (`_canonicalInlineImage`). Unfiltered data is cut to
  its computed length, and any data still containing `EI` is dropped,
  because viewers find the end of inline data differently.
- **Malformed paths** broken off by another operator are dropped. Some
  viewers would paint them at the next paint operator.
- **Clips** are judged like fills, so a glyph outline can't print through
  a later full-page fill. A clip emptied this way clips everything away.
  Clip bounds are tracked for `sh`.
- **Strokes**: regions grow by the reach of the ink (half the width, times
  the miter limit). A dashed stroke goes when its hull touches a box, and
  a `d` no kept stroke uses is blanked. A dash carried in an ExtGState
  `/D` gets a solid copy.
- **Shadings**: stitching functions count as pictures, since their bounds
  are a 1-D raster. A plain gradient also goes when its end points or
  circles sit under a box, and a `sh` clipped to nothing goes.
- **Type 3** glyphs are tested over their own box (`d1` plus the ink the
  procedure actually lays down), with lines at most 0.2 em apart. A
  skewed FontMatrix makes the font's metrics unknown.
- **Composite strings** with a stray byte, or with word spacing set, go
  through the generous path.
- **One redacted copy replaces the original everywhere**
  (`_retireOriginals`, compaction `substitutes`). Any other use (another
  page, an off-page draw, a pattern) gets the copy. With several differing
  copies the original is purged. This removes too much where a repeated
  logo is half covered on one page, and that is deliberate.
- **Structure**: an XObject's own `/StructParent` and MCIDs in forms
  without `/StructParents` (numbered as their invoker's) strip their
  elements' text.
- **Compaction sweep**. With `removeHiddenInformation`, every `/AF`,
  `/Metadata`, `/PieceInfo`, `/Thumb`, `/EF`, `/RF` and JavaScript action
  goes, anywhere in the file. Every string left in the file is scrubbed
  of the removed text (comments, page labels, name-tree keys, field
  values, `/TU`...), and so are `/Dests` keys.
- A sibling widget off its page's crop box no longer counts as shown.

## Round 3: fonts, shared resources, encodings

A third round (21 confirmed failures, 17 regression tests in the `round 3`
group) found these:

- **Glyph metrics viewers disagree on are no longer treated as exact**
  (`_RedFont.knowsCode`).
  - A widthless base-14 font is indexed by WinAnsi code, while viewers
    measure by glyph name. Only codes that name the same glyph either way
    count as exact: all of WinAnsi for an explicit `/WinAnsiEncoding`,
    otherwise printable ASCII except the two quote codes, and never a
    `/Differences` code.
  - `/Widths` with non-numeric entries, codes outside
    FirstChar..min(LastChar, end of table), and Identity-H `/W` with
    overlapping ranges all go through the generous path.
- **Direct resources in shared dictionaries**. A retired entry that lives
  directly in a resource dictionary another page or the page tree shares
  is fixed in that dictionary at save time (`directRetired`). It points at
  its one redacted copy, or else is dropped. Retirement and substitution
  follow reference chains (`_chain`), since an object can hold nothing but
  another reference.
- **Forms**.
  - A field climb only goes through a `/Parent` that is a field listing
    the child.
  - `_guardPageTree` refuses to save if the purge would touch the catalog
    or page tree.
  - A removed annotation's appearance streams and `/MK` icons are purged,
    even where shared.
  - Sibling widgets under `/OC`, or flagged hidden with a real-valued
    `/F`, don't count as shown.
  - Array and stream field values feed the scrubber.
- **Scrubbing**.
  - Strings are read as UTF-16LE (with BOM), PDFDocEncoding and raw
    Latin-1.
  - The scrubber also matches once markup is stripped, character
    references are decoded and percent escapes are decoded (`/RC`, XMP,
    URIs). An XMP packet that only matches decoded is dropped.
  - Named `/Dest`/`/D` values spelled with the text are dropped.
  - Without `removeHiddenInformation`, `/AF` arrays and FileAttachment
    annotations that mention the text go too, matched in UTF-16 as well.

## Round 4: annotations, exact names, copies of shared dictionaries

A fourth round found 14 more failures, each with a test in the `round 4`
group:

- **Annotation extent** (`_annotationExtent`). An annotation goes when any
  place it can draw touches a box:
  - its /Rect;
  - the geometry viewers draw from directly (/L with caption, /InkList,
    /Vertices, /QuadPoints, /CL, padded by 24pt);
  - for NoRotate annotations, the /Rect turned about its upper-left corner.

  An unreadable /Rect takes the annotation. Kept annotations have their
  appearance streams burned through the /BBox→/Rect mapping
  (`_burnKeptAppearances`), because text clipped away by the /BBox still
  extracts at its mapped position.
- **Exact names only**. Only the canonical base-14 names are trusted, case
  and all, with no subset tag or alias, as poppler matches them. Codes are
  exact only under Standard, MacRoman or WinAnsi base encodings (/BaseEncoding
  is honoured). A real /FirstChar, a real /DW, and non-numeric entries
  inside /W arrays all go through the generous path.
- **Copies of shared dictionaries**. A burn records every copy it makes of
  a resource category dictionary (`resourceCopies`). A fix to the
  original's direct entries is applied to every copy, whichever burn made
  it first.
- **Marked content left open** at the end of a stream (opened in a form,
  closed by its invoker) has its replacement text stripped.
- **Shared content streams**. A page showing the very content stream a burn
  replaced is pointed at the burned stream, as a shared form is. A page
  sharing only part of it loses that part.
- Field-tree and number-tree walks keep visited sets. Type 3 ink bounds
  account for line width and treat `gs` as unbounded.

## Known limitations

- Font programs are kept, as in other redaction tools. This includes Type
  3 glyph procedures, whose glyphs may be in use elsewhere. A glyph whose
  shape is itself the secret (a signature turned into a Type 3 glyph), or
  a subset font's list of glyphs, can survive in the file.
- The glyph-position model assumes outlines near the origin
  (0.25..1 em × 0.1..0.7 em). A crafted embedded font with ink far from
  its origin is not detected; the text its codes encode is still placed
  correctly.
- With `removeHiddenInformation: false`, an attachment that holds the text
  compressed (a zip, an Office file) is not detected; the default removes
  every attachment.
- A ligature or a glyph without `/ToUnicode` gives an empty or wrong span,
  so hidden copies of that text are not matched. Structure text tied to
  the content by MCID is still stripped.

## Tests

- `test/redaction_hidden_content_test.dart`: the issue's experiment, with
  13 markers in one file and controls that must survive.
- `test/redaction_bypass_test.dart`: one test per review finding (the
  `round 2` group is the second review). Each asserts its marker is in
  the fixture first, so none can pass vacuously, and each failed on the
  code before its fix.
