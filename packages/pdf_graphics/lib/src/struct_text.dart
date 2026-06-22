/// The logical structure tree joined to extracted text — the read-path
/// bridge between the COS-level structure tree (pdf_document's
/// [PdfStructTree]) and the positioned text runs this layer extracts.
///
/// [PdfStructTree] knows which marked-content ids (/MCID) each structure
/// element tags but cannot decode page text (that needs the font engine,
/// which lives here). This module extracts each page's MCID-tagged runs and
/// joins them back onto the structure tree, yielding a logical document whose
/// elements carry their real Unicode text in reading order.
library;

import 'package:pdf_document/pdf_document.dart';

import 'text_extraction.dart';

/// A node of the logical structure tree with its tagged text filled in.
class PdfLogicalNode {
  PdfLogicalNode({
    required this.element,
    required this.text,
    required this.children,
  });

  /// The underlying structure element (type, alt text, language, …).
  final PdfStructElement element;

  /// The text this element directly tags (its own /MCID marked content),
  /// already in reading order. Empty for grouping elements (e.g. a /Document
  /// or /Sect whose text lives in descendants) and for non-text content.
  final String text;

  /// Child logical nodes, in reading order.
  final List<PdfLogicalNode> children;

  /// The raw structure type (e.g. 'H1', 'P', 'Figure', or a custom role).
  String get structureType => element.structureType;

  /// The structure type mapped to a standard type through the role map.
  String get standardType => element.standardType;

  /// The best accessible text for this node alone: replacement text
  /// (/ActualText) wins, then the tagged [text], then the alternate
  /// description (/Alt) — the order a screen reader would announce.
  String get accessibleText {
    final actual = element.actualText;
    if (actual != null && actual.isNotEmpty) return actual;
    if (text.isNotEmpty) return text;
    return element.alt ?? '';
  }

  /// This node's accessible text followed by every descendant's, joined in
  /// reading order. Grouping elements thus surface their whole subtree.
  String get fullText {
    final parts = <String>[];
    final own = accessibleText;
    if (own.isNotEmpty) parts.add(own);
    for (final child in children) {
      final sub = child.fullText;
      if (sub.isNotEmpty) parts.add(sub);
    }
    return parts.join('\n');
  }
}

/// The whole document's logical structure with text joined in.
class PdfTaggedDocument {
  PdfTaggedDocument({required this.roots});

  /// Top-level logical nodes (the structure tree's roots), in reading order.
  final List<PdfLogicalNode> roots;

  /// Every node in reading order (depth-first pre-order).
  List<PdfLogicalNode> get nodesInReadingOrder {
    final out = <PdfLogicalNode>[];
    void visit(PdfLogicalNode n) {
      out.add(n);
      for (final c in n.children) {
        visit(c);
      }
    }

    for (final r in roots) {
      visit(r);
    }
    return out;
  }

  /// The document's full reading-order text.
  String get text => roots.map((n) => n.fullText).join('\n').trim();
}

/// Joins a document's structure tree to its extracted text.
class PdfTaggedText {
  PdfTaggedText._();

  /// Builds the logical structure of [document] with text joined in, or null
  /// when the document carries no structure tree.
  static PdfTaggedDocument? extract(PdfDocument document) {
    final tree = PdfStructTree.of(document);
    if (tree == null) return null;

    // Extract each page's MCID-tagged text once, lazily. A page's tagged
    // text is indexed by MCID; runs sharing an MCID are sliced from the page
    // text so separators (spaces/newlines) are preserved.
    final cache = <int, Map<int, String>>{};

    Map<int, String> mcidTextFor(int pageIndex) => cache.putIfAbsent(
        pageIndex, () => _mcidText(PdfTextExtractor.extract(document, pageIndex)));

    String elementText(PdfStructElement element) {
      final parts = <String>[];
      for (final ref in element.markedContent) {
        final pageIndex = ref.pageIndex;
        if (pageIndex < 0) continue;
        final text = mcidTextFor(pageIndex)[ref.mcid];
        if (text != null && text.isNotEmpty) parts.add(text);
      }
      return parts.join(' ');
    }

    PdfLogicalNode build(PdfStructElement element) => PdfLogicalNode(
          element: element,
          text: elementText(element),
          children: [for (final c in element.children) build(c)],
        );

    return PdfTaggedDocument(roots: [for (final r in tree.children) build(r)]);
  }

  /// Maps each MCID on a page to its concatenated text, sliced from the
  /// page's full text so inter-run spacing is preserved.
  static Map<int, String> _mcidText(PdfPageText page) {
    // Per MCID, track the span of the page text its runs cover.
    final span = <int, (int start, int end)>{};
    for (final run in page.runs) {
      final mcid = run.mcid;
      if (mcid == null) continue;
      final start = run.startIndex;
      final end = run.startIndex + run.text.length;
      final existing = span[mcid];
      span[mcid] = existing == null
          ? (start, end)
          : (existing.$1 < start ? existing.$1 : start,
              existing.$2 > end ? existing.$2 : end);
    }
    return {
      for (final entry in span.entries)
        entry.key: page.text.substring(entry.value.$1, entry.value.$2),
    };
  }
}
