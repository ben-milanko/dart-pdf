import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'devtools.dart';

/// The rolling GitHub prerelease populated by the nightly Windows workflow.
const dartPdfNightlyTag = 'app-nightly';

/// A parsed semantic version (`major.minor.patch`), tolerant of the leading
/// `app-v` / `v` that the release tags carry, an optional `+build` metadata
/// suffix (ignored for ordering, per semver), and an optional `-prerelease`
/// label (a release *without* one always ranks above the same numbers *with*
/// one). Returns null from [tryParse] for anything it can't read, so callers
/// can degrade gracefully rather than crash on a malformed tag.
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, {this.preRelease});

  final int major;
  final int minor;
  final int patch;

  /// The `-foo.1` label without its leading dash, or null for a final release.
  final String? preRelease;

  static final _pattern = RegExp(
    r'^(?:app-)?v?'
    r'(\d+)\.(\d+)(?:\.(\d+))?'
    r'(?:-([0-9A-Za-z.-]+))?'
    r'(?:\+[0-9A-Za-z.-]+)?$',
  );

  static AppVersion? tryParse(String raw) {
    final match = _pattern.firstMatch(raw.trim());
    if (match == null) return null;
    final pre = match.group(4);
    return AppVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3) ?? '0'),
      preRelease: (pre == null || pre.isEmpty) ? null : pre,
    );
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // Equal numbers: a final release outranks a pre-release of the same number.
    if (preRelease == null && other.preRelease == null) return 0;
    if (preRelease == null) return 1;
    if (other.preRelease == null) return -1;
    return preRelease!.compareTo(other.preRelease!);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch &&
      other.preRelease == preRelease;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() {
    final base = '$major.$minor.$patch';
    return preRelease == null ? base : '$base-$preRelease';
  }
}

/// A GitHub release of the standalone app, parsed down to the fields the
/// updater needs: the version, where to read the notes, and the per-platform
/// download URLs keyed by asset file name.
@immutable
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.name,
    required this.notes,
    required this.htmlUrl,
    required this.assets,
    this.assetSizes = const {},
    this.isNightly = false,
    this.commitSha,
  });

  final AppVersion version;
  final String tagName;
  final String name;
  final String notes;
  final String htmlUrl;

  /// Asset file name → `browser_download_url`.
  final Map<String, String> assets;

  /// Asset file name → byte size, from the GitHub release metadata. Used to
  /// verify an in-app update download landed complete (a truncated download
  /// is rejected rather than written over the running install).
  final Map<String, int> assetSizes;

  /// Whether this is the rolling build produced from the tip of `main`.
  final bool isNightly;

  /// Source commit recorded by the nightly workflow, when present.
  final String? commitSha;

  /// Human-readable build label for update banners and buttons.
  String get displayVersion {
    if (!isNightly) return version.toString();
    final sha = commitSha;
    final shortSha = sha?.substring(0, sha.length < 7 ? sha.length : 7);
    return shortSha == null || shortSha.isEmpty
        ? 'nightly'
        : 'nightly ($shortSha)';
  }

  /// Stable identity used by "Later". A rolling tag alone is insufficient:
  /// every nightly shares `app-nightly`, so include its source commit.
  String get identity =>
      isNightly && commitSha != null ? '$tagName@$commitSha' : tagName;

  static final _nightlyCommitMarker =
      RegExp(r'<!-- main-sha: ([0-9a-fA-F]{7,40}) -->');
  static final _nightlyVersionMarker =
      RegExp(r'<!-- app-version: ([0-9A-Za-z.+-]+) -->');

  /// Builds a release from one element of the GitHub `/releases` array,
  /// returning null when the tag isn't a parseable version (so non-app tags
  /// and malformed entries are simply skipped).
  static ReleaseInfo? fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String?;
    if (tag == null) return null;
    final notes = (json['body'] as String?)?.trim() ?? '';
    final isNightly = tag == dartPdfNightlyTag;
    final version = AppVersion.tryParse(tag) ??
        (isNightly
            ? AppVersion.tryParse(
                _nightlyVersionMarker.firstMatch(notes)?.group(1) ?? '')
            : null);
    if (version == null) return null;
    final commitSha =
        _nightlyCommitMarker.firstMatch(notes)?.group(1)?.toLowerCase();
    final assets = <String, String>{};
    final assetSizes = <String, int>{};
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final asset in rawAssets) {
        if (asset is! Map) continue;
        final name = asset['name'];
        final url = asset['browser_download_url'];
        if (name is String && url is String) {
          assets[name] = url;
          final size = asset['size'];
          if (size is int && size > 0) assetSizes[name] = size;
        }
      }
    }
    return ReleaseInfo(
      version: version,
      tagName: tag,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : tag,
      notes: notes,
      htmlUrl: (json['html_url'] as String?) ?? '',
      assets: assets,
      assetSizes: assetSizes,
      isNightly: isNightly,
      commitSha: commitSha,
    );
  }
}

