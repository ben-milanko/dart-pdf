# Migrating to 6.0.0

The eight established packages move together to 6.0.0. The companion releases
are `dart_pdf_cli` 0.3.0, `dart_pdf_printing` 0.3.0 and
`dart_pdf_editor_flutter_gpu` 0.5.0. Update hosted dependency constraints together.

## Submit controls

`PdfDialogSubmit.child` now has type `Widget`, allowing a submit action from
any widget host. Existing calls to the original constructor still compile,
but code reading `child.onPressed` or other `ButtonStyleButton` members must
keep its own button reference or check/cast the widget type.

Prefer `PdfDialogSubmit.action(onSubmit: save, child: control)` for new code.

## Custom workers

`PdfRenderWorker` adds `void trimMemory()`. Classes extending it inherit a
no-op implementation. Classes implementing it must supply this method;
release reconstructible decode caches when possible, or use a no-op when
the worker owns none. No render-command wire-format change is required.

## Deprecated compatibility APIs

`PdfEditingPreferences.themeMode`, the original `PdfDialogSubmit` constructor
and `pdfSearchInputBorder` remain supported in 6.0.0. Their removal is deferred
to 7.0.0. Prefer `themePreference`, `PdfDialogSubmit.action` and
`pdfSearchFieldBorderRadius`, respectively.

The editor and asset companion now declare their actual Flutter floor, 3.44.0;
5.0.0 already used APIs introduced there. Printing requires Flutter 3.47.0 and
the experimental GPU companion also requires Flutter 3.44.0.
