// Overprint state parsing + delivery guard (issue #502).
//
// The renderer composites in RGB and cannot yet reproduce faithful subtractive
// overprint (§8.6.7), so the Ghent GWG030 gray/K/separation overprint patch is
// an accepted baseline deviation like the DeviceN GWG190/191/192 patches. What
// this guard pins is the half that IS implemented and must not regress: the
// /OP (stroke), /op (fill) and /OPM (mode) ExtGState keys are parsed into the
// graphics state, survive q/Q, and are delivered to the device - so a future
// colorant-buffer compositor has the state to act on. It sits alongside
// ghent_jpx_indexed_test.dart: pinning a low-level operation directly rather
// than relying on the tolerated raster baseline.
import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';
import 'package:test/test.dart';

/// A device that records only the overprint tuples it is handed, in order.
class _OverprintRecorder implements PdfDevice {
  final overprints = <(bool fill, bool stroke, int mode)>[];

  @override
  void setOverprint(
          {required bool fill, required bool stroke, required int mode}) =>
      overprints.add((fill, stroke, mode));

  @override
  void save() {}
  @override
  void restore() {}
  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) {}
  @override
  void fillPathGradient(
      PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {}
  @override
  void fillMesh(PdfMesh mesh, double alpha) {}
  @override
  void strokePath(
      PdfPath path, PdfColor color, PdfStroke stroke, double alpha) {}
  @override
  void clipPath(PdfPath path, PdfFillRule rule) {}
  @override
  void drawText(PdfTextRun run) {}
  @override
  void drawImage(PdfImageRequest request) {}
  @override
  void setBlendMode(PdfBlendMode mode) {}
  @override
  void beginGroup(double alpha, {bool knockout = false}) {}
  @override
  void endGroup() {}
  @override
  void beginSoftMasked() {}
  @override
  void endSoftMasked({
    required bool luminosity,
    required PdfRect backdrop,
    required void Function() drawMask,
    double backdropLuminance = 0,
    double transferScale = 1,
    double transferOffset = 0,
  }) =>
      drawMask();
}

/// Wraps [gsEntries] as an /ExtGState resource dictionary keyed by name, then
/// interprets [content] against it and returns the overprint tuples delivered.
List<(bool, bool, int)> _run(
    String content, Map<String, CosDictionary> gsEntries) {
  final extGState = CosDictionary();
  gsEntries.forEach((name, dict) => extGState[name] = dict);
  final resources = CosDictionary()..['ExtGState'] = extGState;
  final device = _OverprintRecorder();
  PdfInterpreter(cos: CosDocument.open(_minimalPdf), device: device).run(
    ContentStreamParser.parse(Uint8List.fromList(content.codeUnits)),
    resources,
  );
  return device.overprints;
}

CosDictionary _gs({bool? op, bool? opLower, int? opm}) {
  final d = CosDictionary()..['Type'] = const CosName('ExtGState');
  if (op != null) d['OP'] = CosBoolean(op);
  if (opLower != null) d['op'] = CosBoolean(opLower);
  if (opm != null) d['OPM'] = CosInteger(opm);
  return d;
}

void main() {
  test('/op sets the fill flag, /OP the stroke flag, /OPM the mode', () {
    final ops = _run('/GS gs 0 0 100 100 re f', {
      'GS': _gs(op: true, opLower: true, opm: 1),
    });
    expect(ops, [(true, true, 1)]);
  });

  test('/OP alone applies to nonstroking too when /op is absent (§8.6.7)', () {
    // Backward-compat rule: with no /op key, /OP drives fill overprint as well.
    final ops = _run('/GS gs 0 0 100 100 re f', {'GS': _gs(op: true)});
    expect(ops, [(true, true, 0)]);
  });

  test('an explicit /op overrides the /OP fallback for fill', () {
    final ops =
        _run('/GS gs 0 0 100 100 re f', {'GS': _gs(op: true, opLower: false)});
    expect(ops, [(false, true, 0)]);
  });

  test('/OPM is clamped to {0, 1}', () {
    final ops = _run('/GS gs f', {'GS': _gs(opLower: true, opm: 5)});
    expect(ops, [(true, false, 1)]);
  });

  test('unchanged overprint state is not re-delivered', () {
    final ops = _run('/GS gs /GS gs f', {'GS': _gs(op: true, opLower: true)});
    expect(ops, [(true, true, 0)], reason: 'second identical gs is a no-op');
  });

  test('q/Q restores the overprint state, re-notifying the device', () {
    // Turn overprint on, save, turn it off, then Q back to the on state.
    final ops = _run('/ON gs q /OFF gs Q f', {
      'ON': _gs(op: true, opLower: true, opm: 1),
      'OFF': _gs(op: false, opLower: false, opm: 0),
    });
    expect(ops, [
      (true, true, 1), // /ON
      (false, false, 0), // /OFF inside the q/Q
      (true, true, 1), // restored by Q
    ]);
  });

  group('GWG030 gray/K/separation overprint fixture', () {
    final path =
        '../../test_corpora/ghent/2-SPOT/GWG030_Gray_K_black_OP_X1.pdf';
    final file = File(path);

    test('every /OP /op /OPM ExtGState is consumed by the interpreter', () {
      if (!file.existsSync()) {
        markTestSkipped('test_corpora/ghent not found');
        return;
      }
      final doc = PdfDocument.open(file.readAsBytesSync());
      final device = _OverprintRecorder();
      PdfInterpreter(cos: doc.cos, device: device).drawPage(doc.page(0));

      // The page drives overprint through many ExtGStates (probed: GS0..GS10
      // carry OP/op/OPM). If overprint were still parsed nowhere the device
      // would never be told; pin that it is, and that OPM 1 (nonzero mode)
      // reaches it.
      expect(device.overprints, isNotEmpty,
          reason: 'overprint state never reached the device');
      expect(device.overprints.any((o) => o.$1 || o.$2), isTrue,
          reason: 'at least one patch enables fill or stroke overprint');
      expect(device.overprints.any((o) => o.$3 == 1), isTrue,
          reason: 'OPM 1 (nonzero overprint mode) must be delivered');
    });
  });
}

/// Smallest valid PDF the interpreter can resolve names against - the content
/// here references no indirect objects, so an empty catalog suffices.
final Uint8List _minimalPdf = Uint8List.fromList(
  '%PDF-1.7\n'
          '1 0 obj<</Type/Catalog>>endobj\n'
          'xref\n0 2\n'
          '0000000000 65535 f \n'
          '0000000009 00000 n \n'
          'trailer<</Size 2/Root 1 0 R>>\n'
          'startxref\n9\n%%EOF'
      .codeUnits,
);
