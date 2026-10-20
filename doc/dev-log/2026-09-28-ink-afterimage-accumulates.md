# Back-to-back ink commits no longer hide each other

Report (iPad, Apple Pencil, a filled form at 188%): writing "2", then
"3", briefly showed "23" and then only "3". Every new ink annotation
hid the previous one on screen, while the annotation list still showed
all of them.

## Why

While editing, annotations are not in the page raster. They come from
`_AnnotationAppearanceLayer` (pdf_viewer.dart), which re-renders an
annotation's appearance through a paced pass (`paceUiWork`, quiet class,
since #950). Until the page is current again (`rasterCurrent` =
`_rastered && _annotationLayerCurrent && same COS`), the editing overlay
paints the just-committed strokes as an afterimage
(`committedInkOn`).

That afterimage held **only the latest commit**. Ink auto-commits 800 ms
after the last stroke, so quick handwriting commits the next glyph before
the page has drawn the previous one. The new revision restarts the
layer's pass (a new page wrapper bumps its generation), and the previous
glyph was in neither the layer nor the afterimage. It stayed invisible
until the page caught up, or for good if the render never landed.

## Fix

- `PdfEditingController` keeps a run of committed inks
  (`_committedInks`). A commit whose previous revision was the last ink
  commit extends the run. Any other revision in between (undo, another
  edit) starts a new run. `committedInksOn(page)` returns the run
  (oldest first), and `committedInkOn` stays as the newest, for existing
  callers.
- `_PdfViewerPageState` records the editing revision its page belongs to
  when the page arrives (`_pageRevision`). Once the page's raster and
  layer are both current, it calls
  `retireCommittedInk(page, throughRevision:)`, so the overlay stops
  carrying strokes the page now draws itself. The revision is read on
  arrival, not when the page becomes ready: a render that finishes between
  the next commit and the rebuild delivering its page must not retire
  the newer ink.
- The overlay paints every entry, and the viewer mounts the overlay
  whenever `committedInksOn` is non-empty.

## Tests

- `editing_polish_test.dart` "back-to-back ink commits all stay painted
  until the page catches up": gates the appearance renderer
  (`debugAnnotationAppearancePicturesRendererOverride`), draws two
  strokes, and checks the pixels of both, then releases the gate and
  checks that the afterimages retired and the layer draws both. Before
  the fix, the first stroke's pixels were gone after the second commit.
- `editing_test.dart` "back-to-back ink commits accumulate their
  afterimages": run growth, per-page retirement, and an undo resetting
  the run.

## Not found

Why the device's layer or raster was slow enough to expose this is
unconfirmed. The COS in-place fold, the native worker's in-place
revisions (#957/#981), and a corpus sweep of three consecutive inks all
checked out. A finger-pan cancel in pencil mode releases the render hold
correctly. If a page still lags behind edits noticeably, the next
suspects are the paced layer pass being restarted before it publishes,
and a held-class render not being granted.
