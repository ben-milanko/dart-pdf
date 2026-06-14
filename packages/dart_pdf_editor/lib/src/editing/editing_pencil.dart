import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'editing_controller.dart';

/// Bridges the Apple Pencil's hardware double-tap gesture to an editing
/// action — by default toggling the eraser on the attached controller.
///
/// Flutter exposes no framework event for the pencil's double-tap (or the
/// Apple Pencil Pro squeeze); it is an iOS [UIPencilInteraction] that lives
/// outside the engine. The host app registers that interaction natively and
/// forwards each gesture over the shared [channel] (see the iOS runner in the
/// example/app), and this listens on the Dart side and routes it to
/// [PdfEditingController.togglePencilEraser]. The [PdfEditorView] shell
/// attaches one automatically on iOS, so consumers usually never touch this
/// class directly.
///
/// Only one handler can listen on a [MethodChannel] at a time, so attaching a
/// second binding (or any other listener on the same channel name) replaces
/// the first. Typical single-editor apps have exactly one, so this is a
/// non-issue; [dispose] clears the handler.
class PdfPencilInteraction {
  /// Creates a binding. [onDoubleTap], when supplied, runs on every gesture
  /// instead of the default eraser toggle — pass it to map the pencil's
  /// double-tap to a custom action.
  PdfPencilInteraction({this.onDoubleTap});

  /// The method channel the native side invokes. The host registers a
  /// `UIPencilInteraction` whose delegate calls the `pencilDoubleTap` method
  /// on a `FlutterMethodChannel` with this name.
  static const MethodChannel channel =
      MethodChannel('dart_pdf_editor/pencil');

  /// The method name the native side invokes for a double-tap.
  static const String doubleTapMethod = 'pencilDoubleTap';

  /// Runs on every pencil double-tap when set; otherwise the attached
  /// controller's eraser is toggled.
  final VoidCallback? onDoubleTap;

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
      if (onDoubleTap != null) {
        onDoubleTap!();
      } else {
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
