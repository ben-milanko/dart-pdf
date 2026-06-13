# PDF.js Corpus Render Comparisons

Checked-in visual results for the PDF.js corpus: PDF.js baseline, Dart render, and diff images. The diff percentage is computed from the checked-in diff PNGs, where solid red pixels mark channels that exceeded the comparison tolerance.

Regenerate this file after adding or removing PNGs with:

```sh
fvm dart packages/dart_pdf_editor/tool/rebuild_pdfjs_render_index.dart
```

| PDF | Page | Size | Diff | Result |
| --- | ---: | ---: | ---: | :---: |
| 90ms_rksj_h_sample.pdf | 1 | 612x792 | 0.180% | ❌ fail |
| ContentStreamCycleType3insideType3.pdf | 1 | 600x840 | 0.866% | ❌ fail |
| ContentStreamNoCycleType3insideType3.pdf | 1 | 600x840 | 0.888% | ❌ fail |
| IdentityToUnicodeMap_charCodeOf.pdf | 1 | 200x50 | 4.170% | ❌ fail |
| IndexedCS_negative_and_high.pdf | 1 | 500x100 | 0.000% | ✅ pass |
| PDFBOX-3148-2-fuzzed.pdf | 1 | 612x792 | 0.000% | ✅ pass |
| PDFBOX-4352-0.pdf | 1 | 200x50 | 0.000% | ✅ pass |
| PDFJS-7562-reduced.pdf | 1 | 596x842 | 0.004% | ✅ pass |
| Pages-tree-refs.pdf | 1 | 595x842 | n/a | — |
| ShowText-ShadingPattern.pdf | 1 | 612x792 | 1.140% | ❌ fail |
| SimFang-variant.pdf | 1 | 463x626 | 0.282% | ❌ fail |
| TrueType_without_cmap.pdf | 1 | 200x50 | 0.110% | ❌ fail |
| Type3WordSpacing.pdf | 1 | 300x80 | 5.375% | ❌ fail |
| XiaoBiaoSong.pdf | 1 | 463x626 | 6.212% | ❌ fail |
| ZapfDingbats.pdf | 1 | 576x792 | 12.972% | ❌ fail |
| ZapfDingbats.pdf | 2 | 576x792 | 5.821% | ❌ fail |
| alphatrans.pdf | 1 | 596x842 | 1.032% | ❌ fail |
| annotation-highlight-without-appearance.pdf | 1 | 612x792 | 0.077% | ❌ fail |
| annotation-ink-without-appearance.pdf | 1 | 612x792 | 0.536% | ❌ fail |
| annotation-line-without-appearance-empty-Rect.pdf | 1 | 650x792 | 0.340% | ❌ fail |
| annotation-line-without-appearance.pdf | 1 | 612x792 | 0.012% | ✅ pass |
| annotation-square-circle-without-appearance.pdf | 1 | 612x792 | 0.333% | ❌ fail |
| annotation-squiggly-without-appearance.pdf | 1 | 612x792 | 0.080% | ❌ fail |
| annotation-strikeout-without-appearance.pdf | 1 | 612x792 | 0.073% | ❌ fail |
| annotation-tx.pdf | 1 | 612x792 | 0.074% | ❌ fail |
| annotation-underline-without-appearance.pdf | 1 | 612x792 | 0.074% | ❌ fail |
| arial_unicode_ab_cidfont.pdf | 1 | 595x842 | 0.015% | ✅ pass |
| asciihexdecode.pdf | 1 | 795x842 | 0.253% | ❌ fail |
| bad-PageLabels.pdf | 1 | 200x50 | 8.490% | ❌ fail |
| bigboundingbox.pdf | 1 | 612x792 | 1.320% | ❌ fail |
| bitmap-halftone.pdf | 1 | 399x400 | 0.000% | ✅ pass |
| bitmap-mmr.pdf | 1 | 399x400 | 0.000% | ✅ pass |
| bitmap-refine.pdf | 1 | 399x400 | 0.000% | ✅ pass |
| bitmap-symbol-symhuff-texthuff.pdf | 1 | 399x400 | 0.000% | ✅ pass |
| bitmap-symbol-textcomposite.pdf | 1 | 399x400 | 0.000% | ✅ pass |
| bitmap-symbol.pdf | 1 | 399x400 | 0.000% | ✅ pass |
| bitmap-template1.pdf | 1 | 399x400 | 0.000% | ✅ pass |
| bitmap-template2-tpgdon.pdf | 1 | 399x400 | 0.000% | ✅ pass |
| bitmap-template3-customat.pdf | 1 | 399x400 | 0.000% | ✅ pass |
| blendmode.pdf | 1 | 596x842 | 4.931% | ❌ fail |
| boundingBox_invalid.pdf | 1 | 612x792 | 0.359% | ❌ fail |
| boundingBox_invalid.pdf | 2 | 800x600 | 0.337% | ❌ fail |
| boundingBox_invalid.pdf | 3 | 600x800 | 0.855% | ❌ fail |
| bug1011159.pdf | 1 | 200x50 | 2.660% | ❌ fail |
| bug1065245.pdf | 1 | 596x843 | 0.311% | ❌ fail |
| bug1552113.pdf | 1 | 250x50 | 14.832% | ❌ fail |
| bug1782186.pdf | 1 | 842x596 | 0.202% | ❌ fail |
| bug816075.pdf | 1 | 596x842 | 0.000% | ✅ pass |
| bug866395.pdf | 1 | 200x50 | 4.790% | ❌ fail |
| bug886717.pdf | 1 | 596x842 | 0.029% | ✅ pass |
| bug898853.pdf | 1 | 200x50 | 0.000% | ✅ pass |
| bug921409.pdf | 1 | 200x50 | 0.020% | ✅ pass |
| bug946506.pdf | 1 | 799x596 | 2.030% | ❌ fail |
| calgray.pdf | 1 | 850x1100 | 0.665% | ❌ fail |
| calgray.pdf | 2 | 850x1100 | 0.758% | ❌ fail |
| calgray.pdf | 3 | 850x1100 | 0.658% | ❌ fail |
| calrgb.pdf | 1 | 850x1100 | 3.014% | ❌ fail |
| calrgb.pdf | 2 | 850x1100 | 2.969% | ❌ fail |
| calrgb.pdf | 3 | 850x1100 | 2.960% | ❌ fail |
| calrgb.pdf | 4 | 850x1100 | 3.107% | ❌ fail |
| calrgb.pdf | 5 | 850x1100 | 3.007% | ❌ fail |
| calrgb.pdf | 6 | 850x1100 | n/a | — |
| ccitt_EndOfBlock_false.pdf | 1 | 596x842 | 9.054% | ❌ fail |
| checkbox-bad-appearance.pdf | 1 | 596x842 | 0.034% | ✅ pass |
| cid_cff.pdf | 1 | 756x562 | 0.000% | ✅ pass |
| cidfont_cmap_overflow.pdf | 1 | 400x150 | 0.000% | ✅ pass |
| clippath.pdf | 1 | 200x100 | 0.000% | ✅ pass |
| close-path-bug.pdf | 1 | 612x792 | 0.001% | ✅ pass |
| cmykjpeg.pdf | 1 | 612x792 | 0.845% | ❌ fail |
| colorkeymask.pdf | 1 | 596x842 | 0.000% | ✅ pass |
| colorspace_atan.pdf | 1 | 276x276 | 0.068% | ❌ fail |
| complex_ttf_font.pdf | 1 | 595x842 | 0.323% | ❌ fail |
| coons-allflags-withfunction.pdf | 1 | 612x792 | 0.436% | ❌ fail |
| decodeACSuccessive.pdf | 1 | 400x400 | 2.978% | ❌ fail |
| devicen.pdf | 1 | 612x792 | 0.000% | ✅ pass |
| empty.pdf | 1 | 612x792 | 0.000% | ✅ pass |
| empty_protected.pdf | 1 | 612x792 | 0.000% | ✅ pass |
| encrypted-attachment.pdf | 1 | 612x792 | 0.126% | ❌ fail |
| endchar.pdf | 1 | 15x34 | 0.588% | ❌ fail |
| extractPages_null_in_array.pdf | 1 | 612x792 | 0.000% | ✅ pass |
| file_url_link.pdf | 1 | 200x50 | 9.770% | ❌ fail |
| font_ascent_descent.pdf | 1 | 842x595 | 0.006% | ✅ pass |
| franz.pdf | 1 | 200x50 | 10.600% | ❌ fail |
| franz_2.pdf | 1 | 200x50 | 98.170% | ❌ fail |
| freetext_no_appearance.pdf | 1 | 612x792 | 0.000% | ✅ pass |
| function_based_shading.pdf | 1 | 612x792 | 5.768% | ❌ fail |
| glyph_accent.pdf | 1 | 200x50 | 0.080% | ❌ fail |
| gradientfill.pdf | 1 | 596x842 | 0.169% | ❌ fail |
| hello_world_rotated.pdf | 1 | 792x612 | 0.551% | ❌ fail |
| hello_world_rotated.pdf | 2 | 792x612 | 0.551% | ❌ fail |
| hello_world_rotated.pdf | 3 | 792x612 | 0.551% | ❌ fail |
| hello_world_rotated.pdf | 4 | 792x612 | 0.551% | ❌ fail |
| hello_world_rotated.pdf | 5 | 792x612 | 0.551% | ❌ fail |
| helloworld-bad.pdf | 1 | 200x200 | 0.775% | ❌ fail |
| image-rotated-black-white-ratio.pdf | 1 | 612x792 | 0.023% | ✅ pass |
| images_1bit_grayscale.pdf | 1 | 596x842 | 9.987% | ❌ fail |
| issue1293r.pdf | 1 | 200x50 | 4.900% | ❌ fail |
| issue14802.pdf | 1 | 260x50 | 9.246% | ❌ fail |
| issue15893_reduced.pdf | 1 | 200x50 | 10.750% | ❌ fail |
| issue269_1.pdf | 1 | 100x100 | 0.000% | ✅ pass |
| issue2761.pdf | 1 | 612x792 | 0.531% | ❌ fail |
| issue3061.pdf | 1 | 596x842 | 0.173% | ❌ fail |
| issue3371.pdf | 1 | 596x842 | 0.318% | ❌ fail |
| issue3458.pdf | 1 | 720x540 | 0.192% | ❌ fail |
| issue3521.pdf | 1 | 596x842 | 0.272% | ❌ fail |
| issue3566.pdf | 1 | 200x50 | 0.000% | ✅ pass |
| issue3584.pdf | 1 | 200x50 | 0.050% | ✅ pass |
| issue3928.pdf | 1 | 300x50 | 0.033% | ✅ pass |
| issue3928.pdf | 2 | 300x50 | 0.020% | ✅ pass |
| issue4246.pdf | 1 | 595x842 | 0.012% | ✅ pass |
| issue4461.pdf | 1 | 30x20 | 0.000% | ✅ pass |
| issue4573.pdf | 1 | 200x50 | 0.000% | ✅ pass |
| issue4684.pdf | 1 | 400x50 | 0.000% | ✅ pass |
| issue4800.pdf | 1 | 200x50 | 0.300% | ❌ fail |
| issue5138.pdf | 1 | 200x50 | 0.110% | ❌ fail |
| issue5280.pdf | 1 | 595x842 | 0.004% | ✅ pass |
| issue5564_reduced.pdf | 1 | 200x50 | 0.000% | ✅ pass |
| issue5686.pdf | 1 | 300x50 | 0.013% | ✅ pass |
| issue6010_1.pdf | 1 | 200x50 | 5.010% | ❌ fail |
| issue6010_2.pdf | 1 | 200x50 | 5.010% | ❌ fail |
| issue7115.pdf | 1 | 200x50 | 9.310% | ❌ fail |
| issue7446.pdf | 1 | 200x200 | 2.107% | ❌ fail |
| issue7665.pdf | 1 | 200x50 | 4.900% | ❌ fail |
| issue7872.pdf | 1 | 250x50 | 8.344% | ❌ fail |
| jbig2_file_header.pdf | 1 | 128x96 | 0.000% | ✅ pass |
| jbig2_symbol_offset.pdf | 1 | 596x842 | 1.560% | ❌ fail |
| jp2k-resetprob.pdf | 1 | 30x21 | 8.571% | ❌ fail |
| knockout_isolated_overlap.pdf | 1 | 200x160 | 0.000% | ✅ pass |
| knockout_smask.pdf | 1 | 200x160 | 12.500% | ❌ fail |
| labelled_pages.pdf | 1 | 612x792 | 0.000% | ✅ pass |
| labelled_pages.pdf | 2 | 612x792 | 0.000% | ✅ pass |
| labelled_pages.pdf | 3 | 612x792 | 0.000% | ✅ pass |
| labelled_pages.pdf | 4 | 612x792 | 0.000% | ✅ pass |
| labelled_pages.pdf | 5 | 612x792 | 0.000% | ✅ pass |
| labelled_pages.pdf | 6 | 612x792 | n/a | — |
| mesh_shading_empty.pdf | 1 | 500x250 | 0.795% | ❌ fail |
| mmtype1.pdf | 1 | 200x50 | 0.010% | ✅ pass |
| multiple-filters-length-zero.pdf | 1 | 612x792 | 0.048% | ✅ pass |
| nested_outline.pdf | 1 | 596x842 | 0.394% | ❌ fail |
| nested_outline.pdf | 2 | 596x842 | 0.431% | ❌ fail |
| nested_outline.pdf | 3 | 596x842 | 0.388% | ❌ fail |
| nested_outline.pdf | 4 | 596x842 | 0.475% | ❌ fail |
| nested_outline.pdf | 5 | 596x842 | 0.385% | ❌ fail |
| noembed-eucjp.pdf | 1 | 595x842 | 0.123% | ❌ fail |
| noembed-identity.pdf | 1 | 595x842 | 0.033% | ✅ pass |
| noembed-sjis.pdf | 1 | 595x842 | 0.184% | ❌ fail |
| non-embedded-NuptialScript.pdf | 1 | 350x50 | 18.549% | ❌ fail |
| openoffice.pdf | 1 | 200x50 | 1.340% | ❌ fail |
| operator-in-TJ-array.pdf | 1 | 595x839 | 0.244% | ❌ fail |
| operator_list_cycle.pdf | 1 | 612x792 | 0.249% | ❌ fail |
| pattern_text_embedded_font.pdf | 1 | 596x842 | 0.966% | ❌ fail |
| pdfjsbad1586.pdf | 1 | 612x792 | 0.003% | ✅ pass |
| pdfkit_compressed.pdf | 1 | 612x792 | 0.045% | ✅ pass |
| poppler-67295-0.pdf | 1 | 612x792 | 0.282% | ❌ fail |
| poppler-91414-0-53.pdf | 1 | 795x842 | 0.146% | ❌ fail |
| poppler-91414-0-54.pdf | 1 | 795x842 | 0.146% | ❌ fail |
| pr4922.pdf | 1 | 400x50 | 7.955% | ❌ fail |
| pr4922.pdf | 2 | 400x50 | 8.010% | ❌ fail |
| quadpoints.pdf | 1 | 596x842 | 0.551% | ❌ fail |
| radial_gradients.pdf | 1 | 595x842 | 2.969% | ❌ fail |
| radial_gradients.pdf | 2 | 595x842 | 2.898% | ❌ fail |
| radial_gradients.pdf | 3 | 595x842 | 3.070% | ❌ fail |
| radial_gradients.pdf | 4 | 595x842 | 9.252% | ❌ fail |
| radial_gradients.pdf | 5 | 595x842 | 9.275% | ❌ fail |
| rc_annotation.pdf | 1 | 100x100 | 0.000% | ✅ pass |
| rc_annotation.pdf | 2 | 100x100 | 0.000% | ✅ pass |
| recursiveCompositGlyf.pdf | 1 | 612x792 | 0.000% | ✅ pass |
| rotation.pdf | 1 | 612x792 | 0.440% | ❌ fail |
| rotation.pdf | 2 | 792x612 | 0.391% | ❌ fail |
| scan-bad.pdf | 1 | 612x792 | 0.048% | ✅ pass |
| sci-notation.pdf | 1 | 612x792 | 0.362% | ❌ fail |
| secHandler.pdf | 1 | 612x792 | 0.165% | ❌ fail |
| shading_extend.pdf | 1 | 596x842 | 2.098% | ❌ fail |
| simpletype3font.pdf | 1 | 612x792 | 0.000% | ✅ pass |
| sizes.pdf | 1 | 612x792 | 0.004% | ✅ pass |
| sizes.pdf | 2 | 649x323 | 0.003% | ✅ pass |
| sizes.pdf | 3 | 792x612 | 0.006% | ✅ pass |
| smask_alpha_bc.pdf | 1 | 220x160 | 0.011% | ✅ pass |
| smask_alpha_oob.pdf | 1 | 600x600 | 0.222% | ❌ fail |
| smask_alpha_oob_transfer.pdf | 1 | 600x600 | 97.332% | ❌ fail |
| smask_luminosity_oob_transfer.pdf | 1 | 500x300 | 96.800% | ❌ fail |
| smaskdim.pdf | 1 | 612x792 | 0.012% | ✅ pass |
| standard_fonts.pdf | 1 | 596x842 | 10.454% | ❌ fail |
| standard_fonts.pdf | 2 | 596x842 | 11.142% | ❌ fail |
| standard_fonts.pdf | 3 | 596x842 | 10.682% | ❌ fail |
| standard_fonts.pdf | 4 | 596x842 | 12.529% | ❌ fail |
| standard_fonts.pdf | 5 | 596x842 | 11.006% | ❌ fail |
| standard_fonts.pdf | 6 | 596x842 | n/a | — |
| tensor-allflags-withfunction.pdf | 1 | 612x792 | 0.477% | ❌ fail |
| text_clip_cff_cid.pdf | 1 | 580x200 | 0.008% | ✅ pass |
| text_rise_eol_bug.pdf | 1 | 612x792 | 0.220% | ❌ fail |
| textfields.pdf | 1 | 612x792 | 1.172% | ❌ fail |
| tiling-pattern-box.pdf | 1 | 596x842 | 0.997% | ❌ fail |
| tiling-pattern-large-steps.pdf | 1 | 4000x400 | 0.001% | ✅ pass |
| tiling_patterns_variations.pdf | 1 | 600x800 | 4.001% | ❌ fail |
| transparent.pdf | 1 | 200x200 | 0.000% | ✅ pass |
| type4psfunc.pdf | 1 | 612x792 | 0.008% | ✅ pass |
| vertical.pdf | 1 | 250x322 | 1.512% | ❌ fail |
| vertical.pdf | 2 | 250x322 | 0.932% | ❌ fail |
| vertical.pdf | 3 | 250x322 | 0.932% | ❌ fail |
| visibility_expressions.pdf | 1 | 341x341 | 0.243% | ❌ fail |
| xobject-image.pdf | 1 | 200x100 | 0.000% | ✅ pass |
| xref_command_missing.pdf | 1 | 200x50 | 8.480% | ❌ fail |
| zerowidthline.pdf | 1 | 596x842 | 0.935% | ❌ fail |

