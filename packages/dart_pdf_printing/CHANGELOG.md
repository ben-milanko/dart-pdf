## 0.2.0

- Stop the print dialog carrying a previous document's page range. The Range
  field restored the last job's typed pages even when the dialog reopened in
  All mode, so a 2-page file showed a 14-page file's "1-14"; the saved range
  is now restored only when the job resumes in Range mode.
- Render copies once on the desktop print path. The composer lays copies out
  as repeated pages sharing one content stream; each distinct sheet is now
  encoded once and reused for later copies (up to 64 MB), and progress counts
  distinct sheets - 10 copies of a 2-page file report "2 of 2", not "20". The
  runner still receives every copy, so collation and duplex pairing are
  unchanged.
- Align dependency constraints with the dart-pdf 5.0.0 package suite.

## 0.1.1

- Align dependency constraints with the dart-pdf 4.5.0 package suite.

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
