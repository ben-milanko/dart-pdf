# Annotation editing polish

Ctrl/Cmd+B, I, and U now act on selected free-text boxes as well as text being
edited inside a box. The field's focus-node handler claims formatting keys before
platform text actions can consume them. Whole-box changes preserve run colors,
other font traits, and annotation grouping. PDF page selections support bold and
italic content rewrites and underline markup. Identity-H composite text can be
restyled through the shared run rewriter while retaining surrounding glyphs and
their placement.

Callouts persist independent leader color, width, and dash metadata. The text-box
outline continues to use the standard default appearance and border dictionary.
Properties exposes a Leader section with color, width, dash, and arrow ending,
plus a separate outline width. Removing an outline or setting its width to zero
leaves the leader visible. Text edits, font changes, reshapes, and appearance
regeneration retain the independent leader settings. Long property labels now
wrap inside the panel's width.

Ink undo consumes pending strokes in drawing order before moving backward through
document revisions. Redo restores the pending strokes and their pressures after
redoing any earlier document revisions. Undo cancels the auto-commit timer so it
cannot commit leftover strokes during the undo sequence.

Paste now captures its destination, serializes clipboard reads, and rejects reads
or image decodes that finish after another document edit. New external images
supersede older local annotation copies; desktop readers recognize clipboard
revisions superseded by local copy operations. Windows clipboard opens retry brief
ownership contention. Image reads validate registered PNG data, accept both PNG
format names, and try DIBV5 before DIB and bitmap conversion.

The annotation context menu rotates multi-selections around their combined bounds
or each annotation's own center, taking an angle in degrees. Each command is one
undoable revision, preserves annotation slots and grouping, and applies a separate
shared pivot on each selected page. Single-selection rotation handles retain their
existing behavior.

Regression coverage includes formatting keyboard flows, composite text placement,
callout line persistence and property fields, ink undo/redo, image paste precedence
and stale reads, both rotation menu actions, and geometry for both pivots. Existing
text, callout, clipboard, menu, selection, ink, and rotation suites also pass. The
Windows DIB decoder tests run on Linux; the full native Windows clipboard runner
requires a Windows runtime smoke test.
