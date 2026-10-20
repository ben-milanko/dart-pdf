# Annotation sidebar: thread "more" menu + ⌘/Ctrl/Shift multi-select

Two annotation-list interaction changes in
`packages/dart_pdf_editor/lib/src/editing/editing_sidebar.dart`.

## Reply / Resolve moved into a per-row "more" (⋮) menu

The thread controls used to be an always-visible Reply / Resolve
`TextButton` row rendered inline under every markup row by
`_threadSection`. They now live in a `PopupMenuButton<_ThreadAction>`
(`_threadMenu`) in the row's trailing area, revealed on hover next to the
delete button (`_rowActions` builds the trailing `Row`, wrapped in the
existing hover `Visibility`). `_threadSection` keeps only the review-state
chip, the reply tree, and - when open - the inline reply field.

- Menu-item keys `pdf-reply-button` / `pdf-resolve-button` are kept (now
  on the `PopupMenuItem`s), so the actions still fire the same controller
  calls; the trigger has its own key `pdf-annotation-more-<page>-<slot>`.
- The menu shows for any thread-hosting (`behavior.selectable`) row, even a
  locked one - reply/resolve add *new* annotations rather than editing the
  locked one, matching the old inline behavior (which never gated on
  `isAnnotationEditable`). Delete stays gated on editability.
- Reply is disabled when the root has no `/NM` (a reply is matched to its
  root by name, so there'd be no field to open).
- Removed the now-unused `_threadActionStyle`.

Gotcha for tests: the trailing hover `Visibility` uses
`maintainState`/`maintainSize` but not `maintainInteractivity`, so while
invisible the button is wrapped in `IgnorePointer` and can't be tapped.
Widget tests must hover the row first (a mouse `TestGesture.moveTo` the
row centre) before tapping the ⋮ - see `openMore` in
`editing_thread_test.dart`. Because the open menu is an overlay route it
survives the pointer leaving; `openMore` removes its pointer at the end so
a second call (resolve → reopen) can add its own without tripping the
mouse-tracker add/remove assertion.

## ⌘/Ctrl-click and Shift-click multi-select

The list already had a touch-friendly long-press → checkbox mode; desktop
now also gets modifier selection, mirroring the viewer.

- `_onTileTap` reads `HardwareKeyboard.instance`: Ctrl/⌘ toggles the row in
  the selection (`controller.toggleAnnotationSelection`), Shift selects the
  range from `_anchor` to the row (`controller.selectAnnotationSlots`), and
  a plain click keeps the old navigate + select + flash. Modifier gestures
  leave the viewport put (no `showRect`/flash).
- The range runs along `ordered`, a per-build list of every displayed,
  selectable+editable slot in display order, captured by each row's tap
  handler (it's complete by tap time). `_anchor` is set on plain and
  Ctrl/⌘ clicks and cleared on every revision (slots shift under edits).
- New controller methods (`editing_controller.dart`):
  `toggleAnnotationSelection(page, index)` and
  `selectAnnotationSlots(slots)` - both arm the select tool and drop
  invalid/unselectable/locked slots, matching `selectAnnotation`'s gate.

Tests: `editing_thread_test.dart` (menu open flow), `editing_sidebar_test.dart`
(ctrl-toggle, shift-range).
