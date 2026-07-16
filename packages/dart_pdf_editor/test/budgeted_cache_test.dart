// PdfBudgetedCache is the one LRU every in-package cache delegates to, so the
// eviction invariants that used to be re-derived (and re-broken) per call site
// are pinned here once: never evict the just-inserted entry, a handed-out clone
// survives its master's eviction, weight-0 entries stay bounded by the count
// cap, and a disposer runs on every dropped value.
import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// A disposable value that tracks whether it (and its clones) are still live,
/// standing in for a ui.Image master + clones.
class _Res {
  _Res(this.id, {this.weight = 1, _Res? master}) : _master = master;
  final int id;
  final int weight;
  final _Res? _master;
  bool disposed = false;

  _Res clone() => _Res(id, weight: weight, master: this);
  bool get masterDisposed => (_master ?? this).disposed;
}

void main() {
  group('count bound', () {
    test('never grows past maxEntries; evicts the LRU, keeps the newest', () {
      final dropped = <int>[];
      final cache = PdfBudgetedCache<int, _Res>(
        maxEntries: 3,
        disposer: (r) => dropped.add(r.id),
      );
      for (var i = 0; i < 10; i++) {
        cache.put(i, _Res(i));
      }
      expect(cache.length, 3);
      expect(cache.keys, [7, 8, 9]);
      expect(dropped, [0, 1, 2, 3, 4, 5, 6]);
    });

    test('a take marks its key most-recently used', () {
      final cache = PdfBudgetedCache<int, _Res>(maxEntries: 3);
      cache.put(0, _Res(0));
      cache.put(1, _Res(1));
      cache.put(2, _Res(2));
      expect(cache.take(0), isNotNull); // touch 0
      cache.put(3, _Res(3)); // evicts the untouched LRU, which is now 1
      expect(cache.containsKey(0), isTrue);
      expect(cache.containsKey(1), isFalse);
    });

    test('the cap is floored at 1', () {
      final cache = PdfBudgetedCache<int, _Res>(maxEntries: 0);
      cache.put(0, _Res(0));
      cache.put(1, _Res(1));
      expect(cache.length, 1);
      expect(cache.keys, [1]);
    });
  });

  group('weight budget', () {
    test('evicts LRU weight-bearing entries down to the budget', () {
      final cache = PdfBudgetedCache<int, _Res>(
        weigher: (r) => r.weight,
        maxWeight: 30,
      );
      cache.put(0, _Res(0, weight: 10));
      cache.put(1, _Res(1, weight: 10));
      cache.put(2, _Res(2, weight: 10));
      expect(cache.weight, 30);
      cache.put(3, _Res(3, weight: 10)); // over budget → drop LRU (0)
      expect(cache.weight, 30);
      expect(cache.containsKey(0), isFalse);
      expect(cache.keys, [1, 2, 3]);
    });

    test('keeps the most-recently-used entry even when it alone exceeds budget',
        () {
      final cache = PdfBudgetedCache<int, _Res>(
        weigher: (r) => r.weight,
        maxWeight: 100,
      );
      cache.put(0, _Res(0, weight: 500));
      expect(cache.length, 1, reason: 'kept for the render that just asked');
      cache.put(1, _Res(1, weight: 500));
      expect(cache.containsKey(0), isFalse, reason: 'aged out on next insert');
      expect(cache.length, 1);
    });

    test('lowering maxWeight retrims immediately', () {
      final cache = PdfBudgetedCache<int, _Res>(
        weigher: (r) => r.weight,
        maxWeight: 100,
      );
      for (var i = 0; i < 5; i++) {
        cache.put(i, _Res(i, weight: 20));
      }
      expect(cache.length, 5);
      cache.maxWeight = 40;
      expect(cache.weight, lessThanOrEqualTo(40));
      expect(cache.keys, [3, 4]);
    });

    test('rejectOversize leaves an over-budget value uncached, others intact',
        () {
      final dropped = <int>[];
      final cache = PdfBudgetedCache<int, _Res>(
        weigher: (r) => r.weight,
        maxWeight: 100,
        rejectOversize: true,
        disposer: (r) => dropped.add(r.id),
      );
      cache.put(0, _Res(0, weight: 50));
      // An oversize value is not stored (contrast the keep-MRU cache above).
      cache.put(1, _Res(1, weight: 500));
      expect(cache.containsKey(1), isFalse);
      expect(cache.containsKey(0), isTrue, reason: 'the fitting entry survives');
      expect(cache.weight, 50);
      // A re-store of an oversize value leaves any existing entry untouched.
      cache.put(0, _Res(100, weight: 500));
      expect(cache.peek(0)!.id, 0, reason: 'the old fitting entry is kept');
      expect(dropped, isEmpty, reason: 'nothing was stored, nothing disposed');
    });
  });

  group('weight-0 entries', () {
    test('the weight budget skips them but the count cap still bounds them', () {
      // The #283 shape: image-free / vector-first buffers weigh 0, so a byte
      // budget cannot see them; only the entry cap stops one-per-page growth.
      final cache = PdfBudgetedCache<int, _Res>(
        weigher: (r) => r.weight,
        maxWeight: 1000,
        maxEntries: 4,
      );
      for (var i = 0; i < 20; i++) {
        cache.put(i, _Res(i, weight: 0));
      }
      expect(cache.weight, 0);
      expect(cache.length, 4, reason: 'count cap bounds the weightless tail');
      expect(cache.keys, [16, 17, 18, 19]);
    });

    test('weight eviction never sacrifices a weightless entry for bytes', () {
      final cache = PdfBudgetedCache<int, _Res>(
        weigher: (r) => r.weight,
        maxWeight: 10,
      );
      cache.put(0, _Res(0, weight: 0)); // costless vector buffer
      cache.put(1, _Res(1, weight: 10));
      cache.put(2, _Res(2, weight: 10)); // over budget
      // The heavy LRU (1) is evicted; the costless entry 0 is untouched.
      expect(cache.containsKey(0), isTrue);
      expect(cache.containsKey(1), isFalse);
      expect(cache.containsKey(2), isTrue);
    });
  });

  group('clone-on-take', () {
    test('a handed-out clone survives its master being evicted', () {
      final cache = PdfBudgetedCache<int, _Res>(
        maxEntries: 1,
        cloner: (r) => r.clone(),
        disposer: (r) => r.disposed = true,
      );
      final handed = cache.putAndClone(0, _Res(0));
      // Evict the master by inserting past the cap.
      cache.put(1, _Res(1));
      expect(cache.containsKey(0), isFalse);
      expect(handed.masterDisposed, isTrue, reason: 'master was disposed');
      expect(handed.disposed, isFalse, reason: 'the clone itself lives on');
    });

    test('putAndClone returns a copy distinct from the retained master', () {
      final cache = PdfBudgetedCache<int, _Res>(
        maxEntries: 2,
        cloner: (r) => r.clone(),
        disposer: (r) => r.disposed = true,
      );
      final master = _Res(0);
      final handed = cache.putAndClone(0, master);
      expect(identical(handed, master), isFalse, reason: 'a clone, not master');
      final taken = cache.take(0);
      expect(taken, isNotNull);
      expect(identical(handed, taken), isFalse);
    });
  });

  group('disposer', () {
    test('runs on eviction, overwrite, evict, and clear', () {
      final dropped = <int>[];
      final cache = PdfBudgetedCache<int, _Res>(
        maxEntries: 2,
        disposer: (r) => dropped.add(r.id),
      );
      cache.put(0, _Res(0));
      cache.put(1, _Res(1));
      cache.put(0, _Res(100)); // overwrite → old 0 disposed
      expect(dropped, [0]);
      cache.put(2, _Res(2)); // evict LRU (1)
      expect(dropped, [0, 1]);
      cache.evict(2);
      expect(dropped, [0, 1, 2]);
      cache.clear(); // disposes the survivor, the overwrite value 100
      expect(dropped, [0, 1, 2, 100]);
    });
  });

  group('getOrAdd', () {
    test('computes once, then serves and refreshes recency without recompute',
        () {
      final cache = PdfBudgetedCache<int, _Res>(maxEntries: 3);
      var builds = 0;
      _Res build(int id) {
        builds++;
        return _Res(id);
      }

      cache.getOrAdd(0, () => build(0));
      cache.getOrAdd(1, () => build(1));
      cache.getOrAdd(2, () => build(2));
      cache.getOrAdd(0, () => build(0)); // hit, no build; 0 now MRU
      expect(builds, 3);
      cache.getOrAdd(3, () => build(3)); // evicts LRU (1), not the touched 0
      expect(cache.containsKey(0), isTrue);
      expect(cache.containsKey(1), isFalse);
      expect(builds, 4);
    });
  });

  group('put after dispose', () {
    test('returns the value uncached and stores nothing', () {
      final cache = PdfBudgetedCache<int, _Res>(maxEntries: 2);
      cache.dispose();
      final r = _Res(0);
      expect(identical(cache.put(0, r), r), isTrue);
      expect(cache.length, 0);
    });

    test('putAndClone and getOrAdd after dispose return the value uncached', () {
      final cache = PdfBudgetedCache<int, _Res>(
        maxEntries: 2,
        cloner: (r) => r.clone(),
      );
      cache.dispose();
      final a = _Res(1);
      expect(identical(cache.putAndClone(1, a), a), isTrue,
          reason: 'no master to stay independent from once disposed');
      final b = _Res(2);
      expect(identical(cache.getOrAdd(2, () => b), b), isTrue);
      expect(cache.length, 0);
    });
  });

  group('accessors', () {
    test('report the configured cap and the live contents', () {
      final cache = PdfBudgetedCache<int, _Res>(maxEntries: 3);
      cache.put(1, _Res(1));
      cache.put(2, _Res(2));
      expect(cache.maxEntries, 3);
      expect(cache.keys, [1, 2]);
      expect(cache.values.map((r) => r.id), [1, 2]);
      expect(cache.weightOf(1), 0, reason: 'no weigher → weight 0');
      expect(cache.weightOf(99), isNull, reason: 'a miss peeks null');
      expect(cache.peek(1)!.id, 1);
    });
  });

  group('counters', () {
    test('hits/misses track take; resetCounters zeroes them', () {
      final cache = PdfBudgetedCache<int, _Res>(maxEntries: 4);
      cache.put(0, _Res(0));
      expect(cache.take(0), isNotNull);
      expect(cache.take(9), isNull);
      expect(cache.hits, 1);
      expect(cache.misses, 1);
      cache.resetCounters();
      expect(cache.hits, 0);
      expect(cache.misses, 0);
    });
  });

  group('PdfCacheRegistry', () {
    test('memory pressure clears every registered cache and sums weight', () {
      final registry = PdfCacheRegistry.instance;
      final before = registry.registrationCount;
      final a = PdfBudgetedCache<int, _Res>(
        weigher: (r) => r.weight,
        maxWeight: 1000,
        clearsUnderMemoryPressure: true,
      );
      final b = PdfBudgetedCache<int, _Res>(
        weigher: (r) => r.weight,
        maxWeight: 1000,
        clearsUnderMemoryPressure: true,
      );
      addTearDown(() {
        a.dispose();
        b.dispose();
      });
      a.put(0, _Res(0, weight: 40));
      b.put(0, _Res(0, weight: 60));
      expect(registry.registrationCount, before + 2);
      expect(registry.totalWeight, greaterThanOrEqualTo(100));

      final freed = registry.handleMemoryPressure();
      expect(freed, greaterThanOrEqualTo(100));
      expect(a.length, 0);
      expect(b.length, 0);
    });

    test('dispose unregisters from the pressure path', () {
      final registry = PdfCacheRegistry.instance;
      final before = registry.registrationCount;
      final c = PdfBudgetedCache<int, _Res>(
        maxEntries: 2,
        clearsUnderMemoryPressure: true,
      );
      expect(registry.registrationCount, before + 1);
      c.dispose();
      expect(registry.registrationCount, before);
    });

    test('evictWhere drops only the matching keys and disposes them', () {
      final dropped = <int>[];
      final c = PdfBudgetedCache<int, _Res>(
        maxEntries: 10,
        disposer: (v) => dropped.add(v.id),
      );
      addTearDown(c.dispose);
      for (var i = 0; i < 6; i++) {
        c.put(i, _Res(i));
      }
      // Evict the even keys (mirrors a worker dropping a changed page set).
      c.evictWhere((key) => key.isEven);
      expect(c.length, 3);
      expect(c.keys, [1, 3, 5]);
      expect(dropped, [0, 2, 4]);
    });

    test('a cache without clearsUnderMemoryPressure is not registered', () {
      final registry = PdfCacheRegistry.instance;
      final before = registry.registrationCount;
      final c = PdfBudgetedCache<int, _Res>(maxEntries: 2);
      addTearDown(c.dispose);
      c.put(0, _Res(0));
      expect(registry.registrationCount, before, reason: 'opted out');
      registry.handleMemoryPressure();
      expect(c.length, 1, reason: 'pressure does not touch an unregistered cache');
    });
  });
}