71 of 200 compared pages pass (≤ 0.050% of pixels differing); 129 fail.

## Visual Comparisons

### 90ms_rksj_h_sample.pdf page 1

612x792; diff: 0.180%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](90ms_rksj_h_sample.pdf.p0.baseline.png)](90ms_rksj_h_sample.pdf.p0.baseline.png) | [![Dart render](90ms_rksj_h_sample.pdf.p0.dart.png)](90ms_rksj_h_sample.pdf.p0.dart.png) | [![Diff](90ms_rksj_h_sample.pdf.p0.diff.png)](90ms_rksj_h_sample.pdf.p0.diff.png) |

### ContentStreamCycleType3insideType3.pdf page 1

600x840; diff: 0.866%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](ContentStreamCycleType3insideType3.pdf.p0.baseline.png)](ContentStreamCycleType3insideType3.pdf.p0.baseline.png) | [![Dart render](ContentStreamCycleType3insideType3.pdf.p0.dart.png)](ContentStreamCycleType3insideType3.pdf.p0.dart.png) | [![Diff](ContentStreamCycleType3insideType3.pdf.p0.diff.png)](ContentStreamCycleType3insideType3.pdf.p0.diff.png) |

### ContentStreamNoCycleType3insideType3.pdf page 1

600x840; diff: 0.888%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](ContentStreamNoCycleType3insideType3.pdf.p0.baseline.png)](ContentStreamNoCycleType3insideType3.pdf.p0.baseline.png) | [![Dart render](ContentStreamNoCycleType3insideType3.pdf.p0.dart.png)](ContentStreamNoCycleType3insideType3.pdf.p0.dart.png) | [![Diff](ContentStreamNoCycleType3insideType3.pdf.p0.diff.png)](ContentStreamNoCycleType3insideType3.pdf.p0.diff.png) |

### IdentityToUnicodeMap_charCodeOf.pdf page 1

200x50; diff: 4.170%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](IdentityToUnicodeMap_charCodeOf.pdf.p0.baseline.png)](IdentityToUnicodeMap_charCodeOf.pdf.p0.baseline.png) | [![Dart render](IdentityToUnicodeMap_charCodeOf.pdf.p0.dart.png)](IdentityToUnicodeMap_charCodeOf.pdf.p0.dart.png) | [![Diff](IdentityToUnicodeMap_charCodeOf.pdf.p0.diff.png)](IdentityToUnicodeMap_charCodeOf.pdf.p0.diff.png) |

### IndexedCS_negative_and_high.pdf page 1

500x100; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](IndexedCS_negative_and_high.pdf.p0.baseline.png)](IndexedCS_negative_and_high.pdf.p0.baseline.png) | [![Dart render](IndexedCS_negative_and_high.pdf.p0.dart.png)](IndexedCS_negative_and_high.pdf.p0.dart.png) | [![Diff](IndexedCS_negative_and_high.pdf.p0.diff.png)](IndexedCS_negative_and_high.pdf.p0.diff.png) |

### PDFBOX-3148-2-fuzzed.pdf page 1

612x792; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](PDFBOX-3148-2-fuzzed.pdf.p0.baseline.png)](PDFBOX-3148-2-fuzzed.pdf.p0.baseline.png) | [![Dart render](PDFBOX-3148-2-fuzzed.pdf.p0.dart.png)](PDFBOX-3148-2-fuzzed.pdf.p0.dart.png) | [![Diff](PDFBOX-3148-2-fuzzed.pdf.p0.diff.png)](PDFBOX-3148-2-fuzzed.pdf.p0.diff.png) |

### PDFBOX-4352-0.pdf page 1

200x50; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](PDFBOX-4352-0.pdf.p0.baseline.png)](PDFBOX-4352-0.pdf.p0.baseline.png) | [![Dart render](PDFBOX-4352-0.pdf.p0.dart.png)](PDFBOX-4352-0.pdf.p0.dart.png) | [![Diff](PDFBOX-4352-0.pdf.p0.diff.png)](PDFBOX-4352-0.pdf.p0.diff.png) |

### PDFJS-7562-reduced.pdf page 1

596x842; diff: 0.004%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](PDFJS-7562-reduced.pdf.p0.baseline.png)](PDFJS-7562-reduced.pdf.p0.baseline.png) | [![Dart render](PDFJS-7562-reduced.pdf.p0.dart.png)](PDFJS-7562-reduced.pdf.p0.dart.png) | [![Diff](PDFJS-7562-reduced.pdf.p0.diff.png)](PDFJS-7562-reduced.pdf.p0.diff.png) |

### Pages-tree-refs.pdf page 1

595x842; diff: n/a

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| missing | [![Dart render](Pages-tree-refs.pdf.p0.dart.png)](Pages-tree-refs.pdf.p0.dart.png) | missing |

### ShowText-ShadingPattern.pdf page 1

612x792; diff: 1.140%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](ShowText-ShadingPattern.pdf.p0.baseline.png)](ShowText-ShadingPattern.pdf.p0.baseline.png) | [![Dart render](ShowText-ShadingPattern.pdf.p0.dart.png)](ShowText-ShadingPattern.pdf.p0.dart.png) | [![Diff](ShowText-ShadingPattern.pdf.p0.diff.png)](ShowText-ShadingPattern.pdf.p0.diff.png) |

### SimFang-variant.pdf page 1

463x626; diff: 0.282%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](SimFang-variant.pdf.p0.baseline.png)](SimFang-variant.pdf.p0.baseline.png) | [![Dart render](SimFang-variant.pdf.p0.dart.png)](SimFang-variant.pdf.p0.dart.png) | [![Diff](SimFang-variant.pdf.p0.diff.png)](SimFang-variant.pdf.p0.diff.png) |

### TrueType_without_cmap.pdf page 1

200x50; diff: 0.110%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](TrueType_without_cmap.pdf.p0.baseline.png)](TrueType_without_cmap.pdf.p0.baseline.png) | [![Dart render](TrueType_without_cmap.pdf.p0.dart.png)](TrueType_without_cmap.pdf.p0.dart.png) | [![Diff](TrueType_without_cmap.pdf.p0.diff.png)](TrueType_without_cmap.pdf.p0.diff.png) |

### Type3WordSpacing.pdf page 1

300x80; diff: 5.375%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](Type3WordSpacing.pdf.p0.baseline.png)](Type3WordSpacing.pdf.p0.baseline.png) | [![Dart render](Type3WordSpacing.pdf.p0.dart.png)](Type3WordSpacing.pdf.p0.dart.png) | [![Diff](Type3WordSpacing.pdf.p0.diff.png)](Type3WordSpacing.pdf.p0.diff.png) |

### XiaoBiaoSong.pdf page 1

463x626; diff: 6.212%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](XiaoBiaoSong.pdf.p0.baseline.png)](XiaoBiaoSong.pdf.p0.baseline.png) | [![Dart render](XiaoBiaoSong.pdf.p0.dart.png)](XiaoBiaoSong.pdf.p0.dart.png) | [![Diff](XiaoBiaoSong.pdf.p0.diff.png)](XiaoBiaoSong.pdf.p0.diff.png) |

