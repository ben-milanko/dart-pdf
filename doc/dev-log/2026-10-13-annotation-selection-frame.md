# Annotation selection frames during rotation

Grouped annotation chrome previously used the union of page-aligned `/Rect`
bounds. Committing a rotation therefore changed the selection box's width and
height, even though the live preview rotated the original rectangle.

Groups now retain a private `DartPdfGroupRotation` angle on each member. The
selection frame encloses the appearance quads measured along those axes;
standard `/RT /Group`, `/IRT`, appearances and `/Rect` remain interoperable.
The saved angle follows transforms, copy/paste, text rewrites and leader removal.
Newly merged groups start square to the page, and ungrouping removes the angle.

The overlay rotates handles with this frame and uses its centre for rotation.
Local resize stretches all group artwork along those same axes, including on
sideways pages. Mirroring retains the frame orientation. Body hit tests use the
visible frame rather than its surrounding page-aligned bounds.

Review also found that the old 0.3-degree "noise" threshold flattened deliberate
small rotations of single annotations. Model, resize and chrome now ignore only
floating point noise, preserving a single ink box during a 0.1-degree turn.

Regression coverage checks repeated arbitrary turns, single and grouped ink,
live preview versus commit, local resize and flips, all four page rotations,
undo/redo, save/reopen, copy/page moves, text rewrites, foreign groups in both
multi-selection rotation modes, regrouping and leader removal.
