# macOS "does not have permission to open" via Finder

Opening a file with the app from Finder ("Open With" / double-click /
drag onto the dock icon) could fail before the app ever saw the file, with
the system dialog:

> The application "DartPDF" does not have permission to open "CH458 Leeor Loop".

## Root cause

DartPDF's macOS runner is sandboxed (`com.apple.security.app-sandbox`).
For a sandboxed app, the entitlement `files.user-selected.read-write` only
covers files chosen through the app's own open/save panels (Powerbox). A
file the app is *launched to open by Finder* is instead granted an implicit
security-scoped sandbox extension by LaunchServices - **but only when the
file's UTI matches one of the app's declared `CFBundleDocumentTypes`.**

The app declared exactly one document type, `com.adobe.pdf`. That works for
a file whose type resolves to the PDF UTI (normally via a `.pdf`
extension). It does **not** cover a PDF delivered without a `.pdf`
extension or with an unrecognised dynamic UTI - common for files exported
from document-management / engineering systems (the reporting file,
"CH458 Leeor Loop", is a signalling drawing). Such a file resolves to
`public.data` (or a `dyn.*` UTI), which the app didn't declare, so
LaunchServices refused to issue the grant and Finder showed the
permission error. Nothing in the Swift runner (`AppDelegate.application(_:
open:)` → `deliver` → `payload`) is reached in that case.

## Fix

`app/macos/Runner/Info.plist`: add a second `CFBundleDocumentTypes` entry
declaring the generic base types `public.data` + `public.content` with
`CFBundleTypeRole` `Viewer` and, crucially, `LSHandlerRank` `None`.

`LSHandlerRank None` means the app is never advertised as a handler and
never becomes the default for arbitrary files - so this does **not** put
DartPDF in every file's "Open With" list. It only tells LaunchServices
that the app *can* be assigned to any file, which is enough for the sandbox
to issue the security-scoped grant when the user explicitly force-opens a
file with DartPDF. The existing `com.adobe.pdf` / `Alternate` entry is
unchanged, so genuine `.pdf` files keep offering DartPDF as an alternate
handler with the PDF document icon.

Scope: macOS only (the reported failure is Finder-specific). The
`packages/dart_pdf_editor/example` runner declares no document types, so it
is unaffected. The runner's file-read path already degrades gracefully -
`payload(for:)` still returns `path`/`bookmark` when byte reading fails -
so the Dart `IncomingFileService` fallback is unchanged.
