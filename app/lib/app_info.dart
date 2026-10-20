import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'build_channel.dart';

/// Static product identity, surfaced in the About box.
///
/// [version] is loaded from the build artifact by [load] (called once at
/// startup), so it always matches the version stamped into the release from
/// `app/pubspec.yaml` - no hardcoded constant to drift. The fallback below is
/// only used if [load] hasn't run or `PackageInfo` is unavailable.
class AppInfo {
  static const name = 'DartPDF';
  static const tagline = 'A fully native Flutter PDF editor';
  static const sourceUrl = 'https://github.com/ben-milanko/dart-pdf';

  /// Where the About box sends feedback: the GitHub "App feedback" issue
  /// form, and an email address for users without a GitHub account.
  static const feedbackIssueUrl =
      '$sourceUrl/issues/new?template=app_feedback.yml';
  static const feedbackEmail = 'ben.milanko@protonmail.com';

  /// A `mailto:` link to [feedbackEmail], its subject naming the build so a
  /// report says which version it is about. Encoded by hand: [Uri]'s
  /// `queryParameters` writes spaces as `+`, which mail clients show as-is.
  static Uri feedbackMailto() => Uri.parse('mailto:$feedbackEmail?subject='
      '${Uri.encodeComponent('$displayName $displayVersion feedback')}');

  /// [name] as the running build presents it: `DartPDF Nightly` for the
  /// rolling nightly, so it is never mistaken for a stable install.
  static const displayName = kProductDisplayName;

  /// Release channel from `PDF_BUILD_CHANNEL` (`stable` unless CI says
  /// otherwise).
  static const buildChannel = kBuildChannel;
  static const isNightly = kIsNightlyBuild;

  /// Git commit supplied by CI through `--dart-define=PDF_BUILD_COMMIT=...`.
  /// Release builds without the define stay honest rather than inventing one.
  static const buildCommit =
      String.fromEnvironment('PDF_BUILD_COMMIT', defaultValue: 'unknown');

  static String version = '1.4.1';

  /// Build number from the same artifact (`+18` in `2.0.0+18`). Empty when
  /// unavailable. Kept separate from [version] because two builds of one
  /// version are otherwise indistinguishable in a diagnostics export.
  static String buildNumber = '';

  /// The version as shown to the user. Every nightly shares the package
  /// version of the release it is heading towards, so a nightly adds its
  /// source commit to tell one night's build from the next.
  static String get displayVersion => formatDisplayVersion(
        version: version,
        nightly: isNightly,
        commit: buildCommit,
      );

  /// [displayVersion] for an explicit channel and commit, so both channels
  /// are testable from one compiled build.
  @visibleForTesting
  static String formatDisplayVersion({
    required String version,
    required bool nightly,
    required String commit,
  }) {
    if (!nightly) return version;
    final short = commit.length > 7 ? commit.substring(0, 7) : commit;
    return short.isEmpty || short == 'unknown'
        ? '$version nightly'
        : '$version nightly ($short)';
  }

  /// Populates [version] from the platform package metadata. Best-effort: any
  /// failure leaves the fallback in place.
  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) version = info.version;
      buildNumber = info.buildNumber;
    } catch (_) {
      // Keep the fallback; the About box is non-critical.
    }
  }
}
