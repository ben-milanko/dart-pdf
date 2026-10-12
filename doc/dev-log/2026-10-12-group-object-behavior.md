# Annotation groups behave as one object

A persistent annotation group now has one selection box and shared resize and
rotation handles. The drag preview records all members into one picture. Moving
a group carries all artwork, including callout arrow tips; the empty space within
the selection box can also be dragged. Groups remain units when mixed with other
selected annotations: alignment and individual-center rotation act on each group
as a whole. A group can move between pages in one undoable revision while keeping
its member names and group links.

Group resizing applies a shared affine transform to the appearance streams and
page-space point geometry. Text and strokes scale with the artwork. The complete
operation is validated and appearance streams are decoded before any member is
changed. Shared appearances are detached, so imported annotations cannot mutate
each other's streams. New stream objects use decoded data so encryption does not
carry ciphertext encrypted for an old object number.

Free-text restyling preserves the authored appearance frame and its transform,
including after resizing and ungrouping. Style and opacity regeneration keeps
that frame too. Callout leader styling likewise returns scaled or moved geometry
to the original frame before rebuilding it, and a local-inset marker keeps the
text box's geometry correct after ungrouping.

Regression coverage includes shared handles and live gestures, group move from
the empty interior, proportional resize/flip/rotation, alignment with ordinary
annotations, cross-page move and undo, transformed text formatting, and shared
appearance streams in imported PDFs.
