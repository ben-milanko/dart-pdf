# Annotation locking (+ Bluebeam interop)

Let users lock/unlock markup annotations from the editor UI, writing the
standard PDF flags so the lock round-trips with Acrobat and Bluebeam Revu.

## What was already there

The enforcement half was complete and tested before this change:

- `PdfAnnotation.isLocked` (/F bit 8, 128), `isLockedContents` (bit 10,
  512), `isReadOnly` (bit 7, 64) getters (`annotation.dart`).
- `PdfEditor.setAnnotationFlags(pageIndex, annotation, flags)`
  (`annotation_editor.dart`) - the low-level flag writer.
- `PdfEditingController.isAnnotationEditable` is the single chokepoint:
  `!isReadOnly && !isLocked && (host predicate)`. Because *selection*
  routes through it, a locked annotation never enters `_selected`, so
  move/resize/rotate/delete/restyle are all transitively refused;
  `isLockedContents` blocks text edits separately (`canEditSelectedText`,
  `setSelectedContents`). Covered by `editing_readonly_test.dart`.

So the gap was purely the authoring side: nothing in the UI *set* the
flags, and - the sharp edge - once an annotation is locked it's no longer
selectable, so it could never be reached to unlock again.

## What landed

**Controller (`editing_controller.dart`).** A lock-management API that is
deliberately *not* gated by `isAnnotationEditable` (that would make unlock
impossible), only by a new `isAnnotationLockManageable` = selectable
markup && !ReadOnly && host predicate:

- `setAnnotationLocked(page, index, locked)` - slot-based so it reaches a
  locked, unselectable annotation. Locking ORs in **both** Locked (128)
  and LockedContents (512); unlocking clears just those two bits, leaving
  Print/Hidden/NoView and anything else intact. Locking also drops the
  slot from the selection (`resizable` is a *capability*, not a
  permission, so stale handles would otherwise linger).
- `toggleAnnotationLock(page, index)` - the sidebar's per-row button.
- `canLockSelected` + `lockSelectedAnnotations()` - the context-menu path
  for the current (necessarily unlocked) selection; locks as one revision
  then clears the selection.

**Context menu (`editing_menu.dart` + `pdf_viewer.dart`).** A "Lock" entry
beside Delete, enabled on `canLockSelected`, for the (necessarily
unlocked) selection. For the reverse, a right-click *on a locked
annotation* opens an Unlock-only menu: since the annotation can't be
selected, `_onSecondaryTapUp` falls through the normal
`selectableAnnotationAt` miss to `lockedAnnotationAt` (a locked-aware hit
test) and passes the slot to `showPdfAnnotationMenu(unlockTarget:)`, which
then shows a standalone "Unlock" item (and suppresses the otherwise-always
Paste row). So mouse users get both directions from the page itself.

**Sidebar (`editing_sidebar.dart`).** A lock/unlock icon on every markup
row (`pdf-annotation-lock-$page-$index`) that hover-reveals with the row's
other actions (delete, thread menu), and stays reachable for a locked row
even though its edit actions are gone - the touch counterpart to
right-click Unlock, mirroring Bluebeam's Markups-List lock column.

## Bluebeam interop

Bluebeam Revu's "Lock" (right-click, or the Markups List Lock column)
prevents a markup from being changed or deleted while still allowing
status changes, replies, export, and copy - exactly the standard /F
Locked semantics. Both Acrobat and Revu read and write the same bits, so:

- an annotation *we* lock (128|512) shows as locked and is protected in
  Revu/Acrobat;
- one locked *there* (bit 8) arrives with `isLocked` true, so our editor
  already refuses to move/resize/delete it, the sidebar shows it locked,
  and the row's Unlock lifts it.

We treat bit 8 (Locked) as the canonical "is locked" indicator because
that's the load-bearing, cross-tool bit; we additionally set
LockedContents so a locked markup can't be retyped either, matching how
Acrobat/Revu fully lock. Setting /F changes no appearance, so no glyphs
move.

## Tests

- `editing_readonly_test.dart` `group('locking')`: lock sets both bits +
  clears selection + refuses every mutating path; slot-based unlock
  reaches an unselectable locked annotation; unrelated /F bits (Print)
  survive; toggle; ReadOnly and the host predicate veto lock management;
  `canLockSelected` tracking.
- `editing_sidebar_test.dart`: the row's lock button locks then unlocks,
  with the delete action disappearing while locked.
- `editing_menu_test.dart`: "Lock" from the context menu locks + clears
  the selection; a right-click on the locked annotation then offers
  Unlock (not Lock/Delete), unlocks it, and it selects normally again.

l10n: `menuLock`, `sidebarLockAnnotation`, `sidebarUnlockAnnotation`
(en.arb + regenerated `dart_pdf_editor_localizations*.dart`).
