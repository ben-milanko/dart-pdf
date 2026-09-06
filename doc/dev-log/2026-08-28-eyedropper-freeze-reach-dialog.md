# Eyedropper: the freeze, the one-page reach, the zoom, and the dialog

Four complaints about the colour picker, which turned out to be four
separate defects in the same tool. All of them are in
`packages/dart_pdf_editor`.

## 1. Arming the eyedropper froze the app

`_EditingPageOverlayState.build` warmed the sampling raster:

```dart
if (_controller.isPickingColor) unawaited(_ensureSampler());
```

Every mounted page overlay ran that, and the overlay is mounted for every
page in the lazy list's cache extent - so arming the tool kicked off one
**full page render per mounted page, all at once**. Each of those went
through `PdfPageColorSampler.of`, which called
`renderPictureRecordedWithPlan` on the **UI isolate**: the content-stream
parse and interpreter walk, then a rasterize and a `toByteData`, times
however many pages happened to be mounted. On an ordinary report that is
the whole freeze; on anything raster-heavy it was worse, because the
sampler passed no `maxImagePixelRatio` at all, so every image decoded at
its native resolution for a raster that is only ever read three pixels at
a time.

Three changes:

- **Lazy, per-page.** The warm moved out of `build` and onto the pointer:
  `MouseRegion.onEnter` and `_updatePickPreview`. Only the page the
  pointer actually reaches builds a raster. `build` now does the opposite
  - `_dropSampler()` when the tool is put away, since the overlay often
  stays mounted for a selection or another tool and a page of RGBA is
  megabytes.
- **Off the UI isolate.** `PdfPageColorSampler.of` takes the viewer's
  `PdfRenderWorker` (plumbed `PdfViewer` → `EditingPageOverlay` →
  sampler) and records through it, exactly like page rendering. Only the
  replay and the raster stay on the UI thread. A worker that declines (an
  inline image, no worker on this platform) falls back to the local
  render as before.
- **A pixel ceiling.** `PdfPageColorSampler.maxPixels` (4 MP) caps the
  raster; a bigger page is rasterized scaled-down and `colorAt` maps into
  it, so callers still speak page points. An A0 sheet was 32 MB of RGBA,
  a large-format plan far more. Images are capped to the raster's own
  resolution now too.

## 2. It only worked on the page it was armed over

The overlay's `GestureDetector` kept its pan recognizer while the
eyedropper was armed. `_panStart` does nothing for it (`case null: break;
// eyedropper only - taps, no drags`) - but the recognizer still *claimed*
the drag, so the document could not be scrolled for as long as the tool
was armed. The eyedropper reached exactly the pages that were on screen
when it was armed, which is what "doesn't work across more than one page"
was.

`onPanStart/Update/End` (and the double-tap callbacks) are now dropped
while picking, the same way cropping drops them, so the scroll view wins
the drag. Two consequences had to be handled:

- The raw `Listener`'s pointer-up is the eyedropper's commit, and it
  fires whether or not the gesture went to the scroll view - so ending a
  touch scroll picked whatever colour the finger lifted over and put the
  tool away. `_pickDragged` marks a touch/stylus pointer that has passed
  `kTouchSlop`; a dragged pointer's lift commits nothing. Mouse and
  trackpad keep press-drag-release (those devices don't drag-scroll a
  list), which is a deliberate feature - you can watch the preview chip
  while you hunt for the colour.
- A gesture keeps being routed to the render object it went down on, so a
  page scrolled out from under a live pointer delivers moves and an up to
  an *unmounted* overlay - which promptly tripped
  `ValueNotifier used after being disposed`. The raw handlers and both
  repaint bumps now tolerate being called late.

The viewer's `_touchPanEnabledAt` also stood the zoomed touch-pan
recognizer down while picking, on the assumption that the overlay would
handle those drags. It doesn't, so a zoomed page could not be panned at
all. The eyedropper is now on the "viewer owns pan" side of that gate.

## 3. The preview chip ignored zoom

The chip lives inside the viewer's zoom transform, like everything else
in the overlay - and unlike everything else it did not counter-scale, so
at 800% it was a billboard covering the thing being sampled and at 25% it
was unreadable. It now scales by `_chromeScale` (anchored top-left, with
its offset from the pointer scaled to match), the same treatment the
selection chrome, handles and rotate knob get.

The *sample* is zoom-aware now too. The 3x3 patch exists so an
anti-aliased stroke reads as its colour, but 3 points of a magnified page
is most of a glyph stem, so at high zoom the reading was a blur of the
paper either side of what the pointer was on.
`PdfPageColorSampler.patchRadiusForZoom` sizes the patch in *screen*
pixels instead: 3x3 at 1:1, a single pixel past 2x, wider when zoomed out.

## 4. Sampling from the colour dialog

`PdfEditingController.pickColorFromPage()` arms the eyedropper and
resolves with the sample, and - unlike `startColorPick` - does **not**
adopt it as the annotation `color`: the caller asked for a colour for its
own purposes, and quietly repainting the tool with it would be a second
edit nobody asked for. `finishColorPick` routes to a waiting caller when
there is one; `cancelColorPick` and `dispose` resolve it null.

`PdfColorPicker` grows an `onPickFromPage` callback, shown as an
eyedropper button in the value row. The picker can't sample the page
itself - it is a dialog *over* the page - so `showPdfColorPicker` closes
the dialog immediately after firing the callback, and `pickEditingColor`
loops: close, arm, wait for the tap, reopen seeded with the sample so the
user can confirm or nudge it. A cancelled sample ends the whole choice
rather than bouncing the dialog back.

Because every piece of editing chrome already goes through
`pickEditingColor`, that puts the eyedropper everywhere a colour is
chosen. Pickers nested inside another modal pass `fromPage: false` (the
signature dialog is the one stock case) - there is no reachable page from
there, so the button would be a dead end.
