# 6.0 PR A: the libraries move to material_ui (app stays legacy)

The breaking half of the material_ui plan's 6.0.0 milestone: `dart_pdf_editor`
and `dart_pdf_printing` build on `material_ui`/`cupertino_ui` instead of
`package:flutter/material.dart`/`cupertino.dart`. The app and the editor's
example stay on the legacy library in this PR on purpose: they are the canary
for a legacy `MaterialApp` hosting the flipped library. PR B moves them.
Migration notes for hosts: `doc/migrating-to-6.md`.

## What changed

- **`dart fix --apply --code=migrate_design_widgets`** over the editor
  (lib + test) and printing (lib, test, example). It rewrote the import
  lines only (C9 held: 229 fixes, 3 analyzer errors, all in
  `material_host.dart`); the edits it made to `packages/dart_pdf_editor/example/`
  were reverted. The `any` constraints it writes became `material_ui: ^1.4.0`
  / `cupertino_ui: ^1.1.1`; every Flutter package's floor is `>=3.47.0`
  (`sdk: ^3.5.0` and language 3.5 unchanged). No export directive needed
  fixing. The gpu package imports only the widgets layer; only its floor
  moved.
- **`PdfMaterialHost`** (`design/material_host.dart`) is the 6.0 wrapper.
  `_needsHost` is "material_ui `MaterialLocalizations` or cupertino_ui
  `CupertinoLocalizations` missing, or no material_ui `Theme`, or the scope's
  tokens set colours" - a legacy `MaterialApp` provides none of those types,
  so it gets the full wrapper. Theme order: `PdfEditorThemeData.primary`/
  `brightness` tokens (new) -> material_ui `Theme` -> legacy `Theme` through
  the bridge (re-applying the host's `IconTheme` inside, C2) -> cupertino_ui
  `CupertinoTheme` -> legacy `CupertinoTheme` through the bridge ->
  widgets-layer signals. Localizations: the fallback delegates now wrap
  material_ui's `GlobalMaterialLocalizations` and cupertino_ui's
  `GlobalCupertinoLocalizations` (always both, C4).
- **The bridge** (`lib/src/legacy/legacy_host_bridge.dart`, C7) is the only
  lib file importing the legacy libraries (as `legacy`/`legacy_cupertino`).
  Lean reads: `findAncestorWidgetOfExactType<legacy.Theme>()?.data` +
  `legacy.Theme.maybeBrightnessOf` for the dependency, mapped to a
  material_ui `ThemeData` (all colour roles, text theme, icon theme,
  platform, density, M3 flag) cached in an `Expando` per host `ThemeData`.
  Notices: material_ui messenger -> legacy host messenger (a legacy
  `SnackBar` with the Undo action) -> overlay toast.
- **`PdfEditorLocalizations.delegates`** (`l10n/editor_localizations.dart`):
  `[DartPdfEditorLocalizations.delegate, ...GlobalMaterialLocalizations.delegates]`.
  The generated `localizationsDelegates` stays legacy (gen-l10n has no
  option, and the file is regenerated on every build with `generate: true`,
  so it cannot be hand-edited).
- **Removed** `themeMode`, the `ButtonStyleButton` `PdfDialogSubmit`
  constructor and `pdfSearchInputBorder`.
- **`tool/check_design_imports.dart`**: "design library" now means
  material_ui, cupertino_ui and the two legacy libraries, for the allowlist
  and the headless closures alike; a new hard rule (d) allows the legacy
  libraries only under `lib/src/legacy/` and `flutter_localizations` only
  there and in the generated `lib/l10n/`; the gpu package's lib is scanned
  too; the `deprecatedMaterialEdges` mechanism is gone with its only entry.
  The baseline was edited by hand: +`editor_localizations.dart`,
  +`legacy_host_bridge.dart`, -`editing_preferences.dart`,
  -`search_field_style.dart`.
- **Ink audit.** `test/ink_surface_test.dart` walks every `InkResponse` on
  screen (resting, each tool group, each panel toggle, a selection; desktop
  and compact) and fails when an opaque fill sits between it and its
  `Material`. One hit: the toolbar's floating card (`_centeredCard`), whose
  `BoxDecoration` fill hid every strip splash under any host. It now holds a
  transparent `Material`.
- **CI**: `floor-analyze` runs on Flutter 3.47.0; new `legacy-bridge-dce`
  job runs `tool/check_legacy_bridge_dce.sh`.

## Gotchas

- **Guard shape matters for byte-identity.** The plan's guard
  (`if (!kFlag) return null; ...`) strips the legacy code but the build
  still differed by ~1.2 KB from a build without the bridge: dart2js counts
  the dead branch's call sites before pruning it, which changes inlining
  decisions elsewhere (`Opacity$`, `Hero$`, `SchemeContent$` factories
  appeared un-inlined). `kFlag && impl()` had the same problem. Only the
  expression form `kFlag ? _impl() : null` folds early enough: with it the
  define-off build is byte-identical. Keep every public bridge entry in
  that form.
- **Configurable imports cannot test a `-D` define.** `import 'a.dart' if
  (MY_FLAG == 'false') 'b.dart'` compiled the default branch under both
  `dart run -D` and `dart compile js -D` (3.47.5). Only `dart.library.*`
  works, so a stub-swapping import was not an option.
- **A material_ui host does not strip the bridge by itself** (the plan
  expected it would): the probe shows the marker present and +12 KB with the
  define on. The legacy `SnackBar` builds a legacy `Theme`, and the
  `findAncestorWidgetOfExactType` result types are not narrowed per type
  argument. Hence the define.
- **Cost under a legacy host in the probe**: +127 KB, almost all of it the
  legacy `SnackBar`/`SnackBarAction` machinery a tiny probe host never uses
  otherwise; a real legacy app that shows SnackBars already has it.
- **`fvm` in a temp dir** picks its global SDK, not `.fvmrc`'s. The DCE
  script resolves the pinned SDK's `flutterRoot` once from the repo root.
- **The `uk` crash (C9)** reproduced: with the host-side override disabled,
  a material_ui `MaterialApp` registering the generated (legacy) list throws
  "No MaterialLocalizations found" for `uk`. `test/non_english_host_test.dart`
  covers it (uk legacy list, de and ar with the new list). The host's own
  Localizations still logs its "locale not supported" warning; the test
  consumes it.
- **First-frame localization cost.** Loading material_ui's
  `GlobalMaterialLocalizations` initializes intl's date symbols for every
  locale. The base never did that under the legacy harness host (it had the
  legacy English defaults), so wheel-text's `buildMax` rose ~19 -> ~25 ms.
  The fallback delegates now hand plain/US English the built-in defaults
  (`_usEnglish`), and the A/B is flat.
- **Generated delegate lists in material_ui-hosted tests.** After the fix
  flipped a test's `MaterialApp` to material_ui, a test that registered
  gen-l10n's (legacy) list for `uk`/`fr` fails on the host Localizations'
  "locale not supported" warning. Those tests now register the material_ui
  list (`PdfEditorLocalizations.delegates`, or the printing delegate plus
  `GlobalMaterialLocalizations.delegates`).
- **Canary hit in the example.** Its toolbar helper found buttons with
  `widget is Tooltip` (the legacy type), which matches nothing in the
  flipped library; it uses the `pdf-*` keys now. The app's 677 tests passed
  unchanged.
- `PdfShellBar` is not exported; tests that need its context import
  `package:dart_pdf_editor/src/shell_chrome.dart` directly.

## Tests

- `test/support/pump_host.dart` gained `PdfTestHost.legacyMaterial` and
  `legacyCupertino`; `any_host_test.dart` runs every host (68 cases, 28 of them new).
- `test/legacy_host_test.dart`: dark seeded legacy theme -> exact primary,
  dark brightness and the painted header colour in the chrome, a theme change
  rebuilding it, the host `IconTheme` surviving, tokens winning, dialogs from
  the editor and from host code (Android/iOS/macOS text menus), a dropdown in
  a dialog, a sheet, and notices with Undo on the host's legacy messenger.

## Verification

- `fvm dart analyze --fatal-infos` at the workspace root: clean (the legacy
  app and example compile against the flipped library).
- Suites vs the branch base (`db440c97`): editor 3128 passed / 33 skipped
  (base 3084/33: +28 any-host cases for the two legacy hosts, +13 legacy host,
  +3 non-English, +2 ink, -2 removed deprecated-API tests), printing 97
  (97), gpu 17 / 105 skipped (code unchanged), example 67 (67), app 677
  (677).
- `tool/check_legacy_bridge_dce.sh`: PASS (define off byte-identical; legacy
  host: present by default, gone with the define off).
- Web A/B (`tool/perf.sh webdiff`, 6 interleaved runs): wheel-text flat
  (buildMax +0.8%, jank 5 -> 4). toolbar-arm: per-arm build -1%, buildP50
  -22%, but jankCount 16 -> 20 (runs 12-18 vs 17-24), unchanged when the
  toolbar card's new Material is reverted, so it comes with the library
  switch itself under the legacy harness host; worth a look in PR B, where
  the harness becomes a material_ui host.
- App `main.dart.js` (release web): 4,478,710 bytes vs 4,507,631 at the
  base (-28.9 KB raw; gzip 1,091,448 vs 1,095,447).
