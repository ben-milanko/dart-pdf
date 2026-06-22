# Accessibility & archival conformance (Tagged PDF, PDF/UA, PDF/A)

This document covers the Tagged-PDF, PDF/UA-1, and PDF/A APIs in
`pdf_document` (with the text join in `pdf_graphics`), the rules the checkers
enforce, and the known limitations.

## APIs at a glance

Read (Tagged PDF):

```dart
final tree = PdfStructTree.of(document);          // null if untagged
for (final el in tree!.elementsInReadingOrder()) {
  print('${el.structureType} -> ${el.standardType}  alt=${el.alt}');
}
final logical = PdfTaggedText.extract(document);  // pdf_graphics: text joined in
print(logical!.text);                             // reading-order Unicode
```

Write / auto-tag:

```dart
final editor = PdfEditor(document);
editor.autoTag(title: 'My Report', lang: 'en-US');   // heuristic tagging + XMP
// or author explicitly:
editor.writeStructTree([
  PdfStructSpec('Document', children: [
    PdfStructSpec('H1', pageIndex: 0, mcids: [0]),
    PdfStructSpec('P',  pageIndex: 0, mcids: [1]),
  ]),
], lang: 'en-US');
final bytes = editor.save();
```

Validate:

```dart
final ua = validatePdfUa(document);          // PdfConformanceReport
print(ua.summary());

final a  = validatePdfA(document, part: 2);   // A-1b / A-2b / A-3b
print(a.summary());
```

Convert to PDF/A:

```dart
PdfEditor(document).convertToPdfA(
  iccProfile: sRgbIccBytes, iccComponents: 3,
  part: 2, level: 'B', title: 'My Report',
)..save();
```

## External validation (veraPDF)

veraPDF is the intended external oracle for both PDF/A and PDF/UA. **It could
not be run in the development environment** — the network policy blocks
`software.verapdf.org` (HTTP 403 `host_not_allowed`), so the checkers in this
package were implemented directly against the ISO specifications and validated
with the in-repo round-trip tests (auto-tag → `validatePdfUa` passes; convert →
`validatePdfA` passes). Before claiming formal conformance, run veraPDF
locally:

```sh
# auto-tag, save, then:
verapdf --flavour ua1 out.pdf
verapdf --flavour 2b  out.pdf
```

and reconcile any findings with the rule coverage below.

## PDF/UA-1 rules checked (`validatePdfUa`, ISO 14289-1)

| Clause | Check |
|--------|-------|
| 7.1 | `/MarkInfo /Marked true`; `/MarkInfo /Suspects` not true |
| 7.1 | `/StructTreeRoot` present |
| 7.2 | document `/Lang` present and non-empty |
| 7.1 | document title (`/Info /Title`) present and `/ViewerPreferences /DisplayDocTitle true` |
| 5   | XMP `/Metadata` with `pdfuaid:part = 1` |
| 7.1 | every structure type is standard or mapped via `/RoleMap` |
| 7.3 | `Figure` elements carry `/Alt` or `/ActualText` |
| 7.1 | fully-tagged content: no real content (text/path/image) outside a marked-content sequence that is tagged (`/MCID` in the tree) or an `/Artifact`; every content `/MCID` is referenced by the structure tree |
| 7.18 | link annotations carry `/StructParent` (warning) |
| 7.10 | `Formula` elements carry a text alternative (warning) |

Out of scope (cannot be decided mechanically): whether alt text / reading
order is *meaningful*, heading-level nesting semantics, table regularity,
contrast.

## PDF/A rules checked (`validatePdfA`, ISO 19005, level B)

| Clause | Check |
|--------|-------|
| 6.1.3 | not encrypted; trailer has a valid `/ID` |
| 6.1.2 | version ≤ profile max (A-1 → 1.4, A-2/A-3 → 1.7; catalog `/Version` honoured) |
| 6.2.2 | an OutputIntent `/S /GTS_PDFA1` with a `/DestOutputProfile` ICC stream (`/N` ∈ {1,3,4}) |
| 6.7   | XMP `/Metadata` with `pdfaid:part` and `pdfaid:conformance` matching the claimed profile |
| 6.3   | all fonts embedded (FontFile/2/3 on the descriptor; Type0 via descendant; Type3 exempt) |
| 6.1   | no `LZWDecode` filter |
| 6.6.1 | no document/annotation JavaScript or Launch actions; no `/AA` |
| 6.x   | (A-1/A-2 only) no `/EmbeddedFiles` |
| 6.5.3 | annotations are printable and not hidden (warning) |

## `convertToPdfA` — what it does and does not do

Adds, by incremental update: the OutputIntent + ICC, the `pdfaid` XMP packet,
a trailer `/ID`, and a catalog `/Version` cap. It refuses an encrypted
document (PDF/A forbids encryption and the converter does not re-emit content).

It does **not** synthesize font embedding or convert colour. A file whose
fonts are already embedded and whose colour is device-independent (or covered
by the OutputIntent) becomes conformant; a file using the non-embedded
standard-14 fonts still fails the font-embedding rule after conversion (run
`validatePdfA` to see what remains).

## Known limitations / remaining gaps

- **Font embedding for arbitrary input.** Converting a file that relies on the
  standard-14 (non-embedded) fonts to PDF/A would require substituting embedded
  font programs and subsetting. The `PdfEmbeddedFont` infrastructure
  (`font_embedder.dart`) embeds arbitrary TrueType/OpenType as a Type0 font and
  is the basis to build on; wiring it into the converter (with a bundled
  metric-compatible substitute for each base-14 face) is the main open item.
- **Auto-tagger semantics.** Roles are inferred from text geometry (size →
  heading, bullet → list); it produces *structurally valid* Tagged PDF, not
  semantically perfect tagging. Tables, multi-column reading order beyond the
  paragraph grouping, and figure alt text are not inferred — supply alt text
  and richer structure via `writeStructTree` when needed. Image/graphic content
  is marked as `/Artifact`; tag it as a `Figure` (with alt) explicitly when it
  conveys meaning.
- **veraPDF** was not run here (network-blocked); the in-repo checkers are the
  oracle for the acceptance round-trips.
