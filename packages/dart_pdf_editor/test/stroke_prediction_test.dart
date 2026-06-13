import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pdfPredictStrokeLead', () {
    test('needs at least two samples', () {
      expect(pdfPredictStrokeLead(const []), isEmpty);
      expect(pdfPredictStrokeLead(const [(0, 0)]), isEmpty);
    });

    test('extends straight motion along the velocity', () {
      // velocity (10, 0), no curvature: lead = last + v * gain (0.9)
      final lead = pdfPredictStrokeLead(const [(0, 0), (10, 0), (20, 0)]);
      expect(lead, hasLength(1));
      expect(lead.single.$1, closeTo(29, 1e-9));
      expect(lead.single.$2, closeTo(0, 1e-9));
    });

    test('bends the lead along the stroke curvature', () {
      // v = (10, 5), previous v = (10, 0): acceleration (0, 5) curves it up
      final lead = pdfPredictStrokeLead(const [(0, 0), (10, 0), (20, 5)]);
      expect(lead, hasLength(1));
      // dx = 10*0.9 = 9 ; dy = 5*0.9 + 0.5*5*0.9^2*0.5 = 4.5 + 1.0125
      expect(lead.single.$1, closeTo(29, 1e-6));
      expect(lead.single.$2, closeTo(5 + 5.5125, 1e-6));
    });

    test('does not predict a near-stationary pen', () {
      // last segment 0.5 < minSegment (0.75): extrapolation is just jitter
      expect(pdfPredictStrokeLead(const [(0, 0), (0.5, 0)]), isEmpty);
    });

    test('does not predict across a sharp reversal', () {
      // the pen doubled back (180°): a forward lead would overshoot the cusp
      expect(pdfPredictStrokeLead(const [(0, 0), (10, 0), (2, 0)]), isEmpty);
    });

    test('caps the lead so a noisy estimate cannot fling off the tip', () {
      // straight v = (10, 0), speed 10; cap = speed * maxLeadFactor
      final lead = pdfPredictStrokeLead(
        const [(0, 0), (10, 0), (20, 0)],
        maxLeadFactor: 0.5,
      );
      expect(lead, hasLength(1));
      // raw step would be 9; capped to 10 * 0.5 = 5 → 20 + 5
      expect(lead.single.$1, closeTo(25, 1e-9));
      expect(lead.single.$2, closeTo(0, 1e-9));
    });

    test('returns the requested number of forward steps', () {
      final lead = pdfPredictStrokeLead(
        const [(0, 0), (10, 0), (20, 0)],
        steps: 2,
      );
      expect(lead, hasLength(2));
      // straight motion: each step advances by v * gain (9)
      expect(lead[0].$1, closeTo(29, 1e-9));
      expect(lead[1].$1, closeTo(38, 1e-9));
    });

    test('a two-sample stroke predicts without curvature', () {
      final lead = pdfPredictStrokeLead(const [(0, 0), (10, 0)]);
      expect(lead, hasLength(1));
      expect(lead.single.$1, closeTo(19, 1e-9));
    });
  });
}
