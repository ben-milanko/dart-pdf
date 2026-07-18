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
| `text-report-40p.pdf` | office text | page tree walk, base-14 text runs, extraction |
| `image-scan-4p.pdf` | scan-like images | full-page RGB decode (Flate), image cache |
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
`diagram-dense` an ARTC overhead-wiring diagram (279k ops/page), and
`plan-set` a 58-sheet rail territory plan (81k ops/page sustained,
0.5 GB peak RSS). Keep the originals in the gitignored `corpus/` for the
`local-corpus-sweep` scenario; when you meet a new document class worth
covering, profile it the same way and add a seeded builder for its shape.

Generators: `packages/pdf_document/tool/gen_public_corpus.dart` and
`packages/pdf_cos/tool/gen_cad_pdf.dart`, orchestrated by
`tool/gen_corpus.sh`. New classes welcome - add a builder, keep it seeded
and deterministic, document it here.

Note for perf tooling: the two damaged files *intentionally* trip the
`xrefRecovered`/offset-shift paths - structural-event counters firing on
them is correct; firing on any *other* file is a bug.
