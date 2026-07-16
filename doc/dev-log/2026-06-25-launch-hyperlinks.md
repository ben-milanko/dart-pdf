# Launching hyperlinks from the viewer

Tapping a `/Link` whose action is `/URI` used to do nothing on its own -
the viewer surfaced every URI to `PdfViewer.onAction` and left opening it
to the host. So a plain web link in a PDF was inert unless the embedding
app wired `url_launcher` itself. This adds built-in launching.

## What changed

`PdfViewer` now follows web hyperlinks itself.

- New `PdfUrlLauncher` typedef (`Future<bool> Function(Uri)`) and
  `PdfViewer.onLaunchUrl` (threaded through `PdfReader` too).
- `_activate` routes `PdfUriAction` into `_openUri`, which calls
  `onLaunchUrl ?? _launchExternalUrl`. The default opens the well-known
  external schemes - `http`, `https`, `mailto`, `tel`, `sms` - through
  `url_launcher`'s `launchUrl(..., LaunchMode.externalApplication)` and
  returns `false` for anything else.
- `url_launcher: ^6.3.0` is now a direct dependency of `dart_pdf_editor`
  (it was already used by `app/` and the example). It is web-safe and
  pulls in no `dart:io`, so the layering rules hold - only the top
  `dart_pdf_editor` layer touches it.

## The onAction fallback is preserved deliberately

Custom schemes are the established convention for "a PDF drives its host
app" (`app://counter/increment` in the demo), so they must still reach
`onAction`. The contract is now:

- `onLaunchUrl` returns `true` → the link is consumed, `onAction` never
  fires for it.
- returns `false`, throws, or the URI won't parse → the viewer falls
  through to `onAction`, exactly as before.

The default launcher's scheme allow-list is what makes `app://…` fall
through untouched, which is why the existing `buildAnnotatedPdf`
(`app://invoice/42`) test still expects `onAction`. A host that wants to
open custom schemes, confirm before leaving, or route links into the app
supplies its own `onLaunchUrl`; it sees every parseable URI, custom
scheme included.

`_openUri` wraps the launcher in try/catch so a platform with no
`url_launcher` binding (or a launcher that throws) degrades to the
`onAction` fallback instead of swallowing the tap.

## Testing seam

`url_launcher` can't reach a real platform in widget tests. Two seams:

- The `onLaunchUrl` override is plain Dart - most tests pass a closure
  that records the `Uri` (and return true/false/throw) and assert against
  `onAction`. No platform mock needed.
- For the *default* path (proving `http` actually reaches
  `url_launcher`), `pdf_viewer_test.dart` swaps in a
  `_FakeUrlLauncher extends UrlLauncherPlatform with
  MockPlatformInterfaceMixin` via `UrlLauncherPlatform.instance` and taps
  an `https` link in a one-page `buildUriLinkPdf` fixture. `plugin_-
  platform_interface` + `url_launcher_platform_interface` are dev-only
  deps for that fake.

## Demo

The example's page 1 gains a real `https://pub.dev/...` text link beneath
the table of contents - the viewer opens it with zero host wiring, in
contrast to the `app://` buttons above it that the demo dispatches through
`onAction`. `demo_document_test` now expects 9 page-1 links (was 8).
