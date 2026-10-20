# macOS: file drag-and-drop under the multi-window runner

**Symptom:** dropping a PDF from Finder onto a DartPDF window on macOS did
nothing - no drag highlight, no open/insert.

**Cause:** the macOS runner runs Flutter's experimental multi-window
bootstrap (`DartPdfWindowingBootstrap.isEnabled`): plugins register on a
headless `FlutterEngine` that has no implicit view, and Dart creates every
window. `desktop_drop`'s macOS plugin installs its drop view from
`registrar.view` and returns early when that is nil, so it never registered
a drop destination (or even its method channel). The Windows runner hit the
same wall earlier and got a per-HWND bridge.

**Fix:** `app/macos/Runner/WindowDropService.swift` speaks the Windows
bridge's channel protocol (`dev.milanko.dartpdf/windows_drop`:
`register`/`unregister` by window handle, `entered`/`updated`/`exited`/
`performOperation` events carrying `handle`, physical top-left `x`/`y` and
`paths`). The handle is the NSWindow address Flutter's multi-window
controllers expose (the same one `window_geometry`'s `locateDrop` uses);
registering lays a `desktop_drop`-style overlay view over that window's
Flutter view. File URLs, legacy filename arrays and file promises are all
accepted, like `desktop_drop`. The Dart widget is now
`NativeWindowDropTarget` (`native_window_drop_target.dart`, renamed from
`WindowsDropTarget`), used by `EditorScreen._buildFileDropTarget` on
Windows and macOS whenever a native window handle is known; the plain
`DropTarget` remains for Linux and web.

Not verifiable in the Linux cloud container (no Xcode) - confirm on a Mac:
drop onto the body (open/insert prompt), onto the thumbnail strip
(positioned insert), and into a second window (only that window reacts).
