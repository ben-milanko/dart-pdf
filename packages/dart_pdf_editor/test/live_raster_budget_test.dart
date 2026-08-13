import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake live page: fixed bytes + distance, records whether it was evicted.
///
/// [onScreen] defaults to "only the focused page is visible" - the shape of a
/// document whose pages each fill the viewport, which is what the ordering
/// tests below are about. Cases where a neighbour is *also* on screen pass it
/// explicitly.
class _FakeHolder implements PdfLiveRasterHolder {
  _FakeHolder(this.label,
      {required int bytes, required this.distance, bool? onScreen})
      : _bytes = bytes,
        onScreen = onScreen ?? distance == 0;

  final String label;
  int _bytes;
  final int distance;
  final bool onScreen;
  bool evicted = false;

  @override
  int get liveRasterBytes => _bytes;

  @override
  int get liveRasterDistance => distance;

  @override
  bool get liveRasterOnScreen => onScreen;

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

    test('a farther off-screen page goes before a nearer visible one', () {
      // The #657 shape: two large-format pages share the screen (the centre is
      // on `focus`, so its neighbour sits at distance 1 while still filling
      // half the viewport) with a prefetched page behind them. Reclaiming the
      // visible neighbour blanks a page the user is reading; the prefetch is
      // there to be given back.
      budget.maxBytes = 100;
      final focus = _FakeHolder('focus', bytes: 50, distance: 0);
      final visibleNeighbour =
          _FakeHolder('visible', bytes: 50, distance: 1, onScreen: true);
      final prefetch =
          _FakeHolder('prefetch', bytes: 50, distance: 2, onScreen: false);
      add(focus);
      add(visibleNeighbour);
      add(prefetch); // total 150 > 100
      expect(budget.rebalance(), 50);
      expect(prefetch.evicted, isTrue);
      expect(visibleNeighbour.evicted, isFalse);
      expect(focus.evicted, isFalse);
    });

    test('every off-screen page goes before any visible one', () {
      // Ordering across the two passes, not just the single nearest/farthest
      // pair: the visible neighbour is farther from focus than both prefetches
      // and must still outlive them.
      budget.maxBytes = 100;
      final focus = _FakeHolder('focus', bytes: 40, distance: 0);
      final visible =
          _FakeHolder('visible', bytes: 60, distance: 3, onScreen: true);
      final p1 = _FakeHolder('p1', bytes: 40, distance: 1, onScreen: false);
      final p2 = _FakeHolder('p2', bytes: 40, distance: 2, onScreen: false);
      add(focus);
      add(visible);
      add(p1);
      add(p2); // total 180 > 100
      budget.rebalance();
      // 180 -> drop p2 (140) -> drop p1 (100) -> fits, visible untouched.
      expect(p2.evicted, isTrue);
      expect(p1.evicted, isTrue);
      expect(visible.evicted, isFalse);
      expect(budget.totalBytes, 100);
    });

    test('reaches visible pages only once the off-screen ones are gone', () {
      // The safety valve: zoomed out far enough that the visible pages alone
      // blow the budget, the reclaim must still make progress rather than
      // grow without bound.
      budget.maxBytes = 100;
      final focus = _FakeHolder('focus', bytes: 60, distance: 0);
      final near =
          _FakeHolder('near', bytes: 60, distance: 1, onScreen: true);
      final far = _FakeHolder('far', bytes: 60, distance: 2, onScreen: true);
      final prefetch =
          _FakeHolder('prefetch', bytes: 60, distance: 5, onScreen: false);
      add(focus);
      add(near);
      add(far);
      add(prefetch); // total 240 > 100
      budget.rebalance();
      // 240 -> prefetch (180) -> then visible, farthest first: far (120),
      // near (60) -> fits. The focused page is never touched.
      expect(prefetch.evicted, isTrue);
      expect(far.evicted, isTrue);
      expect(near.evicted, isTrue);
      expect(focus.evicted, isFalse);
      expect(budget.totalBytes, 60);
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

    test('evictReclaimable spares pages that are still on screen', () {
      // Pressure has to come from what the user is not looking at: an
      // on-screen page re-rasterizes the instant it is dropped, so evicting it
      // buys a flicker and a higher peak, not headroom.
      budget.maxBytes = 1 << 30;
      final focus = _FakeHolder('focus', bytes: 100, distance: 0);
      final visible =
          _FakeHolder('visible', bytes: 100, distance: 1, onScreen: true);
      final prefetch =
          _FakeHolder('prefetch', bytes: 100, distance: 2, onScreen: false);
      add(focus);
      add(visible);
      add(prefetch);
      expect(budget.evictReclaimable(), 100);
      expect(focus.evicted, isFalse);
      expect(visible.evicted, isFalse);
      expect(prefetch.evicted, isTrue);
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
