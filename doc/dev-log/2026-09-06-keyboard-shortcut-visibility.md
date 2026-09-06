# Show shortcut hints when a mobile keyboard is connected

The native app's `KeyboardAvailability` wraps the Navigator through
`MaterialApp.builder`. It publishes `PdfKeyboardAvailability` for menus,
dialogs, the command palette, and the editor toolbar. Mobile starts with
hints hidden until the native inventory reports a keyboard; desktop keeps
its normal hints. The reusable editor scope defaults to showing hints when
the host does not supply a connection signal. Mobile web has no native
inventory and conservatively hides hints.

Android uses `InputManager.InputDeviceListener` and queries enabled,
non-virtual, alphabetic input devices. This excludes on-screen keyboards,
volume keys, and remotes. The `isEnabled` check is gated at API 27.
iOS queries `GCKeyboard.coalesced` and observes first-connect/last-disconnect
notifications. Both bridges use `dev.milanko.dartpdf/keyboard` with an
`isConnected` query and `changed` events. Foregrounding refreshes inventory;
a sequence guard prevents an old query reply from overriding a newer event.
Native APIs: [Android InputDevice](https://developer.android.com/reference/android/view/InputDevice)
and [Apple keyboard notifications](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/gckeyboarddidconnect).

App-menu tiles read the scope in their own Builders so an already-open menu
updates. Command-palette key labels and navigation hints disappear, while
disabled-action explanations remain. Undo/redo/save use their existing
localized plain labels; tool tooltips omit their key suffixes. Shortcut
configuration is hidden from Settings without changing any bindings.
The tablet popup reads availability inside a mounted menu entry because
`PopupMenuButton.itemBuilder` runs only when opening. This keeps an open
Settings popup current on both disconnect and reconnect, without an empty row.

Validation: 9 keyboard regressions cover Android/iOS connection changes,
software-keyboard exclusion, foreground refresh, stale query replies,
missing bridges, live menus/Settings/tooltips, and functioning commands with
hidden hints. The existing app menu/palette/save regressions (18) and shell/
tool-shortcut suites (92) pass. Changed Dart files analyze cleanly. The
Android ARM64 release builds and passes the scanner-constructor APK check;
the iOS simulator app also builds successfully.
The Pixel remains disconnected, so physical attach/detach has not been tested.
