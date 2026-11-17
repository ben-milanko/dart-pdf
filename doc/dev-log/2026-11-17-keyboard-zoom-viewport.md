# Grey band while editing text with the keyboard open

On a zoomed PDF, opening the phone keyboard shrinks the viewport and the
scroll list inside it. The zoom transform retained its previous translation.
That translation could move the newly shortened list entirely above the bottom
of the viewport, exposing the grey canvas and clipping the text editor.

The regression uses a nine-page generated PDF, an active inline free-text
editor and iOS platform settings. With a 400 x 850 viewport, 1.3 pixels per PDF
point and a 500-pixel keyboard inset, the old code leaves the transformed list
ending at y=275.825 in a 350-pixel viewport: a 74.175-pixel blank band.

After a viewport resize, the viewer now clamps the zoom translation against
the new dimensions once layout has produced the new scroll extents. It moves
the main-axis correction into the scroll offset where possible, keeping the
text editor at its previous screen position. Zoom, focus and typed text remain
intact. A live sub-fit pinch is left alone.

`keyboard_viewport_resize_test.dart` covers keyboard opening and closing,
text entry and save/reopen, and main-axis window resizing in both vertical and
horizontal layouts. The iOS keyboard regression failed against the original
code and passed with the fix. Physical iPhone confirmation remains outstanding.

This is separate from PR #1095, which concerns iOS web keyboard focus and a
blank band after keyboard dismissal. No app release or deployment is included.
