// Ground truth for the reflow (reading-view) evaluation corpus.
//
// The corpus is SYNTHESIZED (tool/reflow/corpus.dart), so the truth is not a
// human annotation that can drift from the bytes - the same builder that
// emits a page's content stream records the blocks it laid down. A truth file
// is therefore exact by construction: every block's role, its reading order,
// and the page box it occupies are what the generator actually drew.
//
// Real-world tagged PDFs (a /StructTreeRoot) are a second, opportunistic
// truth source - see `PdfTaggedText` - but only three of the 242 checked-in
// corpus files carry one, which is why the primary corpus is generated.
library;

import 'package:pdf_document/pdf_document.dart';

/// What a block *is*, independent of how any particular engine found it.
enum ReflowRole {
  /// A section heading. Carries a [ReflowTruthBlock.headingLevel].
  heading,

  /// Running prose.
  paragraph,

  /// One item of a bulleted or numbered list.
  listItem,

  /// A figure or table caption.
  caption,

  /// Text inside a table cell.
  tableCell,

  /// A figure: a raster image, or vector artwork that reads as one picture.
  figure,

  /// A footnote body, typically under a rule in smaller type.
  footnote,

  /// A pull quote or sidebar inset out of the main text flow.
  pullQuote,

  /// A running head, running foot, or page number. Page furniture, not
  /// content: a reading view must NOT emit it into the text stream.
  artifact,
}

/// One block the generator drew, with the reading position it belongs at.
class ReflowTruthBlock {
  const ReflowTruthBlock({
    required this.pageIndex,
    required this.role,
    required this.text,
    required this.bounds,
    required this.readingIndex,
    this.headingLevel,
    this.listDepth,
    this.tableId,
    this.isRaster = false,
    this.continuesPrevious = false,
  });

  final int pageIndex;
  final ReflowRole role;

  /// The text a perfect reading view would emit for this block: line breaks
  /// resolved to spaces, end-of-line hyphenation repaired, justification
  /// padding gone. Empty for [ReflowRole.figure].
  final String text;

  /// Page-space box the block occupies.
  final PdfRect bounds;

  /// Document-wide reading position. Artifacts get -1: they have no place in
  /// the reading order because they should not be read at all.
  final int readingIndex;

  /// 1-6 for [ReflowRole.heading], else null.
  final int? headingLevel;

  /// 0-based nesting depth for [ReflowRole.listItem], else null.
  final int? listDepth;

  /// Groups the cells of one table, else null.
  final String? tableId;

  /// True when this block is the tail of a block that began in the previous
  /// column or on the previous page. The generator splits a flowed paragraph
  /// at the break and records both halves, because today's engine reflows one
  /// page at a time by design - so a per-page pipeline can score perfectly
  /// here, and *joining* the halves is measured separately once the pipeline
  /// claims to do it (Phase 3), without regenerating the corpus.
  final bool continuesPrevious;

  /// For [ReflowRole.figure]: true when drawn as an image XObject, false when
  /// drawn as vector artwork. The distinction matters - the reading view
  /// currently surfaces only images, so vector figures score as misses and
  /// that gap shows up as a number instead of an anecdote.
  final bool isRaster;

  bool get isArtifact => role == ReflowRole.artifact;

  Map<String, Object?> toJson() => {
        'page': pageIndex,
        'role': role.name,
        'text': text,
        'bounds': [bounds.left, bounds.bottom, bounds.right, bounds.top],
        'reading': readingIndex,
        if (headingLevel != null) 'level': headingLevel,
        if (listDepth != null) 'depth': listDepth,
        if (tableId != null) 'table': tableId,
        if (role == ReflowRole.figure) 'raster': isRaster,
        if (continuesPrevious) 'continues': true,
      };

  static ReflowTruthBlock fromJson(Map<String, Object?> json) {
    final box = (json['bounds']! as List).cast<num>();
    return ReflowTruthBlock(
      pageIndex: json['page']! as int,
      role: ReflowRole.values.byName(json['role']! as String),
      text: json['text']! as String,
      bounds: PdfRect(box[0].toDouble(), box[1].toDouble(), box[2].toDouble(),
          box[3].toDouble()),
      readingIndex: json['reading']! as int,
      headingLevel: json['level'] as int?,
      listDepth: json['depth'] as int?,
      tableId: json['table'] as String?,
      isRaster: json['raster'] as bool? ?? false,
      continuesPrevious: json['continues'] as bool? ?? false,
    );
  }
}

/// One generated document and everything that is true about it.
class ReflowTruth {
  const ReflowTruth({
    required this.name,
    required this.description,
    required this.pageCount,
    required this.blocks,
  });

  /// Corpus file stem (`two-column` → `two-column.pdf`).
  final String name;

  /// What layout trait this document exists to test.
  final String description;

  final int pageCount;

  /// Every block drawn, artifacts included, in the order they were laid out.
  final List<ReflowTruthBlock> blocks;

  /// The content blocks in reading order (artifacts and figures excluded).
  List<ReflowTruthBlock> get readableBlocks => [
        for (final b in blocks)
          if (!b.isArtifact && b.role != ReflowRole.figure) b
      ]..sort((a, b) => a.readingIndex.compareTo(b.readingIndex));

  List<ReflowTruthBlock> get artifacts => [
        for (final b in blocks)
          if (b.isArtifact) b
      ];

  List<ReflowTruthBlock> get figures => [
        for (final b in blocks)
          if (b.role == ReflowRole.figure) b
      ];

  Map<String, Object?> toJson() => {
        'name': name,
        'description': description,
        'pages': pageCount,
        'blocks': [for (final b in blocks) b.toJson()],
      };

  static ReflowTruth fromJson(Map<String, Object?> json) => ReflowTruth(
        name: json['name']! as String,
        description: json['description']! as String,
        pageCount: json['pages']! as int,
        blocks: [
          for (final b
              in (json['blocks']! as List).cast<Map<String, Object?>>())
            ReflowTruthBlock.fromJson(b)
        ],
      );
}
