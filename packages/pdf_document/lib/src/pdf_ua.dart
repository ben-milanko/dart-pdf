/// A machine-checkable PDF/UA-1 (ISO 14289-1) validator. It checks the
/// rules that can be decided from the file structure - tagging, metadata,
/// language, fully-tagged content, figure alt text, standard roles - and
/// emits a [PdfConformanceReport]. Requirements a machine cannot judge
/// (whether alt text is *meaningful*, whether reading order is correct) are
/// out of scope or surfaced as warnings.
library;

import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';

import 'conformance.dart';
import 'document.dart';
import 'struct_tree.dart';
import 'xmp.dart';

/// Standard structure types (PDF 1.7 Table 333). Any other type must be
/// mapped onto one of these through the structure tree's /RoleMap.
const Set<String> kStandardStructureTypes = {
  'Document', 'Part', 'Art', 'Sect', 'Div', 'BlockQuote', 'Caption', 'TOC',
  'TOCI', 'Index', 'NonStruct', 'Private', 'P', 'H', 'H1', 'H2', 'H3', 'H4',
  'H5', 'H6', 'L', 'LI', 'Lbl', 'LBody', 'Table', 'TR', 'TH', 'TD', 'THead',
  'TBody', 'TFoot', 'Span', 'Quote', 'Note', 'Reference', 'BibEntry', 'Code',
  'Link', 'Annot', 'Ruby', 'RB', 'RT', 'RP', 'Warichu', 'WT', 'WP', 'Figure',
  'Formula', 'Form',
};

/// Validates [document] against PDF/UA-1.
PdfConformanceReport validatePdfUa(PdfDocument document) =>
    _PdfUaValidator(document).run();

class _PdfUaValidator {
  _PdfUaValidator(this.document);

  final PdfDocument document;
  final issues = <PdfConformanceIssue>[];

  CosDocument get cos => document.cos;

  void _err(String rule, String message, {int? pageIndex, int? objectNumber}) =>
      issues.add(PdfConformanceIssue(
          rule: rule,
          severity: PdfConformanceSeverity.error,
          message: message,
          pageIndex: pageIndex,
          objectNumber: objectNumber));

  void _warn(String rule, String message, {int? pageIndex}) =>
      issues.add(PdfConformanceIssue(
          rule: rule,
          severity: PdfConformanceSeverity.warning,
          message: message,
          pageIndex: pageIndex));

  PdfConformanceReport run() {
    final tree = PdfStructTree.of(document);

    // 7.1 - the document must be marked as Tagged PDF.
    if (!pdfIsMarkedTagged(document)) {
      _err('UA1:7.1',
          'Document is not marked as tagged (/MarkInfo << /Marked true >>).');
    }
    final markInfo = cos.resolve(document.catalog['MarkInfo']);
    if (markInfo is CosDictionary) {
      final suspects = cos.resolve(markInfo['Suspects']);
      if (suspects is CosBoolean && suspects.value) {
        _err('UA1:7.1',
            '/MarkInfo /Suspects is true: content may not be reliably tagged.');
      }
    }

    // 7.1 - a structure tree is required.
    if (tree == null) {
      _err('UA1:7.1', 'No /StructTreeRoot: the document has no structure tree.');
    }

    // 7.2 - natural language must be specified for the document.
    final lang = cos.resolve(document.catalog['Lang']);
    if (lang is! CosString || lang.text.trim().isEmpty) {
      _err('UA1:7.2',
          'Document /Lang is missing: a default natural language is required.');
    }

    // 7.1 - the title must be set and shown in the title bar.
    _checkTitle();

    // 5 - XMP metadata must carry the PDF/UA identifier.
    _checkMetadata();

    if (tree != null) {
      _checkRolesAndFigures(tree);
      _checkContentTagging(tree);
    }
    _checkLinks();

    return PdfConformanceReport('PDF/UA-1', issues);
  }

  void _checkTitle() {
    final title = document.info['Title'];
    final hasTitle = title != null && title.trim().isNotEmpty;
    if (!hasTitle) {
      _err('UA1:7.1',
          'Document title (/Info /Title or dc:title) is missing or empty.');
    }
    final vp = cos.resolve(document.catalog['ViewerPreferences']);
    final display =
        vp is CosDictionary ? cos.resolve(vp['DisplayDocTitle']) : null;
    if (display is! CosBoolean || !display.value) {
      _err('UA1:7.1',
          '/ViewerPreferences /DisplayDocTitle must be true so the title '
          '(not the file name) is shown.');
    }
  }

  void _checkMetadata() {
    final meta = cos.resolve(document.catalog['Metadata']);
    if (meta is! CosStream) {
      _err('UA1:5', 'No XMP /Metadata stream in the catalog.');
      return;
    }
    final bytes = cos.decodeStreamData(meta);
    final part = readPdfUaPart(bytes);
    if (part != 1) {
      _err('UA1:5',
          'XMP metadata does not declare pdfuaid:part = 1 '
          '(found ${part ?? 'none'}).');
    }
  }

