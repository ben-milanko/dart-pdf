# Print: stale page list, copies re-rendered

Two print-options bugs reported together.

- **Stale range text.** `PrintPreferences` persists the Range field's text so
  a deliberate custom range survives. The dialog restored it whatever mode
  came back, so after printing a 14-page file, a 2-page file opened in *All*
  still showed `1-14`. `_loadPreferences` now restores the text only when the
  restored mode is `custom`; otherwise the field keeps this document's own
  default (`current-last`).
- **Copies rendered N times.** `preparePrintDocument` expands copies into
  repeated page dictionaries that share one `/Contents` stream, so the desktop
  path (`native_print_io.dart`) lowered 10 copies of a 2-page file 20 times and
  reported "x of 20". It now keys each sheet by its page dictionary minus
  `/Parent` (`_sheetKey`), encodes each distinct sheet once, keeps the bytes
  only while a later copy still needs them (64 MB cap - an evicted sheet is
  re-encoded silently), and reports progress in distinct sheets. The final
  tick is held until the last copy is spooled so the progress dialog doesn't
  close early. The runner still receives every copy; native `dmCopies`/GTK
  n-copies was not used because it can't express uncollated or duplex-paired
  copies the composer already lays out.
