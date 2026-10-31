import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'sync.dart';

/// One file in a [PdfSyncStore]: its [name] and the store's own last-write
/// time for it (the cloud provider's or file system's clock, not the
/// device's - presence is judged against it).
class PdfSyncStoreEntry {
  const PdfSyncStoreEntry(this.name, this.modified);

  final String name;
  final DateTime modified;

  @override
  String toString() => 'PdfSyncStoreEntry($name, $modified)';
}

/// The storage seam a [PdfSharedFolderSyncTransport] runs over: one flat
/// folder of small files, sitting beside the shared PDF.
///
/// Anything that can list, read, write and delete files is a store: a
/// folder a sync client keeps in step (OneDrive, Google Drive, iCloud
/// Drive, Dropbox, an SMB share - all `dart:io` in the host), or a
/// provider's REST API (Microsoft Graph, Drive, WebDAV) for platforms with
/// no local sync client, the web included. No storage code lives in this
/// package; [PdfMemorySyncStore] is the in-process reference.
///
/// The transport only ever **creates** files whose name carries its own
/// writer id, and only ever rewrites or deletes those same files. No file
/// has two writers, so no provider ever has a write conflict to resolve -
/// which is where "Report (1).pdf" / "Report-LAPTOP.pdf" duplicates come
/// from.
///
/// Stores may be eventually consistent: a file can be listed before its
/// bytes have arrived, or arrive truncated while a sync client is still
/// downloading it. [read] returning null or bytes that don't parse is
/// retried on the next poll, never treated as data.
abstract class PdfSyncStore {
  /// Every file currently in the folder.
  Future<List<PdfSyncStoreEntry>> list();

  /// The bytes of [name], or null when it is gone (or not readable yet).
  Future<Uint8List?> read(String name);

  /// Creates or replaces [name] with [bytes]. Implementations should write
  /// atomically where the medium allows (temp file + rename), so a reader
  /// never sees a half-written file under the final name.
  Future<void> write(String name, Uint8List bytes);

  /// Removes [name]; a missing file is not an error.
  Future<void> delete(String name);
}

