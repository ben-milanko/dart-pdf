// PdfPageCurrency: when a committed edit's held result retires, and whether
// a page still needs its editing overlay - no widgets pumped.

import 'package:dart_pdf_editor/src/editing/page_currency.dart';
import 'package:flutter_test/flutter_test.dart';

const _slot = #after;
const _ink = #ink;

void main() {
  late PdfPageCurrency currency;
  late List<String> retired;

  setUp(() {
    currency = PdfPageCurrency();
    retired = [];
  });

  void hold(int page, String value,
          {int? revision, Object slot = _slot, bool run = false}) =>
      currency.hold(page, slot, value,
          revision: revision, run: run, onRetire: () => retired.add(value));

  test('a result retires once its page is current at its revision', () {
    currency.documentAt(1, changedPages: [0]);
    hold(0, 'move', revision: 1);
    expect(currency.needsOverlay(0), isTrue);
    currency.pageCurrent(0, 0); // a render of the old page landing late
    expect(currency.heldOn<String>(0, _slot), 'move');
    currency.pageCurrent(0, 1);
    expect(currency.heldOn<String>(0, _slot), isNull);
    expect(retired, ['move']);
    expect(currency.needsOverlay(0), isFalse);
  });

  test('a document move retires results from other revisions', () {
    currency.documentAt(1, changedPages: [0]);
    hold(0, 'shape', revision: 1);
    currency.documentAt(2, changedPages: [0]); // undo, or another edit
    expect(retired, ['shape']);
  });

  test('a pending preview survives its commit and is then tagged', () {
    hold(0, 'stamp'); // painted ahead of the commit
    currency.documentAt(1, changedPages: [0]);
    expect(currency.heldOn<String>(0, _slot), 'stamp');
    currency.stamp(0, _slot, 1);
    currency.pageCurrent(0, 1);
    expect(retired, ['stamp']);
  });

  test('a slot holds one result; holding again retires the last', () {
    currency.documentAt(1, changedPages: [0]);
    hold(0, 'first', revision: 1);
    hold(0, 'second', revision: 1);
    expect(retired, ['first']);
    expect(currency.heldOn<String>(0, _slot), 'second');
  });

  test('nothing is held for a page that already shows the revision', () {
    currency
      ..documentAt(1, changedPages: [1])
      ..pageCurrent(0, 0);
    // revision 1 did not change page 0, which is current
    hold(0, 'ghost', revision: 1);
    expect(retired, ['ghost']);
    expect(currency.needsOverlay(0), isFalse);
  });

  test('a page that changed is not current until it shows the change', () {
    currency.pageCurrent(0, 0);
    expect(currency.isCurrent(0), isTrue);
    currency.documentAt(1, changedPages: null); // every page
    expect(currency.isCurrent(0), isFalse);
    currency.pageStale(0);
    currency.pageCurrent(0, 1);
    expect(currency.isCurrent(0), isTrue);
  });

  group('ink runs', () {
    test('back-to-back commits accumulate and retire page by page', () {
      currency.documentAt(1, changedPages: [0]);
      hold(0, 'a', revision: 1, slot: _ink, run: true);
      currency.documentAt(2, changedPages: [0, 1], extendsRun: true);
      hold(0, 'b', revision: 2, slot: _ink, run: true);
      hold(1, 'c', revision: 2, slot: _ink, run: true);
      expect(currency.allHeldOn<String>(0, _ink), ['a', 'b']);
      currency.pageCurrent(0, 1); // caught up with the first commit only
      expect(currency.allHeldOn<String>(0, _ink), ['b']);
      expect(currency.allHeldOn<String>(1, _ink), ['c']);
    });

    test('any other revision ends the run', () {
      currency.documentAt(1, changedPages: [0]);
      hold(0, 'a', revision: 1, slot: _ink, run: true);
      currency.documentAt(2, changedPages: [0]); // not an ink commit
      expect(currency.allHeldOn<String>(0, _ink), isEmpty);
    });

    test('a run only extends from its newest revision', () {
      currency.documentAt(1, changedPages: [0]);
      hold(0, 'a', revision: 1, slot: _ink, run: true);
      currency.documentAt(2, changedPages: [0]);
      currency.documentAt(3, changedPages: [0], extendsRun: true);
      expect(retired, ['a']);
    });
  });

  group('overlay mount', () {
    test('kept mounted until the page is current, then released', () {
      currency.documentAt(1, changedPages: [0]);
      currency.keepOverlayUntilCurrent(0);
      expect(currency.needsOverlay(0), isTrue);
      currency.pageCurrent(0, 0);
      expect(currency.needsOverlay(0), isTrue, reason: 'still behind');
      currency.pageCurrent(0, 1);
      expect(currency.needsOverlay(0), isFalse);
    });

    test('a current page is never held mounted', () {
      currency.pageCurrent(0, 0);
      currency.keepOverlayUntilCurrent(0);
      expect(currency.needsOverlay(0), isFalse);
    });
  });

  test('clear retires everything', () {
    currency.documentAt(1, changedPages: [0, 1]);
    hold(0, 'a', revision: 1);
    hold(1, 'b', revision: 1, slot: _ink, run: true);
    currency.clear();
    expect(retired, unorderedEquals(['a', 'b']));
    expect(currency.needsOverlay(0) || currency.needsOverlay(1), isFalse);
  });
}
