import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'editing_controller.dart';

/// The double-tap action the user selected in iOS Settings → Apple Pencil,
/// reported by `UIPencilInteraction.preferredTapAction`. The native side
/// forwards it with every gesture so the Dart policy — not the runner —
/// decides what to do, honoring the user's choice (notably [ignore], when
/// they turn the gesture off).
enum PdfPencilTapAction {
  /// The user turned the double-tap off — do nothing.
  ignore,

  /// Switch between the current tool and the eraser.
  switchEraser,

  /// Switch between the current tool and the last-used one.
  switchPrevious,

  /// Show the color palette.
  showColorPalette,

  /// Show the ink-attributes / tool palette.
  showInkAttributes,

  /// Run a system shortcut.
  runSystemShortcut,

  /// No preference reported — an older iOS, the system default, or a
  /// legacy call with no action attached. Treated as a tool switch so the
  /// gesture still works out of the box.
  unspecified;

  /// Parses the name the native side sends; unknown/absent names map to
  /// [unspecified].
  static PdfPencilTapAction fromName(String? name) => switch (name) {
        'ignore' => ignore,
        'switchEraser' => switchEraser,
        'switchPrevious' => switchPrevious,
        'showColorPalette' => showColorPalette,
        'showInkAttributes' => showInkAttributes,
        'runSystemShortcut' => runSystemShortcut,
        _ => unspecified,
      };

  /// Whether the default binding toggles the eraser for this action — true
  /// for the tool-switch actions ([switchEraser], [switchPrevious]) and
  /// [unspecified], false for [ignore] and the palette/shortcut actions this
  /// editor doesn't implement. Not hijacking those into an eraser toggle is
  /// how the user's non-eraser choice is honored.
  bool get togglesEraser =>
      this == switchEraser || this == switchPrevious || this == unspecified;
}

/// Runs on every Apple Pencil double-tap, carrying the user's preferred
/// action so a host can fully override the default eraser toggle.
typedef PdfPencilTapHandler = void Function(PdfPencilTapAction action);

/// Bridges the Apple Pencil's hardware double-tap gesture to an editing
/// action — by default toggling the eraser on the attached controller, but
/// only when the user's iOS setting asks for a tool switch.
///
/// Flutter exposes no framework event for the pencil's double-tap (or the
/// Apple Pencil Pro squeeze); it is an iOS [UIPencilInteraction] that lives
/// outside the engine. The host app registers that interaction natively and
/// forwards each gesture — together with the user's
/// `UIPencilInteraction.preferredTapAction` — over the shared [channel] (see
/// the iOS runner in the example/app). This listens on the Dart side and,
/// unless an [onDoubleTap] override is given, routes a tool-switch action to
/// [PdfEditingController.togglePencilEraser] while leaving the user's other
/// choices (off / show palette) alone. The [PdfEditorView] shell attaches one
/// automatically on iOS, so consumers usually never touch this class directly.
///
/// Only one handler can listen on a [MethodChannel] at a time, so attaching a
/// second binding (or any other listener on the same channel name) replaces
/// the first. Typical single-editor apps have exactly one, so this is a
/// non-issue; [dispose] clears the handler.
class PdfPencilInteraction {
  /// Creates a binding. [onDoubleTap], when supplied, runs on every gesture
  /// (receiving the user's [PdfPencilTapAction]) instead of the default
  /// policy — pass it to map the pencil's double-tap to a custom action.
  PdfPencilInteraction({this.onDoubleTap});

  /// The method channel the native side invokes. The host registers a
  /// `UIPencilInteraction` whose delegate calls the `pencilDoubleTap` method
  /// on a `FlutterMethodChannel` with this name, passing
  /// `{'preferredAction': <name>}`.
  static const MethodChannel channel =
      MethodChannel('dart_pdf_editor/pencil');

  /// The method name the native side invokes for a double-tap.
  static const String doubleTapMethod = 'pencilDoubleTap';

  /// Runs on every pencil double-tap when set, fully replacing the default
  /// eraser-toggle policy (so the host owns honoring [PdfPencilTapAction]).
  final PdfPencilTapHandler? onDoubleTap;

  PdfEditingController? _controller;
  bool _listening = false;

  /// Whether this binding currently holds the channel's handler.
  bool get isAttached => _listening;

  /// Starts listening, routing double-taps to [controller] (ignored when an
  /// [onDoubleTap] was given). Idempotent; calling it again just switches the
  /// target controller.
  void attach(PdfEditingController controller) {
    _controller = controller;
    if (_listening) return;
    _listening = true;
    channel.setMethodCallHandler(handleMethodCall);
  }

  /// The channel handler. Exposed for tests; hosts call [attach] instead.
  @visibleForTesting
  Future<Object?> handleMethodCall(MethodCall call) async {
    if (call.method == doubleTapMethod) {
      final args = call.arguments;
      final action = PdfPencilTapAction.fromName(
          args is Map ? args['preferredAction'] as String? : null);
      if (onDoubleTap != null) {
        onDoubleTap!(action);
      } else if (action.togglesEraser) {
        _controller?.togglePencilEraser();
      }
    }
    return null;
  }

  /// Stops listening and drops the controller reference. Safe to call when
  /// never attached.
  void dispose() {
    _controller = null;
    if (!_listening) return;
    _listening = false;
    channel.setMethodCallHandler(null);
  }
}
