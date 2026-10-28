// Live sync (experimental): two people - or one person on two devices - with
// the same PDF open from a shared folder (OneDrive, SharePoint, Google Drive,
// iCloud Drive, Dropbox, a network share) see each other's annotations as
// they work, and the folder never collects conflict copies.
//
// The protocol lives in the packages: PdfSharedFolderSyncTransport writes
// each session's changes as its own immutable files in a sidecar folder next
// to the PDF, and PdfEditingSync merges them into the editing controller.
// This file is the app's session around them: polling, status, who else is
// in the document, and folding the merged result back into the PDF from one
// device at a time. See doc/dev-log/2026-10-28-shared-folder-live-sync.md.

import 'dart:async';
import 'dart:math';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf_document/pdf_document.dart';

/// Where live sync can run and how it reaches the folder beside a PDF.
/// The platform implementation is `platformLiveSyncBackend`
/// (live_sync_store.dart); tests inject their own.
abstract class LiveSyncBackend {
  const LiveSyncBackend();

  /// The sidecar store for the PDF at [path], or null when a document there
  /// can't be synced (no folder to write beside it).
  PdfSyncStore? storeFor(String path);

  /// A short label for this device ("Ben's MacBook"), shown to the others.
  String get deviceName;

  /// Asks the user for access to the folder holding [path] when the
  /// platform needs it (a sandboxed Mac only has the file it opened).
  /// Returns whether access was granted; true where nothing is needed.
  Future<bool> requestFolderAccess(String path) async => true;
}

/// Where a live sync session stands.
enum LiveSyncStatus {
  /// Reading the folder's history before the first edit goes out.
  connecting,

  /// Polling the folder successfully.
  live,

  /// The last poll failed (folder unreachable, permissions); retrying.
  offline,
}

/// Someone else in the document.
@immutable
class LiveSyncPeer {
  const LiveSyncPeer({required this.id, required this.name, this.device});

  /// The session's writer id - unique per open, so the same person on two
  /// devices is two peers.
  final String id;

  /// The display name they chose (their annotation author name), or their
  /// device name when they have none.
  final String name;

  /// Their device label, when they published one.
  final String? device;

  @override
  bool operator ==(Object other) =>
      other is LiveSyncPeer &&
      other.id == id &&
      other.name == name &&
      other.device == device;

  @override
  int get hashCode => Object.hash(id, name, device);
}

/// One document's live sync: owns the folder transport and the editing
/// sync, polls on a timer, and exposes [status], [peers] and whether this
/// device is the one that writes the PDF ([isWriter]).
///
/// **Writing the PDF.** The change files are the shared truth while people
/// work; the PDF itself is rewritten from the merged state by exactly one
/// session at a time - the live peer with the lowest writer id - after
/// [compactAfter] without changes, on [saveNow], and when it stops. Every
/// session holds the same merged annotations, so whichever one writes, the
/// file carries everyone's work; and because only one writes, the folder
/// does not fill with "(conflict)" copies.
class LiveSyncSession extends ChangeNotifier {
  LiveSyncSession({
    required this.controller,
    required this.store,
    required this.name,
    required this.writePdf,
    this.device,
    String? writerId,
    int? writtenLength,
    this.pollInterval = const Duration(seconds: 2),
    this.compactAfter = const Duration(seconds: 10),
    this.presenceTimeout = const Duration(seconds: 45),
    DateTime Function()? now,
  })  : writerId = writerId ?? newWriterId(),
        _writtenLength = writtenLength ?? -1,
        _now = now ?? DateTime.now;

  /// A fresh random writer id. Ids only need to be unique; their order
  /// picks the PDF writer, so random is as fair as anything.
  static String newWriterId([Random? random]) {
    final rng = random ?? Random.secure();
    return 'w${List.generate(12, (_) => rng.nextInt(16).toRadixString(16)).join()}';
  }

  /// The edit session being synced.
  final PdfEditingController controller;

  /// The sidecar folder next to the PDF.
  final PdfSyncStore store;

  /// What the others see this session as.
  final String name;

  /// This device's label, also shown to the others.
  final String? device;

  /// Writes the merged document over the shared PDF; resolves to whether it
  /// landed.
  final Future<bool> Function(Uint8List bytes) writePdf;

  /// This session's id in the folder.
  final String writerId;

  /// How often the folder is read and pending changes written.
  final Duration pollInterval;

  /// How long the document must be quiet before the writer folds the
  /// changes into the PDF.
  final Duration compactAfter;

  /// How long a session stays listed after its last heartbeat.
  final Duration presenceTimeout;

  final DateTime Function() _now;

  PdfSharedFolderSyncTransport? _transport;
  PdfEditingSync? _sync;
  StreamSubscription<List<PdfAnnotationChange>>? _localChanges;
  StreamSubscription<List<PdfAnnotationChange>>? _remoteChanges;
  Timer? _timer;
  bool _ticking = false;
  bool _closed = false;

  LiveSyncStatus _status = LiveSyncStatus.connecting;
  Object? _error;
  List<LiveSyncPeer> _peers = const [];
  DateTime? _lastSyncedAt;
  DateTime? _pdfWrittenAt;
  DateTime _lastActivity = DateTime.fromMillisecondsSinceEpoch(0);
  int _writtenLength;

  final StreamController<({LiveSyncPeer peer, bool joined})> _peerChanges =
      StreamController.broadcast();

  /// Where the session stands.
  LiveSyncStatus get status => _status;

  /// Why the last poll failed, while [status] is offline.
  Object? get error => _error;

  /// Everyone else currently in the document, by name.
  List<LiveSyncPeer> get peers => _peers;

  /// When the folder was last read successfully.
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// When this session last wrote the PDF.
  DateTime? get pdfWrittenAt => _pdfWrittenAt;

