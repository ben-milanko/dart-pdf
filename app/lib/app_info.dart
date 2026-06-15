import 'package:package_info_plus/package_info_plus.dart';

/// Static product identity, surfaced in the About box.
///
/// [version] is loaded from the build artifact by [load] (called once at
/// startup), so it always matches the version stamped into the release from
/// `app/pubspec.yaml` — no hardcoded constant to drift. The fallback below is
/// only used if [load] hasn't run or `PackageInfo` is unavailable.
class AppInfo {
  static const name = 'DartPDF';
  static const tagline = 'A fully native Flutter PDF editor';
  static const sourceUrl = 'https://github.com/ben-milanko/dart-pdf';

  static String version = '1.1.0';

  /// Populates [version] from the platform package metadata. Best-effort: any
  /// failure leaves the fallback in place.
  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) version = info.version;
    } catch (_) {
      // Keep the fallback; the About box is non-critical.
    }
  }
}
