# App shell: preference ticks skip MaterialApp, font discovery off the UI isolate

Two small app-host fixes from the wave-2 perf pass. Neither touches a
package `lib/`, rendering, or saved bytes.

## 1. The window shell rebuilds only for theme and locale

### Why

`_DartPdfWindow` (app/lib/app.dart) wrapped `MaterialApp` in a
`ListenableBuilder` over `Listenable.merge([prefs, showPerformanceOverlay,
localeOverride])`. `PdfEditingPreferences` notifies for every preference,
and the toolbar's stroke-width, opacity, eraser and font-size sliders write
one on each `onChanged`. So every drag tick rebuilt `MaterialApp`, both
`ThemeData(colorSchemeSeed)`, and - through `Navigator.didUpdateWidget` ->
`Route.changedExternalState`, which force-rebuilds every route's page - the
whole `EditorScreen`. Nothing in the shell reads those values:
`EditorScreen.build` reads no preference, and the widgets that do
(`PdfEditorView`, `SettingsDialog`, `PdfReader`) listen to the preferences
themselves. The merge dates from the original app and was extended for the
DevTools locale override (#512); it was never a deliberate choice.

### What changed

`_WindowShellSelector`, a private StatefulWidget inside `_DartPdfWindow`'s
build, listens to the preferences plus the two DevTools notifiers and calls
`setState` only when the record `(prefs.themeMode, prefs.locale,
localeOverride.value, showPerformanceOverlay.value)` changes. It
re-subscribes in `didUpdateWidget` if the preferences instance changes and
removes its listeners in `dispose`. Both `_DartPdfWindow` construction
sites (the primary window and `_openNewWindow`) get their own. `ThemeData`
stays built inline: a `static final` would capture `defaultTargetPlatform`
at first construction and pin it across `TargetPlatformVariant` tests, and
with the selector in place the inline build only runs on a real theme or
locale change anyway. The #512 comments on `locale:` and
`localeListResolutionCallback` are unchanged.

The controller's `preferences.addListener(notifyListeners)` forward stays.
Removing it saves nothing (PdfEditorView also listens to the preferences
directly), and hosts, the tune popup and the `controller.color` /
`fontFamily` / `dashedStroke` getters rely on it.

### Trap: baseline the selection eagerly

The first version declared `late ... _selected = _select();`. A lazy `late`
initializer runs on first read, and nothing read it until the first
`_onChanged`. That first notification is normally the asynchronous
preference load, so a saved dark theme or saved language was compared with
itself, looked unchanged, and the window stayed on the system theme until
some later change. The selection is now taken in `initState`, and
`app_prefs_rebuild_test.dart` has a "saved theme and language apply once
preferences load" case (seeded `SharedPreferences`) that fails on the lazy
version.

### Measured

`flutter test`, the checked-in 40-page letterhead report at 1600x1000 on
the Linux platform, element rebuilds counted with
`debugOnRebuildDirtyWidget`. Deterministic: identical across 3 interleaved
runs of each side.

| per real notification | main | branch |
|---|---|---|
| strokeWidth tick | 1,367.9 | 1,034.9 (0.76x) |
| opacity tick | 1,367.4 | 1,034.4 (0.76x) |
| page-rulers toggle | 1,379.0 | 1,046.0 (0.76x) |
| themeMode switch | 1,382.2 | 1,382.2 (must rebuild) |

MaterialApp and EditorScreen rebuilds over 10 stroke-width ticks: 10 -> 0.
The earlier profiling harness writes `strokeWidth = 2.0 + i * 0.25` for
`i = 0..9` and divides by 10; the first write equals the default and does
not notify, so it reads 1,231 -> 931 for the same change. Its per-subtree
buckets show where the rest is: PdfEditorView's own body 349, thumbnail
strip 262, toolbar 245, viewer 71. An earlier release-web probe (dart2js +
CanvasKit, headless Chrome) put the per-tick UI frame at 11.65 -> 9.1 ms
for this change; that was not re-run here.

### Follow-up (not in this change)

The remaining ~1,030 rebuilds per tick come from PdfEditorView's root
`Listenable.merge([_session, _prefs, _viewMode])` and the thumbnail strip's
unconditional `setState` in `_onPreferences`. PdfEditorView hears each
preference twice, directly and through the controller's forward, so
cutting either path alone changes nothing. The earlier profiling cut both
and a tick fell to ~260 (all thumbnail strip), but view toggles such as
rulers stopped reaching the viewer. The follow-up needs an aspect-scoped
selector over the preferences PdfEditorView actually reads, per-toggle
tests, and the controller forward kept for hosts.

## 2. Installed-font discovery runs on a helper isolate

### Why

`loadPlatformFonts()` (app/lib/platform_fonts_io.dart, and the identical
copy in the example app) is `async` but never awaited anything, so the
recursive `listSync`, the per-file name parsing and the sort all ran
synchronously inside `_DartPdfEditorAppState.initState`. Because the app
library is a deferred import, that is not the first painted frame (the
"Loading DartPDF" spinner is), but it is the frame that swaps the spinner
for the editor shell.

**Correction:** 2026-07-24-lazy-bundled-font-registration.md lists
platform-font discovery among startup work that is "already
`unawaited`/deferred". It was unawaited, but not deferred: the whole scan
ran before `initState` returned. This note supersedes that line.

### What changed

- A top-level `List<(String, String)> _scanFontRecords()` runs
  `_fontDirectories()`, the scan, the case-insensitive sort by family and
  the 300 cap, and returns (family, path) records. `loadPlatformFonts()`
  is `await Isolate.run(_scanFontRecords)` (a tear-off, so nothing from the
  caller is captured) and then builds the `PdfPlatformFont`s, with their
  lazy `loadBytes` closures, on the main isolate in the same order. The
  sort stays in the helper: on a large tree, sorting on main after the
  await still cost up to ~3 ms (two `toLowerCase` per comparison).
- `_baseName` uses `max(lastIndexOf('/'), lastIndexOf('\\'))` instead of a
  regex `lastIndexOf`. Checked equal to the old one on 200k random
  separator-heavy strings plus Windows, UNC and mixed-separator paths. The
  `_prettify` RegExps were left alone; the VM caches them.
- The app skips discovery under `runningUnderFlutterTest`, so widget tests
  no longer scan the CI host's fonts into the process-wide
  `pdfPlatformFonts`. `app/test/platform_fonts_test.dart` calls
  `loadPlatformFonts()` directly and checks the list's invariants (sorted,
  one entry per family, at most 300, bytes still load).
- The existing try/catch around the call (app and example) already turns
  any failure into "no platform fonts", as before.

### Measured

An AOT replica (`dart compile exe`) built mechanically from the real
source file, with `PdfPlatformFont` stubbed and an env override for the
directories, run as fresh processes, 12 interleaved rounds per side. The
"blocked" time is the call until it first yields plus the post-await
continuation; "gap" is the longest event-loop stall while the scan runs.

| tree | main blocked | branch blocked | branch gap | list ready |
|---|---|---|---|---|
| this Mac's fonts (384 entries, 243 families) | 2.26 ms | 0.16 ms | 0.09 ms | 2.26 -> 2.29 ms |
| synthetic Linux tree (3,600 entries, 300 kept) | 30.5 ms | 0.19 ms | 0.35 ms | 30.5 -> 27.9 ms |

Identity: the replica's dump (family, byte length and hash of the file each
entry loads) is byte-identical between main and the branch on both trees,
including 40 families that differ only in case (sort ties) inside the
capped 300. On macOS the saving is well under a frame; it matters on Linux
or Android installs with large font sets. Web is unaffected (stub).
