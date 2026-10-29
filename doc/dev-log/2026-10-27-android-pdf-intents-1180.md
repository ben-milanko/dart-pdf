# Android PDF intent compatibility (#1180)

The application already declared VIEW + DEFAULT + BROWSABLE with
application/pdf, and SEND with application/pdf. MainActivity already handled
cold starts through getInitialFile and warm singleTop starts through
onNewIntent/openFile. Adding a second identical VIEW filter would not fix it.

The explicit content/file schemes excluded type-only resolver queries, including
queries used to discover PDF handlers before choosing a URI. A MIME-only filter
matches those queries and still admits content/file URIs implicitly, without
claiming HTTP(S) URLs or unrelated types.

Two incoming-provider gaps also existed: SEND required EXTRA_STREAM even when
ClipData supplied the URI, and a failed DISPLAY_NAME query discarded bytes that
had already been read successfully. IncomingPdfHandler keeps the existing
cold/warm channel contract, adds the ClipData fallback, and treats metadata as
optional. It reads through ContentResolver under the sender's temporary grant;
no broad storage permission, persistable grant or writable path is introduced.
Dart receives bytes and opens a separate document through _openIncoming.

Native Robolectric tests exercise the merged manifest resolver, cold/warm
payloads, one-shot draining, content and file streams, missing metadata and
read denial. The Flutter incoming-file test checks byte payloads across the
channel without inventing a writable origin. Existing combine-incoming widget
tests cover the editor's OS-open entry point with generated PDFs.

This does not prove the reporter's particular WhatsApp/Android 17 combination:
there is no attached Android device, and the local emulator images stop at
Android 16. The existing whole-file read remains synchronous; denied reads
still return without a new error UI. Those broader UX changes are outside this
compatibility patch. No renderer, editing, experiment or release settings change.

For device acceptance, install the candidate build, open a synthetic PDF from
Files and WhatsApp with the app stopped and then already running, select
DartPDF/Always where the system offers it, edit, Save As, and reopen the saved
copy. Android controls which default-app chooser is available; this change does
not force a default or replace another app's saved choice.
