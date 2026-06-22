# Accessibility & archival conformance: Tagged PDF, PDF/UA, PDF/A

Accessibility + archival conformance (Tagged PDF, PDF/UA, PDF/A). A four-phase
structural effort spanning pdf_cos's content parser, pdf_document, and
pdf_graphics. veraPDF — the intended external oracle for PDF/A and PDF/UA —
could NOT be run here: the environment's network policy blocks
software.verapdf.org (403 host_not_allowed), so the conformance checkers were
implemented against the ISO specs and our own checkers are the oracle for the
acceptance round-trips. Re-run veraPDF locally before claiming formal
conformance; see doc/conformance.md for the rule coverage and known
deviations.

Phase A — Tagged PDF read (struct_tree.dart, pure COS). `PdfStructTree.of(doc)`
wraps catalog /StructTreeRoot; `PdfStructElement` exposes /S, the role-mapped
`standardType` (transitive /RoleMap), /Alt, /ActualText, /Lang (inherited up
/P), /T, parent/children, and the content it tags: integer-/MCID and /MCR
marked-content references (`markedContent`) plus /OBJR object references
(`objectReferences`). `elementsInReadingOrder()` is a depth-first pre-order
walk; `markedContentInReadingOrder()` flattens MCIDs interleaving sub-structure
in true order. `PdfStructParentTree` parses /ParentTree (a number tree, kids +
Nums) for bottom-up MCID/StructParent->element lookup; `pageStructParentsKey`
reads a page's /StructParents. Gotcha: a struct element's /Pg is inherited by
its kids when they omit it (§14.7.4.4) — threaded as `inheritedPage`, NOT read
fresh per element. The text join lives one layer up (pdf_graphics, since
decoding glyph->Unicode needs the font engine, which pdf_document must not
import): the interpreter now keeps an MCID stack in lockstep with the
marked-content visibility stack (pushed/popped together at BDC/BMC/EMC, trimmed
to the same saved depth at every Form XObject / `_run` boundary and cleared
with it), and `_currentMcid` (innermost non-null) tags every PdfTextRun.
PdfTextRun.mcid -> PdfExtractedRun.mcid threads through extraction;
`PdfTaggedText.extract(doc)` slices each page's text by MCID span (preserving
separators) and joins it onto the tree as PdfLogicalNodes with real Unicode,
`accessibleText` (ActualText|text|Alt) and reading-order `fullText`.

Phase B — write/auto-tag (struct_tree_editor.dart, a new editor part).
`PdfStructSpec` is the author-side element description. `writeStructTree(roots)`
writes /StructElem objects (/S /P /Pg /Alt /ActualText /Lang /T, /K = mcids +
/OBJR + child refs), builds the /ParentTree (per-page MCID-indexed arrays +
one key per tagged object), stamps page /StructParents and object
/StructParent, and wires the catalog (/StructTreeRoot, /MarkInfo Marked true,
/Lang, /ViewerPreferences DisplayDocTitle, optional /RoleMap). Reserve the root
ref first (empty dict via addObject), fill /K after children exist — the same
adopt-then-mutate shape the rest of the editor uses. `autoTag()` is the
heuristic tagger: a self-contained light text-positioning pass over the parsed
content ops (own inline 6-double affine math — pdf_document can't depend on
pdf_graphics's PdfMatrix), groups runs into visual lines then paragraph blocks,
classifies by relative size (H1 >=1.7x median, H2 >=1.2x) and list markers
(L/LI/LBody), then rewrites the page content wrapping each tagged show op in
`/Tag <</MCID n>> BDC .. EMC` and each non-text painting op in
`/Artifact BMC .. EMC`, and authors the matching tree. One MCID per show op,
assigned in content order so the parent-tree array is naturally indexed. Why
self-contained instead of reusing the reflow inference: TJ emits one run per
array string, so emitted-run order does NOT correlate 1:1 with show-operator
index — a cross-layer run->operator mapping is fragile, and the tagger needs to
splice BDC/EMC into the operator stream anyway. Gotcha: `_writeOp`/`_setContent`
are private to OTHER editor extensions and not callable across Dart extensions,
so the tagger carries its own op serializer and writes /Contents directly via
`_updater`.

Phase C — PDF/UA-1 (conformance.dart shared report; xmp.dart; pdf_ua.dart).
`validatePdfUa(doc)` checks: tagged (/MarkInfo Marked, no Suspects),
/StructTreeRoot, document /Lang, title + DisplayDocTitle, XMP pdfuaid:part=1,
standard-or-role-mapped structure types, figures have /Alt|/ActualText,
fully-tagged content (a content-stream scan: every real-content operator —
text show, path paint, sh/Do/BI — must sit inside a marked-content sequence
that either carries an /MCID in the structure tree or is an /Artifact; and
every content MCID must be referenced by the tree), and link tagging. XMP is
plain-text RDF/XML (no platform XML dep) via `buildXmpPacket` with the dc/xmp/
pdf/pdfaid/pdfuaid schemas; `readPdfUaPart`/`readPdfaPart`/`readPdfaConformance`
parse it back. `setXmpMetadata`/`setMetadataStream` attach the catalog
/Metadata stream; `autoTag` now also writes pdfuaid:part=1 XMP, so its output
passes `validatePdfUa` (the acceptance round-trip).

Phase D — PDF/A (pdf_a.dart checker; convertToPdfA in the same editor
extension as the XMP helpers, because cross-extension private calls don't
work). `validatePdfA(doc, part:, level:)` checks A-1b/A-2b/A-3b level-B rules:
no encryption, trailer /ID, version cap (A-1 1.4, A-2/A-3 1.7, catalog
/Version overriding the header), an OutputIntent /S /GTS_PDFA1 with an ICC
/DestOutputProfile (/N in {1,3,4}), XMP pdfaid part+conformance match, ALL
fonts embedded (FontFile/2/3 on the descriptor; Type0 via descendant; Type3
exempt), no LZWDecode, no JavaScript/Launch/AA, and (A-1/A-2 only) no embedded
files. `convertToPdfA(iccProfile:..)` adds what it can without rewriting
content — OutputIntent+ICC, pdfaid XMP, /ID (md5 of bytes), version cap — and
refuses an encrypted document (can't re-emit content). It does NOT synthesize
font embedding: a base-14 (non-embedded Helvetica) file still fails the font
rule after conversion (asserted), while an already-embedded-font file
(buildEmbeddedFontPdf) converts to a passing PDF/A-2b — the acceptance round-
trip against our checker. Full arbitrary-PDF font embedding (substituting
embedded programs for the standard 14, subsetting) is the documented remaining
gap; the PdfEmbeddedFont infrastructure exists to build on.

Fixtures: `buildTaggedPdf()` (a marked, tagged one-page doc: Document -> H1 via
RoleMap / P / Figure with Alt+ActualText / Link OBJR, with a /ParentTree).
Tests: pdf_document struct_tree_test (10), struct_tree_editor_test (5),
pdf_ua_test (10), pdf_a_test (8); pdf_graphics struct_text_test (4). analyze
--fatal-infos clean; Ghent + PDF.js pure-Dart corpora and the Ghent render
baselines unchanged (the MCID work is purely additive to PdfTextRun).
