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
  scenarios.json; added to the nightly sweep list. Sweep-verified: all 6
  files parse/interpret/extract/save clean (cad sheet: 442k content ops).