  /// Whether this session is the one that writes the PDF.
  bool get isWriter {
    final ids = _transport?.peers;
    if (ids == null || ids.isEmpty) return true;
    return ids.reduce((a, b) => a.compareTo(b) <= 0 ? a : b) == writerId;
  }

  /// Whether every local change has reached the folder.
  bool get isFlushed => (_transport?.pendingCount ?? 0) == 0;

  /// Someone joining or leaving, for a toast.
  Stream<({LiveSyncPeer peer, bool joined})> get peerChanges =>
      _peerChanges.stream;

  /// Joins the folder: names the document's annotations when this is the
  /// first session (and writes those names into the PDF so the others
  /// start from them), replays the folder's history into the document,
  /// then polls every [pollInterval].
  Future<void> start() async {
    final existing = await store.list().then(
      (entries) => entries.any((e) => e.name.startsWith('ops.')),
      onError: (Object error) {
        _setOffline(error);
        return true; // unknown: don't rename anything
      },
    );
    if (_closed) return;
    if (!existing && controller.ensureAnnotationNames() > 0) {
      // Everyone else must start from these names, so they go into the file
      // before anyone can join.
      if (await writePdf(controller.bytes)) {
        _writtenLength = controller.bytes.length;
        _pdfWrittenAt = _now();
      }
      if (_closed) return;
    }
    final transport = _transport = PdfSharedFolderSyncTransport(
      store: store,
      sessionId: writerId,
      // the timer below flushes; a send still lands within one tick
      flushDelay: pollInterval,
      presenceInterval: pollInterval * 5,
      presenceTimeout: presenceTimeout,
      presenceInfo: {
        'name': name,
        if (device != null) 'device': device!,
      },
      now: _now,
    );
    _sync = PdfEditingSync(controller: controller, transport: transport);
    _localChanges = controller.annotationChanges.listen((_) => _touch());
    _remoteChanges = _sync!.remoteChanges.listen((_) => _touch());
    await _tick();
    if (_closed) return;
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_tick()));
  }

  void _touch() => _lastActivity = _now();

  /// One round: write pending changes, read everyone else's, refresh who
  /// is here, and fold into the PDF when this session is the writer and
  /// the document has been quiet.
  Future<void> _tick() async {
    final transport = _transport;
    if (transport == null || _ticking || _closed) return;
    _ticking = true;
    final before = _visibleState;
    try {
      await transport.flush();
      await transport.poll();
      if (_closed) return;
      _error = null;
      _status = LiveSyncStatus.live;
      _lastSyncedAt = _now();
      _updatePeers(transport);
      if (isWriter &&
          _hasUnwrittenChanges &&
          _now().difference(_lastActivity) >= compactAfter) {
        await _writePdf();
      }
    } catch (error) {
      _setOffline(error);
    } finally {
      _ticking = false;
    }
    // Only real changes notify: a tick every couple of seconds must not
    // rebuild the header for nothing.
    if (!_closed && _visibleState != before) notifyListeners();
  }

  /// What listeners can observe, to notify only when it changes.
  /// The document length is part of it: a merged remote change leaves the
  /// tab "dirty" until a listener hears the folder already holds it.
  Object get _visibleState => Object.hash(
      _status,
      _error,
      Object.hashAll(_peers),
      isWriter,
      isFlushed,
      _pdfWrittenAt,
      controller.bytes.length);

  bool get _hasUnwrittenChanges => controller.bytes.length != _writtenLength;

  void _setOffline(Object error) {
    _error = error;
    _status = LiveSyncStatus.offline;
    if (!_closed) notifyListeners();
  }

  void _updatePeers(PdfSharedFolderSyncTransport transport) {
    final next = [
      for (final MapEntry(key: id, value: info) in transport.peerInfo.entries)
        LiveSyncPeer(
          id: id,
          name: info['name'] ?? info['device'] ?? '',
          device: info['device'],
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
    final before = {for (final p in _peers) p.id: p};
    final after = {for (final p in next) p.id: p};
    for (final peer in next) {
      if (!before.containsKey(peer.id)) {
        _peerChanges.add((peer: peer, joined: true));
      }
    }
    for (final peer in _peers) {
      if (!after.containsKey(peer.id)) {
        _peerChanges.add((peer: peer, joined: false));
      }
    }
    _peers = List.unmodifiable(next);
  }

  Future<bool> _writePdf() async {
    final bytes = Uint8List.fromList(controller.bytes);
    if (!await writePdf(bytes)) return false;
    _writtenLength = bytes.length;
    _pdfWrittenAt = _now();
    return true;
  }

  /// What Save does while syncing: sends every pending change now and, on
  /// the writer, folds them into the PDF. Returns whether this session
  /// wrote the PDF (false on the others, whose changes the writer folds in).
  Future<bool> saveNow() async {
    await _transport?.flush();
    if (_closed || !isWriter || !_hasUnwrittenChanges) return false;
    final wrote = await _writePdf();
    if (!_closed) notifyListeners();
    return wrote;
  }

  /// Leaves the folder: stops polling and merging, sends what is pending,
  /// and - when this session is the writer - folds everything into the PDF
  /// one last time. Safe to call from a tab's dispose: everything that
  /// touches [controller] happens before the first await.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    final transport = _transport;
    final writer = isWriter && _hasUnwrittenChanges;
    final bytes = Uint8List.fromList(controller.bytes);
    unawaited(_localChanges?.cancel());
    unawaited(_remoteChanges?.cancel());
    unawaited(_sync?.dispose());
    unawaited(_peerChanges.close());
    if (transport == null) return;
    try {
      await transport.flush();
      if (writer) await writePdf(bytes);
    } catch (_) {
      // Best effort: the change files already hold whatever was flushed.
    } finally {
      transport.close();
    }
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
