import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Preview-style trackpad signatures on macOS: the runner's
/// `TrackpadSignatureCapture` (MainFlutterWindow.swift) lays a touch-taking
/// view over the key window, parks and hides the cursor, and streams the
/// drawing finger's absolute position on the trackpad until a key is pressed.
class MacTrackpadSignatureCapture implements PdfTrackpadSignatureCapture {
  const MacTrackpadSignatureCapture();

  static const _channel =
      EventChannel('dev.milanko.dartpdf/trackpad_signature');

  /// Installs the capture as [PdfTrackpadSignatureCapture.platform] on macOS;
  /// everywhere else the signature pad keeps its pointer-only drawing.
  static void installIfSupported() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    PdfTrackpadSignatureCapture.platform = const MacTrackpadSignatureCapture();
  }

  @override
  Stream<PdfTrackpadSignatureEvent> capture() => _channel
      .receiveBroadcastStream()
      .map(decodeEvent)
      .where((event) => event != null)
      .cast<PdfTrackpadSignatureEvent>();

  /// Parses one channel message; null for anything malformed.
  @visibleForTesting
  static PdfTrackpadSignatureEvent? decodeEvent(Object? raw) {
    if (raw is! Map) return null;
    final phase = switch (raw['phase']) {
      'down' => PdfTrackpadSignaturePhase.down,
      'move' => PdfTrackpadSignaturePhase.move,
      'up' => PdfTrackpadSignaturePhase.up,
      'finish' => PdfTrackpadSignaturePhase.finish,
      _ => null,
    };
    if (phase == null) return null;
    final x = raw['x'], y = raw['y'];
    return PdfTrackpadSignatureEvent(
      phase,
      x: x is num ? x.toDouble() : 0,
      y: y is num ? y.toDouble() : 0,
    );
  }
}
