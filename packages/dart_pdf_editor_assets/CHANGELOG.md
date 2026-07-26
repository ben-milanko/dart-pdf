# Changelog

## 3.1.1

- Lockstep patch release to align the optional bundled assets with
  `dart_pdf_editor` 3.1.1.

## 3.1.0

- The bundled web render worker is now generated at build time by
  `dart_pdf_editor`'s `build_web_worker` tool instead of being committed as a
  prebuilt file, so the asset always matches the editor sources (#582). The
  worker gained the streaming-partial-record and off-thread text-extraction
  protocols (see `dart_pdf_editor` 3.1.0) (#564, #396).
- The bundled editor fonts defer off app cold start: they register their byte
  loaders without reading font data until first use (#569).

## 3.0.0

- Initial release. Holds the optional `dart_pdf_editor` bundled assets - the six
  editor fonts and the prebuilt web render worker - split out of
  `dart_pdf_editor` so viewer-only apps do not bundle them. Call
  `registerBundledEditorAssets()` at startup to restore the full-featured
  editor defaults.