### ZapfDingbats.pdf page 1

576x792; diff: 12.972%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](ZapfDingbats.pdf.p0.baseline.png)](ZapfDingbats.pdf.p0.baseline.png) | [![Dart render](ZapfDingbats.pdf.p0.dart.png)](ZapfDingbats.pdf.p0.dart.png) | [![Diff](ZapfDingbats.pdf.p0.diff.png)](ZapfDingbats.pdf.p0.diff.png) |

### ZapfDingbats.pdf page 2

576x792; diff: 5.821%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](ZapfDingbats.pdf.p1.baseline.png)](ZapfDingbats.pdf.p1.baseline.png) | [![Dart render](ZapfDingbats.pdf.p1.dart.png)](ZapfDingbats.pdf.p1.dart.png) | [![Diff](ZapfDingbats.pdf.p1.diff.png)](ZapfDingbats.pdf.p1.diff.png) |

### alphatrans.pdf page 1

596x842; diff: 1.032%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](alphatrans.pdf.p0.baseline.png)](alphatrans.pdf.p0.baseline.png) | [![Dart render](alphatrans.pdf.p0.dart.png)](alphatrans.pdf.p0.dart.png) | [![Diff](alphatrans.pdf.p0.diff.png)](alphatrans.pdf.p0.diff.png) |

### annotation-highlight-without-appearance.pdf page 1

612x792; diff: 0.077%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](annotation-highlight-without-appearance.pdf.p0.baseline.png)](annotation-highlight-without-appearance.pdf.p0.baseline.png) | [![Dart render](annotation-highlight-without-appearance.pdf.p0.dart.png)](annotation-highlight-without-appearance.pdf.p0.dart.png) | [![Diff](annotation-highlight-without-appearance.pdf.p0.diff.png)](annotation-highlight-without-appearance.pdf.p0.diff.png) |

### annotation-ink-without-appearance.pdf page 1

612x792; diff: 0.536%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](annotation-ink-without-appearance.pdf.p0.baseline.png)](annotation-ink-without-appearance.pdf.p0.baseline.png) | [![Dart render](annotation-ink-without-appearance.pdf.p0.dart.png)](annotation-ink-without-appearance.pdf.p0.dart.png) | [![Diff](annotation-ink-without-appearance.pdf.p0.diff.png)](annotation-ink-without-appearance.pdf.p0.diff.png) |

### annotation-line-without-appearance-empty-Rect.pdf page 1

650x792; diff: 0.340%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](annotation-line-without-appearance-empty-Rect.pdf.p0.baseline.png)](annotation-line-without-appearance-empty-Rect.pdf.p0.baseline.png) | [![Dart render](annotation-line-without-appearance-empty-Rect.pdf.p0.dart.png)](annotation-line-without-appearance-empty-Rect.pdf.p0.dart.png) | [![Diff](annotation-line-without-appearance-empty-Rect.pdf.p0.diff.png)](annotation-line-without-appearance-empty-Rect.pdf.p0.diff.png) |

### annotation-line-without-appearance.pdf page 1

612x792; diff: 0.012%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](annotation-line-without-appearance.pdf.p0.baseline.png)](annotation-line-without-appearance.pdf.p0.baseline.png) | [![Dart render](annotation-line-without-appearance.pdf.p0.dart.png)](annotation-line-without-appearance.pdf.p0.dart.png) | [![Diff](annotation-line-without-appearance.pdf.p0.diff.png)](annotation-line-without-appearance.pdf.p0.diff.png) |

### annotation-square-circle-without-appearance.pdf page 1

612x792; diff: 0.333%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](annotation-square-circle-without-appearance.pdf.p0.baseline.png)](annotation-square-circle-without-appearance.pdf.p0.baseline.png) | [![Dart render](annotation-square-circle-without-appearance.pdf.p0.dart.png)](annotation-square-circle-without-appearance.pdf.p0.dart.png) | [![Diff](annotation-square-circle-without-appearance.pdf.p0.diff.png)](annotation-square-circle-without-appearance.pdf.p0.diff.png) |

### annotation-squiggly-without-appearance.pdf page 1

612x792; diff: 0.080%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](annotation-squiggly-without-appearance.pdf.p0.baseline.png)](annotation-squiggly-without-appearance.pdf.p0.baseline.png) | [![Dart render](annotation-squiggly-without-appearance.pdf.p0.dart.png)](annotation-squiggly-without-appearance.pdf.p0.dart.png) | [![Diff](annotation-squiggly-without-appearance.pdf.p0.diff.png)](annotation-squiggly-without-appearance.pdf.p0.diff.png) |

### annotation-strikeout-without-appearance.pdf page 1

612x792; diff: 0.073%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](annotation-strikeout-without-appearance.pdf.p0.baseline.png)](annotation-strikeout-without-appearance.pdf.p0.baseline.png) | [![Dart render](annotation-strikeout-without-appearance.pdf.p0.dart.png)](annotation-strikeout-without-appearance.pdf.p0.dart.png) | [![Diff](annotation-strikeout-without-appearance.pdf.p0.diff.png)](annotation-strikeout-without-appearance.pdf.p0.diff.png) |

### annotation-tx.pdf page 1

612x792; diff: 0.074%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](annotation-tx.pdf.p0.baseline.png)](annotation-tx.pdf.p0.baseline.png) | [![Dart render](annotation-tx.pdf.p0.dart.png)](annotation-tx.pdf.p0.dart.png) | [![Diff](annotation-tx.pdf.p0.diff.png)](annotation-tx.pdf.p0.diff.png) |

### annotation-underline-without-appearance.pdf page 1

612x792; diff: 0.074%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](annotation-underline-without-appearance.pdf.p0.baseline.png)](annotation-underline-without-appearance.pdf.p0.baseline.png) | [![Dart render](annotation-underline-without-appearance.pdf.p0.dart.png)](annotation-underline-without-appearance.pdf.p0.dart.png) | [![Diff](annotation-underline-without-appearance.pdf.p0.diff.png)](annotation-underline-without-appearance.pdf.p0.diff.png) |

### arial_unicode_ab_cidfont.pdf page 1

595x842; diff: 0.015%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](arial_unicode_ab_cidfont.pdf.p0.baseline.png)](arial_unicode_ab_cidfont.pdf.p0.baseline.png) | [![Dart render](arial_unicode_ab_cidfont.pdf.p0.dart.png)](arial_unicode_ab_cidfont.pdf.p0.dart.png) | [![Diff](arial_unicode_ab_cidfont.pdf.p0.diff.png)](arial_unicode_ab_cidfont.pdf.p0.diff.png) |

### asciihexdecode.pdf page 1

795x842; diff: 0.253%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](asciihexdecode.pdf.p0.baseline.png)](asciihexdecode.pdf.p0.baseline.png) | [![Dart render](asciihexdecode.pdf.p0.dart.png)](asciihexdecode.pdf.p0.dart.png) | [![Diff](asciihexdecode.pdf.p0.diff.png)](asciihexdecode.pdf.p0.diff.png) |

### bad-PageLabels.pdf page 1

200x50; diff: 8.490%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bad-PageLabels.pdf.p0.baseline.png)](bad-PageLabels.pdf.p0.baseline.png) | [![Dart render](bad-PageLabels.pdf.p0.dart.png)](bad-PageLabels.pdf.p0.dart.png) | [![Diff](bad-PageLabels.pdf.p0.diff.png)](bad-PageLabels.pdf.p0.diff.png) |

### bigboundingbox.pdf page 1

612x792; diff: 1.320%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bigboundingbox.pdf.p0.baseline.png)](bigboundingbox.pdf.p0.baseline.png) | [![Dart render](bigboundingbox.pdf.p0.dart.png)](bigboundingbox.pdf.p0.dart.png) | [![Diff](bigboundingbox.pdf.p0.diff.png)](bigboundingbox.pdf.p0.diff.png) |

### bitmap-halftone.pdf page 1

399x400; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bitmap-halftone.pdf.p0.baseline.png)](bitmap-halftone.pdf.p0.baseline.png) | [![Dart render](bitmap-halftone.pdf.p0.dart.png)](bitmap-halftone.pdf.p0.dart.png) | [![Diff](bitmap-halftone.pdf.p0.diff.png)](bitmap-halftone.pdf.p0.diff.png) |

### bitmap-mmr.pdf page 1

399x400; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bitmap-mmr.pdf.p0.baseline.png)](bitmap-mmr.pdf.p0.baseline.png) | [![Dart render](bitmap-mmr.pdf.p0.dart.png)](bitmap-mmr.pdf.p0.dart.png) | [![Diff](bitmap-mmr.pdf.p0.diff.png)](bitmap-mmr.pdf.p0.diff.png) |

### bitmap-refine.pdf page 1

399x400; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bitmap-refine.pdf.p0.baseline.png)](bitmap-refine.pdf.p0.baseline.png) | [![Dart render](bitmap-refine.pdf.p0.dart.png)](bitmap-refine.pdf.p0.dart.png) | [![Diff](bitmap-refine.pdf.p0.diff.png)](bitmap-refine.pdf.p0.diff.png) |

### bitmap-symbol-symhuff-texthuff.pdf page 1

399x400; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bitmap-symbol-symhuff-texthuff.pdf.p0.baseline.png)](bitmap-symbol-symhuff-texthuff.pdf.p0.baseline.png) | [![Dart render](bitmap-symbol-symhuff-texthuff.pdf.p0.dart.png)](bitmap-symbol-symhuff-texthuff.pdf.p0.dart.png) | [![Diff](bitmap-symbol-symhuff-texthuff.pdf.p0.diff.png)](bitmap-symbol-symhuff-texthuff.pdf.p0.diff.png) |

### bitmap-symbol-textcomposite.pdf page 1

399x400; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bitmap-symbol-textcomposite.pdf.p0.baseline.png)](bitmap-symbol-textcomposite.pdf.p0.baseline.png) | [![Dart render](bitmap-symbol-textcomposite.pdf.p0.dart.png)](bitmap-symbol-textcomposite.pdf.p0.dart.png) | [![Diff](bitmap-symbol-textcomposite.pdf.p0.diff.png)](bitmap-symbol-textcomposite.pdf.p0.diff.png) |

### bitmap-symbol.pdf page 1

399x400; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bitmap-symbol.pdf.p0.baseline.png)](bitmap-symbol.pdf.p0.baseline.png) | [![Dart render](bitmap-symbol.pdf.p0.dart.png)](bitmap-symbol.pdf.p0.dart.png) | [![Diff](bitmap-symbol.pdf.p0.diff.png)](bitmap-symbol.pdf.p0.diff.png) |

### bitmap-template1.pdf page 1

399x400; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bitmap-template1.pdf.p0.baseline.png)](bitmap-template1.pdf.p0.baseline.png) | [![Dart render](bitmap-template1.pdf.p0.dart.png)](bitmap-template1.pdf.p0.dart.png) | [![Diff](bitmap-template1.pdf.p0.diff.png)](bitmap-template1.pdf.p0.diff.png) |

### bitmap-template2-tpgdon.pdf page 1

399x400; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bitmap-template2-tpgdon.pdf.p0.baseline.png)](bitmap-template2-tpgdon.pdf.p0.baseline.png) | [![Dart render](bitmap-template2-tpgdon.pdf.p0.dart.png)](bitmap-template2-tpgdon.pdf.p0.dart.png) | [![Diff](bitmap-template2-tpgdon.pdf.p0.diff.png)](bitmap-template2-tpgdon.pdf.p0.diff.png) |

### bitmap-template3-customat.pdf page 1

399x400; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bitmap-template3-customat.pdf.p0.baseline.png)](bitmap-template3-customat.pdf.p0.baseline.png) | [![Dart render](bitmap-template3-customat.pdf.p0.dart.png)](bitmap-template3-customat.pdf.p0.dart.png) | [![Diff](bitmap-template3-customat.pdf.p0.diff.png)](bitmap-template3-customat.pdf.p0.diff.png) |

### blendmode.pdf page 1

596x842; diff: 4.931%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](blendmode.pdf.p0.baseline.png)](blendmode.pdf.p0.baseline.png) | [![Dart render](blendmode.pdf.p0.dart.png)](blendmode.pdf.p0.dart.png) | [![Diff](blendmode.pdf.p0.diff.png)](blendmode.pdf.p0.diff.png) |

### boundingBox_invalid.pdf page 1

612x792; diff: 0.359%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](boundingBox_invalid.pdf.p0.baseline.png)](boundingBox_invalid.pdf.p0.baseline.png) | [![Dart render](boundingBox_invalid.pdf.p0.dart.png)](boundingBox_invalid.pdf.p0.dart.png) | [![Diff](boundingBox_invalid.pdf.p0.diff.png)](boundingBox_invalid.pdf.p0.diff.png) |

### boundingBox_invalid.pdf page 2

