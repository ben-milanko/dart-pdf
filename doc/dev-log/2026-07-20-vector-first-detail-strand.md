# A failed deep-zoom detail render stranded the full-image refinement

## Symptom

On a deep-zoomed page (a dense CAD sheet at several hundred percent) the
document sometimes got stuck on its blurry, resolution-capped base raster and
would not sharpen at all. Opening the browser devtools (F12) reliably fixed it.

## Why F12 "fixed" it

The devtools panel docks beside the viewer body in a `Row`, so opening it
relays the viewer out narrower (see
`2026-07-18-devtools-and-cache-ceiling.md`). That width change trips
`_PdfPageViewState._noteLayoutWidth`, which posts a fresh `_render()` after the
frame. Any relayout would do it - F12 is just the convenient trigger. So the
page *could* render sharp; something was dropping the render that should have
happened when the zoom settled, and only an unrelated `_render()` recovered it.

## Root cause

`deferFullRenderUntilDetailPaint` (default on) has a cold deep-zoom page paint
its lightweight visible-region detail patch *before* it interprets the full
image record, so the sharp slice lands first and the heavy full decode does not
start under the main thread's detail work. `_renderNow` implements this by
awaiting a `paintReady` completer that `_paintVectorFirst` wires up:

```dart
final paintReady = Completer<bool>();
final detailFuture = _updateDetail(detailGeometry: ..., onPaint: () {
  if (!paintReady.isCompleted) paintReady.complete(true);
});
_progressiveDetailFuture = paintReady.future;
unawaited(detailFuture.then((ready) {                 // no onError!
  if (!paintReady.isCompleted) paintReady.complete(ready);
}));
```

`_updateDetail` can *throw* - a worker record that errors, a region raster that
fails, an OOM on web. The `.then` had **no `onError`**, so a thrown detail left
`paintReady` uncompleted forever. `_renderNow`'s `await progressiveDetail` then
hung, the full-image record behind it never ran, `_picture` stayed null, and the
page never sharpened until an external relayout kicked a new `_render` (which,
with `_progressiveDetailFuture` already cleared and a soft preview usually
present, skips the vector-first defer and interprets the full record directly -
exactly the F12 recovery).

The failure only bites when `onPaint` had not already fired, i.e. the local
vector rasterize was skipped because an image draw overlaps the visible region
(`_imagesIntersectRegion`) - the CAD-sheet case where the detail must come from
the worker.

## Fix (`pdf_page_view.dart`)

1. Complete `paintReady` on error too: `detailFuture.then(onValue, onError:)`
   treats a failed detail as "not ready" and lets the full pass proceed. The
   deferral is an optimization, never a correctness gate.
2. Defensive hygiene: read and clear `_progressiveDetailFuture` in `_renderNow`
   *before* the supersession early-return, so a newer generation can never
   inherit a stale progressive-detail future from an abandoned paint.

## Test

`test/vector_first_detail_error_test.dart` builds a full-page-image page (every
detail region intersects the image, forcing the worker detail path), drives it
at scale 8 through a worker that fails the pre-full-record region detail, and
asserts the full-page image record still starts and the sharp base raster lands
- no relayout needed. It times out (the strand) on the pre-fix code and passes
after. The failure is modelled as transient (detail records after the full
record escapes the strand are allowed through) because in production
`_renderNow` runs under the render scheduler's try/catch, so a *persistently*
failing detail just fails silently - it is the deferred full render that must
never be starved.
