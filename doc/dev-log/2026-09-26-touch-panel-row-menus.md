# Touch panel rows: actions fold into the ⋮ menu

On touch targets (`!pdfPanelControlsRevealOnHover()` - iOS/Android/Fuchsia)
panel row actions are always visible, so the annotation sidebar showed a
lock, a ⋮ and a delete on every row, and the bookmark panel an add-child /
edit / delete strip. Those rows now show a single ⋮ menu instead:

- `PdfAnnotationSidebar._moreMenu` (was `_threadMenu`): Reply / Resolve for
  a thread host, then Lock/Unlock (`isAnnotationLockManageable`), then
  Delete (or Delete signature, which still confirms). Desktop is unchanged -
  hover-revealed icons with the ⋮ carrying only the thread actions.
- `PdfBookmarkSidebar._moreMenu`: Add child / Edit / Delete.

The popup items keep the old buttons' keys (`pdf-annotation-lock-P-I`,
`pdf-annotation-delete-P-I`, `pdf-signature-delete-P-I`,
`pdf-bookmark-{add-child,edit,delete}-PATH`), so a touch-platform test opens
`pdf-annotation-more-P-I` / `pdf-bookmark-more-PATH` first, then taps the
same key. Remember flutter_test's default platform is Android (touch).