800x600; diff: 0.337%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](boundingBox_invalid.pdf.p1.baseline.png)](boundingBox_invalid.pdf.p1.baseline.png) | [![Dart render](boundingBox_invalid.pdf.p1.dart.png)](boundingBox_invalid.pdf.p1.dart.png) | [![Diff](boundingBox_invalid.pdf.p1.diff.png)](boundingBox_invalid.pdf.p1.diff.png) |

### boundingBox_invalid.pdf page 3

600x800; diff: 0.855%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](boundingBox_invalid.pdf.p2.baseline.png)](boundingBox_invalid.pdf.p2.baseline.png) | [![Dart render](boundingBox_invalid.pdf.p2.dart.png)](boundingBox_invalid.pdf.p2.dart.png) | [![Diff](boundingBox_invalid.pdf.p2.diff.png)](boundingBox_invalid.pdf.p2.diff.png) |

### bug1011159.pdf page 1

200x50; diff: 2.660%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bug1011159.pdf.p0.baseline.png)](bug1011159.pdf.p0.baseline.png) | [![Dart render](bug1011159.pdf.p0.dart.png)](bug1011159.pdf.p0.dart.png) | [![Diff](bug1011159.pdf.p0.diff.png)](bug1011159.pdf.p0.diff.png) |

### bug1065245.pdf page 1

596x843; diff: 0.311%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bug1065245.pdf.p0.baseline.png)](bug1065245.pdf.p0.baseline.png) | [![Dart render](bug1065245.pdf.p0.dart.png)](bug1065245.pdf.p0.dart.png) | [![Diff](bug1065245.pdf.p0.diff.png)](bug1065245.pdf.p0.diff.png) |

### bug1552113.pdf page 1

250x50; diff: 14.832%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bug1552113.pdf.p0.baseline.png)](bug1552113.pdf.p0.baseline.png) | [![Dart render](bug1552113.pdf.p0.dart.png)](bug1552113.pdf.p0.dart.png) | [![Diff](bug1552113.pdf.p0.diff.png)](bug1552113.pdf.p0.diff.png) |

### bug1782186.pdf page 1

842x596; diff: 0.202%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bug1782186.pdf.p0.baseline.png)](bug1782186.pdf.p0.baseline.png) | [![Dart render](bug1782186.pdf.p0.dart.png)](bug1782186.pdf.p0.dart.png) | [![Diff](bug1782186.pdf.p0.diff.png)](bug1782186.pdf.p0.diff.png) |

### bug816075.pdf page 1

596x842; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bug816075.pdf.p0.baseline.png)](bug816075.pdf.p0.baseline.png) | [![Dart render](bug816075.pdf.p0.dart.png)](bug816075.pdf.p0.dart.png) | [![Diff](bug816075.pdf.p0.diff.png)](bug816075.pdf.p0.diff.png) |

### bug866395.pdf page 1

200x50; diff: 4.790%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bug866395.pdf.p0.baseline.png)](bug866395.pdf.p0.baseline.png) | [![Dart render](bug866395.pdf.p0.dart.png)](bug866395.pdf.p0.dart.png) | [![Diff](bug866395.pdf.p0.diff.png)](bug866395.pdf.p0.diff.png) |

### bug886717.pdf page 1

596x842; diff: 0.029%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bug886717.pdf.p0.baseline.png)](bug886717.pdf.p0.baseline.png) | [![Dart render](bug886717.pdf.p0.dart.png)](bug886717.pdf.p0.dart.png) | [![Diff](bug886717.pdf.p0.diff.png)](bug886717.pdf.p0.diff.png) |

### bug898853.pdf page 1

200x50; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bug898853.pdf.p0.baseline.png)](bug898853.pdf.p0.baseline.png) | [![Dart render](bug898853.pdf.p0.dart.png)](bug898853.pdf.p0.dart.png) | [![Diff](bug898853.pdf.p0.diff.png)](bug898853.pdf.p0.diff.png) |

### bug921409.pdf page 1

200x50; diff: 0.020%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bug921409.pdf.p0.baseline.png)](bug921409.pdf.p0.baseline.png) | [![Dart render](bug921409.pdf.p0.dart.png)](bug921409.pdf.p0.dart.png) | [![Diff](bug921409.pdf.p0.diff.png)](bug921409.pdf.p0.diff.png) |

### bug946506.pdf page 1

799x596; diff: 2.030%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](bug946506.pdf.p0.baseline.png)](bug946506.pdf.p0.baseline.png) | [![Dart render](bug946506.pdf.p0.dart.png)](bug946506.pdf.p0.dart.png) | [![Diff](bug946506.pdf.p0.diff.png)](bug946506.pdf.p0.diff.png) |

### calgray.pdf page 1

850x1100; diff: 0.665%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](calgray.pdf.p0.baseline.png)](calgray.pdf.p0.baseline.png) | [![Dart render](calgray.pdf.p0.dart.png)](calgray.pdf.p0.dart.png) | [![Diff](calgray.pdf.p0.diff.png)](calgray.pdf.p0.diff.png) |

### calgray.pdf page 2

850x1100; diff: 0.758%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](calgray.pdf.p1.baseline.png)](calgray.pdf.p1.baseline.png) | [![Dart render](calgray.pdf.p1.dart.png)](calgray.pdf.p1.dart.png) | [![Diff](calgray.pdf.p1.diff.png)](calgray.pdf.p1.diff.png) |

### calgray.pdf page 3

850x1100; diff: 0.658%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](calgray.pdf.p2.baseline.png)](calgray.pdf.p2.baseline.png) | [![Dart render](calgray.pdf.p2.dart.png)](calgray.pdf.p2.dart.png) | [![Diff](calgray.pdf.p2.diff.png)](calgray.pdf.p2.diff.png) |

### calrgb.pdf page 1

850x1100; diff: 3.014%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](calrgb.pdf.p0.baseline.png)](calrgb.pdf.p0.baseline.png) | [![Dart render](calrgb.pdf.p0.dart.png)](calrgb.pdf.p0.dart.png) | [![Diff](calrgb.pdf.p0.diff.png)](calrgb.pdf.p0.diff.png) |

### calrgb.pdf page 2

850x1100; diff: 2.969%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](calrgb.pdf.p1.baseline.png)](calrgb.pdf.p1.baseline.png) | [![Dart render](calrgb.pdf.p1.dart.png)](calrgb.pdf.p1.dart.png) | [![Diff](calrgb.pdf.p1.diff.png)](calrgb.pdf.p1.diff.png) |

### calrgb.pdf page 3

850x1100; diff: 2.960%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](calrgb.pdf.p2.baseline.png)](calrgb.pdf.p2.baseline.png) | [![Dart render](calrgb.pdf.p2.dart.png)](calrgb.pdf.p2.dart.png) | [![Diff](calrgb.pdf.p2.diff.png)](calrgb.pdf.p2.diff.png) |

### calrgb.pdf page 4

850x1100; diff: 3.107%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](calrgb.pdf.p3.baseline.png)](calrgb.pdf.p3.baseline.png) | [![Dart render](calrgb.pdf.p3.dart.png)](calrgb.pdf.p3.dart.png) | [![Diff](calrgb.pdf.p3.diff.png)](calrgb.pdf.p3.diff.png) |

### calrgb.pdf page 5

850x1100; diff: 3.007%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](calrgb.pdf.p4.baseline.png)](calrgb.pdf.p4.baseline.png) | [![Dart render](calrgb.pdf.p4.dart.png)](calrgb.pdf.p4.dart.png) | [![Diff](calrgb.pdf.p4.diff.png)](calrgb.pdf.p4.diff.png) |

### calrgb.pdf page 6

850x1100; diff: n/a

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| missing | [![Dart render](calrgb.pdf.p5.dart.png)](calrgb.pdf.p5.dart.png) | missing |

### ccitt_EndOfBlock_false.pdf page 1

596x842; diff: 9.054%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](ccitt_EndOfBlock_false.pdf.p0.baseline.png)](ccitt_EndOfBlock_false.pdf.p0.baseline.png) | [![Dart render](ccitt_EndOfBlock_false.pdf.p0.dart.png)](ccitt_EndOfBlock_false.pdf.p0.dart.png) | [![Diff](ccitt_EndOfBlock_false.pdf.p0.diff.png)](ccitt_EndOfBlock_false.pdf.p0.diff.png) |

### checkbox-bad-appearance.pdf page 1

596x842; diff: 0.034%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](checkbox-bad-appearance.pdf.p0.baseline.png)](checkbox-bad-appearance.pdf.p0.baseline.png) | [![Dart render](checkbox-bad-appearance.pdf.p0.dart.png)](checkbox-bad-appearance.pdf.p0.dart.png) | [![Diff](checkbox-bad-appearance.pdf.p0.diff.png)](checkbox-bad-appearance.pdf.p0.diff.png) |

### cid_cff.pdf page 1

756x562; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](cid_cff.pdf.p0.baseline.png)](cid_cff.pdf.p0.baseline.png) | [![Dart render](cid_cff.pdf.p0.dart.png)](cid_cff.pdf.p0.dart.png) | [![Diff](cid_cff.pdf.p0.diff.png)](cid_cff.pdf.p0.diff.png) |

### cidfont_cmap_overflow.pdf page 1

400x150; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](cidfont_cmap_overflow.pdf.p0.baseline.png)](cidfont_cmap_overflow.pdf.p0.baseline.png) | [![Dart render](cidfont_cmap_overflow.pdf.p0.dart.png)](cidfont_cmap_overflow.pdf.p0.dart.png) | [![Diff](cidfont_cmap_overflow.pdf.p0.diff.png)](cidfont_cmap_overflow.pdf.p0.diff.png) |

### clippath.pdf page 1

200x100; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](clippath.pdf.p0.baseline.png)](clippath.pdf.p0.baseline.png) | [![Dart render](clippath.pdf.p0.dart.png)](clippath.pdf.p0.dart.png) | [![Diff](clippath.pdf.p0.diff.png)](clippath.pdf.p0.diff.png) |

### close-path-bug.pdf page 1

612x792; diff: 0.001%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](close-path-bug.pdf.p0.baseline.png)](close-path-bug.pdf.p0.baseline.png) | [![Dart render](close-path-bug.pdf.p0.dart.png)](close-path-bug.pdf.p0.dart.png) | [![Diff](close-path-bug.pdf.p0.diff.png)](close-path-bug.pdf.p0.diff.png) |

### cmykjpeg.pdf page 1

612x792; diff: 0.845%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](cmykjpeg.pdf.p0.baseline.png)](cmykjpeg.pdf.p0.baseline.png) | [![Dart render](cmykjpeg.pdf.p0.dart.png)](cmykjpeg.pdf.p0.dart.png) | [![Diff](cmykjpeg.pdf.p0.diff.png)](cmykjpeg.pdf.p0.diff.png) |

### colorkeymask.pdf page 1

596x842; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](colorkeymask.pdf.p0.baseline.png)](colorkeymask.pdf.p0.baseline.png) | [![Dart render](colorkeymask.pdf.p0.dart.png)](colorkeymask.pdf.p0.dart.png) | [![Diff](colorkeymask.pdf.p0.diff.png)](colorkeymask.pdf.p0.diff.png) |

### colorspace_atan.pdf page 1

276x276; diff: 0.068%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](colorspace_atan.pdf.p0.baseline.png)](colorspace_atan.pdf.p0.baseline.png) | [![Dart render](colorspace_atan.pdf.p0.dart.png)](colorspace_atan.pdf.p0.dart.png) | [![Diff](colorspace_atan.pdf.p0.diff.png)](colorspace_atan.pdf.p0.diff.png) |

### complex_ttf_font.pdf page 1

595x842; diff: 0.323%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](complex_ttf_font.pdf.p0.baseline.png)](complex_ttf_font.pdf.p0.baseline.png) | [![Dart render](complex_ttf_font.pdf.p0.dart.png)](complex_ttf_font.pdf.p0.dart.png) | [![Diff](complex_ttf_font.pdf.p0.diff.png)](complex_ttf_font.pdf.p0.diff.png) |

### coons-allflags-withfunction.pdf page 1

612x792; diff: 0.436%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](coons-allflags-withfunction.pdf.p0.baseline.png)](coons-allflags-withfunction.pdf.p0.baseline.png) | [![Dart render](coons-allflags-withfunction.pdf.p0.dart.png)](coons-allflags-withfunction.pdf.p0.dart.png) | [![Diff](coons-allflags-withfunction.pdf.p0.diff.png)](coons-allflags-withfunction.pdf.p0.diff.png) |

### decodeACSuccessive.pdf page 1

400x400; diff: 2.978%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](decodeACSuccessive.pdf.p0.baseline.png)](decodeACSuccessive.pdf.p0.baseline.png) | [![Dart render](decodeACSuccessive.pdf.p0.dart.png)](decodeACSuccessive.pdf.p0.dart.png) | [![Diff](decodeACSuccessive.pdf.p0.diff.png)](decodeACSuccessive.pdf.p0.diff.png) |

### devicen.pdf page 1

612x792; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](devicen.pdf.p0.baseline.png)](devicen.pdf.p0.baseline.png) | [![Dart render](devicen.pdf.p0.dart.png)](devicen.pdf.p0.dart.png) | [![Diff](devicen.pdf.p0.diff.png)](devicen.pdf.p0.diff.png) |

