# Phone app menu as a bottom sheet

On a phone the app menu popup ran 15 rows + 3 headers (~two screens), with
Open Recent as a touch-hostile submenu. Phones now get a bottom sheet
(`app/lib/app_menu_sheet.dart`); tablets and desktops keep the popup.

## Shape

- Search pill on top → the existing command palette (`menu-command-palette`),
  so nothing is unreachable.
- Four large buttons: **New, Open, Print, Sign** (Print/Sign only with a
  document). New opens a Blank / Scan page when there is more than one
  creation action (`menu-new`); a phone always has the platform scanner.
- Up to 3 recent files inline + See all (`RecentFilesScreen`).
- "This document": **Export** (reduce size, page as image, Save As where it is
  not Share) and **More tools** (OCR, compare, insert document/scan) open a page
  inside the sheet; a group of one shows as its own row instead.
- Read-only switch + Settings at the foot.
- Share (`save-as` under `_usesMobileShare`) is left out: the header's Share
  button already does it.

## Wiring

- Gate: `_usesAppMenuSheet` = touch platform (`!_usesCompactAppMenu`) **and**
  compact width (< `pdfShellCompactWidth`). The default 800px test surface
  therefore still gets the popup, which is why the existing menu tests needed
  no change.
- Placement lives on the action: `_MenuAction.sheet` (`_SheetPlacement`) plus
  `sheetTitle` for the short button labels. The menu, the palette and the sheet
  all read the same `_fileActions`/`_documentActions`/`_appActions` lists.
- The sheet pops with the chosen callback and the caller runs it (the popup's
  `onSelected` contract), so an action's dialog never stacks on the closing
  sheet. Rows keep their `menu-<id>` keys.
- Tests: `app/test/app_menu_sheet_test.dart`.
