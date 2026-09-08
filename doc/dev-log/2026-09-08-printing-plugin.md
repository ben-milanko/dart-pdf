# Optional printing plugin

`packages/dart_pdf_printing` packages the existing app print module as an
independently versioned Flutter plugin (0.1.0). `dart_pdf_editor` does not depend
on it. Apps opt in through their pubspec and call `printPdfWithPreview`,
`printPdfWithProgress`, or `printPdfBytes`. `PrintSettings`, the sheet composer,
and the standalone preview/progress widgets are public for custom host flows.

The DartPDF app now uses the package. Its runner-specific print registrations
and implementations have moved to the plugin, as have the print translations
and isolated print tests. File picking, committing pending edits, menu actions,
and host-specific error messages stay in the app. The public example shows a
small host without any DartPDF app imports.

Flutter registers five native backends on `dev.milanko.dart_pdf_printing`:
PDFKit on macOS, UIKit on iOS, ActivityAware PrintManager on Android, GDI/WIC on
Windows, and GTK/Cairo on Linux. Browser printing uses a conditional Dart
implementation. Desktop registration tolerates an engine with no implicit
view, and native job state belongs to the plugin instance. Dart rejects
concurrent jobs on one channel instead of allowing a second beginJob to
replace the active page buffers. Windows printer preferences are scoped to
the host executable. macOS sandbox hosts must add the printing entitlement;
the app already has it.

The plugin includes merged PR #899 (`dc14f28a`) and builds on current main.
Windows preview choices select a queue, color, duplex mode and tray, with
explicit advanced driver properties and asynchronous printer queries. Print
goes directly to the selected queue. The preferences model, new translations,
native backend and regression tests all moved into the plugin. Common options
keep their original SharedPreferences key (already scoped to the host app);
opaque driver settings use the plugin's host-specific registry namespace.
Both the app and `printPdfWithPreview` forward the destination and pair duplex
sides before expanding copies. Missing printers and incompatible paper sizes
remain errors rather than selecting a different queue or clipping output.

The progress helper owns its exact dialog route and removes it even when a
host dialog has opened above it. Browser load/print exceptions propagate to
the host, and the temporary frame/blob URL are cleaned up on failures.

Validation: package and app print tests, workspace analysis, ARB coverage and
regional spelling checks, pub publish dry-run, and native app builds for
macOS, Android and the iOS simulator. A separate web host compiles including
its Wasm dry run. `tool/test_print_plugin.sh` builds a fresh desktop host and
checks registration using invalid arguments (never sends a print job); the
macOS check passes locally, and the Windows/Linux/macOS matrix runs in CI.
After integrating #899: 95 plugin tests and 27 affected app tests pass, with
clean workspace analysis and localization checks. The Windows backend and
plugin adapter cross-compile as x64 C++17 with conversion warnings treated as
errors. The native registration test also checks the Windows printer-control
methods with invalid arguments, without opening a driver dialog.

Gotcha: reusing the Flutter plugin scaffold's own example let Xcode retain the
scaffold's placeholder plugin source path after changing the Dart dependency.
Generated registration looked correct and the build passed, but the channel
was still missing at runtime. The fresh-host script avoids the stale native
package cache and proves automatic registration independently of the app.

Publishing is prepared, not performed: the plugin is in the release script
and tag-triggered pub workflow. The first publication still needs the usual
pub.dev package ownership/OIDC setup. Physical-printer output was not tested.
