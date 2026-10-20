# CI: stop PR checks queueing for hours on macOS

PR checks like `Preview App / linux-gpu` and `CI / flutter-gpu-smoke` sat
"started" for 1-2 hours. The jobs themselves are short (linux-gpu ~2.5 min,
Preview macos-gpu ~7 min). The time went to **waiting for a macOS runner**:
for example, the 2026-10-08 run for #1045 queued `macos-gpu` 1h40m and
`flutter-gpu-smoke` 45 min. The shared macOS concurrency pool was saturated
for two reasons:

1. `ci.yml` had no `concurrency` group, so every superseded PR push kept
   its macOS jobs (`flutter-gpu-smoke`, `Print plugin / macos`) queued and
   running to completion. Two pushes 25 seconds apart cost two full macOS
   runs. CI now cancels in progress per PR (`ci-<PR number>`). Pushes to
   main/deploy group per SHA and are never cancelled.
2. `flutter-gpu-smoke`'s warm-up/first-tile A/B was ~25 of its ~30 minutes
   (17 scenarios x 6 repetitions x PR/main, plus priming) on every PR. A
   `gpu-scope` step now runs it only when the PR diff touches the render path
   (pdf_cos/pdf_document/pdf_graphics `lib/`, dart_pdf_editor `lib/` outside
   `l10n/` and `src/{editing,l10n,design,legacy}/`, the GPU package,
   `test_corpora/`, root pubspec, the summarizer, or ci.yml itself). When it
   is skipped, the step writes a one-line headline so the PR comment says
   why. Over the last 40 merges, 18 would have skipped. The smoke tile, corpus
   parity and same-host corpus comparison still run on every PR.

Patrol and Preview App already cancel superseded runs.