/// Where an update check stands. Drives both the Settings UI and the
/// startup banner.
enum UpdateStatus {
  /// No check has run yet.
  idle,

  /// A check is in flight.
  checking,

  /// The running build is the newest released.
  upToDate,

  /// A newer release exists ([UpdateService.latest] holds it).
  updateAvailable,

  /// The check failed (offline, rate-limited, malformed response).
  failed,
}

/// Returns the releases for the repository, newest first. Injected in tests to
/// avoid real network; production uses [UpdateService]'s GitHub fetcher.
typedef ReleaseFetcher = Future<List<ReleaseInfo>> Function();

/// Checks GitHub Releases for a newer standalone-app build and exposes the
/// result as a [ChangeNotifier] so the Settings panel and the startup banner
/// can both react.
///
/// This is deliberately a *checker*, not a silent binary-replacer: the app
/// ships unsigned desktop bundles and store builds that update through their
/// own channels, so the safe, honest action is to point the user at the right
/// download. [downloadUrl] resolves to the artifact for the current platform
/// (falling back to the release page).
///
/// Mirrors [RecentsStore]'s graceful degradation: when `shared_preferences`
/// is unavailable (widget tests) the throttle/dismissal state simply lives in
/// memory, so the UI stays deterministic with no mocking.
class UpdateService extends ChangeNotifier {
  UpdateService({
    required this.currentVersion,
    this.currentBuildCommit = 'unknown',
    this.repoOwner = 'ben-milanko',
    this.repoName = 'dart-pdf',
    this.tagPrefix = 'app-v',
    this.nightlyTag = dartPdfNightlyTag,
    ReleaseFetcher? fetcher,
    http.Client Function()? clientFactory,
    Duration checkInterval = const Duration(hours: 24),
    DateTime Function() now = DateTime.now,
    TargetPlatform? platform,
  })  : _fetcher = fetcher,
        _clientFactory = clientFactory ?? http.Client.new,
        _checkInterval = checkInterval,
        _now = now,
        _platform = platform {
    _restored = _restore();
  }

  /// The running build's version (from `AppInfo.version`). Mutable so the host
  /// can refresh it once `package_info` resolves the real build version, in
  /// case the service was built against the compile-time fallback.
  String currentVersion;

  /// Git commit stamped into the running binary with `PDF_BUILD_COMMIT`.
  /// Nightly builds use this to avoid offering the exact build already
  /// installed even though every nightly shares one rolling release tag.
  final String currentBuildCommit;

  final String repoOwner;
  final String repoName;

  /// Only releases whose tag starts with this prefix are considered, so the
  /// per-package pub.dev release tags in the same repo are ignored.
  final String tagPrefix;

  /// Exact tag of the rolling nightly prerelease.
  final String nightlyTag;

  final ReleaseFetcher? _fetcher;
  final http.Client Function() _clientFactory;
  final Duration _checkInterval;
  final DateTime Function() _now;
  final TargetPlatform? _platform;

  static const _lastCheckedKey = 'dart_pdf_editor_app.update.lastChecked';
  static const _dismissedKey = 'dart_pdf_editor_app.update.dismissedTag';
  static const _nightlyKey = 'dart_pdf_editor_app.update.nightly';

  UpdateStatus _status = UpdateStatus.idle;
  UpdateStatus get status => _status;

  ReleaseInfo? _latest;

  /// The newest release found by the last check: the available update when
  /// [status] is [UpdateStatus.updateAvailable], otherwise the current
  /// release (for display) when known.
  ReleaseInfo? get latest => _latest;

  Object? _error;
  Object? get error => _error;

  DateTime? _lastChecked;
  DateTime? get lastChecked => _lastChecked;

  String? _dismissedTag;
  bool _nightlyUpdates = false;
  Future<void> _restored = Future.value();

  /// Completes when persisted throttle, dismissal, and channel state is ready.
  Future<void> get ready => _restored;

  TargetPlatform get _targetPlatform => _platform ?? defaultTargetPlatform;

  /// Whether update checks make sense on this platform.
  ///
  /// Only the desktop builds are distributed as direct downloads from GitHub
  /// Releases, so only they benefit from a "newer build available, download it"
  /// nudge. Two platforms opt out:
  ///
  /// * The web build is always served fresh (and an installed PWA refreshes
  ///   through its service worker), so there is nothing to check.
  /// * The Android/iOS builds update through their app stores, and a GitHub
  ///   release routinely lands *before* the store review clears. Checking
  ///   GitHub there would nag mobile users about a version they can't install
  ///   yet, and the "Download" button would only send them to a GitHub page
  ///   that isn't their update channel - exactly the confusing dead end we
  ///   want to avoid.
  ///
  /// This is an instance getter (not static) so the injected [platform] is
  /// honoured and the gate is testable.
  bool get supported {
    if (kIsWeb) return false;
    return switch (_targetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };
  }

