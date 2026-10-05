# Desktop text menu matches the touch selection chip (#1004)

Two separate problems made a mouse text selection look different from a
touch one:

1. **Routing.** `_onSecondaryTapUp` sent any right-click with no annotation
   under it to the annotation menu whenever there was something to paste
   (annotation/snapshot clipboard, or a `systemPdfPasteProvider` - which the
   app always wires). So right-clicking *selected text* in the app showed a
   menu with just "Paste". Now a click inside the current text selection
   (`_clickInTextSelection`, the same test `_prepareTextSelectionAt` used)
   skips the paste branch and gets the text menu. An annotation hit and the
   locked-annotation Unlock menu keep priority; empty page area still pastes.
2. **Layout.** The text menu listed markup kinds flat with Link in the
   markup group. It now follows the chip (`_TextSelectionChrome`): Edit,
   Copy, Markup, Link, Select all, then the host group. `PdfMenuRequest`
   has no submenus, so the Markup row (`pdf-text-menu-markup`, trailing
   chevron) opens the four kinds as a second presenter menu at the same
   point - which also works for custom presenters with no extra API.

API note: `pdf-text-menu-highlight`/`underline`/`strikeout`/`squiggly` are
no longer in a `textMenuEntries` builder's `stock` list; they live in the
second menu. Documented on `PdfTextMenuEntriesBuilder`.

Tests: `editing_menu_test.dart` "text context menu (mouse)" group (order,
Markup submenu applies, the #1004 paste-clipboard regression).
