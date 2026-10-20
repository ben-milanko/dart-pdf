import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pdf_document/pdf_document.dart';

/// Persistence for one-tap [PdfSigningIdentity]s (see
/// [PdfSigningIdentity.generate]). An identity is stored by a caller-chosen
/// [id] as its PEM (`toPem()`), which carries the unprotected private key -
/// so the production backend, [SecureIdentityStore], keeps it in the platform
/// Keychain/Keystore rather than in preferences.
///
/// Implementations are async and backend-agnostic; the "Create signing
/// identity" dialog takes one so the host chooses where keys live (or passes
/// an [InMemoryIdentityStore] for an ephemeral, in-session identity).
abstract interface class PdfIdentityStore {
  /// The ids of every stored identity.
  Future<List<String>> ids();

  /// Loads the identity stored under [id], or null when there is none.
  Future<PdfSigningIdentity?> load(String id);

  /// Stores [identity] under [id], replacing any existing one.
  Future<void> save(String id, PdfSigningIdentity identity);

  /// Removes the identity stored under [id] (a no-op when absent).
  Future<void> delete(String id);
}

/// An in-memory [PdfIdentityStore] - identities live only for the session.
/// Useful for tests and for a "don't remember me" flow.
class InMemoryIdentityStore implements PdfIdentityStore {
  final Map<String, String> _pemById = {};

  @override
  Future<List<String>> ids() async => _pemById.keys.toList(growable: false);

  @override
  Future<PdfSigningIdentity?> load(String id) async {
    final pem = _pemById[id];
    return pem == null ? null : PdfSigningIdentity.fromPem(pem, name: id);
  }

  @override
  Future<void> save(String id, PdfSigningIdentity identity) async {
    _pemById[id] = identity.toPem();
  }

  @override
  Future<void> delete(String id) async {
    _pemById.remove(id);
  }
}

/// A [PdfIdentityStore] backed by the platform Keychain/Keystore via
/// `flutter_secure_storage`, so the private key never lands in plaintext
/// preferences. Each identity's PEM is stored under `'$keyPrefix$id'`, and an
/// index of ids is kept under a reserved key so [ids] can enumerate them.
class SecureIdentityStore implements PdfIdentityStore {
  SecureIdentityStore({
    FlutterSecureStorage? storage,
    this.keyPrefix = 'pdf_signing_identity.',
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// The key namespace, so identities don't collide with the host's own
  /// secure-storage entries.
  final String keyPrefix;

  String get _indexKey => '${keyPrefix}__index';

  Future<List<String>> _index() async {
    final raw = await _storage.read(key: _indexKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded.cast<String>() : <String>[];
  }

  Future<void> _writeIndex(List<String> ids) =>
      _storage.write(key: _indexKey, value: jsonEncode(ids));

  @override
  Future<List<String>> ids() => _index();

  @override
  Future<PdfSigningIdentity?> load(String id) async {
    final pem = await _storage.read(key: '$keyPrefix$id');
    return pem == null ? null : PdfSigningIdentity.fromPem(pem, name: id);
  }

  @override
  Future<void> save(String id, PdfSigningIdentity identity) async {
    await _storage.write(key: '$keyPrefix$id', value: identity.toPem());
    final ids = await _index();
    if (!ids.contains(id)) {
      await _writeIndex([...ids, id]);
    }
  }

  @override
  Future<void> delete(String id) async {
    await _storage.delete(key: '$keyPrefix$id');
    final ids = await _index();
    if (ids.remove(id)) {
      await _writeIndex(ids);
    }
  }
}
