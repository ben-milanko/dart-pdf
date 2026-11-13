# Flutter 3.47.8 → 3.50.0 upgrade

The toolchain pin moved to Flutter 3.50.0 (Dart 3.14.0, released 2026-11-11):
`.fvmrc`, every `flutter-version:`/`FLUTTER_VERSION` in `.github/workflows/`
(including a stale 3.47.5 pin in `screenshots.yml`), the session hook fallback,
README/CONTRIBUTING/CLAUDE/AGENTS, and `benchmark/web`. The app and perf harness
now declare `flutter: '>=3.50.0'`. The published packages keep `>=3.47.0`
because their lib code uses no 3.50-only API, and the `floor-analyze` CI job
still proves that against 3.47.0.

## What broke and how it was fixed

- **Experimental windowing API renames** (`app/lib/window_support.dart`):
  - `RegularWindowController` → `WindowController`
  - `RegularWindowControllerDelegate` → `WindowControllerDelegate`
  - `RegularWindow` → `Window`
  - `.sizedToContent` → `.shrinkWrap` (we don't use it)

  Constructor shape, delegate callbacks and the per-platform `windowHandle`
  are unchanged. `multi_window_test`, `tab_drag_test` and
  `native_window_drop_target_test` pass.
- **New deprecations under `--fatal-infos`.** `package:flutter/material.dart` and
  `cupertino.dart` are deprecated in favour of `material_ui`/`cupertino_ui`, and
  `flutter_localizations`' `GlobalMaterialLocalizations`/
  `GlobalCupertinoLocalizations` are deprecated too.
  - The legacy-host bridge and its tests already carried
    `// ignore: migrate_design_widgets`, so they now ignore
    `deprecated_member_use` as well.
  - 3.50's `gen-l10n` still emits the deprecated delegates. Every `l10n.yaml`
    therefore sets `header: "// ignore_for_file: deprecated_member_use"`, and
    the generated files were regenerated. Drop the header once gen-l10n emits
    the material_ui delegates.
- **Generated Windows plugin registrants** reordered (`share_plus` after
  `url_launcher_windows`). That is just 3.50's tooling sort order.
- **Android toolchain floor.** 3.50's Gradle plugin refuses builds below
  Gradle 9.3.1, AGP 9.1.1 or KGP 2.4.10 (see `DependencyVersionChecker.kt`).
  The example was on Gradle 9.1.0 / AGP 9.0.1 / KGP 2.3.20, and the app on
  KGP 2.3.20. Both now use 3.50's template set: Gradle 9.5.0, AGP 9.3.1,
  KGP 2.4.20, which also clears the warn thresholds. `dart_pdf_printing`'s
  standalone buildscript Kotlin moves to 2.4.20 to match.
- **Font registration lands a real event-loop turn later.** After
  `FontLoader`/`loadFontFromList` registers a new family, the engine's
  `fontsChange` system message now arrives after a widget test's fake-async
  pumps. `RelayoutWhenSystemFontsChangeMixin`'s frame callback is then still
  pending at teardown, and the test fails with "an animation is still
  running". The framework side of this is unchanged between 3.47 and 3.50,
  so the timing change is in the engine. The three tests that register a
  family for the first time in their isolate now end with
  `settleFontRegistration` (`test/support/font_registration.dart`): one
  `runAsync` turn, then a pump.

## Deliberately not changed

`dart_pdf_editor_flutter_gpu/assets/shaders/pdf_tile_gpu.shaderbundle` stays at
its 3.47 build:
- The 3.47 `linux-x64/impellerc` reproduces it byte for byte, so the bundle
  doesn't depend on which host built it.
- A 3.50 build is 312 bytes larger. The 3.50 loader only adds a skip for
  `kOptimizedOutBinding` (DCE'd uniforms/samplers), so the old bundle should
  load unchanged. The macOS `flutter-gpu-smoke` lane is the proof.
- Whether rebuilding with 3.50 is worth it, and whether a 3.50 bundle still
  loads on the 3.47 floor, is ben-milanko/dart-pdf#1269.

## API changes worth knowing (and the perf tickets)

These come from diffing the two SDKs locally (`bin/cache/pkg/sky_engine/lib/ui`,
`bin/cache/pkg/flutter_gpu`, `bin/cache/flutter_web_sdk/lib/_engine`) and from
the 3.50 release notes. Tracking issue: ben-milanko/dart-pdf#1266.

**`dart:ui`**
- `ImageFilter.shader(filterQuality:)`.
- `PlatformDispatcher.resetInternalState()`, for tests only (#1277).
- `ui.Hyphens`: soft hyphens now render at native line breaks. Watch the
  TextPainter fallback paths (#1278).

**`flutter_gpu`**
- `BindingSet`/`bindSet` (#1267).
- Index-cached `UniformSlot` binds (free).
- `texture2DArray` (#1268).
- Memoised pipeline state, and invalid pipelines now raise Dart errors.

**Impeller**
- UberSDF lines, rrects and gradients on desktop (#1270).
- Per-draw allocation cuts.
- Render-target cache purge on low memory (#1277).

**Web engine**
- Unified codecs, which clone each VideoFrame into an ImageBitmap (#1271).
- Skwasm `decodeImageFromPixels` now calls back after `Timer.run` (#1272).
- `PictureImageTracker` keeps a picture's images alive until it is disposed
  (#1273).
- Native filters cached per Dart filter object (#1274).
- Stricter, Dart-side `Vertices` index validation (#1275).
- `drawAtlas` honours `filterQuality` (#1276).

The bare-upgrade A/B and re-baseline is #1278.
