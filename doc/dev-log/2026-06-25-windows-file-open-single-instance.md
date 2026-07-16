# Windows file-open + single-instance runner

After setting DartPDF as the default Windows app for `.pdf`, two bugs showed
up:

1. Double-clicking a PDF opened the DartPDF window but **not the document**.
2. Opening a second PDF spawned a **new process/window** instead of a new tab
   in the running app.

## Root cause

The Dart side was already complete. `IncomingFileService`
(`app/lib/incoming_file.dart`) talks to one `MethodChannel`
(`dev.milanko.dartpdf/incoming`): `getInitialFile` for the cold-start file,
`openFile` for warm-start opens. `EditorScreen` listens to both and also opens
`.pdf` paths from the command-line launch args (`_openLaunchArgs`). macOS, iOS,
and Android all implement the native half of that channel.

**Windows (and Linux) shipped the stock Flutter runner** - no channel handler
and no single-instance logic:

- Warm-start (issue 2): nothing forwarded a later "open with" to the running
  instance, and nothing made the app single-instance, so every open launched a
  fresh process.
- Cold-start (issue 1): delivery relied solely on
  `set_dart_entrypoint_arguments`, which is the only path and is brittle in the
  field. There was no `getInitialFile` fallback like the other platforms have.

## Fix (Windows runner - `app/windows/runner/`)

- **`main.cpp`** - named-mutex single instance
  (`dev.milanko.dartpdf.SingleInstance`). A second launch finds the running
  window by class name (`FindWindowW`, retried ~5s to cover the
  mutex-owned-but-window-not-yet-created race), forwards the first `.pdf`
  argument via `WM_COPYDATA`, surfaces that window, and exits. The first
  instance still gets the launch file two ways: as a dart entrypoint arg (so
  `_hasExplicitLaunchTarget` keeps suppressing session restore) **and** through
  the channel below.
- **`flutter_window.{h,cpp}`** - creates the `dev.milanko.dartpdf/incoming`
  `MethodChannel` once the engine exists. `getInitialFile` drains the
  constructor-supplied launch file exactly once; the `WM_COPYDATA` case decodes
  the forwarded path (guarded by a magic `dwData = 'DPDF'`), invokes `openFile`,
  and brings the window to the foreground. Payload shape matches the other
  runners: `{name, path}`, UTF-8 via the existing `Utf8FromUtf16`.
- **`win32_window.cpp`** - renamed the window class from the generic
  `FLUTTER_RUNNER_WIN32_WINDOW` to `DARTPDF_WIN32_WINDOW` so `FindWindowW`
  locates *our* window and never another Flutter desktop app's. The class name
  is duplicated as `kMainWindowClassName` in `main.cpp`; keep them in sync.

## Fix (Dart - `app/lib/editor_screen.dart`)

`_openIncoming` now focuses an already-open tab with the same `originPath`
instead of opening a duplicate. The cold-start file can now arrive twice (launch
arg + `getInitialFile`); this dedupe makes that a no-op, and as a bonus a
repeated OS "open with" of an open document just surfaces its existing tab.
Drag-drop (`_openDropped`) is unaffected - it has its own path and still opens
duplicates on purpose.

Test: `app/test/tabs_menu_test.dart` - "re-opening the same file focuses its tab
instead of duplicating".

## Couldn't verify the native build here

No Windows/MSVC toolchain in this environment, so the C++ wasn't compiled. It
uses the stable Flutter Windows C++ client-wrapper API (same one plugins use:
`engine()->messenger()`, `MethodChannel<EncodableValue>`,
`StandardMethodCodec::GetInstance()`). The Dart change + new widget test pass
`fvm flutter test`. The Linux runner has the same gap but wasn't in scope
(`my_application.cc` is still `G_APPLICATION_NON_UNIQUE`); worth a follow-up if
Linux file associations matter.

OS registration of the association is still the installer's job (MSIX manifest
per `app/RELEASING.md`); this change only fixes the receive side.
