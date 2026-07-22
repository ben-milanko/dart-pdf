## 2.1.0

- Initial release. Holds the optional `dart_pdf_editor` bundled assets - the six
  editor fonts and the prebuilt web render worker - split out of
  `dart_pdf_editor` so viewer-only apps do not bundle them. Call
  `registerBundledEditorAssets()` at startup to restore the full-featured
  editor defaults.
