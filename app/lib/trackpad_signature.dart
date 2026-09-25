import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Preview-style trackpad signatures, backed by the native runners, which
/// stream the drawing finger's absolute position on the trackpad while the
/// cursor is parked:
///
/// - macOS: `TrackpadSignatureCapture.swift` (indirect `NSTouch`es on an
///   overlay over the key window);
/// - Windows: `trackpad_signature.cpp` (Precision Touchpad HID reports via
///   raw input);
/// - Android: `TrackpadSignatureCapture.kt` (pointer capture, which turns a
///   touchpad into absolute `SOURCE_TOUCHPAD` events).
///
/// Linux, the web, and iPadOS expose no absolute touchpad positions to an
/// app, so the signature pad keeps its pointer-only drawing there.
class PlatformTrackpadSignatureCapture extends PdfTrackpadSignatureCapture {
  PlatformTrackpadSignatureCapture();

  static const _events = EventChannel('dev.milanko.dartpdf/trackpad_signature');
  static const _support =
      MethodChannel('dev.milanko.dartpdf/trackpad_signature_support');

  /// Installs the capture as [PdfTrackpadSignatureCapture.platform] on the
  /// platforms whose runner implements it.
  static void installIfSupported() {
    if (kIsWeb) return;
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS ||
            TargetPlatform.windows ||
            TargetPlatform.android:
        PdfTrackpadSignatureCapture.platform =
            PlatformTrackpadSignatureCapture();
      case _:
    }
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return await _support.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Stream<PdfTrackpadSignatureEvent> capture() => _events
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
