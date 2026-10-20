# Rename mobile documents from the title

Android and iOS title taps now open the localized Rename dialog; on tablets,
the selected tab does the same. A rename updates the app-managed document
name and Share filename while retaining the editing controller, PDF bytes,
undo history, and saved baseline.

`app/lib/rename_document.dart` owns the dialog and controller lifecycle.
The initial selection excludes `.pdf`; confirmation trims whitespace,
normalizes the extension, accepts Unicode, and rejects empty or dot-only
names. Input filtering removes path separators and control characters.

`RecentsStore.rename` keeps source identity, cache availability, bookmarks,
order, and opened time. Session metadata is persisted immediately, and
`AutosaveController.noteMetadataChanged` schedules updated recovery metadata
without creating a PDF revision. New scans without a reusable source also
receive a private snapshot. Recent-name updates run immediately: putting
them behind background cache pruning delayed persistence unnecessarily.

Validation: 65 app tests pass across rename, Recents, tabs, save shortcuts,
and unsaved-change storage/recovery. Rename coverage includes Android and
iOS, tablet title taps, cancellation, validation, sharing, metadata
persistence, and preserving the live edit session. Changed Dart files
analyze cleanly. The Android ARM64 release builds and passes the APK scanner
constructor check. Device installation was deferred when Ben unplugged the
Pixel; the rename flow has not yet been checked on physical hardware.
