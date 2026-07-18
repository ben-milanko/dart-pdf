# 2026-07-18 — dart-pdf public test corpus (test_corpora/dartpdf)

Follow-on to the perf tooling suite (same day, separate PR): a
project-owned, CC0, **byte-deterministic** corpus alongside Ghent and
pdfjs — synthesized entirely by our own writers so it is redistributable
and grows whatever document classes testing needs next.

- Generators: `pdf_document/tool/gen_public_corpus.dart` (text report,
  scan-like images, annotated revision via `PdfEditor`, damaged variants) +
  the existing `pdf_cos/tool/gen_cad_pdf.dart` (8-page A1 sheet), both
  orchestrated by `tool/gen_corpus.sh`. Committed bytes are the
  measurement contract; regen deliberately and review the diff.
- Determinism details: fixed seeds; annotation calls pass explicit
  `name:`/`author:` — otherwise `_addAnnotation` generates a random /NM
  (Random.secure) and output stops reproducing. No timestamps anywhere.
  Verified byte-identical across regens.
- Damaged classes calibrate the structural counters: `broken-startxref`
  is the ONLY file that trips `xrefRecovered` (3.2x open cost vs its
  intact twin `text-report-40p`); `junk-prefix` exercises the
  header-shift leniency path with `xrefRecovered == 0`. Gotcha:
  `CosDocument._findHeader` scans only the first 1024 bytes — a 2 KB junk
  prefix is unopenable by design, keep it under the window.
- Perf wiring: scenario `dartpdf-corpus` (vm-sweep, phases on, ciSafe) in
  scenarios.json; added to the nightly sweep list. Sweep-verified: all
  files parse/interpret/extract/save clean (cad sheet: 442k content ops).

## Profiled classes (sim-not-ship pattern)

Three real documents Ben supplied could not be committed (commercial /
third-party copyright - public availability on a website is not a
redistribution license), so each was profiled with
`perf_sweep.dart --one <file> --phases` and its workload signature
synthesized:

- `styled-booklet-24p.pdf` ← 62pp RPG quickstart (24 MB): 93 embedded
  font programs, ~13 content tokenizations/page (Form XObjects), 8.3k
  ops/page, transparency. Sim: 8 embedded copies of the fixture TTF (A/B
  glyphs only - headings are AB-strings; explicit resourceNames), 12
  forms/page (8 shared + 4 unique), alpha ExtGState over a shared
  background image, two-column text. Measured: 12.25 tokenizations/page,
  3.8k ops/page.
- `diagram-dense-3p.pdf` ← ARTC overhead-wiring diagram (3pp, 838k ops =
  279k ops/page, ~5 MB content/page). Sim: gen_cad_pdf at param 80000 →
  270k ops/page. Note the generator's actual-ops-per-param yield is
  nonlinear - calibrate against a sweep, don't extrapolate.
- `plan-set-16p.pdf` ← 58-sheet rail territory plan (18 MB, 4.7M ops,
  81k ops/page sustained, 552 MB peak RSS). Sim: 16 pages at param 23000
  → 69k ops/page; full-set memory scale intentionally stays in the
  GENERATED cad-138p-sweep scenario rather than the repo.

All corpus files (including the deliberately damaged pair) validated by
an independent engine: pypdfium2 opens + renders page 0 of every file.
Corpus total ~4.3 MB (ghent is 115 MB for comparison).
