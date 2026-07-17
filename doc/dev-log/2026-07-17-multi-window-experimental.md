# Experimental multi-window support for the app (#—)

Adds a "New window" affordance to the DartPDF app that opens a second
top-level OS window, built on Flutter's **experimental** desktop windowing
API (`RegularWindowController` / `WindowManager` / `runWidget`, Flutter
3.44.x). This is an opt-in experiment gated behind the windowing feature
flag — released builds are untouched and stay single-window.

## Why the flag gate

The windowing API lives in `package:flutter/src/widgets/_window.dart`,
whose own header says: *"Do not import this file in production applications
… Flutter will make breaking changes to this API, even in patch versions."*
Every symbol is `@internal` and throws `UnsupportedError` unless the
`windowing` feature flag is on. So the whole feature is quarantined and
degrades to today's behaviour when the flag is off. See
<https://github.com/flutter/flutter/issues/30701>.

## Turning it on

The flag is a compile-time dart-define the flutter tool sets from config:

```
fvm flutter config --enable-windowing        # once; persists
fvm flutter run -d macos                       # or windows / linux
```

or inline for a single run:

```
fvm flutter run -d macos \
  --dart-define=FLUTTER_ENABLED_FEATURE_FLAGS=windowing
```

`isWindowingEnabled` (in `foundation/_features.dart`) reads
`FLUTTER_ENABLED_FEATURE_FLAGS`.

## Shape of the change

- **`app/lib/window_support.dart`** (new) — the *only* file that touches the
  internal windowing API (file-level `ignore_for_file:
  invalid_use_of_internal_member, implementation_imports`). Exposes a small,
  safe surface so nothing else imports `src/`:
  - `multiWindowSupported` → the flag, read safely.
  - `runDartPdfApp(root)` — bootstrap. Flag on: `runWidget(WindowManager(child:
    RegularWindow(controller, child: root)))`; flag off (or platform declines
    with `UnsupportedError`): the classic `runApp(root)`. The widget tree
    below the window is identical either way.
  - `openRegularWindow(context, builder, title)` — registers a new
    `RegularWindowController` + `WindowEntry` on the shared `WindowRegistry`
    from `context`; auto-unregisters on destroy. No-op when unsupported.
- **`app/lib/app.dart`** — `DartPdfEditorApp` now owns the shared
  `PdfEditingPreferences` and renders a reusable `_DartPdfWindow` (themed
  `MaterialApp` + `EditorScreen`). "New window" opens another `_DartPdfWindow`
  bound to the *same* prefs, so theme/tool styles stay in lock-step across
  windows. Only wired when `multiWindowSupported`.
- **`app/lib/main.dart`** — `main()` routes through `runDartPdfApp` instead of
  `runApp`.
- **`app/lib/editor_screen.dart`** — new optional
  `onNewWindow(BuildContext)` (null hides the affordance) and
  `persistSession` (default true). Adds a "New window" app-menu item
  (`menu-new-window`, key ⇧⌘/Ctrl+Shift+N — plain ⌘N was already "New
  document") wired to `_newWindow()` → `widget.onNewWindow?.call(context)`.

## Gotchas / design notes

- **`WindowManager` wraps the primary `RegularWindow`**, not the reverse — it
  provides the `WindowRegistry` (an ancestor of the whole window subtree) and
  renders secondary windows as sibling sub-views via `ViewAnchor`/
  `ViewCollection`. `WindowRegistry.maybeOf(context)` from any window's
  `EditorScreen` finds it, so a new window can be opened from any window.
- **Callback carries the context, not a captured one.** `onNewWindow` is
  invoked with the requesting `EditorScreen`'s own live context at click time,
  so the registry lookup is always valid.
- **Session ownership.** Each `EditorScreen` owns a `SessionStore`. Letting
  every window restore + persist would double-open tabs and race the shared
  `shared_preferences` key. Fix: only the primary window keeps
  `persistSession: true`; secondary windows pass `false`, so they start empty
  and never write the store. (`_persistSession` already no-ops until
  `_restoreSession` sets `_sessionLoaded`, which secondary windows skip; the
  explicit `!widget.persistSession` guard makes the intent clear.)
- **Known rough edges** (acceptable for an experiment, not yet solved): every
  window's `EditorScreen` starts its own `IncomingFileService`, so an OS
  file-open / share can be delivered to *all* open windows; each also
  registers a `WidgetsBindingObserver`, so `didRequestAppExit`'s unsaved-guard
  runs per window. Closing the primary window doesn't force-quit the app while
  secondary windows remain (no `exit(0)` override — kept out to stay
  `dart:io`-free and web-safe).

## Tests

`app/test/multi_window_test.dart` — the flag is off in the harness (no real
windows), so the tests pin the app-side wiring via the injectable seams:
the `menu-new-window` item appears iff `onNewWindow` is provided and routes
to it with a live context; ⇧⌘N and Ctrl+Shift+N both fire it (document open +
viewer focused, the same recipe as the Save-shortcut tests); and a
`persistSession: false` screen leaves a seeded stored session untouched after
opening a document. Full app suite stays green (171 → 176 tests).
