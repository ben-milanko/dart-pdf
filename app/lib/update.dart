import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  });

  final AppVersion version;
  final String tagName;
  final String name;
  final String notes;
  final String htmlUrl;

  /// Asset file name → `browser_download_url`.
  final Map<String, String> assets;

  /// Builds a release from one element of the GitHub `/releases` array,
  /// returning null when the tag isn't a parseable version (so non-app tags
  /// and malformed entries are simply skipped).
  static ReleaseInfo? fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String?;
    if (tag == null) return null;
    final version = AppVersion.tryParse(tag);
    if (version == null) return null;
    final assets = <String, String>{};
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final asset in rawAssets) {
        if (asset is! Map) continue;
        final name = asset['name'];
        final url = asset['browser_download_url'];
        if (name is String && url is String) assets[name] = url;
      }
    }
    return ReleaseInfo(
      version: version,
      tagName: tag,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : tag,
      notes: (json['body'] as String?)?.trim() ?? '',
      htmlUrl: (json['html_url'] as String?) ?? '',
      assets: assets,
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
    this.repoOwner = 'ben-milanko',
    this.repoName = 'dart-pdf',
    this.tagPrefix = 'app-v',
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
  final String repoOwner;
  final String repoName;

  /// Only releases whose tag starts with this prefix are considered, so the
  /// per-package pub.dev release tags in the same repo are ignored.
  final String tagPrefix;

  final ReleaseFetcher? _fetcher;
  final http.Client Function() _clientFactory;
  final Duration _checkInterval;
  final DateTime Function() _now;
  final TargetPlatform? _platform;

  static const _lastCheckedKey = 'dart_pdf_editor_app.update.lastChecked';
  static const _dismissedKey = 'dart_pdf_editor_app.update.dismissedTag';

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
  Future<void> _restored = Future.value();

  /// Whether update checks make sense on this platform. The web build is always
  /// served fresh (and an installed PWA refreshes through its service worker),
  /// so there is nothing to check there.
  static bool get supported => !kIsWeb;

  TargetPlatform get _targetPlatform => _platform ?? defaultTargetPlatform;

  AppVersion? get _current => AppVersion.tryParse(currentVersion);

  /// True when a strictly newer release was found.
  bool get updateAvailable =>
      _status == UpdateStatus.updateAvailable && _latest != null;

  /// True when the user should be nudged about [latest]: an update is available
  /// and they haven't already dismissed this exact release.
  bool get shouldNotify =>
      updateAvailable && _latest!.tagName != _dismissedTag;

  /// The GitHub endpoint used by the default fetcher.
  Uri get releasesUri => Uri.https(
        'api.github.com',
        '/repos/$repoOwner/$repoName/releases',
        const {'per_page': '30'},
      );

  /// The best download URL for [latest] on the current platform: the matching
  /// release asset when there is one, else the release page (iOS, and anything
  /// without a direct artifact, send the user to the page).
  String? get downloadUrl {
    final release = _latest;
    if (release == null) return null;
    final asset = _platformAsset(release.assets);
    return asset ?? (release.htmlUrl.isEmpty ? null : release.htmlUrl);
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
      final appReleases = releases
          .where((r) => r.tagName.startsWith(tagPrefix))
          .toList()
        ..sort((a, b) => b.version.compareTo(a.version));
      final newest = appReleases.isEmpty ? null : appReleases.first;
      if (newest != null && current != null && newest.version > current) {
        _latest = newest;
        _status = UpdateStatus.updateAvailable;
      } else {
        _latest = newest;
        _status = UpdateStatus.upToDate;
      }
    } catch (e) {
      _error = e;
      _status = UpdateStatus.failed;
    }
    notifyListeners();
  }

  /// Suppresses the startup banner for [latest] until a newer release ships.
  Future<void> dismiss() async {
    final tag = _latest?.tagName;
    if (tag == null) return;
    _dismissedTag = tag;
    notifyListeners();
    await _persistDismissed(tag);
  }

  bool _withinThrottle() {
    final last = _lastChecked;
    return last != null && _now().difference(last) < _checkInterval;
  }

  String? _platformAsset(Map<String, String> assets) {
    if (assets.isEmpty) return null;
    final patterns = switch (_targetPlatform) {
      TargetPlatform.macOS => ['dartpdf-macos.dmg'],
      TargetPlatform.windows => [
          'dartpdf-windows-portable.exe',
          'dartpdf-windows-x64.zip',
        ],
      TargetPlatform.linux => [
          'dartpdf-linux-x86_64.AppImage',
          'dartpdf-linux-x64.tar.gz',
        ],
      TargetPlatform.android => ['app-release.apk'],
      _ => const <String>[],
    };
    for (final pattern in patterns) {
      for (final entry in assets.entries) {
        if (entry.key == pattern) return entry.value;
      }
    }
    return null;
  }

  Future<List<ReleaseInfo>> _fetchFromGitHub() async {
    final client = _clientFactory();
    try {
      final response = await client.get(
        releasesUri,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          // GitHub rejects API requests that don't identify themselves.
          'User-Agent': 'DartPDF-update-checker',
        },
      );
      if (response.statusCode != 200) {
        throw http.ClientException(
          'GitHub returned HTTP ${response.statusCode}',
          releasesUri,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => ReleaseInfo.fromJson(e.cast<String, dynamic>()))
          .whereType<ReleaseInfo>()
          .toList();
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
