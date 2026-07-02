import 'dart:async';
import 'dart:typed_data';

import 'document.dart';
import 'editor.dart';

/// One annotation change wrapped with the metadata the merge layer needs:
/// who produced it ([origin]) and a logical [clock] timestamp. The pair
/// `(clock, origin)` is the total order a [PdfSyncSession] uses for
/// last-writer-wins conflict resolution, keyed on the change's /NM.
///
/// This is the unit a transport ships. [toJson]/[fromJson] make it
/// wire-ready (the host's real transport — WebSocket, WebRTC, a backend —
/// serializes these); the snapshot inside encodes through
/// [PdfAnnotationSnapshot.toJson].
class PdfSyncMessage {
  const PdfSyncMessage({
    required this.change,
    required this.origin,
    required this.clock,
  });

  /// The annotation change to replay (created/modified/removed).
  final PdfAnnotationChange change;

  /// The id of the session that produced the change.
  final String origin;

  /// A Lamport timestamp: monotonically increasing per session and
  /// advanced past any received clock, so `(clock, origin)` totally orders
  /// concurrent edits deterministically.
  final int clock;

  /// The /NM the change targets, the LWW key (null only for anonymous
  /// annotations, which cannot be id-merged).
  String? get name => change.name;

  Map<String, dynamic> toJson() => {
        'origin': origin,
        'clock': clock,
        'kind': change.kind.name,
        'page': change.pageIndex,
        if (change.name != null) 'name': change.name,
        if (change.snapshot != null) 'snapshot': change.snapshot!.toJson(),
      };

  static PdfSyncMessage fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'];
    final kind = PdfAnnotationChangeKind.values
        .where((k) => k.name == kindName)
        .firstOrNull;
    final origin = json['origin'];
    final clock = json['clock'];
    final page = json['page'];
    if (kind == null || origin is! String || clock is! int || page is! int) {
      throw const FormatException('malformed sync message');
    }
    final snapshotJson = json['snapshot'];
    return PdfSyncMessage(
      origin: origin,
      clock: clock,
      change: PdfAnnotationChange(
        kind: kind,
        pageIndex: page,
        name: json['name'] as String?,
        snapshot: snapshotJson is Map<String, dynamic>
            ? PdfAnnotationSnapshot.fromJson(snapshotJson)
            : null,
      ),
    );
  }
}

/// The transport seam a [PdfSyncSession] talks through — the same shape of
/// injectable dependency as the OCR engine: the library defines the
/// interface and a loopback reference ([PdfLoopbackSyncHub]); the host
/// supplies the real one (a WebSocket, WebRTC data channel, or backend
/// fan-out). No networking lives in this package.
///
/// A transport is point-to-the-session: [incoming] delivers messages from
/// *other* peers (a transport never echoes the session's own [send]s back),
/// and [presence] tracks which session ids are currently connected.
abstract class PdfSyncTransport {
  /// This endpoint's session id.
  String get sessionId;

  /// Messages from other peers (never this session's own).
  Stream<PdfSyncMessage> get incoming;

  /// The set of currently connected session ids, emitted whenever a peer
  /// joins or leaves. Always includes [sessionId] while open.
  Stream<Set<String>> get presence;

  /// The currently connected session ids (the latest [presence] value).
  Set<String> get peers;

  /// Broadcasts [message] to every other connected peer.
  void send(PdfSyncMessage message);

  /// Disconnects this endpoint, removing it from the peer set.
  void close();
}

/// An in-memory hub that wires [PdfSyncTransport] endpoints together — the
/// reference transport for tests and local multi-view demos. It is pure
/// Dart (no `dart:io`, no sockets): [connect] returns an endpoint, and a
/// [send] fans out to every *other* connected endpoint on a microtask, so
/// two [PdfSyncSession]s sharing one hub exchange changes and converge.
///
/// The real product transport is the host's concern — swap this for an
/// adapter over your socket and the sessions behave identically.
class PdfLoopbackSyncHub {
  final List<_LoopbackEndpoint> _endpoints = [];

  /// Connects a new endpoint for [sessionId]. Reusing a live id throws.
  PdfSyncTransport connect(String sessionId) {
    if (_endpoints.any((e) => e.sessionId == sessionId)) {
      throw ArgumentError.value(sessionId, 'sessionId', 'already connected');
    }
    final endpoint = _LoopbackEndpoint(this, sessionId);
    _endpoints.add(endpoint);
    _broadcastPresence();
    return endpoint;
  }

  Set<String> get _ids => {for (final e in _endpoints) e.sessionId};

