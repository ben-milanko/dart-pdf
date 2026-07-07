/// A machine-checkable PDF/A (ISO 19005) conformance checker for the level-B
/// profiles A-1b, A-2b and A-3b. It reports the structural violations that can
/// be decided from the file: encryption, trailer /ID, version, OutputIntent +
/// ICC, XMP identification, font embedding, banned filters, JavaScript and
/// other forbidden actions, and (for A-1/A-2) embedded files. Emits a
/// [PdfConformanceReport].
library;

import 'package:pdf_cos/pdf_cos.dart';

import 'conformance.dart';
import 'document.dart';
import 'xmp.dart';

/// Validates [document] against PDF/A-[part]b (part 1, 2, or 3; level B).
PdfConformanceReport validatePdfA(PdfDocument document,
        {int part = 2, String level = 'B'}) =>
    _PdfAValidator(document, part, level.toUpperCase()).run();

class _PdfAValidator {
  _PdfAValidator(this.document, this.part, this.level);

  final PdfDocument document;
  final int part;
  final String level;
  final issues = <PdfConformanceIssue>[];

  CosDocument get cos => document.cos;
  String get profile => 'PDF/A-$part${level.toLowerCase()}';

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
    _checkEncryption();
    _checkId();
    _checkVersion();
    _checkOutputIntent();
    _checkMetadata();
    _checkFonts();
    _checkFilters();
    _checkActions();
    _checkEmbeddedFiles();
    _checkAnnotations();
    return PdfConformanceReport(profile, issues);
  }

  // 6.1.3 - a conforming file shall not be encrypted.
  void _checkEncryption() {
    if (cos.isEncrypted) {
      _err('A$part:6.1.3', 'The document is encrypted; PDF/A forbids '
          'encryption and any security handler.');
    }
  }

  // 6.1.3 - the file trailer shall contain an /ID.
  void _checkId() {
    final id = cos.resolve(cos.trailer['ID']);
    if (id is! CosArray || id.length < 2) {
      _err('A$part:6.1.3', 'The trailer is missing a valid /ID array.');
    }
  }

  // The version shall not exceed the profile's PDF version (A-1 → 1.4,
  // A-2/A-3 → 1.7). A catalog /Version name overrides the header.
  void _checkVersion() {
    final catVersion = cos.resolve(document.catalog['Version']);
    final version =
        catVersion is CosName ? catVersion.value : document.version;
    final max = part == 1 ? 1.4 : 1.7;
    final value = double.tryParse(version) ?? 0;
    if (value > max + 1e-9) {
      _err('A$part:6.1.2',
          'PDF version $version exceeds the maximum ($max) for this profile.');
    }
  }

  // 6.2.2 - an OutputIntent with subtype GTS_PDFA1 and a DestOutputProfile
  // ICC stream is required when device-dependent colour is used. We require it
  // unconditionally for level B (the safe assumption for arbitrary content).
  void _checkOutputIntent() {
    final intents = cos.resolve(document.catalog['OutputIntents']);
    if (intents is! CosArray || intents.length == 0) {
      _err('A$part:6.2.2',
          'No /OutputIntents: a PDF/A OutputIntent with an ICC '
          'DestOutputProfile is required.');
      return;
    }
    var foundPdfa = false;
    for (final entry in intents.items) {
      final dict = cos.resolve(entry);
      if (dict is! CosDictionary) continue;
      final s = cos.resolve(dict['S']);
      if (s is CosName && s.value == 'GTS_PDFA1') {
        foundPdfa = true;
        final profileStream = cos.resolve(dict['DestOutputProfile']);
        if (profileStream is! CosStream) {
          _err('A$part:6.2.2',
              'The PDF/A OutputIntent has no /DestOutputProfile ICC stream.');
        } else {
          final n = cos.resolve(profileStream.dictionary['N']);
          if (n is! CosInteger || ![1, 3, 4].contains(n.value)) {
            _err('A$part:6.2.2',
                'The OutputIntent ICC profile has an invalid /N '
                '(must be 1, 3 or 4).');
          }
        }
      }
    }
    if (!foundPdfa) {
      _err('A$part:6.2.2',
          'No OutputIntent with /S /GTS_PDFA1 was found.');
    }
  }

  // 6.7 - XMP metadata with the pdfaid part and conformance is required.
  void _checkMetadata() {
    final meta = cos.resolve(document.catalog['Metadata']);
    if (meta is! CosStream) {
      _err('A$part:6.7.2', 'No XMP /Metadata stream in the catalog.');
      return;
    }
    final bytes = cos.decodeStreamData(meta);
    final declaredPart = readPdfaPart(bytes);
    final declaredLevel = readPdfaConformance(bytes);
    if (declaredPart != part) {
      _err('A$part:6.7.3',
          'XMP pdfaid:part is ${declaredPart ?? 'absent'}, expected $part.');
    }
    if (declaredLevel?.toUpperCase() != level) {
      _err('A$part:6.7.3',
          'XMP pdfaid:conformance is ${declaredLevel ?? 'absent'}, '
          'expected $level.');
    }
  }

  // 6.3 - every font used for rendering shall be embedded.
  void _checkFonts() {
    final visited = <CosDictionary>{};
    for (var p = 0; p < document.pageCount; p++) {
      _checkResourceFonts(document.page(p).resources, p, visited);
    }
  }

  void _checkResourceFonts(
      CosDictionary resources, int pageIndex, Set<CosDictionary> visited) {
    final fonts = cos.resolve(resources['Font']);
    if (fonts is CosDictionary) {
      fonts.entries.forEach((name, value) {
        final font = cos.resolve(value);
        if (font is CosDictionary && visited.add(font)) {
          if (!_fontEmbedded(font)) {
            final base = cos.resolve(font['BaseFont']);
            final label = base is CosName ? base.value : name;
            _err('A$part:6.3.4',
                'Font "$label" is not embedded.', pageIndex: pageIndex);
          }
        }
      });
    }
    // Recurse one level into form XObjects' own resources.
    final xobjects = cos.resolve(resources['XObject']);
    if (xobjects is CosDictionary) {
      for (final value in xobjects.entries.values) {
        final xobj = cos.resolve(value);
        if (xobj is CosStream) {
          final res = cos.resolve(xobj.dictionary['Resources']);
          if (res is CosDictionary && visited.add(res)) {
            _checkResourceFonts(res, pageIndex, visited);
          }
        }
      }
    }
  }

  bool _fontEmbedded(CosDictionary font) {
    final subtype = cos.resolve(font['Subtype']);
    final name = subtype is CosName ? subtype.value : '';
    if (name == 'Type3') return true; // glyphs are content streams
    if (name == 'Type0') {
      final desc = cos.resolve(font['DescendantFonts']);
      final descFont =
          desc is CosArray && desc.length > 0 ? cos.resolve(desc[0]) : null;
      if (descFont is! CosDictionary) return false;
      return _descriptorHasFile(cos.resolve(descFont['FontDescriptor']));
    }
    return _descriptorHasFile(cos.resolve(font['FontDescriptor']));
  }

  bool _descriptorHasFile(CosObject? fd) {
    if (fd is! CosDictionary) return false;
    for (final key in const ['FontFile', 'FontFile2', 'FontFile3']) {
      if (cos.resolve(fd[key]) is CosStream) return true;
    }
    return false;
  }

  // 6.1.x - LZWDecode is forbidden (so is the deprecated /Crypt usage).
  void _checkFilters() {
    var reported = false;
    for (final number in cos.objectNumbers) {
      if (reported) break;
      CosObject obj;
      try {
        obj = cos.getObject(number, 0);
      } catch (_) {
        continue;
      }
      if (obj is! CosStream) continue;
      final filter = cos.resolve(obj.dictionary['Filter']);
      final names = <String>[
        if (filter is CosName) filter.value,
        if (filter is CosArray)
          for (final f in filter.items)
            if (cos.resolve(f) is CosName) (cos.resolve(f) as CosName).value,
      ];
      if (names.contains('LZWDecode')) {
        _err('A$part:6.1.10',
            'LZWDecode filter is used (forbidden in PDF/A).',
            objectNumber: number);
        reported = true;
      }
    }
  }

  // 6.6.1 - interactive features that run code are forbidden.
  void _checkActions() {
    final names = cos.resolve(document.catalog['Names']);
    if (names is CosDictionary &&
        cos.resolve(names['JavaScript']) is CosDictionary) {
      _err('A$part:6.6.1',
          'Document-level JavaScript (/Names /JavaScript) is forbidden.');
    }
    if (cos.resolve(document.catalog['AA']) is CosDictionary) {
      _err('A$part:6.6.1',
          'Catalog additional-actions (/AA) are forbidden.');
    }
    for (var p = 0; p < document.pageCount; p++) {
      final page = document.page(p);
      if (cos.resolve(page.dict['AA']) is CosDictionary) {
        _err('A$part:6.6.1', 'Page additional-actions (/AA) are forbidden.',
            pageIndex: p);
      }
      for (final annot in page.annotations) {
        final action = cos.resolve(annot.dict['A']);
        if (action is CosDictionary) {
          final s = cos.resolve(action['S']);
          final type = s is CosName ? s.value : '';
          if (type == 'JavaScript' || type == 'Launch') {
            _err('A$part:6.6.1',
                'A $type action is forbidden in PDF/A.', pageIndex: p);
          }
        }
      }
    }
  }

  // 6.x - A-1 and A-2 forbid embedded files; A-3 allows them (with metadata).
  void _checkEmbeddedFiles() {
    if (part >= 3) return;
    final names = cos.resolve(document.catalog['Names']);
    if (names is CosDictionary) {
      final ef = cos.resolve(names['EmbeddedFiles']);
      if (ef is CosDictionary) {
        _err('A$part:6.x',
            'Embedded files (/Names /EmbeddedFiles) are forbidden in '
            'PDF/A-$part.');
      }
    }
  }

  // 6.5.3 - annotations shall be set to print and not hidden; appearances are
  // required. Reported as warnings (rendering-dependent).
  void _checkAnnotations() {
    for (var p = 0; p < document.pageCount; p++) {
      for (final annot in document.page(p).annotations) {
        if (annot.subtype == 'Popup' || annot.subtype == 'Link') continue;
        final flags = annot.flags;
        const printBit = 1 << 2;
        const hiddenBit = 1 << 1;
        if (flags & printBit == 0) {
          _warn('A$part:6.5.3',
              '${annot.subtype} annotation does not have the Print flag set.',
              pageIndex: p);
        }
        if (flags & hiddenBit != 0) {
          _warn('A$part:6.5.3',
              '${annot.subtype} annotation is Hidden.', pageIndex: p);
        }
      }
    }
  }
}
