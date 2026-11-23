# Migrating to DartPDF 16.2

Update the eight lockstep packages together to 16.2.0. The CLI (0.12.0),
printing plugin (0.13.0) and GPU companion (0.14.0) remain compatible. Flutter
packages still require Flutter 3.50.0.

No source changes are required. The built-in editor remembers the last tool
used in each toolbar group and restores it when opening the group if doing
so requires no prompt and does not edit the document. Custom toolbars can
query the same choice with `PdfEditorCommands.toolOnOpen`.
