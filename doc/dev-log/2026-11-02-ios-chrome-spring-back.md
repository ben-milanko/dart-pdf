# Keep elastic scrolling from reversing the phone chrome

On iPhone, a fling at the end of a short document hid the header and bottom
toolbar, then brought them back without a new gesture. The chrome's resize
changed the viewer's available height while the elastic scroll was settling.

`PdfChromeAutoHide` counted out-of-range `ScrollUpdateNotification`s as reading
travel. The iOS spring's return therefore crossed the reverse-scroll threshold.
Ignore those updates and clear accumulated travel until scrolling is back within
the document bounds. Normal scrolling, reverse scrolling and tap-to-toggle keep
their existing behavior; the viewer's elastic physics are unchanged.

The editor regression uses a generated two-page PDF at a 402 by 874 logical-pixel
iOS viewport, including status-bar and home-indicator insets. Before the fix, one
upward fling emitted chrome visibility `[false, true]`; after it, `[false]`.
A reader regression covers spring-back at the start, and a controller test checks
that elastic travel cannot leak into the next in-range update. Both shell tests
also perform a deliberate scroll afterward to verify that auto-hide still works.

Validation: 36 tests passed across `auto_hide_chrome_test.dart`,
`viewer_scroll_lifecycle_test.dart`, `editing_fling_test.dart` and
`wheel_scroll_test.dart`. Workspace `dart analyze --fatal-infos` passed.
Physical-device confirmation and an installed release are separate steps.

Related PR #1176 addresses Safari's outer document rubber-band. This fix is in
the shared Flutter shell and does not change the web host page.
