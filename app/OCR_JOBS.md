# Resumable OCR

OCR runs locally while the app is open. Each job saves a private copy of the
source PDF and checkpoints every completed page, including pages without text.
Closing the app does not discard those checkpoints. On the next open, unfinished
jobs resume from the first page that has not been saved.

This applies to Windows, macOS, Linux, Android, iOS/iPadOS and web. There are no
detached processes, background services or requests for extended OS execution.
When the app becomes hidden or pauses, an in-flight page can finish and save;
the job pauses before starting another page. Returning to the app resumes it.
The browser uses IndexedDB, so clearing browser storage also clears saved jobs.

Closing the source document tab does not replace the job's saved input. Recovered
output opens as a separate PDF and never overwrites a document edited since the
job began. Cancellation discards the job. A failed job can be retried from its
saved pages by choosing OCR again for the same PDF snapshot.

An exclusive job lock prevents multiple windows or browser tabs from processing
the same job. A separate delivery lock prevents duplicate result tabs. Completed
output is retained until it has been cached and included in session persistence.

## Persistence

Native checkpoints use flushed temporary files, atomic replacement and OS file
locks. Browser writes await IndexedDB transaction completion and use Web Locks
for ownership. Final output is assembled from the immutable source and saved
text spans; retrying final assembly cannot add a second OCR text layer.

Tests cover saved and empty pages, interruption between a page write and its
progress update, cancellation, pause and resume, failed writes, result adoption
and multiple-window ownership. Platform builds and runtime checks are separate
from these persistence tests.
