# Long OCR jobs

OCR stays on the device. A job saves a private snapshot of the requested PDF,
then commits each page's recognized text independently. Closing the source tab
does not change the job's input. Completed pages are not recognized again after
an interruption, including pages with no text.

## Closing or backgrounding

| Platform | Behaviour |
| --- | --- |
| Windows, macOS, Linux | A separate, hidden app process runs OCR independently of the editor window. Reopening the editor reconnects to saved progress or adopts the finished result. |
| Android | A foreground service keeps the Flutter engine alive while the activity is backgrounded or removed from Recents. Its notification shows page progress and allows cancellation. The service uses the OS's local-file-processing type and respects its time limit. |
| iOS/iPadOS 26+ | A manual OCR request asks for Continued Processing with system progress. The OS can deny or end that grant. Automatic OCR uses finite UIKit background time instead. |
| Earlier iOS/iPadOS | Finite UIKit background time can finish current work; an unfinished job resumes when the app returns. |
| Web | Work can continue while the browser permits the tab to run. A frozen or closed tab cannot keep executing local OCR. IndexedDB checkpoints let it resume on the next open. |

Force-stop, reboot, browser storage removal and OS resource limits cannot be
overridden. Pending/running jobs resume from saved pages when the app next opens.
A reported failure stops instead of retrying indefinitely; choosing OCR again
for the same PDF snapshot retries from its checkpoints.

Recovered output opens as a separate PDF, never over a document edited since
the job started. The completed job is retained until its output has been cached
and included in session persistence. An exclusive delivery lock prevents two
windows/tabs from adopting the same result. Cancellation discards the job rather
than reopening it later.

## Implementation and verification

Native checkpoints use flushed temporary files, atomic replacement and OS file
locks. Browser checkpoints await IndexedDB transaction completion, with Web Locks
for ownership. Final PDF generation always starts with the immutable source and
the saved spans, so retrying that stage cannot add duplicate text layers.

Local verification covers checkpoint/restart, empty pages, cancellation,
expiration, failed writes, result adoption and the existing OCR UI. Linux, web
and Android debug builds were checked. A real Linux worker was terminated after
eight committed pages, then completed all 30 pages on restart; the eight saved
page hashes were unchanged. Windows/macOS/iOS native execution and Apple
background/raster behaviour still need platform verification before release.
