## 0.1.0

- Extract DartPDF's print preview, sheet composer and system printing into an
  optional Flutter plugin for Android, iOS, macOS, Windows, Linux and web.
- Include page ranges, paper sizes, scaling, n-up layout, copies, cropping,
  markup controls, batch-file callbacks and the existing translations.
- Register native backends automatically, with no PDFium dependency or host
  runner code. Keep print buffers per plugin instance and reject overlapping
  jobs on a native channel.
- Include #899's direct Windows printing, printer discovery, color/duplex/tray
  selection, advanced driver properties and saved print preferences.
- Pair duplex fronts and backs before expanding copies, adding blank backs
  for odd page counts and paper-size changes.
