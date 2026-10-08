# Hide annotations by subtype (display-only "Hide links")

A host (Trax) wanted a per-user "Hide links" switch. Removing the `/Link`
annotations through `PdfEditingController.apply` recorded an undo step (so
Undo brought the links back while the app said they were hidden), and
`applyRemoteChange` can't redraw a link because `PdfAnnotationSnapshot`
excludes `/Link`. What was needed is a sibling of `showAnnotations`: a switch
that changes only what is drawn.

## Public API

- `PdfEditingPreferences.hiddenAnnotationSubtypes` (`Set<String>`, default
  empty, persisted as a string list under `hiddenAnnotationSubtypes`) plus the
  `showLinks` convenience over it.
- `PdfViewer.hiddenAnnotationSubtypes` (default `const {}`). `PdfEditorView`
  and `PdfReader` feed it from their preferences, like `showAnnotations`.
- Lower layers carry the same name: `PdfPageView`, `PdfPageRenderPlan`
  (part of its `==`/`hashCode`), `PdfPageRenderer.renderPicture`/
  `renderPictureRecorded`/`renderImage`, `PdfThumbnailSidebar`/
  `PdfThumbnailView`, `rasterizeThumbnail`, and every `PdfRenderWorker` page
  method (`record`, `binStrips`, `recordStripDetail`, `buildRegionIndex`,
  `PdfPageSurfaceSession.render`).
- `PdfInterpreter.drawAnnotations(page, skipSubtypes:)` in pdf_graphics. It
  sits beside `skip:`; an annotation either one matches is left out, so the
  editing overlay's lift/resize predicate still combines with the filter.

Adding the optional named parameter to the abstract `PdfRenderWorker` methods
means a custom worker subclass must add it to its overrides (every test fake
here gained one line).

## How it flows

- **Plan.** `PdfPageRenderPlan.hiddenAnnotationSubtypes` makes every
  plan-keyed cache (retained scenes, tile store, tile disk keys) distinct per
  setting with no extra work.
- **Workers.** A predicate can't cross an isolate, which is why the setting is
  a `Set<String>`. Internally the workers carry a `PdfAnnotationLayerSpec`
  (`annotation_display_filter.dart`): `draw` + hidden set, value equality, and
  `toWire`/`fromWire` (null = none, else the sorted names). It replaces the bare
  `bool annotations` in the native isolate's request/message slot 3, the
  suspended-record and bin-command caches, the web transcript cache and
  page-surface bitmap key. The web message keeps `annotations` as a bool and
  adds an optional `hiddenAnnotationSubtypes` string array.
  `PdfCachingRenderWorker`'s record key slot 2 is now `(bool, String)`, so a
  toggle can never be answered with the other setting's buffer.
- **Page view.** `PdfPageRenderIntent` carries the set; the session treats a
  change like a `showAnnotations` flip (invalidate + re-render), so in-flight
  worker results recorded under the old setting are rejected.
- **Viewer caches.** The viewer already clears its preview cache and re-keys
  the disk namespace (`_rasterKey`) when annotation visibility flips; the
  hidden set joins both. `PdfPageRasterSignature` also carries it, and the
  persistent full-raster/thumbnail/tile keys append `annots-<names>` only when
  something is hidden, so existing stores stay valid.
- **Edit mode.** While editing, page rasters are annotation-free and
  `_AnnotationAppearanceLayer` paints each appearance itself. It takes
  `hiddenSubtypes`, filters through `_paints`, and on a toggle drops the newly
  hidden pictures at once (`_dropStalePictures`) before re-rendering.
- **Interaction.** `_annotationHitAt` (every viewer tap/hover/cursor path for
  annotations, links included) skips hidden subtypes. The editing controller's
  on-page hit tests (`selectableAnnotationAt`, `lockedAnnotationAt`,
  `selectableWidgetAt`, `inkAnnotationAt`, `selectAnnotationsIn`) skip
  `preferences.hiddenAnnotationSubtypes` - the controller's own preferences,
  which are the shell's in `PdfEditorView`/`PdfReader`. A host driving a bare
  `PdfViewer` with its own controller should set both.

## Out of scope / unchanged

Printing (`vector_print.dart`), export, `controller.bytes`, the annotation
sidebar list, annotation search, and the snapshot tool's clipboard capture are
unchanged. `render_trace.dart`'s diagnostic capture still draws everything.

## Tests

`test/hidden_annotation_subtypes_test.dart`: interpreter skip, renderer
pixels (link gone, square kept, combined with `skipAnnotation`), plan
equality, a real worker + record cache across toggles, a `PdfPageView` toggle
re-recording through the worker with no stale scene, the edit-mode annotation
layer (mutation-checked), viewer link taps, the preference (notifies,
persists, revision/undo/redo/bytes untouched), and controller hit tests.
