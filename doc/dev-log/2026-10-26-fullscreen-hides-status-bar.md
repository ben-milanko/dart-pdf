# Full-screen reading hides the status bar

On a phone the auto-hide chrome (`PdfAutoHideBar`, `design/auto_hide_chrome.dart`)
used to keep a status-bar-height spacer when the header slid away, so the
page stopped under an empty black band with the clock and battery still
showing. Now a top bar that sits under the status bar (a non-zero
`MediaQuery.paddingOf(context).top` while showing) hides the system UI with
it (`SystemUiMode.immersiveSticky`) and restores it (`edgeToEdge`) when the
chrome comes back, the bar is disabled, or it is disposed. The spacer is
gone: the page runs to the top edge.

- `_underStatusBar` is sampled only while the bar has not hidden the status
  bar, because hiding it can zero the inset (Android, non-notched iPhones).
- On notched iPhones the safe-area inset stays when the status bar hides, so
  the page draws under the sensor housing - the usual immersive look.
- A host that embeds the shell below its own app bar has no top inset there,
  so it never touches the system UI.
- Test: `auto_hide_chrome_test.dart` "hidden chrome takes the status bar".
