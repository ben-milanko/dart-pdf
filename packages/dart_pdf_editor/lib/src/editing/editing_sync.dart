import 'dart:async';
import 'dart:convert';

import 'package:pdf_document/pdf_document.dart';

import 'editing_controller.dart';

/// Live annotation sync for an editing session: connects a
/// [PdfEditingController] to a [PdfSyncTransport] (a
/// [PdfSharedFolderSyncTransport] over a network folder, the in-memory
/// [PdfLoopbackSyncHub], or the host's own socket).
///
/// Outbound, every batch on [PdfEditingController.annotationChanges] - edits,
/// undo and redo alike - is stamped by a [PdfSyncClock] and sent. Inbound,
/// each message the clock [PdfSyncClock.accept]s is replayed through
/// [PdfEditingController.applyRemoteChange], which neither re-emits (so
/// nothing echoes) nor lets local undo cross it. The merge is the same
/// last-writer-wins on /NM as [PdfSyncSession], so controllers and sessions
/// sharing a transport converge together.
///
/// Experimental scope, which the host is responsible for:
///
/// - **Annotations and comment threads only.** Changes carry a page index,
///   so page insert/remove/reorder on one device would put the other
///   devices' annotations on the wrong pages: the sync turns on
///   [PdfEditingController.pageStructureLocked] while it runs (wire
///   [PdfEditingController.onPageStructureLocked] to tell the user). Content,
///   form and signing edits are not synced at all.
/// - **Identity.** Every participant must start from bytes in which every
///   annotation already has its /NM. Only the first participant may run
///   [PdfEditingController.ensureAnnotationNames], and it must share the
///   named bytes before anyone else joins; names minted independently on
///   two devices never reconcile.
/// - **Catch up before editing.** The clock only moves past the shared
///   history once the transport has delivered it (for the folder
///   transport: await [PdfSharedFolderSyncTransport.startPolling] before
///   enabling edits). Otherwise a fresh participant's first edits lose to
///   older ones.
class PdfEditingSync {
  PdfEditingSync({required this.controller, required this.transport})
      : _clock = PdfSyncClock(transport.sessionId),
        _wasPageStructureLocked = controller.pageStructureLocked {
    controller.pageStructureLocked = true;
    _incoming = transport.incoming.listen(_onRemote);
    _outgoing = controller.annotationChanges.listen(_onLocal);
  }

  /// The edit session being synced.
  final PdfEditingController controller;

  /// The transport changes go out on and come in from. The host owns its
  /// lifecycle: [dispose] does not close it.
  final PdfSyncTransport transport;

  final PdfSyncClock _clock;
  final bool _wasPageStructureLocked;
  late final StreamSubscription<PdfSyncMessage> _incoming;
  late final StreamSubscription<List<PdfAnnotationChange>> _outgoing;
  final StreamController<List<PdfAnnotationChange>> _remoteChanges =
      StreamController<List<PdfAnnotationChange>>.broadcast();
  bool _disposed = false;

  /// This participant's id (the transport's session id).
  String get id => transport.sessionId;

  /// The participants currently connected, this one included.
  Set<String> get peers => transport.peers;

  /// [peers] whenever someone joins or leaves.
  Stream<Set<String>> get presence => transport.presence;

  /// Remote changes that won the merge and changed the document, one batch
  /// per message - for a "Alice added a note" toast or a sidebar flash.
  Stream<List<PdfAnnotationChange>> get remoteChanges => _remoteChanges.stream;

  void _onLocal(List<PdfAnnotationChange> changes) {
    if (_disposed) return;
    for (final change in changes) {
      transport.send(_clock.stamp(change));
    }
  }

  void _onRemote(PdfSyncMessage message) {
    if (_disposed) return;
    if (!_clock.accept(message)) return;
    if (_alreadyHolds(message.change)) return;
    if (controller.applyRemoteChange(message.change)) {
      _remoteChanges.add([message.change]);
    }
  }

  /// Whether the document already holds [change]'s exact annotation - the
  /// common case when a reopened document replays a log it was saved from.
  /// Skipping it saves a revision (and an undo checkpoint) per replayed op.
  bool _alreadyHolds(PdfAnnotationChange change) {
    final snapshot = change.snapshot;
    final name = change.name;
    if (snapshot == null || name == null) return false;
    final found = controller.findAnnotationByName(name);
    if (found == null || found.$1 != change.pageIndex) return false;
    final page = controller.document.page(found.$1);
    final held = PdfAnnotationSnapshot.capture(controller.document, found.$2,
        keepName: true, sourcePageRotation: page.rotation);
    return held != null &&
        jsonEncode(held.toJson()) == jsonEncode(snapshot.toJson());
  }

  /// Stops syncing: local edits are no longer sent and remote ones no
  /// longer applied. Leaves the controller and the transport open.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    controller.pageStructureLocked = _wasPageStructureLocked;
    await _outgoing.cancel();
    await _incoming.cancel();
    await _remoteChanges.close();
  }
}