### empty.pdf page 1

612x792; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](empty.pdf.p0.baseline.png)](empty.pdf.p0.baseline.png) | [![Dart render](empty.pdf.p0.dart.png)](empty.pdf.p0.dart.png) | [![Diff](empty.pdf.p0.diff.png)](empty.pdf.p0.diff.png) |

### empty_protected.pdf page 1

612x792; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](empty_protected.pdf.p0.baseline.png)](empty_protected.pdf.p0.baseline.png) | [![Dart render](empty_protected.pdf.p0.dart.png)](empty_protected.pdf.p0.dart.png) | [![Diff](empty_protected.pdf.p0.diff.png)](empty_protected.pdf.p0.diff.png) |

### encrypted-attachment.pdf page 1

612x792; diff: 0.126%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](encrypted-attachment.pdf.p0.baseline.png)](encrypted-attachment.pdf.p0.baseline.png) | [![Dart render](encrypted-attachment.pdf.p0.dart.png)](encrypted-attachment.pdf.p0.dart.png) | [![Diff](encrypted-attachment.pdf.p0.diff.png)](encrypted-attachment.pdf.p0.diff.png) |

### endchar.pdf page 1

15x34; diff: 0.588%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](endchar.pdf.p0.baseline.png)](endchar.pdf.p0.baseline.png) | [![Dart render](endchar.pdf.p0.dart.png)](endchar.pdf.p0.dart.png) | [![Diff](endchar.pdf.p0.diff.png)](endchar.pdf.p0.diff.png) |

### extractPages_null_in_array.pdf page 1

612x792; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](extractPages_null_in_array.pdf.p0.baseline.png)](extractPages_null_in_array.pdf.p0.baseline.png) | [![Dart render](extractPages_null_in_array.pdf.p0.dart.png)](extractPages_null_in_array.pdf.p0.dart.png) | [![Diff](extractPages_null_in_array.pdf.p0.diff.png)](extractPages_null_in_array.pdf.p0.diff.png) |

### file_url_link.pdf page 1

200x50; diff: 9.770%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](file_url_link.pdf.p0.baseline.png)](file_url_link.pdf.p0.baseline.png) | [![Dart render](file_url_link.pdf.p0.dart.png)](file_url_link.pdf.p0.dart.png) | [![Diff](file_url_link.pdf.p0.diff.png)](file_url_link.pdf.p0.diff.png) |

### font_ascent_descent.pdf page 1

842x595; diff: 0.006%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](font_ascent_descent.pdf.p0.baseline.png)](font_ascent_descent.pdf.p0.baseline.png) | [![Dart render](font_ascent_descent.pdf.p0.dart.png)](font_ascent_descent.pdf.p0.dart.png) | [![Diff](font_ascent_descent.pdf.p0.diff.png)](font_ascent_descent.pdf.p0.diff.png) |

### franz.pdf page 1

200x50; diff: 10.600%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](franz.pdf.p0.baseline.png)](franz.pdf.p0.baseline.png) | [![Dart render](franz.pdf.p0.dart.png)](franz.pdf.p0.dart.png) | [![Diff](franz.pdf.p0.diff.png)](franz.pdf.p0.diff.png) |

### franz_2.pdf page 1

200x50; diff: 98.170%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](franz_2.pdf.p0.baseline.png)](franz_2.pdf.p0.baseline.png) | [![Dart render](franz_2.pdf.p0.dart.png)](franz_2.pdf.p0.dart.png) | [![Diff](franz_2.pdf.p0.diff.png)](franz_2.pdf.p0.diff.png) |

### freetext_no_appearance.pdf page 1

612x792; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](freetext_no_appearance.pdf.p0.baseline.png)](freetext_no_appearance.pdf.p0.baseline.png) | [![Dart render](freetext_no_appearance.pdf.p0.dart.png)](freetext_no_appearance.pdf.p0.dart.png) | [![Diff](freetext_no_appearance.pdf.p0.diff.png)](freetext_no_appearance.pdf.p0.diff.png) |

### function_based_shading.pdf page 1

612x792; diff: 5.768%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](function_based_shading.pdf.p0.baseline.png)](function_based_shading.pdf.p0.baseline.png) | [![Dart render](function_based_shading.pdf.p0.dart.png)](function_based_shading.pdf.p0.dart.png) | [![Diff](function_based_shading.pdf.p0.diff.png)](function_based_shading.pdf.p0.diff.png) |

### glyph_accent.pdf page 1

200x50; diff: 0.080%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](glyph_accent.pdf.p0.baseline.png)](glyph_accent.pdf.p0.baseline.png) | [![Dart render](glyph_accent.pdf.p0.dart.png)](glyph_accent.pdf.p0.dart.png) | [![Diff](glyph_accent.pdf.p0.diff.png)](glyph_accent.pdf.p0.diff.png) |

### gradientfill.pdf page 1

596x842; diff: 0.169%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](gradientfill.pdf.p0.baseline.png)](gradientfill.pdf.p0.baseline.png) | [![Dart render](gradientfill.pdf.p0.dart.png)](gradientfill.pdf.p0.dart.png) | [![Diff](gradientfill.pdf.p0.diff.png)](gradientfill.pdf.p0.diff.png) |

### hello_world_rotated.pdf page 1

792x612; diff: 0.551%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](hello_world_rotated.pdf.p0.baseline.png)](hello_world_rotated.pdf.p0.baseline.png) | [![Dart render](hello_world_rotated.pdf.p0.dart.png)](hello_world_rotated.pdf.p0.dart.png) | [![Diff](hello_world_rotated.pdf.p0.diff.png)](hello_world_rotated.pdf.p0.diff.png) |

### hello_world_rotated.pdf page 2

792x612; diff: 0.551%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](hello_world_rotated.pdf.p1.baseline.png)](hello_world_rotated.pdf.p1.baseline.png) | [![Dart render](hello_world_rotated.pdf.p1.dart.png)](hello_world_rotated.pdf.p1.dart.png) | [![Diff](hello_world_rotated.pdf.p1.diff.png)](hello_world_rotated.pdf.p1.diff.png) |

### hello_world_rotated.pdf page 3

792x612; diff: 0.551%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](hello_world_rotated.pdf.p2.baseline.png)](hello_world_rotated.pdf.p2.baseline.png) | [![Dart render](hello_world_rotated.pdf.p2.dart.png)](hello_world_rotated.pdf.p2.dart.png) | [![Diff](hello_world_rotated.pdf.p2.diff.png)](hello_world_rotated.pdf.p2.diff.png) |

### hello_world_rotated.pdf page 4

792x612; diff: 0.551%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](hello_world_rotated.pdf.p3.baseline.png)](hello_world_rotated.pdf.p3.baseline.png) | [![Dart render](hello_world_rotated.pdf.p3.dart.png)](hello_world_rotated.pdf.p3.dart.png) | [![Diff](hello_world_rotated.pdf.p3.diff.png)](hello_world_rotated.pdf.p3.diff.png) |

### hello_world_rotated.pdf page 5

792x612; diff: 0.551%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](hello_world_rotated.pdf.p4.baseline.png)](hello_world_rotated.pdf.p4.baseline.png) | [![Dart render](hello_world_rotated.pdf.p4.dart.png)](hello_world_rotated.pdf.p4.dart.png) | [![Diff](hello_world_rotated.pdf.p4.diff.png)](hello_world_rotated.pdf.p4.diff.png) |

### helloworld-bad.pdf page 1

200x200; diff: 0.775%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](helloworld-bad.pdf.p0.baseline.png)](helloworld-bad.pdf.p0.baseline.png) | [![Dart render](helloworld-bad.pdf.p0.dart.png)](helloworld-bad.pdf.p0.dart.png) | [![Diff](helloworld-bad.pdf.p0.diff.png)](helloworld-bad.pdf.p0.diff.png) |

### image-rotated-black-white-ratio.pdf page 1

612x792; diff: 0.023%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](image-rotated-black-white-ratio.pdf.p0.baseline.png)](image-rotated-black-white-ratio.pdf.p0.baseline.png) | [![Dart render](image-rotated-black-white-ratio.pdf.p0.dart.png)](image-rotated-black-white-ratio.pdf.p0.dart.png) | [![Diff](image-rotated-black-white-ratio.pdf.p0.diff.png)](image-rotated-black-white-ratio.pdf.p0.diff.png) |

### images_1bit_grayscale.pdf page 1

596x842; diff: 9.987%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](images_1bit_grayscale.pdf.p0.baseline.png)](images_1bit_grayscale.pdf.p0.baseline.png) | [![Dart render](images_1bit_grayscale.pdf.p0.dart.png)](images_1bit_grayscale.pdf.p0.dart.png) | [![Diff](images_1bit_grayscale.pdf.p0.diff.png)](images_1bit_grayscale.pdf.p0.diff.png) |

### issue1293r.pdf page 1

200x50; diff: 4.900%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue1293r.pdf.p0.baseline.png)](issue1293r.pdf.p0.baseline.png) | [![Dart render](issue1293r.pdf.p0.dart.png)](issue1293r.pdf.p0.dart.png) | [![Diff](issue1293r.pdf.p0.diff.png)](issue1293r.pdf.p0.diff.png) |

### issue14802.pdf page 1

260x50; diff: 9.246%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue14802.pdf.p0.baseline.png)](issue14802.pdf.p0.baseline.png) | [![Dart render](issue14802.pdf.p0.dart.png)](issue14802.pdf.p0.dart.png) | [![Diff](issue14802.pdf.p0.diff.png)](issue14802.pdf.p0.diff.png) |

### issue15893_reduced.pdf page 1

200x50; diff: 10.750%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue15893_reduced.pdf.p0.baseline.png)](issue15893_reduced.pdf.p0.baseline.png) | [![Dart render](issue15893_reduced.pdf.p0.dart.png)](issue15893_reduced.pdf.p0.dart.png) | [![Diff](issue15893_reduced.pdf.p0.diff.png)](issue15893_reduced.pdf.p0.diff.png) |

### issue269_1.pdf page 1

100x100; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue269_1.pdf.p0.baseline.png)](issue269_1.pdf.p0.baseline.png) | [![Dart render](issue269_1.pdf.p0.dart.png)](issue269_1.pdf.p0.dart.png) | [![Diff](issue269_1.pdf.p0.diff.png)](issue269_1.pdf.p0.diff.png) |

### issue2761.pdf page 1

612x792; diff: 0.531%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue2761.pdf.p0.baseline.png)](issue2761.pdf.p0.baseline.png) | [![Dart render](issue2761.pdf.p0.dart.png)](issue2761.pdf.p0.dart.png) | [![Diff](issue2761.pdf.p0.diff.png)](issue2761.pdf.p0.diff.png) |

### issue3061.pdf page 1

596x842; diff: 0.173%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue3061.pdf.p0.baseline.png)](issue3061.pdf.p0.baseline.png) | [![Dart render](issue3061.pdf.p0.dart.png)](issue3061.pdf.p0.dart.png) | [![Diff](issue3061.pdf.p0.diff.png)](issue3061.pdf.p0.diff.png) |

### issue3371.pdf page 1

596x842; diff: 0.318%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue3371.pdf.p0.baseline.png)](issue3371.pdf.p0.baseline.png) | [![Dart render](issue3371.pdf.p0.dart.png)](issue3371.pdf.p0.dart.png) | [![Diff](issue3371.pdf.p0.diff.png)](issue3371.pdf.p0.diff.png) |

### issue3458.pdf page 1

720x540; diff: 0.192%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue3458.pdf.p0.baseline.png)](issue3458.pdf.p0.baseline.png) | [![Dart render](issue3458.pdf.p0.dart.png)](issue3458.pdf.p0.dart.png) | [![Diff](issue3458.pdf.p0.diff.png)](issue3458.pdf.p0.diff.png) |

### issue3521.pdf page 1

596x842; diff: 0.272%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue3521.pdf.p0.baseline.png)](issue3521.pdf.p0.baseline.png) | [![Dart render](issue3521.pdf.p0.dart.png)](issue3521.pdf.p0.dart.png) | [![Diff](issue3521.pdf.p0.diff.png)](issue3521.pdf.p0.diff.png) |

### issue3566.pdf page 1

200x50; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue3566.pdf.p0.baseline.png)](issue3566.pdf.p0.baseline.png) | [![Dart render](issue3566.pdf.p0.dart.png)](issue3566.pdf.p0.dart.png) | [![Diff](issue3566.pdf.p0.diff.png)](issue3566.pdf.p0.diff.png) |

### issue3584.pdf page 1

200x50; diff: 0.050%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue3584.pdf.p0.baseline.png)](issue3584.pdf.p0.baseline.png) | [![Dart render](issue3584.pdf.p0.dart.png)](issue3584.pdf.p0.dart.png) | [![Diff](issue3584.pdf.p0.diff.png)](issue3584.pdf.p0.diff.png) |

### issue3928.pdf page 1