  void _send(PdfSyncMessage message, _LoopbackEndpoint from) {
    for (final endpoint in List.of(_endpoints)) {
      if (!identical(endpoint, from)) endpoint._receive(message);
    }
  }

  void _disconnect(_LoopbackEndpoint endpoint) {
    if (!_endpoints.remove(endpoint)) return;
    _broadcastPresence();
  }

  void _broadcastPresence() {
    final ids = _ids;
    for (final endpoint in _endpoints) {
      endpoint._updatePresence(ids);
    }
  }
}

class _LoopbackEndpoint implements PdfSyncTransport {
  _LoopbackEndpoint(this._hub, this.sessionId);

  final PdfLoopbackSyncHub _hub;

  @override
  final String sessionId;

  final StreamController<PdfSyncMessage> _incoming =
      StreamController<PdfSyncMessage>.broadcast();
  final StreamController<Set<String>> _presence =
      StreamController<Set<String>>.broadcast();
  Set<String> _peers = const {};
  bool _closed = false;

  @override
  Stream<PdfSyncMessage> get incoming => _incoming.stream;

  @override
  Stream<Set<String>> get presence => _presence.stream;

  @override
  Set<String> get peers => _peers;

  @override
  void send(PdfSyncMessage message) {
    if (_closed) return;
    _hub._send(message, this);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _hub._disconnect(this);
    _incoming.close();
    _presence.close();
  }

  void _receive(PdfSyncMessage message) {
    if (_closed) return;
    _incoming.add(message);
  }

  void _updatePresence(Set<String> ids) {
    _peers = Set.unmodifiable(ids);
    if (!_closed) _presence.add(_peers);
  }
}

/// A transport-agnostic collaborative editing session over one document's
/// annotations, built on the snapshot + diff primitives
/// ([pdfDiffAnnotations], [PdfAnnotationSnapshot],
/// [PdfAnnotationSyncEditing.upsertAnnotation]).
///
/// The session owns a mutable byte buffer and the live [document] reopened
/// from it. A local [apply] runs an editor optimistically, diffs the
/// result, and broadcasts each change through the injected [transport];
/// incoming remote changes are merged with **last-writer-wins keyed on
/// /NM**, ordered by the message's `(clock, origin)`. Because that order
/// is total and every session evaluates it identically, sessions sharing a
/// transport **converge to the same annotation set** regardless of
/// delivery order — conflicting edits to the same /NM resolve to the same
/// winner everywhere.
///
/// Seed every collaborator from the *same* bytes (run
/// [PdfAnnotationEditing.nameAnnotations] once on the source so every
/// annotation has a durable /NM before sharing) — independently minted
/// names would never reconcile.
///
/// Anonymous annotations (no /NM) cannot be id-merged: they ride along as
/// create/remove but are skipped by the LWW table.
class PdfSyncSession {
  PdfSyncSession({
    required Uint8List bytes,
    required this.transport,
    String password = '',
  })  : _password = password,
        _bytes = Uint8List.fromList(bytes),
        _document = PdfDocument.open(bytes, password: password) {
    _subscription = transport.incoming.listen(_onRemote);
  }

  /// The transport this session sends through and listens on.
  final PdfSyncTransport transport;

  final String _password;
  Uint8List _bytes;
  PdfDocument _document;
  late final StreamSubscription<PdfSyncMessage> _subscription;

  int _clock = 0;

  /// The last accepted write per /NM: `(clock, origin)`. New writes win
  /// only when strictly greater in this total order, which is what makes
  /// the merge deterministic and convergent.
  final Map<String, (int, String)> _lastWrite = {};

  final StreamController<List<PdfAnnotationChange>> _changes =
      StreamController<List<PdfAnnotationChange>>.broadcast();

  /// This session's id (its transport endpoint's).
  String get id => transport.sessionId;

  /// The current document bytes — what "save to disk" would write.
  Uint8List get bytes => Uint8List.sublistView(_bytes);

  /// The live document for the current state.
  PdfDocument get document => _document;

  /// The session ids currently connected (from the transport's presence).
  Set<String> get peers => transport.peers;

  /// Presence updates from the transport: the connected session ids
  /// whenever a peer joins or leaves.
  Stream<Set<String>> get presence => transport.presence;

  /// Every annotation change this session applies — both local edits and
  /// accepted remote merges — so a host can refresh its UI. Local edits
  /// are also broadcast to peers; remote merges are not re-broadcast (no
  /// echo).
  Stream<List<PdfAnnotationChange>> get changes => _changes.stream;

