# Foreground the app when the OS opens a file

Opening a PDF from the OS (double-click, "Open With", drag onto the icon,
`dartpdf file.pdf`) while DartPDF is running should bring its window forward,
even if it is minimized or hidden. Windows already did this; macOS and Linux
had gaps.

## macOS (`app/macos/Runner/AppDelegate.swift`)

The runner never activated itself. It relied on LaunchServices, which activates
the app for a Finder open but never unhides a Cmd-H'd app or restores a
window minimized to the Dock. The document then opened in a tab nobody
could see. `deliver(path:)` now calls `surfaceForIncomingFile()`: unhide,
activate (`activate()` on 14+, `activate(ignoringOtherApps:)` below),
deminiaturize, then `makeKeyAndOrderFront`. The target is `mainFlutterWindow`
in the single-window runner. In multi-window mode it is the frontmost
Dart-owned `FlutterViewController` window, falling back to a minimized one
(never the hidden services window). On a cold start no window exists yet, so
it only activates.

## Linux (`app/linux/runner/my_application.cc`)

`present_existing_window` uses `gtk_window_present`, which is fine on X11:
GtkApplication's `before_emit` takes `desktop-startup-id` from the forwarding
process's platform data, and GDK derives the user time from its `_TIME`
suffix. On Wayland, focus needs an xdg-activation token. GLib (2.76+)
forwards `XDG_ACTIVATION_TOKEN` as `activation-token`, but GTK 3 only reads
`desktop-startup-id`. A launcher that sets only the token therefore got a
refused focus request (a flash instead of a raise). `my_application_before_emit`
chains up, then hands `activation-token` to
`gdk_wayland_display_set_startup_notification_id`. The next present's
`gdk_window_focus` consumes it via `xdg_activation_v1_activate`.

## Windows (`app/windows/runner/main.cpp`)

The single-instance mutex hands the file over with `WM_COPYDATA`, calls
`AllowSetForegroundWindow(ASFW_ANY)`, then `SW_RESTORE` + `SetForegroundWindow`.
That already worked. The one fix is in the multi-window fallback: when
`GetActiveWindow` is null, `ActiveProcessWindow`'s `EnumWindows` scan now
skips owned and tool windows, so it surfaces a document window rather than a
popup. The same function picks dialog owners.

## Verification

The Linux runner syntax-checks with `-Wall -Werror` against GTK 3.24.41. The
Swift and Win32 changes could not be compiled in the Linux session. Check them
by hand: minimize or hide the app, then open a PDF from Finder, Explorer, or
the file manager.
