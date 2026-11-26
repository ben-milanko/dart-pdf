# dart_pdf_tabs: the app's tab system as a package

The browser-style tabs used to live in the app only: `DocumentTabs`
(document_tabs.dart), `MiddleEllipsisText`, and about 800 lines of
`editor_screen.dart` (`_buildTabStrip`/`_buildTab`, `_TabsOverview`,
`_MobileTabTile`, `_TabDragStartListener`, the width-hold fields). Trax
wanted the same tabs for its document view, so they moved into
`packages/dart_pdf_tabs` (0.1.0, versioned on its own like
`dart_pdf_printing`). It depends on nothing but Flutter and material_ui.

## What moved where

- `DocumentTabs<T extends DocumentTabEntry>`: the model, now generic.
  `DocumentTabEntry` is an `abstract mixin class` with `title`,
  `isPlaceholder` and `dispose()`. `focusOpened`'s old check, "loading,
  deferred or deferred-path", is now `DocumentTab.isPlaceholder`.
- `DocumentTabStripController` holds the strip state that used to be
  screen fields: the scroll controller, hover, the natural and rendered
  widths, and the close-streak hold. The app calls
  `holdWidthForClose()` in `_removeTabs` and `clearHold()` when a tab
  arrives. `tabInsertionIndex` keeps its strip-rect hit test and hands
  the slot maths to `insertionIndexAt`.
- `DocumentTabStrip<T>` draws the strip. The app's extras go through
  `tabBuilder` (`_wrapStripTab`): the native cross-window drag source,
  the hover preview, and the `AnimatedSlide` that makes room for a
  dragged tab. The strip's `externalGapIndex` and `insertionIndex` show
  the drop slot. Widget keys are unchanged (`tab-strip`, `tab-close-N`,
  `desktop-tab-add-button`, ...), so the app's tab tests did not change.
- `DocumentTabsOverview<T>` + `DocumentTabTile`: the grid. The app's
  `_MobileTabTile` is now a thin wrapper that passes its `_TabPreview`
  in through `preview:`.
- Strings come from `DocumentTabsLabels`, which `_tabLabels(context)`
  fills from `appL10n`.

## Releasing

The package is in `publish-pub.yml`, `release-pub-tags.yml` and
`tool/release.sh`, and CI runs its tests. Like `dart_pdf_cli`, its first
publish has to be manual (pub.dev's Admin page only exists after that).
Until then Trax pins it as a git dependency (`path:
packages/dart_pdf_tabs`).