  /// Runs [edit] against the current document, commits it as the new
  /// state, broadcasts the resulting changes, and returns them. [pages]
  /// limits the diff to the touched page indices (null/empty diffs every
  /// page — pass it for speed on large documents). No-op edits return an
  /// empty list and send nothing.
  List<PdfAnnotationChange> apply(void Function(PdfEditor editor) edit,
      {Iterable<int>? pages}) {
    final beforeBytes = _bytes;
    final editor = PdfEditor(_document);
    edit(editor);
    if (!editor.hasChanges) return const [];
    final saved = editor.save();
    final before = PdfDocument.open(beforeBytes, password: _password);
    _bytes = saved;
    _document = PdfDocument.open(saved, password: _password);
    final diffPages =
        (pages == null || pages.isEmpty) ? null : pages;
    final changes =
        pdfDiffAnnotations(before, _document, pages: diffPages);
    for (final change in changes) {
      final clock = ++_clock;
      final name = change.name;
      // a local edit is, by construction, the newest write for its /NM
      if (name != null) _lastWrite[name] = (clock, id);
      transport.send(
          PdfSyncMessage(change: change, origin: id, clock: clock));
    }
    if (changes.isNotEmpty) _changes.add(changes);
    return changes;
  }

  /// The whole current annotation state as created-changes — what a new
  /// peer asks an existing session for to catch up (or what seeds a store).
  /// Mirrors `PdfEditingController.annotationBaseline`.
  List<PdfAnnotationChange> annotationBaseline() {
    final changes = <PdfAnnotationChange>[];
    for (var pageIndex = 0; pageIndex < _document.pageCount; pageIndex++) {
      for (final annotation in _document.page(pageIndex).annotations) {
        final name = annotation.name;
        if (name == null) continue;
        final snapshot = PdfAnnotationSnapshot.capture(_document, annotation,
            keepName: true);
        if (snapshot == null) continue;
        changes.add(PdfAnnotationChange(
          kind: PdfAnnotationChangeKind.created,
          pageIndex: pageIndex,
          name: name,
          snapshot: snapshot,
        ));
      }
    }
    return changes;
  }

  /// A canonical fingerprint of the current annotation state: /NM →
  /// snapshot JSON for every captureable named annotation. Two converged
  /// sessions have equal digests — handy for tests and for detecting drift.
  Map<String, Object?> annotationDigest() {
    final digest = <String, Object?>{};
    for (final change in annotationBaseline()) {
      if (change.name != null && change.snapshot != null) {
        digest[change.name!] = change.snapshot!.toJson();
      }
    }
    return digest;
  }

  void _onRemote(PdfSyncMessage message) {
    // advance the Lamport clock past anything we hear about
    if (message.clock > _clock) _clock = message.clock;
    final name = message.name;
    if (name == null) return; // anonymous: not id-mergeable

    // last-writer-wins: accept only a strictly newer (clock, origin)
    final current = _lastWrite[name];
    final incoming = (message.clock, message.origin);
    if (current != null && !_isNewer(incoming, current)) return;

    // record the winning write even if the apply is a no-op (e.g. a remove
    // of something we never had): the table is the authority on "latest
    // known write for this /NM", so a later stale edit is still dropped
    _lastWrite[name] = incoming;
    if (_applyRemote(message.change)) {
      _changes.add([message.change]);
    }
  }

  /// Strict total order on `(clock, origin)`: higher clock wins; ties break
  /// on the lexicographically greater origin id, so every session picks the
  /// same winner.
  static bool _isNewer((int, String) a, (int, String) b) =>
      a.$1 != b.$1 ? a.$1 > b.$1 : a.$2.compareTo(b.$2) > 0;

  bool _applyRemote(PdfAnnotationChange change) {
    final editor = PdfEditor(_document);
    switch (change.kind) {
      case PdfAnnotationChangeKind.created:
      case PdfAnnotationChangeKind.modified:
        final snapshot = change.snapshot;
        if (snapshot == null || snapshot.name == null) return false;
        if (change.pageIndex < 0 ||
            change.pageIndex >= _document.pageCount) {
          return false;
        }
        editor.upsertAnnotation(change.pageIndex, snapshot);
      case PdfAnnotationChangeKind.removed:
        final name = change.name;
        if (name == null) return false;
        if (!editor.removeAnnotationByName(name)) return false;
    }
    if (!editor.hasChanges) return false;
    _bytes = editor.save();
    _document = PdfDocument.open(_bytes, password: _password);
    return true;
  }

  /// Stops listening and releases the change stream. Does not close the
  /// transport — the host owns its lifecycle.
  Future<void> dispose() async {
    await _subscription.cancel();
    await _changes.close();
  }
}
