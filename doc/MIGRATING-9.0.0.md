# Migrating to dart-pdf 9.0.0

The established packages release together at 9.0.0. The Flutter requirement
remains `>=3.47.0`; the Material migration in 7.0.0 still applies.

## Custom render workers

`PdfRenderWorker.record` takes a new optional named parameter that lets the
caller hold a worker reply before it is decoded on the calling isolate:

```dart
PdfRecordDecodeGate? decodeGate,
```

`PdfRecordDecodeGate` is `Future<bool> Function(int commandCount)`. Custom
implementations and overrides of `record` must accept it. A worker that decodes
a serialized reply should call the gate with the reply's top-level command count
(`serializedCommandCount` from `pdf_graphics`) after the reply arrives and
before `deserializeCommands`, decode only once the future completes, and return
null without decoding when it completes false. A wrapper should forward it to
the wrapped worker. A backend with nothing to decode can ignore it. Existing
callers can omit it and keep the previous behaviour.

The built-in workers already implement the parameter. Applications using them
need only update their dependencies.

## Dependency versions

Use 9.0.0 for `pdf_cos`, `pdf_test_fixtures`, `pdf_document`, `pdf_graphics`,
`dart_pdf_editor`, `dart_pdf_editor_assets`, `pdf_ocr_vlm` and
`pdf_ocr_ondevice`. Their dependencies now require the 9.0.0 suite. The
independently versioned companions are `dart_pdf_cli` 0.6.0,
`dart_pdf_printing` 0.6.0 and `dart_pdf_editor_flutter_gpu` 0.8.0.
