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
    this.group,
  });

  /// Creates a library item with a process-unique persistent identifier.
  factory PdfSavedAnnotation.create({
    required String name,
    required PdfAnnotationSnapshot snapshot,
    String? group,
  }) =>
      PdfSavedAnnotation(
        id: _nextLibraryId('annotation'),
        name: name,
        snapshot: snapshot,
        group: _normalizedGroup(group),
      );

  /// Stable identity used by rename/delete operations.
  final String id;

  /// User-facing label shown in the annotation library.
  final String name;

  /// Fully detached annotation payload, including its appearance.
  final PdfAnnotationSnapshot snapshot;

  /// Optional user-defined library group. Null means the item is ungrouped.
  final String? group;

  /// Copies this entry. Pass `group: (null,)` to move it to Ungrouped;
  /// omitting [group] keeps its current group.
  PdfSavedAnnotation copyWith({String? name, (String?,)? group}) =>
      PdfSavedAnnotation(
        id: id,
        name: name ?? this.name,
        snapshot: snapshot,
        group: group == null ? this.group : _normalizedGroup(group.$1),
      );

  String encode() => jsonEncode({
        'v': 1,
        'id': id,
        'name': name,
        if (group != null) 'group': group,
        'snapshot': snapshot.toJson(),
      });

  /// Parses [encode]'s output; null for malformed or incompatible entries.
  static PdfSavedAnnotation? decode(String source) {
    try {
      final map = jsonDecode(source);
      if (map is! Map<String, dynamic> || map['v'] != 1) return null;
      final id = map['id'];
      final name = map['name'];
      final group = map['group'];
      final snapshot = map['snapshot'];
      if (id is! String ||
          id.isEmpty ||
          name is! String ||
          name.trim().isEmpty ||
          (group != null && group is! String) ||
          snapshot is! Map) {
        return null;
      }
      return PdfSavedAnnotation(
        id: id,
        name: name,
        group: _normalizedGroup(group as String?),
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

String? _normalizedGroup(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

int _libraryIdCounter = 0;

String _nextLibraryId(String kind) {
  final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final sequence = (_libraryIdCounter++).toRadixString(36);
  return '$kind-$micros-$sequence';
}