300x50; diff: 0.033%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue3928.pdf.p0.baseline.png)](issue3928.pdf.p0.baseline.png) | [![Dart render](issue3928.pdf.p0.dart.png)](issue3928.pdf.p0.dart.png) | [![Diff](issue3928.pdf.p0.diff.png)](issue3928.pdf.p0.diff.png) |

### issue3928.pdf page 2

300x50; diff: 0.020%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue3928.pdf.p1.baseline.png)](issue3928.pdf.p1.baseline.png) | [![Dart render](issue3928.pdf.p1.dart.png)](issue3928.pdf.p1.dart.png) | [![Diff](issue3928.pdf.p1.diff.png)](issue3928.pdf.p1.diff.png) |

### issue4246.pdf page 1

595x842; diff: 0.012%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue4246.pdf.p0.baseline.png)](issue4246.pdf.p0.baseline.png) | [![Dart render](issue4246.pdf.p0.dart.png)](issue4246.pdf.p0.dart.png) | [![Diff](issue4246.pdf.p0.diff.png)](issue4246.pdf.p0.diff.png) |

### issue4461.pdf page 1

30x20; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue4461.pdf.p0.baseline.png)](issue4461.pdf.p0.baseline.png) | [![Dart render](issue4461.pdf.p0.dart.png)](issue4461.pdf.p0.dart.png) | [![Diff](issue4461.pdf.p0.diff.png)](issue4461.pdf.p0.diff.png) |

### issue4573.pdf page 1

200x50; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue4573.pdf.p0.baseline.png)](issue4573.pdf.p0.baseline.png) | [![Dart render](issue4573.pdf.p0.dart.png)](issue4573.pdf.p0.dart.png) | [![Diff](issue4573.pdf.p0.diff.png)](issue4573.pdf.p0.diff.png) |

### issue4684.pdf page 1

400x50; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue4684.pdf.p0.baseline.png)](issue4684.pdf.p0.baseline.png) | [![Dart render](issue4684.pdf.p0.dart.png)](issue4684.pdf.p0.dart.png) | [![Diff](issue4684.pdf.p0.diff.png)](issue4684.pdf.p0.diff.png) |

### issue4800.pdf page 1

200x50; diff: 0.300%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue4800.pdf.p0.baseline.png)](issue4800.pdf.p0.baseline.png) | [![Dart render](issue4800.pdf.p0.dart.png)](issue4800.pdf.p0.dart.png) | [![Diff](issue4800.pdf.p0.diff.png)](issue4800.pdf.p0.diff.png) |

### issue5138.pdf page 1

200x50; diff: 0.110%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue5138.pdf.p0.baseline.png)](issue5138.pdf.p0.baseline.png) | [![Dart render](issue5138.pdf.p0.dart.png)](issue5138.pdf.p0.dart.png) | [![Diff](issue5138.pdf.p0.diff.png)](issue5138.pdf.p0.diff.png) |

### issue5280.pdf page 1

595x842; diff: 0.004%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue5280.pdf.p0.baseline.png)](issue5280.pdf.p0.baseline.png) | [![Dart render](issue5280.pdf.p0.dart.png)](issue5280.pdf.p0.dart.png) | [![Diff](issue5280.pdf.p0.diff.png)](issue5280.pdf.p0.diff.png) |

### issue5564_reduced.pdf page 1

200x50; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue5564_reduced.pdf.p0.baseline.png)](issue5564_reduced.pdf.p0.baseline.png) | [![Dart render](issue5564_reduced.pdf.p0.dart.png)](issue5564_reduced.pdf.p0.dart.png) | [![Diff](issue5564_reduced.pdf.p0.diff.png)](issue5564_reduced.pdf.p0.diff.png) |

### issue5686.pdf page 1

300x50; diff: 0.013%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue5686.pdf.p0.baseline.png)](issue5686.pdf.p0.baseline.png) | [![Dart render](issue5686.pdf.p0.dart.png)](issue5686.pdf.p0.dart.png) | [![Diff](issue5686.pdf.p0.diff.png)](issue5686.pdf.p0.diff.png) |

### issue6010_1.pdf page 1

200x50; diff: 5.010%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue6010_1.pdf.p0.baseline.png)](issue6010_1.pdf.p0.baseline.png) | [![Dart render](issue6010_1.pdf.p0.dart.png)](issue6010_1.pdf.p0.dart.png) | [![Diff](issue6010_1.pdf.p0.diff.png)](issue6010_1.pdf.p0.diff.png) |

### issue6010_2.pdf page 1

200x50; diff: 5.010%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue6010_2.pdf.p0.baseline.png)](issue6010_2.pdf.p0.baseline.png) | [![Dart render](issue6010_2.pdf.p0.dart.png)](issue6010_2.pdf.p0.dart.png) | [![Diff](issue6010_2.pdf.p0.diff.png)](issue6010_2.pdf.p0.diff.png) |

### issue7115.pdf page 1

200x50; diff: 9.310%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue7115.pdf.p0.baseline.png)](issue7115.pdf.p0.baseline.png) | [![Dart render](issue7115.pdf.p0.dart.png)](issue7115.pdf.p0.dart.png) | [![Diff](issue7115.pdf.p0.diff.png)](issue7115.pdf.p0.diff.png) |

### issue7446.pdf page 1

200x200; diff: 2.107%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue7446.pdf.p0.baseline.png)](issue7446.pdf.p0.baseline.png) | [![Dart render](issue7446.pdf.p0.dart.png)](issue7446.pdf.p0.dart.png) | [![Diff](issue7446.pdf.p0.diff.png)](issue7446.pdf.p0.diff.png) |

### issue7665.pdf page 1

200x50; diff: 4.900%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue7665.pdf.p0.baseline.png)](issue7665.pdf.p0.baseline.png) | [![Dart render](issue7665.pdf.p0.dart.png)](issue7665.pdf.p0.dart.png) | [![Diff](issue7665.pdf.p0.diff.png)](issue7665.pdf.p0.diff.png) |

### issue7872.pdf page 1

250x50; diff: 8.344%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](issue7872.pdf.p0.baseline.png)](issue7872.pdf.p0.baseline.png) | [![Dart render](issue7872.pdf.p0.dart.png)](issue7872.pdf.p0.dart.png) | [![Diff](issue7872.pdf.p0.diff.png)](issue7872.pdf.p0.diff.png) |

### jbig2_file_header.pdf page 1

128x96; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](jbig2_file_header.pdf.p0.baseline.png)](jbig2_file_header.pdf.p0.baseline.png) | [![Dart render](jbig2_file_header.pdf.p0.dart.png)](jbig2_file_header.pdf.p0.dart.png) | [![Diff](jbig2_file_header.pdf.p0.diff.png)](jbig2_file_header.pdf.p0.diff.png) |

### jbig2_symbol_offset.pdf page 1

596x842; diff: 1.560%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](jbig2_symbol_offset.pdf.p0.baseline.png)](jbig2_symbol_offset.pdf.p0.baseline.png) | [![Dart render](jbig2_symbol_offset.pdf.p0.dart.png)](jbig2_symbol_offset.pdf.p0.dart.png) | [![Diff](jbig2_symbol_offset.pdf.p0.diff.png)](jbig2_symbol_offset.pdf.p0.diff.png) |

### jp2k-resetprob.pdf page 1

30x21; diff: 8.571%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](jp2k-resetprob.pdf.p0.baseline.png)](jp2k-resetprob.pdf.p0.baseline.png) | [![Dart render](jp2k-resetprob.pdf.p0.dart.png)](jp2k-resetprob.pdf.p0.dart.png) | [![Diff](jp2k-resetprob.pdf.p0.diff.png)](jp2k-resetprob.pdf.p0.diff.png) |

### knockout_isolated_overlap.pdf page 1

200x160; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](knockout_isolated_overlap.pdf.p0.baseline.png)](knockout_isolated_overlap.pdf.p0.baseline.png) | [![Dart render](knockout_isolated_overlap.pdf.p0.dart.png)](knockout_isolated_overlap.pdf.p0.dart.png) | [![Diff](knockout_isolated_overlap.pdf.p0.diff.png)](knockout_isolated_overlap.pdf.p0.diff.png) |

### knockout_smask.pdf page 1

200x160; diff: 12.500%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](knockout_smask.pdf.p0.baseline.png)](knockout_smask.pdf.p0.baseline.png) | [![Dart render](knockout_smask.pdf.p0.dart.png)](knockout_smask.pdf.p0.dart.png) | [![Diff](knockout_smask.pdf.p0.diff.png)](knockout_smask.pdf.p0.diff.png) |

### labelled_pages.pdf page 1

612x792; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](labelled_pages.pdf.p0.baseline.png)](labelled_pages.pdf.p0.baseline.png) | [![Dart render](labelled_pages.pdf.p0.dart.png)](labelled_pages.pdf.p0.dart.png) | [![Diff](labelled_pages.pdf.p0.diff.png)](labelled_pages.pdf.p0.diff.png) |

### labelled_pages.pdf page 2

612x792; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](labelled_pages.pdf.p1.baseline.png)](labelled_pages.pdf.p1.baseline.png) | [![Dart render](labelled_pages.pdf.p1.dart.png)](labelled_pages.pdf.p1.dart.png) | [![Diff](labelled_pages.pdf.p1.diff.png)](labelled_pages.pdf.p1.diff.png) |

### labelled_pages.pdf page 3

612x792; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](labelled_pages.pdf.p2.baseline.png)](labelled_pages.pdf.p2.baseline.png) | [![Dart render](labelled_pages.pdf.p2.dart.png)](labelled_pages.pdf.p2.dart.png) | [![Diff](labelled_pages.pdf.p2.diff.png)](labelled_pages.pdf.p2.diff.png) |

### labelled_pages.pdf page 4

612x792; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](labelled_pages.pdf.p3.baseline.png)](labelled_pages.pdf.p3.baseline.png) | [![Dart render](labelled_pages.pdf.p3.dart.png)](labelled_pages.pdf.p3.dart.png) | [![Diff](labelled_pages.pdf.p3.diff.png)](labelled_pages.pdf.p3.diff.png) |

### labelled_pages.pdf page 5

612x792; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](labelled_pages.pdf.p4.baseline.png)](labelled_pages.pdf.p4.baseline.png) | [![Dart render](labelled_pages.pdf.p4.dart.png)](labelled_pages.pdf.p4.dart.png) | [![Diff](labelled_pages.pdf.p4.diff.png)](labelled_pages.pdf.p4.diff.png) |

### labelled_pages.pdf page 6

612x792; diff: n/a

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| missing | [![Dart render](labelled_pages.pdf.p5.dart.png)](labelled_pages.pdf.p5.dart.png) | missing |

### mesh_shading_empty.pdf page 1

500x250; diff: 0.795%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](mesh_shading_empty.pdf.p0.baseline.png)](mesh_shading_empty.pdf.p0.baseline.png) | [![Dart render](mesh_shading_empty.pdf.p0.dart.png)](mesh_shading_empty.pdf.p0.dart.png) | [![Diff](mesh_shading_empty.pdf.p0.diff.png)](mesh_shading_empty.pdf.p0.diff.png) |

### mmtype1.pdf page 1

200x50; diff: 0.010%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](mmtype1.pdf.p0.baseline.png)](mmtype1.pdf.p0.baseline.png) | [![Dart render](mmtype1.pdf.p0.dart.png)](mmtype1.pdf.p0.dart.png) | [![Diff](mmtype1.pdf.p0.diff.png)](mmtype1.pdf.p0.diff.png) |

### multiple-filters-length-zero.pdf page 1

612x792; diff: 0.048%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](multiple-filters-length-zero.pdf.p0.baseline.png)](multiple-filters-length-zero.pdf.p0.baseline.png) | [![Dart render](multiple-filters-length-zero.pdf.p0.dart.png)](multiple-filters-length-zero.pdf.p0.dart.png) | [![Diff](multiple-filters-length-zero.pdf.p0.diff.png)](multiple-filters-length-zero.pdf.p0.diff.png) |

### nested_outline.pdf page 1

596x842; diff: 0.394%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](nested_outline.pdf.p0.baseline.png)](nested_outline.pdf.p0.baseline.png) | [![Dart render](nested_outline.pdf.p0.dart.png)](nested_outline.pdf.p0.dart.png) | [![Diff](nested_outline.pdf.p0.diff.png)](nested_outline.pdf.p0.diff.png) |

### nested_outline.pdf page 2

596x842; diff: 0.431%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](nested_outline.pdf.p1.baseline.png)](nested_outline.pdf.p1.baseline.png) | [![Dart render](nested_outline.pdf.p1.dart.png)](nested_outline.pdf.p1.dart.png) | [![Diff](nested_outline.pdf.p1.diff.png)](nested_outline.pdf.p1.diff.png) |

### nested_outline.pdf page 3

596x842; diff: 0.388%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](nested_outline.pdf.p2.baseline.png)](nested_outline.pdf.p2.baseline.png) | [![Dart render](nested_outline.pdf.p2.dart.png)](nested_outline.pdf.p2.dart.png) | [![Diff](nested_outline.pdf.p2.diff.png)](nested_outline.pdf.p2.diff.png) |

