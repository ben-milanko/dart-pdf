// Phone-reader chrome that gets out of the way: on a compact layout the
// header and the docked toolbar slide off while the reader scrolls on
// through the document, and come back on a scroll back or a tap on the page
// - the behaviour readers expect from mobile PDF apps. Widgets-layer only.

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

/// How far (logical pixels) a user scroll has to travel in one direction
/// before the chrome follows it - enough that the small drift of a tap or a
/// page-settle never flickers the bars.
const double pdfChromeAutoHideTravel = 24;

/// Whether the shell's chrome (header, docked toolbar) is showing on a
/// compact layout. The shells own one and feed it the viewer's scroll
/// notifications ([handleScrollNotification]) and plain taps ([toggle]);
/// [PdfAutoHideBar] animates a bar in and out from it.
///
/// Only *user* scrolling moves it: a jump from the page field, a search hit
/// or a bookmark scrolls programmatically and leaves the chrome alone.
class PdfChromeAutoHide extends ChangeNotifier {
  bool _shown = true;
  bool _pinned = false;
  bool _userScrolling = false;
  double _travel = 0;

  /// Whether the chrome should be on screen.
  bool get visible => _shown || _pinned;

  /// Holds the chrome on screen - while a tool is armed, something is
  /// selected, a sheet is open: anything the chrome is needed for. Unpinning
  /// leaves it showing. Set during the owner's build (the bars read it in
  /// the same build), so it does not notify.
  bool get pinned => _pinned;
  set pinned(bool value) {
    if (value == _pinned) return;
    _pinned = value;
    if (value) {
      _shown = true;
      _travel = 0;
    }
  }

  /// Brings the chrome back.
  void show() => _set(true);

  /// Slides the chrome away, unless it is [pinned].
  void hide() => _set(false);

  /// What a tap on the page does: hides the chrome when it shows and brings
  /// it back when it doesn't.
  void toggle() => _set(!visible);

  void _set(bool shown) {
    _travel = 0;
    if (_pinned) shown = true;
    if (shown == _shown) return;
    _shown = shown;
    notifyListeners();
  }

  /// Feed the viewer's scroll notifications through here: a user scroll
  /// forward through the document hides the chrome, one back brings it
  /// back. Always returns false so the notification keeps bubbling.
  bool handleScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      _userScrolling = notification.direction != ScrollDirection.idle;
      _travel = 0;
    } else if (notification is ScrollUpdateNotification && _userScrolling) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;
      // a change of direction starts the count again
      if (delta.sign != _travel.sign) _travel = 0;
      _travel += delta;
      if (_travel > pdfChromeAutoHideTravel) {
        hide();
      } else if (_travel < -pdfChromeAutoHideTravel) {
        show();
      }
    }
    return false;
  }
}

/// A bar that slides off its [edge] when [controller] hides the chrome.
/// With [enabled] false (a wide layout, or the feature off) it is just
/// [child].
///
/// The bar collapses rather than floating over the content, so the viewer
/// grows into the space it gives up and nothing is ever hidden behind it. A
/// top bar keeps the status-bar inset ([MediaQuery.paddingOf]) as it goes,
/// so the page never runs under the clock and battery icons.
class PdfAutoHideBar extends StatefulWidget {
  const PdfAutoHideBar({
    super.key,
    required this.controller,
    required this.edge,
    required this.child,
    this.enabled = true,
  });

  final PdfChromeAutoHide controller;

  /// [AxisDirection.up] for a header, [AxisDirection.down] for a bottom
  /// toolbar.
  final AxisDirection edge;

  final bool enabled;

  final Widget child;

  static const duration = Duration(milliseconds: 200);

  @override
  State<PdfAutoHideBar> createState() => _PdfAutoHideBarState();
}

class _PdfAutoHideBarState extends State<PdfAutoHideBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: PdfAutoHideBar.duration,
    value: _target ? 1 : 0,
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _shown, curve: Curves.easeOutCubic);

  /// Whether focus is inside the bar - the search field or the page number
  /// being typed into. A bar never slides away from under the keyboard.
  bool _focused = false;

  bool get _target => !widget.enabled || widget.controller.visible || _focused;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
  }

  @override
  void didUpdateWidget(PdfAutoHideBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
    }
    // the owner may have pinned the chrome (or left compact) in this build
    _sync();
  }

  void _sync() {
    if (!widget.enabled) {
      // a wide layout has no animation to wait for
      _shown.value = 1;
    } else if (_target) {
      _shown.forward();
    } else {
      _shown.reverse();
    }
  }

  void _onFocusChange(bool focused) {
    if (focused == _focused) return;
    _focused = focused;
    _sync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A wide layout's bar is just its child: the shells rebuild their header
    // on every preference tick, and nothing here would ever move. (Crossing
    // the compact breakpoint remounts the bar's subtree; the search text and
    // page field live in shell-owned controllers, so nothing is lost.)
    if (!widget.enabled) return widget.child;
    final top = widget.edge == AxisDirection.up;
    final inset = top ? MediaQuery.paddingOf(context).top : 0.0;
    final child = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _onFocusChange,
      child: widget.child,
    );
    // One tree shape at every value: a wrapper that came and went would
    // remount the bar, dropping the search field's text and focus.
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: inset * (1 - t)),
            ClipRect(
              child: Align(
                // the bar keeps whatever is left of its far edge: a header
                // slides up and out, a bottom toolbar down and out
                alignment: top ? Alignment.bottomCenter : Alignment.topCenter,
                heightFactor: t,
                // a bar on its way out takes no taps, and a hidden one no
                // focus traversal
                child: IgnorePointer(
                  ignoring: t < 1 && !_target,
                  child: ExcludeFocus(excluding: t == 0, child: child!),
                ),
              ),
            ),
          ],
        );
      },
      child: child,
    );
  }
}
