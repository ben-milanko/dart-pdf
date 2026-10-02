# 6.0 PR B: the app and the example move to material_ui

The second half of the material_ui plan's 6.0.0 milestone, stacked on PR A
(`2026-10-02-material-ui-6-library.md`). After it nothing in the repo imports
`package:flutter/material.dart` or `cupertino.dart` except the editor's
legacy-host bridge and the editor tests that build legacy hosts on purpose,
and the analyzer enforces that.

## What changed

- **`dart fix --apply --code=migrate_design_widgets`** over `app/` (lib,
  test, integration_test, tool - the perf harness package and the screenshot
  entry included) and `packages/dart_pdf_editor/example/` (lib, test,
  patrol_test, tool): 74 + 24 files, import lines only. The `any`
  constraints became `material_ui: ^1.4.0` (app, harness, example) and
  `cupertino_ui: ^1.1.1` (example, for the Cupertino host). No `export`
  re-exported a design library. The app's `cupertino_icons` dependency was
  unused (no `CupertinoIcons` anywhere) and is gone.
- **Delegates.** `app/lib/l10n/app_delegates.dart` holds
  `appLocalizationsDelegates` = `AppLocalizations.delegate` +
  `DartPdfPrintingLocalizations.delegate` + `PdfEditorLocalizations.delegates`
  (editor + material_ui's `GlobalMaterialLocalizations.delegates`). The three
  `MaterialApp`s (splash in `main.dart`, `app.dart`, `tool/screenshots_main.dart`)
  register it instead of spreading gen-l10n's
  `AppLocalizations.localizationsDelegates`, which still lists the legacy
  `flutter_localizations` delegates (C9: no material_ui strings, a `uk`
  crash). It lives beside the generated files but is hand-written, like
  `app_l10n.dart`. No prefixed imports were needed: once the
  `flutter_localizations` import is gone, `GlobalMaterialLocalizations` only
  resolves to material_ui's. `flutter_localizations` stays a dependency of
  the app and the example because gen-l10n's output imports it.
- **Example.** `main.dart` registers `AppLocalizations.delegate` +
  `PdfEditorLocalizations.delegates`. `cupertino_host.dart` is a cupertino_ui
  `CupertinoApp`, taking `GlobalCupertinoLocalizations` from cupertino_ui and
  only `GlobalWidgetsLocalizations` from flutter_localizations
  (`show`-limited: the unprefixed import would make the Cupertino class
  ambiguous). Neither material_ui nor cupertino_ui exports a widgets
  delegate of its own; material_ui's `delegates` list re-exports
  flutter_localizations' one.
- **Theme.** No code change: `materialThemeMode` and the seeded `ThemeData`s
  are material_ui types once the import flips. With material_ui
  localizations, cupertino_ui localizations and a material_ui `Theme` all
  present, `PdfMaterialHost` installs nothing, so the editor reads the app's
  theme directly and the legacy bridge never runs in the app.
- **Lint.** `migrate_design_widgets` is a linter rule in the Dart 3.13
  analyzer (not on by default; `dart fix` still finds its fixes). It is now
  enabled and raised to `error` in the analysis options of every Flutter
  package (editor, printing, gpu, assets, both OCR packages), the example and
  the app (the perf harness inherits the app's file). Line ignores sit on the
  bridge's two imports and on the three editor test files that build legacy
  hosts (`support/pump_host.dart`, `legacy_host_test.dart`,
  `ink_surface_test.dart`). It flags `flutter/material.dart` and
  `flutter/cupertino.dart` imports but not `flutter_localizations`; that one
  stays `check_design_imports`' rule (d).
- **Tests.** Four tests that spread the generated list now register the
  explicit one. New `app/test/app_delegates_test.dart`: uk/de/ar resolve the
  app, editor and printing bundles plus material_ui's own Material
  translation (not the English default).
- The patrol finders the plan scheduled for this PR had already moved to
  keys in PR A (the legacy example failed CI on them); nothing left to do.

## Gotchas

- **`analyzer: errors: migrate_design_widgets: error` alone does nothing**:
  the rule has to be enabled under `linter: rules:` too.
- **`// ignore: rule, some words`** parses the words as further rule names.
  Put the reason on its own comment line above the ignore.
- `tool/format.dart` reformatted a handful of files the fix touched that had
  drifted from the formatter's output; harmless.

## Verification

- `fvm dart analyze --fatal-infos` at the root: clean, with the lint on
  everywhere. A probe file importing `flutter/material.dart` or
  `flutter/cupertino.dart` in the example fails it.
- `check_design_imports` (+ tests), `check_lockstep_constraints`,
  `check_arb_coverage`: OK.
- Suites vs the base (`ce9426ec`, PR A's head): editor 3128 passed / 33
  skipped (3128/33), printing 97 (97), example 67 (67), app 680 (677 + the
  3 new delegate cases).
- Web A/B, 6 interleaved runs:
  - **toolbar-arm vs PR A** (`ce9426ec`, legacy-hosted harness): jankCount
    17 -> 18, per-arm build -0.1%, buildP50 -0.5%; toolbarArmMsP95 flagged
    +17.6% but both sides are bimodal (~30 or ~47 ms per run) and the median
    moved with the mix.
  - **toolbar-arm vs PR A's base** (`db440c97`, everything legacy): jankCount
    18 -> 20 (runs 13-22 vs 18-19), per-arm build +9.9%, buildP50 1.46 ->
    2.00 ms, arm P95/max faster. So the extra jank PR A saw is **not** the
    legacy host: a material_ui host keeps it. It travels with the chrome
    being material_ui widgets. Not chased here.
  - **wheel-text vs PR A**: flat (buildMax -0.1%, jank 6 -> 5, open -5%).
- App release web (`flutter build web --release`): `main.dart.js`
  4,533,259 B vs 4,478,704 (+54.6 KB raw, +9.7 KB gzip): the splash's
  `MaterialApp` and its localizations are material_ui's now, which used to
  live in the deferred editor part. The deferred part fell 4,848,357 ->
  4,233,227 B (-615 KB) with the legacy Material library gone. Total -560 KB
  raw, -150 KB gzip (2,802,724 -> 2,652,234).
- macOS (debug, Impeller): `tool/screenshots_main.dart` built and run on both
  trees with its signal-file protocol (`DARTPDF_SHOT_SIGNAL_DIR` /
  `DARTPDF_SHOT_OUTPUT_DIR`, pointed into the app's sandbox container since
  the sandbox can't write to /tmp). Welcome, editor (light) and editor (dark)
  are pixel-identical to PR A's legacy-hosted app except anti-aliasing in the
  page thumbnails. No FlutterError in either log; both print the same 12
  Impeller "Texture descriptor was invalid" lines, so those predate this.
  The real `lib/main.dart` entry was built but not launched: it shares the
  installed app's sandbox container (same bundle id), so a run would read
  and rewrite the owner's real recents and session.

## Follow-ups

- The app could build with `--dart-define=PDF_LEGACY_MATERIAL_BRIDGE=false`
  now (~12 KB of web JS) as `doc/migrating-to-6.md` suggests. That touches
  every release lane's build line, so it is left for its own change.
- toolbar-arm's jank (+2 vs all-legacy) and per-arm build (+10%) under
  material_ui.