### nested_outline.pdf page 4

596x842; diff: 0.475%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](nested_outline.pdf.p3.baseline.png)](nested_outline.pdf.p3.baseline.png) | [![Dart render](nested_outline.pdf.p3.dart.png)](nested_outline.pdf.p3.dart.png) | [![Diff](nested_outline.pdf.p3.diff.png)](nested_outline.pdf.p3.diff.png) |

### nested_outline.pdf page 5

596x842; diff: 0.385%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](nested_outline.pdf.p4.baseline.png)](nested_outline.pdf.p4.baseline.png) | [![Dart render](nested_outline.pdf.p4.dart.png)](nested_outline.pdf.p4.dart.png) | [![Diff](nested_outline.pdf.p4.diff.png)](nested_outline.pdf.p4.diff.png) |

### noembed-eucjp.pdf page 1

595x842; diff: 0.123%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](noembed-eucjp.pdf.p0.baseline.png)](noembed-eucjp.pdf.p0.baseline.png) | [![Dart render](noembed-eucjp.pdf.p0.dart.png)](noembed-eucjp.pdf.p0.dart.png) | [![Diff](noembed-eucjp.pdf.p0.diff.png)](noembed-eucjp.pdf.p0.diff.png) |

### noembed-identity.pdf page 1

595x842; diff: 0.033%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](noembed-identity.pdf.p0.baseline.png)](noembed-identity.pdf.p0.baseline.png) | [![Dart render](noembed-identity.pdf.p0.dart.png)](noembed-identity.pdf.p0.dart.png) | [![Diff](noembed-identity.pdf.p0.diff.png)](noembed-identity.pdf.p0.diff.png) |

### noembed-sjis.pdf page 1

595x842; diff: 0.184%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](noembed-sjis.pdf.p0.baseline.png)](noembed-sjis.pdf.p0.baseline.png) | [![Dart render](noembed-sjis.pdf.p0.dart.png)](noembed-sjis.pdf.p0.dart.png) | [![Diff](noembed-sjis.pdf.p0.diff.png)](noembed-sjis.pdf.p0.diff.png) |

### non-embedded-NuptialScript.pdf page 1

350x50; diff: 18.549%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](non-embedded-NuptialScript.pdf.p0.baseline.png)](non-embedded-NuptialScript.pdf.p0.baseline.png) | [![Dart render](non-embedded-NuptialScript.pdf.p0.dart.png)](non-embedded-NuptialScript.pdf.p0.dart.png) | [![Diff](non-embedded-NuptialScript.pdf.p0.diff.png)](non-embedded-NuptialScript.pdf.p0.diff.png) |

### openoffice.pdf page 1

200x50; diff: 1.340%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](openoffice.pdf.p0.baseline.png)](openoffice.pdf.p0.baseline.png) | [![Dart render](openoffice.pdf.p0.dart.png)](openoffice.pdf.p0.dart.png) | [![Diff](openoffice.pdf.p0.diff.png)](openoffice.pdf.p0.diff.png) |

### operator-in-TJ-array.pdf page 1

595x839; diff: 0.244%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](operator-in-TJ-array.pdf.p0.baseline.png)](operator-in-TJ-array.pdf.p0.baseline.png) | [![Dart render](operator-in-TJ-array.pdf.p0.dart.png)](operator-in-TJ-array.pdf.p0.dart.png) | [![Diff](operator-in-TJ-array.pdf.p0.diff.png)](operator-in-TJ-array.pdf.p0.diff.png) |

### operator_list_cycle.pdf page 1

612x792; diff: 0.249%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](operator_list_cycle.pdf.p0.baseline.png)](operator_list_cycle.pdf.p0.baseline.png) | [![Dart render](operator_list_cycle.pdf.p0.dart.png)](operator_list_cycle.pdf.p0.dart.png) | [![Diff](operator_list_cycle.pdf.p0.diff.png)](operator_list_cycle.pdf.p0.diff.png) |

### pattern_text_embedded_font.pdf page 1

596x842; diff: 0.966%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](pattern_text_embedded_font.pdf.p0.baseline.png)](pattern_text_embedded_font.pdf.p0.baseline.png) | [![Dart render](pattern_text_embedded_font.pdf.p0.dart.png)](pattern_text_embedded_font.pdf.p0.dart.png) | [![Diff](pattern_text_embedded_font.pdf.p0.diff.png)](pattern_text_embedded_font.pdf.p0.diff.png) |

### pdfjsbad1586.pdf page 1

612x792; diff: 0.003%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](pdfjsbad1586.pdf.p0.baseline.png)](pdfjsbad1586.pdf.p0.baseline.png) | [![Dart render](pdfjsbad1586.pdf.p0.dart.png)](pdfjsbad1586.pdf.p0.dart.png) | [![Diff](pdfjsbad1586.pdf.p0.diff.png)](pdfjsbad1586.pdf.p0.diff.png) |

### pdfkit_compressed.pdf page 1

612x792; diff: 0.045%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](pdfkit_compressed.pdf.p0.baseline.png)](pdfkit_compressed.pdf.p0.baseline.png) | [![Dart render](pdfkit_compressed.pdf.p0.dart.png)](pdfkit_compressed.pdf.p0.dart.png) | [![Diff](pdfkit_compressed.pdf.p0.diff.png)](pdfkit_compressed.pdf.p0.diff.png) |

### poppler-67295-0.pdf page 1

612x792; diff: 0.282%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](poppler-67295-0.pdf.p0.baseline.png)](poppler-67295-0.pdf.p0.baseline.png) | [![Dart render](poppler-67295-0.pdf.p0.dart.png)](poppler-67295-0.pdf.p0.dart.png) | [![Diff](poppler-67295-0.pdf.p0.diff.png)](poppler-67295-0.pdf.p0.diff.png) |

### poppler-91414-0-53.pdf page 1

795x842; diff: 0.146%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](poppler-91414-0-53.pdf.p0.baseline.png)](poppler-91414-0-53.pdf.p0.baseline.png) | [![Dart render](poppler-91414-0-53.pdf.p0.dart.png)](poppler-91414-0-53.pdf.p0.dart.png) | [![Diff](poppler-91414-0-53.pdf.p0.diff.png)](poppler-91414-0-53.pdf.p0.diff.png) |

### poppler-91414-0-54.pdf page 1

795x842; diff: 0.146%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](poppler-91414-0-54.pdf.p0.baseline.png)](poppler-91414-0-54.pdf.p0.baseline.png) | [![Dart render](poppler-91414-0-54.pdf.p0.dart.png)](poppler-91414-0-54.pdf.p0.dart.png) | [![Diff](poppler-91414-0-54.pdf.p0.diff.png)](poppler-91414-0-54.pdf.p0.diff.png) |

### pr4922.pdf page 1

400x50; diff: 7.955%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](pr4922.pdf.p0.baseline.png)](pr4922.pdf.p0.baseline.png) | [![Dart render](pr4922.pdf.p0.dart.png)](pr4922.pdf.p0.dart.png) | [![Diff](pr4922.pdf.p0.diff.png)](pr4922.pdf.p0.diff.png) |

### pr4922.pdf page 2

400x50; diff: 8.010%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](pr4922.pdf.p1.baseline.png)](pr4922.pdf.p1.baseline.png) | [![Dart render](pr4922.pdf.p1.dart.png)](pr4922.pdf.p1.dart.png) | [![Diff](pr4922.pdf.p1.diff.png)](pr4922.pdf.p1.diff.png) |

### quadpoints.pdf page 1

596x842; diff: 0.551%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](quadpoints.pdf.p0.baseline.png)](quadpoints.pdf.p0.baseline.png) | [![Dart render](quadpoints.pdf.p0.dart.png)](quadpoints.pdf.p0.dart.png) | [![Diff](quadpoints.pdf.p0.diff.png)](quadpoints.pdf.p0.diff.png) |

### radial_gradients.pdf page 1

595x842; diff: 2.969%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](radial_gradients.pdf.p0.baseline.png)](radial_gradients.pdf.p0.baseline.png) | [![Dart render](radial_gradients.pdf.p0.dart.png)](radial_gradients.pdf.p0.dart.png) | [![Diff](radial_gradients.pdf.p0.diff.png)](radial_gradients.pdf.p0.diff.png) |

### radial_gradients.pdf page 2

595x842; diff: 2.898%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](radial_gradients.pdf.p1.baseline.png)](radial_gradients.pdf.p1.baseline.png) | [![Dart render](radial_gradients.pdf.p1.dart.png)](radial_gradients.pdf.p1.dart.png) | [![Diff](radial_gradients.pdf.p1.diff.png)](radial_gradients.pdf.p1.diff.png) |

### radial_gradients.pdf page 3

595x842; diff: 3.070%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](radial_gradients.pdf.p2.baseline.png)](radial_gradients.pdf.p2.baseline.png) | [![Dart render](radial_gradients.pdf.p2.dart.png)](radial_gradients.pdf.p2.dart.png) | [![Diff](radial_gradients.pdf.p2.diff.png)](radial_gradients.pdf.p2.diff.png) |

### radial_gradients.pdf page 4

595x842; diff: 9.252%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](radial_gradients.pdf.p3.baseline.png)](radial_gradients.pdf.p3.baseline.png) | [![Dart render](radial_gradients.pdf.p3.dart.png)](radial_gradients.pdf.p3.dart.png) | [![Diff](radial_gradients.pdf.p3.diff.png)](radial_gradients.pdf.p3.diff.png) |

### radial_gradients.pdf page 5

595x842; diff: 9.275%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](radial_gradients.pdf.p4.baseline.png)](radial_gradients.pdf.p4.baseline.png) | [![Dart render](radial_gradients.pdf.p4.dart.png)](radial_gradients.pdf.p4.dart.png) | [![Diff](radial_gradients.pdf.p4.diff.png)](radial_gradients.pdf.p4.diff.png) |

### rc_annotation.pdf page 1

100x100; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](rc_annotation.pdf.p0.baseline.png)](rc_annotation.pdf.p0.baseline.png) | [![Dart render](rc_annotation.pdf.p0.dart.png)](rc_annotation.pdf.p0.dart.png) | [![Diff](rc_annotation.pdf.p0.diff.png)](rc_annotation.pdf.p0.diff.png) |

### rc_annotation.pdf page 2

100x100; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](rc_annotation.pdf.p1.baseline.png)](rc_annotation.pdf.p1.baseline.png) | [![Dart render](rc_annotation.pdf.p1.dart.png)](rc_annotation.pdf.p1.dart.png) | [![Diff](rc_annotation.pdf.p1.diff.png)](rc_annotation.pdf.p1.diff.png) |

### recursiveCompositGlyf.pdf page 1

612x792; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](recursiveCompositGlyf.pdf.p0.baseline.png)](recursiveCompositGlyf.pdf.p0.baseline.png) | [![Dart render](recursiveCompositGlyf.pdf.p0.dart.png)](recursiveCompositGlyf.pdf.p0.dart.png) | [![Diff](recursiveCompositGlyf.pdf.p0.diff.png)](recursiveCompositGlyf.pdf.p0.diff.png) |

### rotation.pdf page 1

612x792; diff: 0.440%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](rotation.pdf.p0.baseline.png)](rotation.pdf.p0.baseline.png) | [![Dart render](rotation.pdf.p0.dart.png)](rotation.pdf.p0.dart.png) | [![Diff](rotation.pdf.p0.diff.png)](rotation.pdf.p0.diff.png) |

### rotation.pdf page 2

792x612; diff: 0.391%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](rotation.pdf.p1.baseline.png)](rotation.pdf.p1.baseline.png) | [![Dart render](rotation.pdf.p1.dart.png)](rotation.pdf.p1.dart.png) | [![Diff](rotation.pdf.p1.diff.png)](rotation.pdf.p1.diff.png) |

### scan-bad.pdf page 1

612x792; diff: 0.048%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](scan-bad.pdf.p0.baseline.png)](scan-bad.pdf.p0.baseline.png) | [![Dart render](scan-bad.pdf.p0.dart.png)](scan-bad.pdf.p0.dart.png) | [![Diff](scan-bad.pdf.p0.diff.png)](scan-bad.pdf.p0.diff.png) |

### sci-notation.pdf page 1

612x792; diff: 0.362%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](sci-notation.pdf.p0.baseline.png)](sci-notation.pdf.p0.baseline.png) | [![Dart render](sci-notation.pdf.p0.dart.png)](sci-notation.pdf.p0.dart.png) | [![Diff](sci-notation.pdf.p0.diff.png)](sci-notation.pdf.p0.diff.png) |

### secHandler.pdf page 1

612x792; diff: 0.165%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](secHandler.pdf.p0.baseline.png)](secHandler.pdf.p0.baseline.png) | [![Dart render](secHandler.pdf.p0.dart.png)](secHandler.pdf.p0.dart.png) | [![Diff](secHandler.pdf.p0.diff.png)](secHandler.pdf.p0.diff.png) |

### shading_extend.pdf page 1

