# Tab sorting and full file names on hover

- **Sort tabs by name** (tab right-click menu, `tab-menu-sort-name`):
  `DocumentTabs.sortByName()` reorders the strip with `compareTabTitles`
  (case-insensitive, digit runs by value so `sheet 2` < `sheet 10`, untitled
  last, stable for equal names). The active document stays active; the
  restored-block count is left alone, like `reorder`. Persisted through the
  usual tab-set notification.
- **Full name on hover**: the desktop hover card (`_TabHoverPreview` /
  `_DesktopTabPreviewCard` in `editor_screen.dart`) now prints the whole file
  name, extension included, wrapping (up to 6 lines under the thumbnail)
  instead of a middle-ellipsis. The active tab, which used to get no card,
  now gets a title-only card (`titleOnly`, sized to its text) so its
  truncated name can be read too. Still a plain `OverlayEntry`, not a
  `Tooltip`, for the reorderable-list reason noted on the class.
