# Migrating to dart-pdf 8.0.0

The established packages release together at 8.0.0. The Flutter requirement
remains `>=3.47.0`; the Material migration in 7.0.0 still applies.

## Custom render workers

The annotation visibility filter now travels through the public worker API.
Custom implementations and overrides must accept this optional named parameter:

```dart
Set<String> hiddenAnnotationSubtypes = const {},
```

Add it to these `PdfRenderWorker` methods when implementing or overriding them:

- `record`
- `binStrips`
- `recordStripDetail`
- `buildRegionIndex`

Also add it to `PdfPageSurfaceSession.render` in custom page surface sessions.
Forward the set to the wrapped worker or rendering operation. Exclude the named
annotation subtypes from rendering, and include the filter in cache keys so
changing visibility cannot reuse a raster or transcript with the old selection.
The filter changes display and on-page hit testing; it does not remove annotations
from the document. Existing callers can omit it and retain the previous behavior.

The built-in workers and page surface sessions already implement the parameter.
Applications using those implementations need only update their dependencies.

## Dependency versions

Use 8.0.0 for `pdf_cos`, `pdf_test_fixtures`, `pdf_document`, `pdf_graphics`,
`dart_pdf_editor`, `dart_pdf_editor_assets`, `pdf_ocr_vlm` and
`pdf_ocr_ondevice`. Their dependencies now require the 8.0.0 suite. The
independently versioned companions are `dart_pdf_cli` 0.5.0,
`dart_pdf_printing` 0.5.0 and `dart_pdf_editor_flutter_gpu` 0.7.0.