  void _checkRolesAndFigures(PdfStructTree tree) {
    for (final element in tree.elementsInReadingOrder()) {
      final type = element.structureType;
      final standard = element.standardType;
      if (type.isEmpty) {
        _err('UA1:7.1', 'Structure element has no /S structure type.');
        continue;
      }
      if (!kStandardStructureTypes.contains(standard)) {
        _err('UA1:7.1',
            'Structure type "$type" is not a standard type and is not mapped '
            'to one through /RoleMap.');
      }
      // 7.3 - figures need a text alternative.
      if (standard == 'Figure') {
        final hasAlt = (element.alt?.trim().isNotEmpty ?? false) ||
            (element.actualText?.trim().isNotEmpty ?? false);
        if (!hasAlt) {
          _err('UA1:7.3',
              'Figure structure element has no /Alt or /ActualText.');
        }
      }
      // 7.10 - formulas likewise need an alternative.
      if (standard == 'Formula') {
        final hasAlt = (element.alt?.trim().isNotEmpty ?? false) ||
            (element.actualText?.trim().isNotEmpty ?? false);
        if (!hasAlt) {
          _warn('UA1:7.10',
              'Formula structure element has no /Alt or /ActualText.');
        }
      }
    }
  }

  /// 7.1 - every piece of real content must be tagged: inside a marked-content
  /// sequence that is either part of the structure tree (has an /MCID present
  /// in the structure tree) or an artifact.
  void _checkContentTagging(PdfStructTree tree) {
    final structMcids = _structureMcidsPerPage(tree);
    for (var p = 0; p < document.pageCount; p++) {
      final page = document.page(p);
      final scan = _scanContent(page.contentBytes(), page.resources);
      if (scan.untagged > 0) {
        _err('UA1:7.1',
            '${scan.untagged} piece(s) of real content are outside any '
            'marked-content sequence (not tagged, not artifacts).',
            pageIndex: p);
      }
      final known = structMcids[p] ?? const <int>{};
      final orphans = scan.mcids.difference(known);
      if (orphans.isNotEmpty) {
        _err('UA1:7.1',
            'Marked content with MCID(s) ${orphans.toList()..sort()} is not '
            'referenced by the structure tree.',
            pageIndex: p);
      }
    }
  }

  Map<int, Set<int>> _structureMcidsPerPage(PdfStructTree tree) {
    final map = <int, Set<int>>{};
    for (final element in tree.elementsInReadingOrder()) {
      for (final ref in element.markedContent) {
        final pi = ref.pageIndex;
        if (pi >= 0) (map[pi] ??= <int>{}).add(ref.mcid);
      }
    }
    return map;
  }

  /// 7.18 - link annotations should be tagged. Mechanically we can only check
  /// that each /Link annotation carries a /StructParent tying it into the
  /// parent tree; the semantic Link-element nesting is reported as a warning.
  void _checkLinks() {
    for (var p = 0; p < document.pageCount; p++) {
      for (final annot in document.page(p).annotations) {
        if (annot.subtype != 'Link') continue;
        final sp = cos.resolve(annot.dict['StructParent']);
        if (sp is! CosInteger) {
          _warn('UA1:7.18',
              'Link annotation is not tied to the structure tree '
              '(no /StructParent).',
              pageIndex: p);
        }
      }
    }
  }

  /// Walks a page content stream, counting real-content operators that fall
  /// outside any tagging, and collecting the MCIDs that appear.
  _ContentScan _scanContent(Uint8List contentBytes, CosDictionary resources) {
    final ops = ContentStreamParser.parse(contentBytes);
    final stack = <_McFrame>[];
    final mcids = <int>{};
    var untagged = 0;

    bool inMcid() => stack.any((f) => f.mcid != null);
    bool inArtifact() => stack.any((f) => f.artifact);

    for (final op in ops) {
      switch (op.operator) {
        case 'BDC':
          final frame = _frameForBdc(op.operands, resources);
          if (frame.mcid != null) mcids.add(frame.mcid!);
          stack.add(frame);
        case 'BMC':
          final tag = op.operands.isNotEmpty ? op.operands[0] : null;
          stack.add(_McFrame(
              null, tag is CosName && tag.value == 'Artifact'));
        case 'EMC':
          if (stack.isNotEmpty) stack.removeLast();
        default:
          if (_isRealContentOp(op.operator) &&
              !inMcid() &&
              !inArtifact()) {
            untagged++;
          }
      }
    }
    return _ContentScan(untagged, mcids);
  }

  _McFrame _frameForBdc(List<CosObject> operands, CosDictionary resources) {
    final tag = operands.isNotEmpty ? operands[0] : null;
    final artifact = tag is CosName && tag.value == 'Artifact';
    int? mcid;
    if (operands.length >= 2) {
      var props = operands[1];
      if (props is CosName) {
        final dict = cos.resolve(resources['Properties']);
        final named = dict is CosDictionary ? dict[props.value] : null;
        if (named != null) props = cos.resolve(named);
      }
      if (props is CosDictionary) {
        final m = cos.resolve(props['MCID']);
        if (m is CosInteger) mcid = m.value;
      }
    }
    return _McFrame(mcid, artifact);
  }

  static bool _isRealContentOp(String op) => const {
        'Tj', 'TJ', "'", '"', // text
        'S', 's', 'f', 'F', 'f*', 'B', 'B*', 'b', 'b*', // path painting
        'sh', 'Do', 'BI', // shading, xobject, inline image
      }.contains(op);
}

class _McFrame {
  _McFrame(this.mcid, this.artifact);
  final int? mcid;
  final bool artifact;
}

class _ContentScan {
  _ContentScan(this.untagged, this.mcids);
  final int untagged;
  final Set<int> mcids;
}
