# Group mobile Controls by purpose

`PdfShellControlItem.group` separates View, Panels, and document actions.
Both editor and reader shells mark their panel controls explicitly. Settings
and Reflow sit under the existing localized View heading alongside zoom;
panel buttons get the localized Panels heading. Host-provided Save/Share
stays in a separate action row when present. Empty groups are omitted.

The sheet now scrolls within 90% of the screen height so the added section
does not strand controls on smaller displays. Existing tile keys, selected
states, and close-then-open behavior remain intact.

Validation: all 80 `pdf_shell_test.dart` tests pass and changed files analyze
cleanly. A temporary Flutter rendering harness verified the dark Controls
sheet at 430×956 and reached/opened Properties after shrinking to 430×430;
the harness was removed after visual inspection. The Pixel was disconnected.