  /// Whether this platform has a nightly artifact and can opt into the channel.
  bool get nightlySupported =>
      supported && _targetPlatform == TargetPlatform.windows;

  /// Whether rolling builds from `main` participate in update checks.
  bool get nightlyUpdates => _nightlyUpdates && nightlySupported;

  /// Switches update channel and clears the cross-channel throttle so the new
  /// channel can be checked immediately. The Settings UI follows this with a
  /// forced check; startup checks pick up the persisted value through [ready].
  Future<void> setNightlyUpdates(bool value) async {
    await _restored;
    final enabled = value && nightlySupported;
    if (enabled == _nightlyUpdates) return;
    _nightlyUpdates = enabled;
    _status = UpdateStatus.idle;
    _latest = null;
    _error = null;
    _lastChecked = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_nightlyKey, enabled);
      await prefs.remove(_lastCheckedKey);
    } catch (_) {
      // No storage - keep the in-memory choice for this session.
    }
  }

  AppVersion? get _current => AppVersion.tryParse(currentVersion);

  /// True when a strictly newer release was found.
  bool get updateAvailable =>
      _status == UpdateStatus.updateAvailable && _latest != null;

  /// True when the user should be nudged about [latest]: an update is available
  /// and they haven't already dismissed this exact release.
  bool get shouldNotify =>
      updateAvailable && _latest!.identity != _dismissedTag;

  /// The GitHub endpoint used by the default fetcher.
  Uri get releasesUri => Uri.https(
        'api.github.com',
        '/repos/$repoOwner/$repoName/releases',
        const {'per_page': '30'},
      );

  /// Direct endpoint for the rolling release. GitHub orders `/releases` by
  /// creation time, not by later asset/body edits, so a long-lived rolling
  /// release eventually falls out of the first page unless fetched by tag.
  Uri get nightlyReleaseUri => Uri.https(
        'api.github.com',
        '/repos/$repoOwner/$repoName/releases/tags/$nightlyTag',
      );

  /// The best download URL for [latest] on the current platform: the matching
  /// release asset when there is one, else the release page (a desktop build
  /// with no direct artifact falls back to the page). Only resolved on the
  /// desktop platforms where updates are [supported].
  String? get downloadUrl {
    final release = _latest;
    if (release == null) return null;
    final name = _platformAssetName(release.assets);
    final asset = name == null ? null : release.assets[name];
    return asset ?? (release.htmlUrl.isEmpty ? null : release.htmlUrl);
  }

  /// The file name of the platform artifact for [latest], or null when there
  /// is no direct artifact (so only the release page is available). The
  /// in-app installer needs the name to decide how to apply the update and
  /// where to stage the download.
  String? get downloadAssetName {
    final release = _latest;
    if (release == null) return null;
    return _platformAssetName(release.assets);
  }

  /// The expected byte size of [downloadAssetName], when GitHub reported one,
  /// for verifying an in-app download landed complete.
  int? get downloadAssetSize {
    final release = _latest;
    final name = downloadAssetName;
    if (release == null || name == null) return null;
    return release.assetSizes[name];
  }

  /// Queries GitHub for a newer release. Throttled to [_checkInterval] unless
  /// [force] is set (the Settings "Check now" button forces). Never throws -
  /// failures land in [status]/[error].
  Future<void> checkForUpdates({bool force = false}) async {
    if (!supported || _status == UpdateStatus.checking) return;
    await _restored;
    if (!force && _withinThrottle()) return;

    _status = UpdateStatus.checking;
    _error = null;
    notifyListeners();

    try {
      final releases = await (_fetcher ?? _fetchFromGitHub)();
      _lastChecked = _now();
      unawaited(_persistLastChecked());
      final current = _current;
      final stableReleases = releases
          .where((r) => r.tagName.startsWith(tagPrefix))
          .toList()
        ..sort((a, b) => b.version.compareTo(a.version));
      ReleaseInfo? newest =
          stableReleases.isEmpty ? null : stableReleases.first;
      if (nightlyUpdates) {
        final nightlies =
            releases.where((r) => r.tagName == nightlyTag).toList();
        if (nightlies.isNotEmpty) {
          final nightly = nightlies.first;
          // A final release with a higher app version wins. At the same app
          // version the nightly is newer by source commit, so prefer it.
          if (newest == null || nightly.version >= newest.version) {
            newest = nightly;
          }
        }
      }
      if (newest != null && current != null && _isNewer(newest, current)) {
        _latest = newest;
        _status = UpdateStatus.updateAvailable;
      } else {
        _latest = newest;
        _status = UpdateStatus.upToDate;
      }
    } catch (e) {
      AppDevTools.instance
          .addLog('update check failed: $e', level: DevLogLevel.error);
      _error = e;
      _status = UpdateStatus.failed;
    }
    notifyListeners();
  }

  /// Suppresses the startup banner for [latest] until a newer release ships.
  Future<void> dismiss() async {
    final identity = _latest?.identity;
    if (identity == null) return;
    _dismissedTag = identity;
    notifyListeners();
    await _persistDismissed(identity);
  }

  bool _isNewer(ReleaseInfo release, AppVersion current) {
    final versionOrder = release.version.compareTo(current);
    if (versionOrder != 0) return versionOrder > 0;
    if (!release.isNightly) return false;
    return !_sameCommit(release.commitSha, currentBuildCommit);
  }

  static bool _sameCommit(String? a, String? b) {
    if (a == null || b == null) return false;
    final left = a.trim().toLowerCase();
    final right = b.trim().toLowerCase();
    final hex = RegExp(r'^[0-9a-f]{7,40}$');
    if (!hex.hasMatch(left) || !hex.hasMatch(right)) return false;
    return left == right || left.startsWith(right) || right.startsWith(left);
  }

  bool _withinThrottle() {
    final last = _lastChecked;
    return last != null && _now().difference(last) < _checkInterval;
  }

  String? _platformAssetName(Map<String, String> assets) {
    if (assets.isEmpty) return null;
    final patterns = switch (_targetPlatform) {
      TargetPlatform.macOS => ['dartpdf-macos.dmg'],
      TargetPlatform.windows => [
          'dartpdf-nightly-windows-installer.exe',
          'dartpdf-windows-installer.exe',
          'dartpdf-windows-portable.exe',
          'dartpdf-nightly-windows-x64.zip',
          'dartpdf-windows-x64.zip',
        ],
      TargetPlatform.linux => [
          'dartpdf-linux-x86_64.AppImage',
          'dartpdf-linux-x64.tar.gz',
        ],
      // Mobile (Android/iOS) never reaches here: those platforms opt out of
      // update checks (see [supported]) because they update through their app
      // stores, so downloadUrl is only ever resolved for the desktop builds.
      _ => const <String>[],
    };
    for (final pattern in patterns) {
      for (final entry in assets.entries) {
        if (entry.key == pattern) return entry.key;
      }
    }
    return null;
  }

  Future<List<ReleaseInfo>> _fetchFromGitHub() async {
    final client = _clientFactory();
    const headers = {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      // GitHub rejects API requests that don't identify themselves.
      'User-Agent': 'DartPDF-update-checker',
    };
    try {
      final response = await client.get(
        releasesUri,
        headers: headers,
      );
      if (response.statusCode != 200) {
        throw http.ClientException(
          'GitHub returned HTTP ${response.statusCode}',
          releasesUri,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];
      final releases = decoded
          .whereType<Map>()
          .map((e) => ReleaseInfo.fromJson(e.cast<String, dynamic>()))
          .whereType<ReleaseInfo>()
          .toList();
      if (nightlyUpdates) {
        final nightlyResponse =
            await client.get(nightlyReleaseUri, headers: headers);
        // Before the first workflow run there simply is no nightly release.
        if (nightlyResponse.statusCode != 404) {
          if (nightlyResponse.statusCode != 200) {
            throw http.ClientException(
              'GitHub returned HTTP ${nightlyResponse.statusCode}',
              nightlyReleaseUri,
            );
          }
          final nightlyJson = jsonDecode(nightlyResponse.body);
          if (nightlyJson is Map) {
            final nightly =
                ReleaseInfo.fromJson(nightlyJson.cast<String, dynamic>());
            if (nightly != null) {
              releases.removeWhere((r) => r.tagName == nightly.tagName);
              releases.add(nightly);
            }
          }
        }
      }
      return releases;
    } finally {
      client.close();
    }
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_lastCheckedKey);
      if (last != null) {
        _lastChecked = DateTime.fromMillisecondsSinceEpoch(last);
      }
      _dismissedTag = prefs.getString(_dismissedKey);
      _nightlyUpdates =
          (prefs.getBool(_nightlyKey) ?? false) && nightlySupported;
      notifyListeners();
    } catch (_) {
      // No storage (tests) - keep the in-memory defaults.
    }
  }

  Future<void> _persistLastChecked() async {
    final last = _lastChecked;
    if (last == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckedKey, last.millisecondsSinceEpoch);
    } catch (_) {
      // No storage - nothing to persist.
    }
  }

  Future<void> _persistDismissed(String tag) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dismissedKey, tag);
    } catch (_) {
      // No storage - nothing to persist.
    }
  }
}
