import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart' show MouseCursor, SystemMouseCursors;

/// Windows' Flutter embedder maps mouse cursors to Win32 `IDC_*` handles, and
/// there is no native handle for the open-/closed-hand grab cursors. Any
/// [SystemMouseCursors.grab] or [SystemMouseCursors.grabbing] therefore falls
/// back to the plain arrow, so the "drag here to pan" affordance is invisible
/// on Windows. Substitute the four-way move cursor (`IDC_SIZEALL`) there, which
/// reads as "drag to pan". Every other target renders grab natively - macOS
/// (open/closed hand), GTK/Linux, and CSS `grab`/`grabbing` on the web - so
/// they keep the real cursor.
bool get _grabCursorUnsupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// [SystemMouseCursors.grab], or a visible stand-in on platforms that don't
/// render it (see [_grabCursorUnsupported]).
MouseCursor get grabCursor =>
    _grabCursorUnsupported ? SystemMouseCursors.move : SystemMouseCursors.grab;

/// [SystemMouseCursors.grabbing], or a visible stand-in on platforms that don't
/// render it (see [_grabCursorUnsupported]).
MouseCursor get grabbingCursor => _grabCursorUnsupported
    ? SystemMouseCursors.move
    : SystemMouseCursors.grabbing;
