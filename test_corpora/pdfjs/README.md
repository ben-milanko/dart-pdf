# pdf.js test corpus

171 real-world edge-case PDFs curated from the
[mozilla/pdf.js](https://github.com/mozilla/pdf.js) test suite
(`test/pdfs/`, commit `2466a76ba454`), each fetched from
`https://raw.githubusercontent.com/mozilla/pdf.js/2466a76ba45411cf01a0fad278b40be72cdc4bff/test/pdfs/<name>`.

Where the Ghent suite pins print-production features, this corpus pins
robustness: fuzzed crashers, lying xrefs and /Counts, junk inside
content streams, odd font programs, filter and encryption corner cases.
Test layers:

- `packages/pdf_graphics/test/pdfjs_corpus_test.dart` — pure Dart:
  per-file pinned expectations (opens / controlled failure / password /
  may-be-blank); every page must interpret without throwing.
- `packages/dart_pdf_editor/test/pdfjs_render_test.dart` — rasterizes every
  page: by default the decode pipeline must not throw; with
  `PDFJS_BASELINE_DIR` set, Dart rasters are pixel-compared against
  generated PDF.js reference PNGs. Generate those references from the repo
  root:
  `cd packages/dart_pdf_editor/tool/pdfjs_baseline && npm install && npm run render`.

Checked-in visual artifacts:

- [`_baselines/`](_baselines/) — PDF.js reference PNGs generated from this
  corpus.
- [`_renders/README.md`](_renders/README.md) — GitHub-rendered side-by-side
  visual review gallery with PDF.js baseline, Dart render, and diff images,
  plus a summary table of per-page diff percentages and pass/fail results.
  As of the last regeneration,
  <!-- render-summary:start -->**71 of 200 compared pages pass**<!-- render-summary:end -->
  (≤ 0.05% of pixels differing from the PDF.js baseline); see that file for
  the per-file breakdown.
- Rebuild only the gallery index after adding/removing PNGs with
  `fvm dart packages/dart_pdf_editor/tool/rebuild_pdfjs_render_index.dart`
  from the repo root.

## Structure & lenient parsing

- `bad-PageLabels.pdf` — corrupt /PageLabels
- `ContentStreamCycleType3insideType3.pdf` — Type3 charproc cycle
- `ContentStreamNoCycleType3insideType3.pdf` — Type3 in Type3 (no cycle)
- `empty.pdf` — minimal empty document
- `extractPages_null_in_array.pdf` — null entries in arrays
- `franz_2.pdf` — XObject BBox with indirect entry
- `GHOSTSCRIPT-698804-1-fuzzed.pdf` — fuzzed (ghostscript crasher)
- `helloworld-bad.pdf` — broken hello world
- `issue1293r.pdf` — undefined stream /Length
- `issue4461.pdf` — page without /Resources
- `issue5280.pdf` — indirect /DecodeParms
- `issue7872.pdf` — MediaBox/CropBox indirect objects
- `multiple-filters-length-zero.pdf` — filter chain + /Length 0
- `openoffice.pdf` — OpenOffice producer
- `operator-in-TJ-array.pdf` — operator inside TJ array
- `operator_list_cycle.pdf` — content stream cycle
- `Pages-tree-refs.pdf` — page tree reference loops
- `PDFBOX-3148-2-fuzzed.pdf` — fuzzed pdfbox crasher
- `PDFBOX-4352-0.pdf` — fuzzed pdfbox crasher
- `PDFJS-7562-reduced.pdf` — reduced pdf.js crasher
- `pdfjsbad1586.pdf` — broken xref offsets
- `pdfkit_compressed.pdf` — pdfkit object streams
- `poppler-395-0-fuzzed.pdf` — fuzzed poppler crasher
- `poppler-67295-0.pdf` — fuzzed poppler crasher
- `poppler-742-0-fuzzed.pdf` — fuzzed poppler crasher
- `poppler-85140-0.pdf` — fuzzed poppler crasher
- `poppler-91414-0-53.pdf` — fuzzed poppler crasher
- `poppler-91414-0-54.pdf` — fuzzed poppler crasher
- `poppler-937-0-fuzzed.pdf` — fuzzed poppler crasher
- `REDHAT-1531897-0.pdf` — fuzzed (poppler CVE case)
- `scan-bad.pdf` — broken scanned document
- `sci-notation.pdf` — scientific notation numbers
- `xref_command_missing.pdf` — xref keyword missing

## Fonts

- `90ms_rksj_h_sample.pdf` — 90ms-RKSJ-H CMap
- `arial_unicode_ab_cidfont.pdf` — CID TrueType
- `bug1011159.pdf` — Type3 negative HScale
- `bug816075.pdf` — CIDFontType0 whose CFF isn't CID
- `bug866395.pdf` — empty font file
- `bug898853.pdf` — multi-byte char codes
- `bug921409.pdf` — CIDFontType0 with Type1C file
- `bug946506.pdf` — fonts referenced by name only
- `cid_cff.pdf` — CID-keyed CFF
- `cidfont_cmap_overflow.pdf` — CID cmap overflow
- `complex_ttf_font.pdf` — complex TrueType
- `endchar.pdf` — CFF endchar/seac
- `font_ascent_descent.pdf` — ascent/descent metrics
- `franz.pdf` — Type1 refs in /Differences
- `glyph_accent.pdf` — accent glyphs as curves
- `IdentityToUnicodeMap_charCodeOf.pdf` — identity ToUnicode
- `issue3061.pdf` — CFF CID with dual font matrices
- `issue3521.pdf` — predefined CMap GBKp-EUC-H
- `issue3566.pdf` — CFF multiply-encoded glyph
- `issue3584.pdf` — CFF drawn with clipping
- `issue3928.pdf` — Type1 Length1/Length2 wildly wrong
- `issue4573.pdf` — seac with odd /Differences
- `issue4684.pdf` — broken invisible TrueType
- `issue4800.pdf` — TrueType (0,1) cmap
- `issue5138.pdf` — glyph mapped to U+00A0
- `issue5564_reduced.pdf` — cmap with invalid glyph ids
- `issue5686.pdf` — Type1 Length1/Length2 slightly wrong
- `mmtype1.pdf` — Multiple Master Type1
- `noembed-eucjp.pdf` — non-embedded EUC-JP CMap
- `noembed-identity.pdf` — non-embedded Identity CID
- `noembed-sjis.pdf` — non-embedded Shift-JIS CMap
- `non-embedded-NuptialScript.pdf` — exotic non-embedded font
- `pr4922.pdf` — Type3 missing /CharProcs
- `recursiveCompositGlyf.pdf` — recursive composite glyphs
- `SimFang-variant.pdf` — SimFang variant
- `simpletype3font.pdf` — minimal Type3
- `standard_fonts.pdf` — all 14 standard fonts
- `text_clip_cff_cid.pdf` — text clip (Tr 7) with CFF CID
- `TrueType_without_cmap.pdf` — TrueType without cmap
- `Type3WordSpacing.pdf` — Type3 word spacing
- `vertical.pdf` — vertical writing mode
- `XiaoBiaoSong.pdf` — Chinese font subset
- `ZapfDingbats.pdf` — ZapfDingbats base font

## Filters & image codecs

- `asciihexdecode.pdf` — ASCIIHexDecode
- `bitmap-halftone.pdf` — JBIG2 halftone region
- `bitmap-mmr.pdf` — JBIG2 MMR coding
- `bitmap-refine.pdf` — JBIG2 refinement
- `bitmap-symbol-symhuff-texthuff.pdf` — JBIG2 Huffman symbol/text regions
- `bitmap-symbol-textcomposite.pdf` — JBIG2 text region composite
- `bitmap-symbol.pdf` — JBIG2 symbol dictionary
- `bitmap-template1.pdf` — JBIG2 generic template 1
- `bitmap-template2-tpgdon.pdf` — JBIG2 template 2 + TPGDON
- `bitmap-template3-customat.pdf` — JBIG2 template 3 custom AT
- `bug1065245.pdf` — inline JPEG images
- `ccitt_EndOfBlock_false.pdf` — CCITT /EndOfBlock false
- `cmykjpeg.pdf` — CMYK JPEG
- `decodeACSuccessive.pdf` — progressive JPEG
- `jbig2_file_header.pdf` — JBIG2 with file header
- `jbig2_symbol_offset.pdf` — JBIG2 symbol offset
- `jp2k-resetprob.pdf` — JPX reset-prob coder option

## Images & masks

- `colorkeymask.pdf` — color-key mask
- `image-rotated-black-white-ratio.pdf` — rotated 1-bit image
- `images_1bit_grayscale.pdf` — 1-bit grayscale
- `IndexedCS_negative_and_high.pdf` — Indexed out-of-range entries
- `issue2761.pdf` — Indexed over Lab base
- `issue4246.pdf` — mask larger than image
- `smask_alpha_bc.pdf` — SMask alpha + BC
- `smask_alpha_oob.pdf` — SMask alpha out-of-bounds
- `smask_alpha_oob_transfer.pdf` — SMask alpha OOB + transfer fn
- `smask_luminosity_oob_transfer.pdf` — SMask luminosity OOB + transfer
- `smaskdim.pdf` — SMask dimensions mismatch
- `xobject-image.pdf` — minimal image XObject

## Color spaces & functions

- `calgray.pdf` — CalGray color space
- `calrgb.pdf` — CalRGB color space
- `colorspace_atan.pdf` — type 4 function (atan) in colorspace
- `devicen.pdf` — DeviceN
- `type4psfunc.pdf` — type 4 PostScript functions

## Shadings

- `coons-allflags-withfunction.pdf` — Coons patch, all flags + function
- `function_based_shading.pdf` — type 1 function shading
- `gradientfill.pdf` — axial gradient fill
- `mesh_shading_empty.pdf` — empty mesh shading
- `radial_gradients.pdf` — radial gradients
- `shading_extend.pdf` — /Extend semantics
- `tensor-allflags-withfunction.pdf` — tensor patch, all flags + function

## Patterns

- `issue3458.pdf` — pattern transform != base transform
- `pattern_text_embedded_font.pdf` — pattern-filled text
- `ShowText-ShadingPattern.pdf` — text filled with shading pattern
- `tiling-pattern-box.pdf` — tiling pattern BBox
- `tiling-pattern-large-steps.pdf` — tiling with huge steps
- `tiling_patterns_variations.pdf` — tiling variations

## Transparency

- `alphatrans.pdf` — alpha transparency
- `bigboundingbox.pdf` — huge transformed group BBox
- `blendmode.pdf` — every blend mode
- `knockout_isolated_overlap.pdf` — isolated knockout overlap
- `knockout_smask.pdf` — knockout group + soft mask
- `transparent.pdf` — transparency groups

## Graphics operators

- `boundingBox_invalid.pdf` — invalid bounding box
- `clippath.pdf` — clip before path exists
- `close-path-bug.pdf` — close-path edge case
- `hello_world_rotated.pdf` — /Rotate page
- `rotation.pdf` — all /Rotate values
- `sizes.pdf` — mixed page sizes
- `text_rise_eol_bug.pdf` — text rise at EOL
- `zerowidthline.pdf` — zero-width lines

## Annotations

- `annotation-highlight-without-appearance.pdf` — Highlight without AP
- `annotation-ink-without-appearance.pdf` — Ink without AP
- `annotation-line-without-appearance-empty-Rect.pdf` — no AP + empty /Rect
- `annotation-line-without-appearance.pdf` — Line without AP
- `annotation-square-circle-without-appearance.pdf` — Square/Circle without AP
- `annotation-squiggly-without-appearance.pdf` — Squiggly without AP
- `annotation-strikeout-without-appearance.pdf` — StrikeOut without AP
- `annotation-underline-without-appearance.pdf` — Underline without AP
- `bug1552113.pdf` — absurd border width
- `bug886717.pdf` — annotation with no resources
- `file_url_link.pdf` — file:// link
- `freetext_no_appearance.pdf` — FreeText without AP
- `issue14802.pdf` — relative link + Base-URI
- `issue7115.pdf` — annotation /Rect indirect entries
- `issue7446.pdf` — annotation without /Subtype
- `quadpoints.pdf` — QuadPoints variations
- `rc_annotation.pdf` — rich content annotation

## Forms

- `annotation-tx.pdf` — text widget without AP
- `checkbox-bad-appearance.pdf` — checkbox with broken AP
- `textfields.pdf` — text fields

## Encryption

- `bug1782186.pdf` — user password 'Hello'
- `empty_protected.pdf` — owner-protected empty file
- `encrypted-attachment.pdf` — encrypted attachment
- `issue15893_reduced.pdf` — user password 'test'
- `issue3371.pdf` — user password 'ELXRTQWS'
- `issue6010_1.pdf` — user password 'abc'
- `issue6010_2.pdf` — UTF-8 password (æøå)
- `issue7665.pdf` — indirect objects in /Encrypt
- `print_protection.pdf` — print-protected
- `secHandler.pdf` — security handler edge case

## Miscellaneous

- `issue269_1.pdf` — optional/marked content
- `labelled_pages.pdf` — page labels
- `nested_outline.pdf` — nested outlines
- `visibility_expressions.pdf` — OC visibility expressions
