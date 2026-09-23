# Batch open: placeholders up front

**Symptom.** Opening several PDFs from a network location left the welcome
screen up with no sign anything was loading.

**Cause.** `_pickAndOpen` (and the mobile picker and `_openDropped`) walked a
batch one file at a time, and each file's loading tab was only added when its
turn came. Before the first one did, the loop awaited `file.length()` (an
open-trace probe) and `securityBookmarkForPath` (a native channel call on macOS).
On a network share both can take seconds. After that, file N+1's placeholder
waited for file N's whole `readAsBytes`.

**Fix.** `_openLoadingBatch` adds a placeholder for every document right after
the picker returns, before any I/O. The loop then fills them in order through
the `into:` parameter, which `_openProgressive` already had and
`_openLoadedBytes` now has too. A placeholder the user closes while it waits is
skipped without a read. On the desktop picker, each file runs inside its own
try block (`_openPickedFile` + `_failLoading`), so an unexpected throw turns
only that tab into an error tab. It can't strand the rest of the batch on
spinners.

Regression test: `session_restore_test.dart` "a multi-file pick shows every
placeholder before any file is read" (a stalled `XFile`).
