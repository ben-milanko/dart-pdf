import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// The reusable parts of a visible signature - the hand-drawn mark and the
/// logo backdrop - remembered on the device so the next signature can reuse
/// them without redrawing or re-picking.
class SignatureAppearanceConfig {
  const SignatureAppearanceConfig({this.signaturePng, this.logoBytes});

  /// The hand-drawn mark, as PNG bytes (rendered into the box's left panel).
  final Uint8List? signaturePng;

  /// The logo backdrop, as the picked PNG/JPEG bytes.
  final Uint8List? logoBytes;

  bool get isEmpty => signaturePng == null && logoBytes == null;
}

/// Persists a [SignatureAppearanceConfig] on the device.
abstract class SignatureAppearanceStore {
  Future<SignatureAppearanceConfig> load();
  Future<void> save(SignatureAppearanceConfig config);
}

/// A [SignatureAppearanceStore] backed by shared_preferences, storing the
/// images as base64 blobs. Small (a signature mark and a logo), so plain
/// preferences are fine.
class PrefsSignatureAppearanceStore implements SignatureAppearanceStore {
  static const _signatureKey = 'digitalSignature.mark.png';
  static const _logoKey = 'digitalSignature.logo';

  @override
  Future<SignatureAppearanceConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    Uint8List? read(String key) {
      final value = prefs.getString(key);
      if (value == null) return null;
      try {
        return base64Decode(value);
      } catch (_) {
        return null;
      }
    }

    return SignatureAppearanceConfig(
      signaturePng: read(_signatureKey),
      logoBytes: read(_logoKey),
    );
  }

  @override
  Future<void> save(SignatureAppearanceConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    Future<void> write(String key, Uint8List? bytes) => bytes == null
        ? prefs.remove(key)
        : prefs.setString(key, base64Encode(bytes));
    await write(_signatureKey, config.signaturePng);
    await write(_logoKey, config.logoBytes);
  }
}

/// An in-memory [SignatureAppearanceStore] for tests.
class InMemorySignatureAppearanceStore implements SignatureAppearanceStore {
  SignatureAppearanceConfig _config = const SignatureAppearanceConfig();

  @override
  Future<SignatureAppearanceConfig> load() async => _config;

  @override
  Future<void> save(SignatureAppearanceConfig config) async =>
      _config = config;
}