596x842; diff: 2.098%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](shading_extend.pdf.p0.baseline.png)](shading_extend.pdf.p0.baseline.png) | [![Dart render](shading_extend.pdf.p0.dart.png)](shading_extend.pdf.p0.dart.png) | [![Diff](shading_extend.pdf.p0.diff.png)](shading_extend.pdf.p0.diff.png) |

### simpletype3font.pdf page 1

612x792; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](simpletype3font.pdf.p0.baseline.png)](simpletype3font.pdf.p0.baseline.png) | [![Dart render](simpletype3font.pdf.p0.dart.png)](simpletype3font.pdf.p0.dart.png) | [![Diff](simpletype3font.pdf.p0.diff.png)](simpletype3font.pdf.p0.diff.png) |

### sizes.pdf page 1

612x792; diff: 0.004%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](sizes.pdf.p0.baseline.png)](sizes.pdf.p0.baseline.png) | [![Dart render](sizes.pdf.p0.dart.png)](sizes.pdf.p0.dart.png) | [![Diff](sizes.pdf.p0.diff.png)](sizes.pdf.p0.diff.png) |

### sizes.pdf page 2

649x323; diff: 0.003%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](sizes.pdf.p1.baseline.png)](sizes.pdf.p1.baseline.png) | [![Dart render](sizes.pdf.p1.dart.png)](sizes.pdf.p1.dart.png) | [![Diff](sizes.pdf.p1.diff.png)](sizes.pdf.p1.diff.png) |

### sizes.pdf page 3

792x612; diff: 0.006%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](sizes.pdf.p2.baseline.png)](sizes.pdf.p2.baseline.png) | [![Dart render](sizes.pdf.p2.dart.png)](sizes.pdf.p2.dart.png) | [![Diff](sizes.pdf.p2.diff.png)](sizes.pdf.p2.diff.png) |

### smask_alpha_bc.pdf page 1

220x160; diff: 0.011%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](smask_alpha_bc.pdf.p0.baseline.png)](smask_alpha_bc.pdf.p0.baseline.png) | [![Dart render](smask_alpha_bc.pdf.p0.dart.png)](smask_alpha_bc.pdf.p0.dart.png) | [![Diff](smask_alpha_bc.pdf.p0.diff.png)](smask_alpha_bc.pdf.p0.diff.png) |

### smask_alpha_oob.pdf page 1

600x600; diff: 0.222%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](smask_alpha_oob.pdf.p0.baseline.png)](smask_alpha_oob.pdf.p0.baseline.png) | [![Dart render](smask_alpha_oob.pdf.p0.dart.png)](smask_alpha_oob.pdf.p0.dart.png) | [![Diff](smask_alpha_oob.pdf.p0.diff.png)](smask_alpha_oob.pdf.p0.diff.png) |

### smask_alpha_oob_transfer.pdf page 1

600x600; diff: 97.332%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](smask_alpha_oob_transfer.pdf.p0.baseline.png)](smask_alpha_oob_transfer.pdf.p0.baseline.png) | [![Dart render](smask_alpha_oob_transfer.pdf.p0.dart.png)](smask_alpha_oob_transfer.pdf.p0.dart.png) | [![Diff](smask_alpha_oob_transfer.pdf.p0.diff.png)](smask_alpha_oob_transfer.pdf.p0.diff.png) |

### smask_luminosity_oob_transfer.pdf page 1

500x300; diff: 96.800%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](smask_luminosity_oob_transfer.pdf.p0.baseline.png)](smask_luminosity_oob_transfer.pdf.p0.baseline.png) | [![Dart render](smask_luminosity_oob_transfer.pdf.p0.dart.png)](smask_luminosity_oob_transfer.pdf.p0.dart.png) | [![Diff](smask_luminosity_oob_transfer.pdf.p0.diff.png)](smask_luminosity_oob_transfer.pdf.p0.diff.png) |

### smaskdim.pdf page 1

612x792; diff: 0.012%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](smaskdim.pdf.p0.baseline.png)](smaskdim.pdf.p0.baseline.png) | [![Dart render](smaskdim.pdf.p0.dart.png)](smaskdim.pdf.p0.dart.png) | [![Diff](smaskdim.pdf.p0.diff.png)](smaskdim.pdf.p0.diff.png) |

### standard_fonts.pdf page 1

596x842; diff: 10.454%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](standard_fonts.pdf.p0.baseline.png)](standard_fonts.pdf.p0.baseline.png) | [![Dart render](standard_fonts.pdf.p0.dart.png)](standard_fonts.pdf.p0.dart.png) | [![Diff](standard_fonts.pdf.p0.diff.png)](standard_fonts.pdf.p0.diff.png) |

### standard_fonts.pdf page 2

596x842; diff: 11.142%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](standard_fonts.pdf.p1.baseline.png)](standard_fonts.pdf.p1.baseline.png) | [![Dart render](standard_fonts.pdf.p1.dart.png)](standard_fonts.pdf.p1.dart.png) | [![Diff](standard_fonts.pdf.p1.diff.png)](standard_fonts.pdf.p1.diff.png) |

### standard_fonts.pdf page 3

596x842; diff: 10.682%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](standard_fonts.pdf.p2.baseline.png)](standard_fonts.pdf.p2.baseline.png) | [![Dart render](standard_fonts.pdf.p2.dart.png)](standard_fonts.pdf.p2.dart.png) | [![Diff](standard_fonts.pdf.p2.diff.png)](standard_fonts.pdf.p2.diff.png) |

### standard_fonts.pdf page 4

596x842; diff: 12.529%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](standard_fonts.pdf.p3.baseline.png)](standard_fonts.pdf.p3.baseline.png) | [![Dart render](standard_fonts.pdf.p3.dart.png)](standard_fonts.pdf.p3.dart.png) | [![Diff](standard_fonts.pdf.p3.diff.png)](standard_fonts.pdf.p3.diff.png) |

### standard_fonts.pdf page 5

596x842; diff: 11.006%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](standard_fonts.pdf.p4.baseline.png)](standard_fonts.pdf.p4.baseline.png) | [![Dart render](standard_fonts.pdf.p4.dart.png)](standard_fonts.pdf.p4.dart.png) | [![Diff](standard_fonts.pdf.p4.diff.png)](standard_fonts.pdf.p4.diff.png) |

### standard_fonts.pdf page 6

596x842; diff: n/a

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| missing | [![Dart render](standard_fonts.pdf.p5.dart.png)](standard_fonts.pdf.p5.dart.png) | missing |

### tensor-allflags-withfunction.pdf page 1

612x792; diff: 0.477%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](tensor-allflags-withfunction.pdf.p0.baseline.png)](tensor-allflags-withfunction.pdf.p0.baseline.png) | [![Dart render](tensor-allflags-withfunction.pdf.p0.dart.png)](tensor-allflags-withfunction.pdf.p0.dart.png) | [![Diff](tensor-allflags-withfunction.pdf.p0.diff.png)](tensor-allflags-withfunction.pdf.p0.diff.png) |

### text_clip_cff_cid.pdf page 1

580x200; diff: 0.008%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](text_clip_cff_cid.pdf.p0.baseline.png)](text_clip_cff_cid.pdf.p0.baseline.png) | [![Dart render](text_clip_cff_cid.pdf.p0.dart.png)](text_clip_cff_cid.pdf.p0.dart.png) | [![Diff](text_clip_cff_cid.pdf.p0.diff.png)](text_clip_cff_cid.pdf.p0.diff.png) |

### text_rise_eol_bug.pdf page 1

612x792; diff: 0.220%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](text_rise_eol_bug.pdf.p0.baseline.png)](text_rise_eol_bug.pdf.p0.baseline.png) | [![Dart render](text_rise_eol_bug.pdf.p0.dart.png)](text_rise_eol_bug.pdf.p0.dart.png) | [![Diff](text_rise_eol_bug.pdf.p0.diff.png)](text_rise_eol_bug.pdf.p0.diff.png) |

### textfields.pdf page 1

612x792; diff: 1.172%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](textfields.pdf.p0.baseline.png)](textfields.pdf.p0.baseline.png) | [![Dart render](textfields.pdf.p0.dart.png)](textfields.pdf.p0.dart.png) | [![Diff](textfields.pdf.p0.diff.png)](textfields.pdf.p0.diff.png) |

### tiling-pattern-box.pdf page 1

596x842; diff: 0.997%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](tiling-pattern-box.pdf.p0.baseline.png)](tiling-pattern-box.pdf.p0.baseline.png) | [![Dart render](tiling-pattern-box.pdf.p0.dart.png)](tiling-pattern-box.pdf.p0.dart.png) | [![Diff](tiling-pattern-box.pdf.p0.diff.png)](tiling-pattern-box.pdf.p0.diff.png) |

### tiling-pattern-large-steps.pdf page 1

4000x400; diff: 0.001%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](tiling-pattern-large-steps.pdf.p0.baseline.png)](tiling-pattern-large-steps.pdf.p0.baseline.png) | [![Dart render](tiling-pattern-large-steps.pdf.p0.dart.png)](tiling-pattern-large-steps.pdf.p0.dart.png) | [![Diff](tiling-pattern-large-steps.pdf.p0.diff.png)](tiling-pattern-large-steps.pdf.p0.diff.png) |

### tiling_patterns_variations.pdf page 1

600x800; diff: 4.001%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](tiling_patterns_variations.pdf.p0.baseline.png)](tiling_patterns_variations.pdf.p0.baseline.png) | [![Dart render](tiling_patterns_variations.pdf.p0.dart.png)](tiling_patterns_variations.pdf.p0.dart.png) | [![Diff](tiling_patterns_variations.pdf.p0.diff.png)](tiling_patterns_variations.pdf.p0.diff.png) |

### transparent.pdf page 1

200x200; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](transparent.pdf.p0.baseline.png)](transparent.pdf.p0.baseline.png) | [![Dart render](transparent.pdf.p0.dart.png)](transparent.pdf.p0.dart.png) | [![Diff](transparent.pdf.p0.diff.png)](transparent.pdf.p0.diff.png) |

### type4psfunc.pdf page 1

612x792; diff: 0.008%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](type4psfunc.pdf.p0.baseline.png)](type4psfunc.pdf.p0.baseline.png) | [![Dart render](type4psfunc.pdf.p0.dart.png)](type4psfunc.pdf.p0.dart.png) | [![Diff](type4psfunc.pdf.p0.diff.png)](type4psfunc.pdf.p0.diff.png) |

### vertical.pdf page 1

250x322; diff: 1.512%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](vertical.pdf.p0.baseline.png)](vertical.pdf.p0.baseline.png) | [![Dart render](vertical.pdf.p0.dart.png)](vertical.pdf.p0.dart.png) | [![Diff](vertical.pdf.p0.diff.png)](vertical.pdf.p0.diff.png) |

### vertical.pdf page 2

250x322; diff: 0.932%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](vertical.pdf.p1.baseline.png)](vertical.pdf.p1.baseline.png) | [![Dart render](vertical.pdf.p1.dart.png)](vertical.pdf.p1.dart.png) | [![Diff](vertical.pdf.p1.diff.png)](vertical.pdf.p1.diff.png) |

### vertical.pdf page 3

250x322; diff: 0.932%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](vertical.pdf.p2.baseline.png)](vertical.pdf.p2.baseline.png) | [![Dart render](vertical.pdf.p2.dart.png)](vertical.pdf.p2.dart.png) | [![Diff](vertical.pdf.p2.diff.png)](vertical.pdf.p2.diff.png) |

### visibility_expressions.pdf page 1

341x341; diff: 0.243%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](visibility_expressions.pdf.p0.baseline.png)](visibility_expressions.pdf.p0.baseline.png) | [![Dart render](visibility_expressions.pdf.p0.dart.png)](visibility_expressions.pdf.p0.dart.png) | [![Diff](visibility_expressions.pdf.p0.diff.png)](visibility_expressions.pdf.p0.diff.png) |

### xobject-image.pdf page 1

200x100; diff: 0.000%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](xobject-image.pdf.p0.baseline.png)](xobject-image.pdf.p0.baseline.png) | [![Dart render](xobject-image.pdf.p0.dart.png)](xobject-image.pdf.p0.dart.png) | [![Diff](xobject-image.pdf.p0.diff.png)](xobject-image.pdf.p0.diff.png) |

### xref_command_missing.pdf page 1

200x50; diff: 8.480%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](xref_command_missing.pdf.p0.baseline.png)](xref_command_missing.pdf.p0.baseline.png) | [![Dart render](xref_command_missing.pdf.p0.dart.png)](xref_command_missing.pdf.p0.dart.png) | [![Diff](xref_command_missing.pdf.p0.diff.png)](xref_command_missing.pdf.p0.diff.png) |

### zerowidthline.pdf page 1

596x842; diff: 0.935%

| PDF.js baseline | Dart render | Diff |
| --- | --- | --- |
| [![PDF.js baseline](zerowidthline.pdf.p0.baseline.png)](zerowidthline.pdf.p0.baseline.png) | [![Dart render](zerowidthline.pdf.p0.dart.png)](zerowidthline.pdf.p0.dart.png) | [![Diff](zerowidthline.pdf.p0.diff.png)](zerowidthline.pdf.p0.diff.png) |

