# Desktop multi-window on Flutter 3.47

PR #354 proved the Dart-side tab tear-off idea, but it targeted an older shape
of Flutter's experimental windowing API and left the desktop runners using an
implicit `FlutterViewController`/`FlView`. Flutter must enable multiview before
the first view is attached, so that runner shape cannot create a second window
reliably.

This rebuild targets the API shipped in the repo's pinned Flutter 3.47 SDK:

- `RegularWindowController(size:)`, `RegularWindow`, and the multi-view host
  are quarantined in `app/lib/window_support.dart`. Nothing else imports
  Flutter's internal windowing library.
- macOS, Windows, and Linux have an engine-owned experimental bootstrap. The
  engine starts without a template Flutter view; Dart creates the primary and
  every secondary native window.
- Normal launches still use the existing single-window runners. Multi-window
  requires both Flutter's tool flag and DartPDF's matching runner flag, so a
  Store/release build cannot enter half of the experimental path by accident.

Run a desktop debug build with:

```sh
DARTPDF_EXPERIMENTAL_WINDOWING=1 \
FLUTTER_WINDOWING=true \
fvm flutter run -d macos
```

Substitute `windows` or `linux` on those hosts. Both variables are required:
`FLUTTER_WINDOWING` compiles/enables Flutter's framework feature, while
`DARTPDF_EXPERIMENTAL_WINDOWING` selects the compatible native runner at
process start. Omitting either leaves DartPDF in its normal single-window mode.

## App ownership and handoff

Each native window owns a separate `MaterialApp`, `EditorScreen`, editor
controller, viewer controller, and undo stack. Only the primary window owns
process-wide session restoration, OS file-open delivery, update checks, and
the application-exit observer. Secondary windows share preferences and OIDC
configuration but cannot steal the one method-channel handler or overwrite the
single persisted session.

Moving a tab copies its current bytes into a `DocumentHandoff` together with
the exact `savedLength` and its path/bookmark/token/cache origin. That preserves
dirty state and the future Save target. The source tab is removed only after
the native destination window has registered successfully; a platform failure
therefore leaves the document untouched in its original window.

Window close is also per-window. The native controller asks the window's
`DartPdfWindowCloseCoordinator`, which gives that `EditorScreen` a chance to
cancel or confirm discarding its own dirty tabs before destruction. The last
Dart-owned window calls `ServicesBinding.exitApplication(required)` to end the
headless engine cleanly. `SystemNavigator.pop` is not handled by Flutter's
Windows embedder, while `System.exitApplication` is implemented on all three
desktop platforms.

The window registry itself lives above every `View` and renders an equal list
of `RegularWindow`s into a root `ViewCollection`. Flutter's stock
`WindowManager` assumes it is nested inside an existing view; putting it in the
primary would make all secondary view widgets children of the primary, so
closing that first window could tear down their host tree. The root registry
lets the primary close while another window stays usable.

On macOS, `applicationShouldTerminateAfterLastWindowClosed` must return false
in this mode. The NIB services window is hidden before Dart constructs its
primary window; allowing AppKit to own last-window shutdown creates a race in
that gap. Normal launches retain the old `true` behavior.

## Verification and limits

- The normal and `FLUTTER_WINDOWING=true` macOS debug builds compile on Flutter
  3.47. The opt-in build created two real AppKit windows; closing the original
  left the secondary usable, and closing the final window terminated the
  headless process.
- `app/test/multi_window_test.dart` covers hidden production affordances,
  menu/shortcut routing, lossless handoff, failed-creation safety, secondary
  session isolation, and cancel/confirm close behavior.
- Windows and Linux runners mirror Flutter's engine-owned bootstrap but need a
  final compile/run on their native hosts; the macOS machine cannot link those
  runners.

Flutter still marks this entire API `@internal` and explicitly permits breaking
changes in patch releases. Keep it opt-in and out of Store builds until Flutter
publishes a supported desktop windowing API; when that happens, replace only
`window_support.dart` and simplify the runner gates.