/// An in-memory [PdfSyncStore] - the reference store for tests and
/// single-process demos. [now] stamps each write's modified time, so tests
/// can drive presence expiry with a fake clock.
class PdfMemorySyncStore implements PdfSyncStore {
  PdfMemorySyncStore({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, (Uint8List, DateTime)> _files = {};

  /// The current file names, for tests.
  Iterable<String> get names => _files.keys;

  @override
  Future<List<PdfSyncStoreEntry>> list() async => [
        for (final entry in _files.entries)
          PdfSyncStoreEntry(entry.key, entry.value.$2),
      ];

  @override
  Future<Uint8List?> read(String name) async => _files[name]?.$1;

  @override
  Future<void> write(String name, Uint8List bytes) async {
    _files[name] = (Uint8List.fromList(bytes), _now());
  }

  @override
  Future<void> delete(String name) async {
    _files.remove(name);
  }
}

/// A [PdfSyncTransport] over a shared folder ([PdfSyncStore]) - the
/// experimental "live sync through network storage" transport.
///
/// Each open session is one **writer** ([sessionId], unique per open:
/// device id plus a per-open nonce, so the same user on two devices, or
/// two windows on one device, are two writers). Its sends are buffered and
/// [flush]ed as an immutable op file `ops.<writer>.<seq>.json` (a JSON
/// list of [PdfSyncMessage]s); [poll] lists the folder, reads every op
/// file it has not seen from any *other* writer, and delivers its
/// messages on [incoming]. A writer also keeps `presence.<writer>.json`
/// fresh, and [peers] is every writer whose presence file the store saw
/// written within [presenceTimeout].
///
/// The first [poll] replays the folder's whole history - including op
/// files from this device's earlier sessions, which are other writers -
/// so a session that joins late (or reopens after a crash) catches up.
/// Delivery order across writers is whatever the listing yields; that is
/// fine because [PdfSyncSession]'s last-writer-wins merge converges under
/// any order.
///
/// Poll before the first local edit so the Lamport clock has advanced
/// past the folder's history (a fresh session's edits would otherwise
/// lose to older ones). [startPolling] does that and then keeps polling.
///
/// The shared PDF itself is never written by this transport: folding the
/// log back into the file is a separate, single-writer step (see
/// doc/dev-log/2026-10-28-shared-folder-live-sync.md).
class PdfSharedFolderSyncTransport implements PdfSyncTransport {
  PdfSharedFolderSyncTransport({
    required this.store,
    required this.sessionId,
    this.flushDelay = const Duration(milliseconds: 400),
    this.presenceInterval = const Duration(seconds: 15),
    this.presenceTimeout = const Duration(seconds: 60),
    this.presenceInfo = const {},
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    if (!isValidWriterId(sessionId)) {
      throw ArgumentError.value(sessionId, 'sessionId',
          'must be 1-64 characters of A-Z, a-z, 0-9 or _');
    }
    _peers = Set.unmodifiable({sessionId});
  }

  /// Whether [id] can name a writer: it is embedded in file names, so it
  /// is limited to characters every provider accepts and that never clash
  /// with the `.` separator.
  static bool isValidWriterId(String id) => _writerId.hasMatch(id);

  static final RegExp _writerId = RegExp(r'^[A-Za-z0-9_]{1,64}$');
  static final RegExp _opFile =
      RegExp(r'^ops\.([A-Za-z0-9_]{1,64})\.(\d{1,12})\.json$');
  static final RegExp _presenceFile =
      RegExp(r'^presence\.([A-Za-z0-9_]{1,64})\.json$');

  /// The folder the log lives in.
  final PdfSyncStore store;

  @override
  final String sessionId;

  /// How long sends are batched before [flush] writes them as one op file.
  /// Zero still batches everything sent in the same synchronous run.
  final Duration flushDelay;

  /// How often this writer's presence file is rewritten (checked on every
  /// [poll]).
  final Duration presenceInterval;

  /// How long after its last presence write a writer still counts as a
  /// peer. Judged against the store's modified times, so keep it well above
  /// the sync provider's propagation delay plus [presenceInterval].
  final Duration presenceTimeout;

  /// What this writer tells its peers about itself - typically a display
  /// `name` and a `device` label. Written into its presence file; the
  /// peers read it back as [peerInfo].
  final Map<String, String> presenceInfo;

  final DateTime Function() _now;

  final StreamController<PdfSyncMessage> _incoming =
      StreamController<PdfSyncMessage>.broadcast();
  final StreamController<Set<String>> _presence =
      StreamController<Set<String>>.broadcast();
  late Set<String> _peers;
  final Map<String, (DateTime, Map<String, String>)> _peerInfo = {};
  final StreamController<Object> _errors = StreamController<Object>.broadcast();

  final List<PdfSyncMessage> _pending = [];
  Timer? _flushTimer;
  Future<void>? _flushing;
  int _seq = 0;

  /// Op files already delivered (or written by this writer).
  final Set<String> _seen = {};
  bool _polling = false;
  DateTime? _presenceWritten;
  Timer? _pollTimer;
  bool _closed = false;

  @override
  Stream<PdfSyncMessage> get incoming => _incoming.stream;

  @override
  Stream<Set<String>> get presence => _presence.stream;

  @override
  Set<String> get peers => _peers;

  /// The [presenceInfo] each other live peer published, keyed by writer id.
  /// A peer whose presence file has not been read yet maps to an empty map.
  Map<String, Map<String, String>> get peerInfo => {
        for (final id in _peers)
          if (id != sessionId) id: _peerInfo[id]?.$2 ?? const {},
      };

  /// Errors from the background polls [startPolling] runs (a store that
  /// went offline, a permission change). A failed poll is retried on the
  /// next tick; this only reports it.
  Stream<Object> get errors => _errors.stream;

  /// Messages sent but not yet written to the store.
  int get pendingCount => _pending.length;

  @override
  void send(PdfSyncMessage message) {
    if (_closed) return;
    _pending.add(message);
    _flushTimer ??= Timer(flushDelay, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  /// Writes every pending message as one new op file. Safe to call at any
  /// time; concurrent calls queue behind each other. A failed write keeps
  /// the messages pending (and rethrows), so the next flush retries them.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    while (_flushing != null) {
      await _flushing;
    }
    if (_pending.isEmpty) return;
    final batch = List.of(_pending);
    final name = 'ops.$sessionId.${(_seq + 1).toString().padLeft(8, '0')}'
        '.json';
    final done = Completer<void>();
    _flushing = done.future;
    try {
      final json = jsonEncode([for (final m in batch) m.toJson()]);
      await store.write(name, Uint8List.fromList(utf8.encode(json)));
      _seq++;
      _seen.add(name);
      _pending.removeRange(0, batch.length);
    } finally {
      _flushing = null;
      done.complete();
    }
  }

  /// Lists the folder once: delivers every unseen op file from other
  /// writers on [incoming], refreshes this writer's presence, and
  /// recomputes [peers]. Returns how many messages were delivered.
  ///
  /// An op file that can't be read or parsed yet (still syncing down) is
  /// skipped and retried by the next poll. Overlapping calls return 0.
  Future<int> poll() async {
    if (_closed || _polling) return 0;
    _polling = true;
    try {
      final entries = await store.list();
      if (_closed) return 0;
      final unseen = <(String, int, String)>[];
      final live = <String>{sessionId};
      final presence = <String, DateTime>{};
      final now = _now();
      for (final entry in entries) {
        final op = _opFile.firstMatch(entry.name);
        if (op != null) {
          if (op.group(1) == sessionId) {
            // a reused id must never overwrite its own earlier op files
            final seq = int.parse(op.group(2)!);
            if (seq > _seq) _seq = seq;
          } else if (!_seen.contains(entry.name)) {
            unseen.add((op.group(1)!, int.parse(op.group(2)!), entry.name));
          }
          continue;
        }
        final seen = _presenceFile.firstMatch(entry.name);
        if (seen != null && now.difference(entry.modified) <= presenceTimeout) {
          live.add(seen.group(1)!);
          presence[seen.group(1)!] = entry.modified;
        }
      }
      // per writer in sequence order, so one writer's edits replay in the
      // order they were made (the merge does not need it, the UI's
      // intermediate states read better for it)
      unseen.sort((a, b) {
        final byWriter = a.$1.compareTo(b.$1);
        return byWriter != 0 ? byWriter : a.$2.compareTo(b.$2);
      });
      var delivered = 0;
      for (final (_, _, name) in unseen) {
        final messages = await _readOps(name);
        if (_closed) return delivered;
        if (messages == null) continue;
        _seen.add(name);
        for (final message in messages) {
          _incoming.add(message);
          delivered++;
        }
      }
      await _readPresenceInfo(presence);
      if (_closed) return delivered;
      await _touchPresence(now);
      _updatePeers(live);
      return delivered;
    } finally {
      _polling = false;
    }
  }

  /// Polls now and then every [interval] until [close]. The returned future
  /// completes after the first poll (the catch-up), so a host can await it
  /// before enabling local edits.
  Future<void> startPolling(Duration interval) async {
    _pollTimer?.cancel();
    await poll();
    if (_closed) return;
    _pollTimer = Timer.periodic(interval, (_) {
      poll().then((_) {}, onError: (Object error) {
        if (!_closed) _errors.add(error);
      });
    });
  }

  /// Refreshes [_peerInfo] for the live writers in [presence] whose presence
  /// file changed since it was last read, and forgets the ones that left.
  Future<void> _readPresenceInfo(Map<String, DateTime> presence) async {
    _peerInfo.removeWhere((id, _) => !presence.containsKey(id));
    for (final MapEntry(key: id, value: modified) in presence.entries) {
      if (id == sessionId || _peerInfo[id]?.$1 == modified) continue;
      try {
        final bytes = await store.read('presence.$id.json');
        if (bytes == null) continue;
        final decoded = jsonDecode(utf8.decode(bytes));
        final info = decoded is Map ? decoded['info'] : null;
        _peerInfo[id] = (
          modified,
          {
            if (info is Map)
              for (final MapEntry(:key, :value) in info.entries)
                if (key is String && value is String) key: value,
          },
        );
      } on FormatException {
        continue; // still syncing down: retry next poll
      }
    }
  }

  Future<List<PdfSyncMessage>?> _readOps(String name) async {
    try {
      final bytes = await store.read(name);
      if (bytes == null) return null;
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! List) return null;
      return [
        for (final item in decoded)
          PdfSyncMessage.fromJson((item as Map).cast<String, dynamic>()),
      ];
    } on FormatException {
      return null; // truncated mid-download, or not ours: retry next poll
    } on TypeError {
      return null;
    }
  }

  Future<void> _touchPresence(DateTime now) async {
    final last = _presenceWritten;
    if (last != null && now.difference(last) < presenceInterval) return;
    _presenceWritten = now;
    try {
      await store.write(
        'presence.$sessionId.json',
        Uint8List.fromList(utf8.encode(jsonEncode({
          'at': now.millisecondsSinceEpoch,
          if (presenceInfo.isNotEmpty) 'info': presenceInfo,
        }))),
      );
    } catch (_) {
      _presenceWritten = last; // retry next poll
    }
  }

  void _updatePeers(Set<String> live) {
    if (_closed) return;
    if (live.length == _peers.length && live.containsAll(_peers)) return;
    _peers = Set.unmodifiable(live);
    _presence.add(_peers);
  }

  /// Stops polling and removes this writer's presence file. Pending
  /// messages are *not* flushed - call [flush] first to keep them.
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _flushTimer?.cancel();
    _pollTimer?.cancel();
    unawaited(store.delete('presence.$sessionId.json').catchError((_) {}));
    _incoming.close();
    _presence.close();
    _errors.close();
  }
}
