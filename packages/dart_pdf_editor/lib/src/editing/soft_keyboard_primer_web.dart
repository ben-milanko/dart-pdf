import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

web.HTMLInputElement? _primer;
Timer? _primerTimeout;

/// Focuses a hidden input while the current tap is still being handled, so
/// iOS Safari (and every iOS browser, which are all WebKit) raises the soft
/// keyboard for a text editor that only takes focus a frame later.
///
/// WebKit shows the keyboard only for a `focus()` made inside a user
/// gesture. The in-page editors are built by the tap and focused in a
/// post-frame callback, after the gesture has ended, so their focus brings
/// up no keyboard. Once an input holds focus with the keyboard up, though,
/// moving focus to another input keeps it up - so this input catches the
/// keyboard and Flutter's own text input takes it over when it focuses.
///
/// The primer removes itself as soon as it loses focus, and blurs itself if
/// nothing has taken over within a second (an editor that never opened).
void pdfPrimeSoftKeyboard() {
  final input = _primer ??= _createPrimer();
  if (!input.isConnected) web.document.body?.append(input);
  input.focus(web.FocusOptions(preventScroll: true));
  _primerTimeout?.cancel();
  _primerTimeout = Timer(const Duration(seconds: 1), () {
    if (web.document.activeElement == input) input.blur();
    input.remove();
  });
}

web.HTMLInputElement _createPrimer() {
  final input = web.HTMLInputElement()
    ..type = 'text'
    ..tabIndex = -1
    ..setAttribute('aria-hidden', 'true')
    ..setAttribute('autocomplete', 'off');
  // pinned to the viewport corner so focusing it scrolls nothing; 16px keeps
  // iOS from zooming the page in on focus; transparent and inert to pointers
  input.style.cssText = 'position:fixed;top:0;left:0;width:1px;height:1px;'
      'margin:0;padding:0;border:0;opacity:0;font-size:16px;'
      'pointer-events:none;';
  input.addEventListener(
      'blur',
      ((web.Event _) {
        _primerTimeout?.cancel();
        input.remove();
      }).toJS);
  return input;
}
