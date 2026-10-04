# Select mode: links follow, app page widgets stay live; demo opens in Select

Follow-up to 2026-10-03-select-mode-default.md. Making Select the default
showed that two reader behaviours died in Select mode. In Select mode the
editing overlay (`EditingPageOverlay`, opaque) covers every page, so the
viewer's own `_onTapUp` never runs and the host's page widgets never get a
pointer.

- **Links.** The overlay's select-mode tap only selected annotations, and
  link annotations aren't selectable. `PdfEditingInteractionHost.activateLinkAt`
  now lets the overlay hand a plain click (no Shift/⌘) back to the viewer when
  nothing selectable is under it. `PdfViewer._activateLinkAtGlobal` runs the
  same `_annotationHitAt(actionsOnly: true)` + `_activate` path as the reader
  and fires `onAnnotationTap`.
- **Host page widgets (`pageOverlayBuilder`).** They were stacked under the
  editing layer so an armed tool wins their gestures. In Select mode they now
  stack above it, as the form-field tap layer already does. The two layers
  are keyed (`pdf-host-page-overlays`, `pdf-editing-layer`) so the reorder on a
  tool switch keeps the host widgets' state. The host builder runs once per
  layout, not on every editing notification.
- **Example demo** (`example/lib/main.dart` `_DocumentTab.document`) now arms
  `PdfEditTool.select` like the app's tabs. The perf harnesses
  (`patrol_test/perf_e2e_test.dart`, `native_perf_e2e_test.dart`) build their
  own controllers, so their journeys are unchanged.

Tests: `test/select_mode_page_interaction_test.dart`. The example's
`demo_test.dart` link and overlay journeys also cover it.
