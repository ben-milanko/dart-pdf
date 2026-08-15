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
- macOS, Windows, and Linux always use an engine-owned bootstrap. The
  engine starts without a template Flutter view; Dart creates the primary and
  every secondary native window.
- Dart enables Flutter's matching internal feature before
  `WidgetsFlutterBinding` initializes its windowing owner. Native and Dart code
  therefore cannot enter different halves of the experimental path.

Run a desktop build normally:

```sh
fvm flutter run -d macos
```

Substitute `windows` or `linux` on those hosts. No global Flutter configuration
or process environment flag is required; windowing is also the default for
release and Store builds.

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

On macOS, `applicationShouldTerminateAfterLastWindowClosed` must return false.
The NIB services window is hidden before Dart constructs its primary window;
allowing AppKit to own last-window shutdown creates a race in that gap.

## Verification and limits

- The default macOS debug build compiles on Flutter 3.47 and created two real
  AppKit windows; closing the original
  left the secondary usable, and closing the final window terminated the
  headless process. A digital-signature dialog also opens as a native dialog
  window without trying to retrofit multi-view onto an attached engine.
- `app/test/multi_window_test.dart` covers hidden production affordances,
  menu/shortcut routing, lossless handoff, failed-creation safety, secondary
  session isolation, and cancel/confirm close behavior.
- Windows and Linux CI builds compile their matching engine-owned bootstraps;
  the Linux release smoke also launches successfully under Xvfb.

Flutter still marks this entire API `@internal` and explicitly permits breaking
changes in patch releases. Keep the Flutter SDK pinned and exercise all three
desktop builds before upgrading it; when Flutter publishes a supported desktop
windowing API, replace only `window_support.dart` and simplify the runners.
