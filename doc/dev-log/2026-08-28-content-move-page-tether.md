# Content moves are tethered to their page

A drag toward a neighbouring page lost the drawing. `moveSelectedElement`
shifted the element by the full pointer delta in page points, so a drag
aimed at the page below committed it *below* the crop box: the renderer's
page clip hid it and the next page's tile covered it ("it disappears
behind the page"). Aimed at the page above, it committed past the top
edge, and since hit-testing an element needs its bounds under the pointer
there was nothing left to pick up ("I can no longer drag them").

It never came back. That is the part that matters: an annotation off the
paper is still reachable - `PdfEditingReach` routes presses on the
selection back into the page at its nearest inside point - but that works
on the *annotation* selection, and a content element has no equivalent.
Off the page it is invisible and unselectable, i.e. gone, recoverable only
by undo. The document was always correct throughout, which is why this
never showed up in the document- or renderer-level checks: the bytes said
the run had moved exactly as asked.

The repo already had the right instrument for this hazard.
`PdfEditingController._tetherShift` / `pageTether` exists so the point-less
paste cascade cannot march copies out of sight, and its doc comment states
the rule this case needs: annotation geometry is free to run past the edge
(that is what the page clip is for), and the tether belongs where losing
the thing is the alternative. So `moveSelectedElement` now tethers: a drag
toward a neighbour parks the element at this page's edge with a strip
still on the paper. `_tetherShift` keeps `min(pageTether, interval, page)`,
so a run shorter than 24pt - most lines of body text - stays wholly on the
page rather than half off it. An already-hanging element is not yanked
back (the helper leaves tethered intervals alone), and a move the tether
reduces to nothing is refused rather than burning a revision.

One follow-on: the drop afterimage was drawn at the raw pointer delta.
With the tether that would paint the element off the paper until the new
raster landed under it and snapped it back, so `_endGesture` now hands
`_holdElementAfterimage` the delta the commit actually applied
(`_selectedElementRestRect` after the move minus before), not the delta
the pointer travelled.

This makes cross-page dragging *safe*, not *supported*. Content does not
move between pages - that would mean rewriting another page's content
stream, and the element ids, resources and text state all belong to the
page they are on. Relocating content across pages is its own feature.

Worth recording about the hunt, because it cost a lot: the symptom was
reported as "after dropping, the content disappears", and every layer was
verified correct - the document across 7 real corpus PDFs, the recorded
`PdfRenderCommand` buffers before and after a move, the overlay's
afterimage lifecycle on the VM *and* in real Chromium, with the render
worker off and on, and the whole app driven end to end in a browser. All
of it passed, because all of it dragged *within* a page. The bug only
existed on the path nothing was aiming at. The reproduction arrived with
the detail "dragging them to a page below".

Also fixed on the way: `packages/dart_pdf_editor/test/flutter_test_config.dart`
registered the bundled DejaVu fallback through `dart:io`, so
`flutter test --platform chrome` could not load a single test file in this
package - `File.existsSync` throws `Unsupported operation: _Namespace` on
web before any test body runs. Guarded with `kIsWeb`. That is what made
the web half of the stack testable at all, and it is worth knowing that
the suite also forces `debugAutoRenderWorkerEnabled`,
`directPicturePresentation` and `prioritizeBoundedFinalPicture` off, so no
editor test exercises those paths unless it opts back in.

And a build trap: a plain `flutter build web` ships the *placeholder*
render worker and silently falls back to main-thread rendering, logging
`web render worker not built (issue #582)`. Only `app/tool/build_web.sh`
produces a real one. Any web investigation that does not use that script
is testing a different renderer than production.
