import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where [PdfEditingController] keeps password-field values instead of the
/// PDF (ISO 32000 §12.7.4.3: readers "shall never store the value" of a
/// password field in the file).
///
/// Values are filed per document under a stable document id
/// ([pdfFormSecretDocumentId] - the trailer /ID, which incremental saves
/// carry forward) and per field under its fully qualified name, so
/// reopening the same document on the same device brings its passwords
/// back and a different document never sees them.
///
/// Mirrors [PdfIdentityStore]: async and backend-agnostic, with an
/// [InMemoryFormSecretStore] for tests and session-only use, and a
/// [SecureFormSecretStore] on the platform Keychain/Keystore.
abstract interface class PdfFormSecretStore {
  /// Every value stored for [documentId], keyed by field name.
  Future<Map<String, String>> readAll(String documentId);

  /// The value stored for [fieldName] in [documentId], or null.
  Future<String?> read(String documentId, String fieldName);

  /// Stores [value] for [fieldName] in [documentId], replacing any other.
  Future<void> write(String documentId, String fieldName, String value);

  /// Forgets [fieldName]'s value in [documentId] (a no-op when absent).
  Future<void> remove(String documentId, String fieldName);

  /// Forgets every value stored for [documentId].
  Future<void> clearDocument(String documentId);
}

/// The [PdfFormSecretStore] key for a document whose permanent identifier
/// (`pdfPermanentDocumentId` in pdf_document) is [permanentId]: lowercase
/// hex.
String pdfFormSecretDocumentId(Uint8List permanentId) => [
      for (final b in permanentId) b.toRadixString(16).padLeft(2, '0'),
    ].join();

/// A [PdfFormSecretStore] held in memory - values live only as long as the
/// store object. Used for tests, and by hosts (the web app) that must not
/// persist passwords at all.
class InMemoryFormSecretStore implements PdfFormSecretStore {
  final Map<String, Map<String, String>> _byDocument = {};

  @override
  Future<Map<String, String>> readAll(String documentId) async =>
      Map.of(_byDocument[documentId] ?? const {});

  @override
  Future<String?> read(String documentId, String fieldName) async =>
      _byDocument[documentId]?[fieldName];

  @override
  Future<void> write(String documentId, String fieldName, String value) async {
    (_byDocument[documentId] ??= {})[fieldName] = value;
  }

  @override
  Future<void> remove(String documentId, String fieldName) async {
    final values = _byDocument[documentId];
    if (values == null) return;
    values.remove(fieldName);
    if (values.isEmpty) _byDocument.remove(documentId);
  }

  @override
  Future<void> clearDocument(String documentId) async {
    _byDocument.remove(documentId);
  }
}

/// A [PdfFormSecretStore] backed by the platform Keychain/Keystore via
/// `flutter_secure_storage`. Each document's values are one JSON object
/// under `'$keyPrefix$documentId'`, and an index of document ids is kept
/// under a reserved key so [clearAll] can find them.
///
/// Not for the web: `flutter_secure_storage`'s web backend keeps its key
/// next to the data in browser storage, so it is not actually secret
/// there. Use [InMemoryFormSecretStore] on the web.
class SecureFormSecretStore implements PdfFormSecretStore {
  SecureFormSecretStore({
    FlutterSecureStorage? storage,
    this.keyPrefix = 'pdf_form_secret.',
  }) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// The key namespace, so entries don't collide with the host's own
  /// secure-storage entries (or with [SecureIdentityStore]'s).
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
  Future<Map<String, String>> readAll(String documentId) async {
    final raw = await _storage.read(key: '$keyPrefix$documentId');
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {
      for (final e in decoded.entries)
        if (e.key is String && e.value is String)
          e.key as String: e.value as String,
    };
  }

  @override
  Future<String?> read(String documentId, String fieldName) async =>
      (await readAll(documentId))[fieldName];

  Future<void> _writeAll(String documentId, Map<String, String> values) async {
    if (values.isEmpty) {
      await clearDocument(documentId);
      return;
    }
    await _storage.write(
        key: '$keyPrefix$documentId', value: jsonEncode(values));
    final ids = await _index();
    if (!ids.contains(documentId)) await _writeIndex([...ids, documentId]);
  }

  @override
  Future<void> write(String documentId, String fieldName, String value) async {
    final values = await readAll(documentId);
    values[fieldName] = value;
    await _writeAll(documentId, values);
  }

  @override
  Future<void> remove(String documentId, String fieldName) async {
    final values = await readAll(documentId);
    if (values.remove(fieldName) == null) return;
    await _writeAll(documentId, values);
  }

  @override
  Future<void> clearDocument(String documentId) async {
    await _storage.delete(key: '$keyPrefix$documentId');
    final ids = await _index();
    if (ids.remove(documentId)) await _writeIndex(ids);
  }

  /// Forgets every stored value for every document.
  Future<void> clearAll() async {
    for (final id in await _index()) {
      await _storage.delete(key: '$keyPrefix$id');
    }
    await _storage.delete(key: _indexKey);
  }
}
