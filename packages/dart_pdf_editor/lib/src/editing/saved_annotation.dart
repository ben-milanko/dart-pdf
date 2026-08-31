import 'dart:convert';

import 'package:pdf_document/pdf_document.dart';

/// A named, reusable annotation captured as a detached
/// [PdfAnnotationSnapshot].
///
/// The snapshot includes the annotation's appearance streams and has no
/// dependency on the document it came from, so library items survive edits,
/// app restarts, and placement into another PDF. The capture deliberately
/// drops /NM: every placement is a new annotation and receives a fresh
/// identity from [PdfEditor.pasteAnnotation].
class PdfSavedAnnotation {
  const PdfSavedAnnotation({
    required this.id,
    required this.name,
    required this.snapshot,
  });

  /// Creates a library item with a process-unique persistent identifier.
  factory PdfSavedAnnotation.create({
    required String name,
    required PdfAnnotationSnapshot snapshot,
  }) =>
      PdfSavedAnnotation(
        id: _nextLibraryId('annotation'),
        name: name,
        snapshot: snapshot,
      );

  /// Stable identity used by rename/delete operations.
  final String id;

  /// User-facing label shown in the annotation library.
  final String name;

  /// Fully detached annotation payload, including its appearance.
  final PdfAnnotationSnapshot snapshot;

  PdfSavedAnnotation copyWith({String? name}) => PdfSavedAnnotation(
        id: id,
        name: name ?? this.name,
        snapshot: snapshot,
      );

  String encode() => jsonEncode({
        'v': 1,
        'id': id,
        'name': name,
        'snapshot': snapshot.toJson(),
      });

  /// Parses [encode]'s output; null for malformed or incompatible entries.
  static PdfSavedAnnotation? decode(String source) {
    try {
      final map = jsonDecode(source);
      if (map is! Map<String, dynamic> || map['v'] != 1) return null;
      final id = map['id'];
      final name = map['name'];
      final snapshot = map['snapshot'];
      if (id is! String ||
          id.isEmpty ||
          name is! String ||
          name.trim().isEmpty ||
          snapshot is! Map) {
        return null;
      }
      return PdfSavedAnnotation(
        id: id,
        name: name,
        snapshot: PdfAnnotationSnapshot.fromJson(
          Map<String, dynamic>.from(snapshot),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PdfSavedAnnotation && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

int _libraryIdCounter = 0;

String _nextLibraryId(String kind) {
  final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final sequence = (_libraryIdCounter++).toRadixString(36);
  return '$kind-$micros-$sequence';
}
