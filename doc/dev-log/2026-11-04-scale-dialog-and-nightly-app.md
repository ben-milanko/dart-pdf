# 2026-11-04 - screen-tall scale dialog, metric default, nightly as its own app

## Screen-tall "Set measurement scale" dialog

The scale dialog filled the whole window, with its ratio row floating in the
middle and two stray hairlines at the bottom. Cause: `PdfDropdown`'s option
box (`_PdfDropdownItemBox`, `design/material_host.dart`) wrapped each option
in an `Align` with no `heightFactor`. An unfactored `Align` grows to its
parent's max height, and a `Row`'s children get the dialog's max height as
their cross-axis bound, so each picker grew to about 860px. The "stray
lines" were the pickers' own underlines (`Positioned(bottom: 0)`). The fix
is `heightFactor: 1`. It is shared, so it also covers every other
`PdfDropdown` placed in a bounded-height row: the insert-pages dialog, the
table editor, the text-style prompt, stamp date/time, and the property
panels. Regression test: "the scale dialog fits its ratio row" in
`editing_measure_test.dart`, which fails at 384px without the fix.

## Metric default for a US-looking browser

`pdfDefaultMeasurementUnit`/`pdfDefaultPageUnit` already followed the device
locale's country, but on the web that is the browser language. Brave reports
`en-US` everywhere to resist fingerprinting, and many non-US systems use US
English, so an Australian user got `1 in = 1 ft`. A device locale that names
an imperial country (US/LR/MM) is now only believed when
`DateTime.now().timeZoneOffset` falls in one of that country's zones (US:
UTC-10 Hawaii to UTC-4 Eastern daylight; LR: 0; MM: +6:30). An explicit
`Locale` argument is not second-guessed. The `debugPdfTimeZoneOffset` seam
(`models/measurement_scale.dart`) pins the clock in tests. The test VM is
`en_US` at UTC, so `editing_measure_test.dart` pins New York for the whole
file. Known trade-off: an American travelling abroad gets metric until they
set a scale, which is then persisted.

## macOS nightly installs as "DartPDF Nightly.app"

This reverses `2026-10-24-nightly-name-in-finder.md`. Keeping the stable
file name (`DartPDF.app`) with a localized display name meant Finder's
replace prompt offered to overwrite "DartPDF", and "Keep Both" produced
`DartPDF 2.app`, shown as "DartPDF Nightly 2". The nightly is now a separate
app, like Chrome Canary or VS Code Insiders: nightly-desktop.yml renames the
bundle to `DartPDF Nightly.app` and sets `CFBundleIdentifier =
dev.milanko.dartpdf.nightly` and plain `CFBundleName`/`CFBundleDisplayName`.
The `LSHasLocalizedDisplayName` trick is dropped, and the edits happen before
the ad-hoc re-sign. The 2026-10-24 note rejected a rename because two bundles
would share one id; a distinct id removes that objection. Later steps use
`$MACOS_APP`. `CFBundleExecutable` stays `DartPDF`.

Consequences: the nightly's sandbox container, and so its settings and
recents, is separate from stable's. A nightly no longer replaces a stable
install, and the CLI sidecar lives at `/Applications/DartPDF Nightly.app/...`
(added to `packages/dart_pdf_cli/README.md`). An existing `DartPDF.app` that
came from an older nightly stays where it is; delete it by hand if it is not
wanted.
