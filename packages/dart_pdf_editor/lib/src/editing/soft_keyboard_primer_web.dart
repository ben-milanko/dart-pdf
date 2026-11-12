import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

web.HTMLInputElement? _primer;
Timer? _primerTimeout;
Timer? _touchEndFallback;
JSFunction? _onTouchEnd;

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
/// With [atTouchEnd] (a touch lift, called from its `pointerup`), the focus
/// waits for that touch's `touchend`: the device log showed a focus made in
/// `pointerup` taking focus but raising no keyboard, while `touchend` is the
/// event WebKit reliably treats as the user's gesture. Until then, any other
/// prime (the editor opening inside the same dispatch) defers to it, since a
/// second `focus()` on the already-focused input would be a no-op.
///
/// The primer removes itself as soon as it loses focus, and blurs itself if
/// nothing has taken over within a second (an editor that never opened).
void pdfPrimeSoftKeyboard({bool atTouchEnd = false}) {
  final input = _primer ??= _createPrimer();
  // Inside the flutter-view, not beside it: when the framework then focuses
  // its own node, the engine only moves DOM focus to the view element if
  // nothing in the view holds it. With the primer outside, that focus()
  // landed on the view element first and closed the keyboard before
  // Flutter's textarea could take it over.
  final host = web.document.querySelector('flutter-view') ?? web.document.body;
  if (!input.isConnected || input.parentElement != host) host?.append(input);
  if (atTouchEnd) {
    _cancelTouchEnd();
    final onTouchEnd = ((web.Event _) => _focusPrimer(input)).toJS;
    _onTouchEnd = onTouchEnd;
    web.window.addEventListener(
        'touchend', onTouchEnd, web.AddEventListenerOptions(capture: true));
    // a lift that arrives without a touchend (none should) still primes
    _touchEndFallback =
        Timer(const Duration(milliseconds: 250), () => _focusPrimer(input));
    return;
  }
  // the touch's own touchend focuses it - focusing now would spend that
  if (_onTouchEnd != null) return;
  _focusPrimer(input);
}

void _cancelTouchEnd() {
  _touchEndFallback?.cancel();
  _touchEndFallback = null;
  final listener = _onTouchEnd;
  if (listener == null) return;
  web.window.removeEventListener(
      'touchend', listener, web.EventListenerOptions(capture: true));
  _onTouchEnd = null;
}

void _focusPrimer(web.HTMLInputElement input) {
  _cancelTouchEnd();
  if (!input.isConnected) return;
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
