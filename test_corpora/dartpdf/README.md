# dart-pdf public test corpus

The project-owned sibling of the Ghent Output Suite and pdf.js corpora:
every file here is **synthesized by dart-pdf's own writers** from seeded
generators, so the corpus is freely redistributable and grows whatever
document classes our testing needs next.

**License: CC0 1.0 (public domain).** Use these files for anything,
including testing other PDF software.

## The measurement contract

The committed bytes are canonical - perf sweeps (`tool/perf.sh sweep
dartpdf-corpus`), baselines, and cross-revision diffs all assume they do
not drift. Regenerate only for a deliberate corpus change:

    tool/gen_corpus.sh

and review the git diff like a baseline update. Generation is
byte-deterministic (fixed seeds, fixed annotation names - never the random
/NM path, no timestamps), so an unchanged generator reproduces identical
bytes; a serializer change in pdf_cos will legitimately alter them, which
is exactly the kind of diff to review deliberately.

## Document classes

| File | Class | Exercises |
|---|---|---|
| `cad-sheet-8p.pdf` | dense vector CAD (A1) | interpreter throughput, linework/hatch/label density (~55k ops/page) |
| `diagram-dense-3p.pdf` | ultra-dense diagram sheet | tokenizer/interpreter saturation: ~270k ops/page, MB-scale content streams |
| `plan-set-16p.pdf` | multi-sheet plan set | sustained ~70k ops/page across a set (per-sheet density of the 58-sheet class; full-set memory scale lives in the *generated* `cad-138p-sweep` scenario) |
| `styled-booklet-24p.pdf` | designed booklet | 8 embedded TrueType programs, ~12 Form XObject tokenizations/page, transparency (ExtGState), two-column text over full-page art |
| `scan-book-12p.pdf` | scanned circuit book (A3) | memory workload: 3.7 MB decoded grayscale per page (~45 MB/set) behind ~40 KB streams, trivial content ops - the image-cache/OOM class |
| `raster-underlay-1p.pdf` | giant-image survey/CAD sheet | two 9460×2918 `DeviceRGB` underlays (single image wider than the 8192-px GPU max texture) each under a full-size non-DCT gray `/SMask`, 71 OCG layers, ~221 MB RGBA if decoded at native resolution - the soft-masked-underlay / display-resolution-decode class. Committed variant is FlateDecode; the DCTDecode variant that reproduces the platform-JPEG decode pathology is the generated `raster-underlay-render` perf doc |
| `hatch-sections-4p.pdf` | tiling-pattern-hatched sections (A1) | PatternType 1 fills: ~70 regions/page over four shared cells (diagonal/cross/dot + uncolored rotated), ~90k cell executions -> ~300k device commands per page under per-tile re-interpretation - the #524 record-once/replay class |
| `text-report-40p.pdf` | office text | page tree walk, base-14 text runs, extraction |
| `type3-text-6p.pdf` | Type3-font text (TeX-era class) | ~7400 CharProc glyph executions/page over 26 procs (half vector, half 1-bit inline ImageMask); per-occurrence re-interpretation (#535) and the inline-image worker-decline path |
| `image-scan-4p.pdf` | scan-like images | full-page RGB decode (Flate), image cache |
| `cmyk-jpeg-1p.pdf` | print-image color edge (#370) | Adobe YCCK (transform=2) and plain CMYK (transform=0) DCTDecode twins of the same swatches - polarity must render both rows identically |
| `annotated-10p.pdf` | markup revision | annotation appearances (highlight/underline/strikeout/ink/square/circle/line/free text/note), incremental-update parsing |
| `broken-startxref.pdf` | recovery | xref rebuild via the `N G obj` scan (recovery timing class) |
| `junk-prefix.pdf` | leniency | junk before `%PDF-`, header-relative offsets |

## Profiled classes (sim-not-ship)

Real-world documents that cannot be redistributed (commercial or
third-party copyright — "publicly available on a website" is not a
license) are **profiled locally with the perf sweep**
(`perf_sweep.dart --one <file> --phases`) and their workload signature is
reproduced synthetically here: `styled-booklet` mirrors a 62-page RPG
quickstart (93 embedded fonts, 13 form tokenizations/page),
`diagram-dense` an ARTC overhead-wiring diagram (279k ops/page),
`plan-set` a 58-sheet rail territory plan (81k ops/page sustained,
0.5 GB peak RSS), `scan-book` a 187 MB / 198-page scanned relay-room
book from an app-OOM bug report (trivial ops, decoded-pixel memory is the
whole workload), and `raster-underlay` an ~8 MB single-page survey drawing
(two 9460×2918 DCTDecode underlays under non-DCT gray soft masks and 71 OCG
layers - ~220 MB RGBA resident, the giant-single-image + soft-mask class
that overruns the web image-cache budget when decoded at native resolution). Keep the originals in the gitignored `corpus/` for the
`local-corpus-sweep` scenario; when you meet a new document class worth
covering, profile it the same way and add a seeded builder for its shape.

Generators: `packages/pdf_document/tool/gen_public_corpus.dart`,
`packages/pdf_cos/tool/gen_cad_pdf.dart`, and
`packages/pdf_test_fixtures/tool/gen_raster_underlay_pdf.dart`, orchestrated
by `tool/gen_corpus.sh`. New classes welcome - add a builder, keep it seeded
and deterministic, document it here.

Note for perf tooling: the two damaged files *intentionally* trip the
`xrefRecovered`/offset-shift paths - structural-event counters firing on
them is correct; firing on any *other* file is a bug.
