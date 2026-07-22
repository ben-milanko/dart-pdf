import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake live page: fixed bytes + distance, records whether it was evicted.
class _FakeHolder implements PdfLiveRasterHolder {
  _FakeHolder(this.label, {required int bytes, required this.distance})
      : _bytes = bytes;

  final String label;
  int _bytes;
  final int distance;
  bool evicted = false;

  @override
  int get liveRasterBytes => _bytes;

  @override
  int get liveRasterDistance => distance;

  @override
  void evictLiveRaster() {
    evicted = true;
    _bytes = 0; // a real holder drops its rasters; mirror that for totalBytes
  }
}

void main() {
  final budget = PdfLiveRasterBudget.instance;
  final registered = <PdfLiveRasterHolder>[];

  void add(PdfLiveRasterHolder h) {
    budget.register(h);
    registered.add(h);
  }

  setUp(() {
    // The singleton persists across tests; clear any registrations first.
    for (final h in List.of(registered)) {
      budget.unregister(h);
    }
    registered.clear();
    budget.maxBytes = 256 << 20;
  });

  group('PdfLiveRasterBudget', () {
    test('totalBytes sums every registered holder', () {
      add(_FakeHolder('a', bytes: 10, distance: 0));
      add(_FakeHolder('b', bytes: 25, distance: 1));
      expect(budget.totalBytes, 35);
      expect(budget.holderCount, 2);
    });

    test('rebalance is a no-op within budget', () {
      budget.maxBytes = 100;
      final a = _FakeHolder('a', bytes: 40, distance: 2);
      add(a);
      expect(budget.rebalance(), 0);
      expect(a.evicted, isFalse);
    });

    test('evicts farthest-from-viewport first, and stops once it fits', () {
      budget.maxBytes = 100;
      final focus = _FakeHolder('focus', bytes: 60, distance: 0);
      final near = _FakeHolder('near', bytes: 40, distance: 1);
      final far = _FakeHolder('far', bytes: 50, distance: 3);
      add(focus);
      add(near);
      add(far); // total 150 > 100
      final freed = budget.rebalance();
      // Dropping `far` (50) brings 150 -> 100, which fits: `near` is kept.
      expect(freed, 50);
      expect(far.evicted, isTrue);
      expect(near.evicted, isFalse);
      expect(focus.evicted, isFalse);
      expect(budget.totalBytes, 100);
    });

    test('never evicts the focused page even when alone over budget', () {
      budget.maxBytes = 10;
      final focus = _FakeHolder('focus', bytes: 500, distance: 0);
      add(focus);
      expect(budget.rebalance(), 0);
      expect(focus.evicted, isFalse);
    });

    test('keeps evicting outward until it fits', () {
      budget.maxBytes = 50;
      final focus = _FakeHolder('focus', bytes: 30, distance: 0);
      final d1 = _FakeHolder('d1', bytes: 30, distance: 1);
      final d2 = _FakeHolder('d2', bytes: 30, distance: 2);
      final d3 = _FakeHolder('d3', bytes: 30, distance: 3);
      add(focus);
      add(d1);
      add(d2);
      add(d3); // total 120, budget 50 -> must drop d3 and d2 (down to 60?) then d1
      budget.rebalance();
      // 120 -> drop d3 (90) -> drop d2 (60) -> drop d1 (30) -> fits (<=50).
      expect(d3.evicted, isTrue);
      expect(d2.evicted, isTrue);
      expect(d1.evicted, isTrue);
      expect(focus.evicted, isFalse);
      expect(budget.totalBytes, 30);
    });

    test('on a distance tie the larger raster is evicted first', () {
      budget.maxBytes = 100;
      final small = _FakeHolder('small', bytes: 20, distance: 2);
      final big = _FakeHolder('big', bytes: 90, distance: 2);
      final focus = _FakeHolder('focus', bytes: 40, distance: 0);
      add(focus);
      add(small);
      add(big); // total 150 > 100
      budget.rebalance();
      // Evicting `big` (90) alone brings 150 -> 60, which fits: `small` kept.
      expect(big.evicted, isTrue);
      expect(small.evicted, isFalse);
    });

    test('maxBytes <= 0 disables eviction', () {
      budget.maxBytes = 0;
      final far = _FakeHolder('far', bytes: 999, distance: 9);
      add(far);
      expect(budget.rebalance(), 0);
      expect(far.evicted, isFalse);
    });

    test('evictReclaimable sheds every non-focused page (pressure path)', () {
      budget.maxBytes = 1 << 30; // well within budget - pressure ignores it
      final focus = _FakeHolder('focus', bytes: 100, distance: 0);
      final n1 = _FakeHolder('n1', bytes: 100, distance: 1);
      final n2 = _FakeHolder('n2', bytes: 100, distance: 2);
      add(focus);
      add(n1);
      add(n2);
      final freed = budget.evictReclaimable();
      expect(freed, 200);
      expect(focus.evicted, isFalse);
      expect(n1.evicted, isTrue);
      expect(n2.evicted, isTrue);
    });

    test('unregister removes a holder from accounting', () {
      final a = _FakeHolder('a', bytes: 50, distance: 1);
      add(a);
      expect(budget.totalBytes, 50);
      budget.unregister(a);
      registered.remove(a);
      expect(budget.totalBytes, 0);
    });
  });
}
