import 'dart:math' as math;

/// One bounded, least-recently-used cache that every in-package cache is built
/// on, so the eviction rules live (and are property-tested) in exactly one
/// place instead of being re-derived - subtly differently, and with a fresh
/// off-by-one each time - at six call sites.
///
/// A plain Dart map is insertion-ordered, so its first key is the
/// least-recently used; a lookup or store does a remove-then-reinsert to move
/// the entry to the most-recently-used end. Two independent bounds cap growth,
/// either or both of which a call site may leave off:
///
///  * a **weight budget** ([maxWeight]) measured in whatever unit the
///    [weigher] returns - decoded image bytes, exact-raster pixels, retained
///    command slots. Eviction under this budget skips weight-0 entries (they
///    free nothing yet cost a re-decode to rebuild) and never drops the single
///    most-recently-used entry, so a lone page larger than the whole budget is
///    still available for the render that just asked for it - unless
///    `rejectOversize` is set, in which case an entry heavier than the whole
///    budget is never stored (the record cache's policy).
///  * an **entry count** ([maxEntries]), which *does* see weight-0 entries -
///    the bound that stops image-free / vector-first buffers piling up one per
///    page on a long scroll (issue #283, the weight-0 unbounded-growth bug).
///
/// Values that outlive their cache slot are handled by three hooks:
///
///  * [cloner] - when a value is handed out while a master stays cached (a
///    [ui.Image] shared by clone), [take] and [putAndClone] return
///    `cloner(value)` so a caller disposing its copy, or eviction dropping the
///    master, can never pull pixels out from under a picture still painting.
///  * [disposer] - run on every value the cache drops (eviction, [evict],
///    [clear], [dispose], or a same-key overwrite), so retained engine
///    resources are released deterministically.
///  * [onEvicted] - optional diagnostics invoked only when a weight/count or
///    coordinated process budget evicts an entry. Explicit invalidation,
///    clearing, and same-key replacement do not count as policy evictions.
///
/// Registering with [PdfCacheRegistry] (via `clearsUnderMemoryPressure: true`)
/// wires the cache into the one coordinated memory-pressure path.
class PdfBudgetedCache<K, V> {
  /// Creates a cache bounded by [maxWeight] (using [weigher]) and/or
  /// [maxEntries]. At least one bound should be given or the cache grows
  /// without limit. [maxEntries] is floored at 1 so the cache always keeps the
  /// most-recently-used entry. When [clearsUnderMemoryPressure] is set the
  /// cache registers with [PdfCacheRegistry] for its lifetime (until
  /// [dispose]).
  PdfBudgetedCache({
    int Function(V value)? weigher,
    int? maxWeight,
    int? maxEntries,
    void Function(V value)? disposer,
    V Function(V value)? cloner,
    void Function(K key, V value)? onEvicted,
    bool rejectOversize = false,
    bool clearsUnderMemoryPressure = false,
    this.debugLabel = 'cache',
  })  : _weigher = weigher,
        _maxWeight = maxWeight ?? 0,
        _hasWeightBudget = weigher != null && maxWeight != null,
        _maxEntries = maxEntries == null ? null : math.max(1, maxEntries),
        _disposer = disposer,
        _cloner = cloner,
        _onEvicted = onEvicted,
        _rejectOversize = rejectOversize,
        _clearsUnderMemoryPressure = clearsUnderMemoryPressure {
    if (_clearsUnderMemoryPressure) PdfCacheRegistry.instance.register(this);
  }

  final int Function(V value)? _weigher;
  final bool _hasWeightBudget;
  final int? _maxEntries;
  final void Function(V value)? _disposer;
  final V Function(V value)? _cloner;
  final void Function(K key, V value)? _onEvicted;

  /// When set, a value whose weight alone exceeds [maxWeight] is not stored at
  /// all (rather than kept as the protected most-recently-used entry): caching
  /// one entry bigger than the whole budget would starve every reusable entry.
  /// The render-worker record cache wants this; the image and preview caches do
  /// not (they keep an oversize master for the render that just asked for it).
  final bool _rejectOversize;
  final bool _clearsUnderMemoryPressure;

  /// A short name used in registry accounting and diagnostics.
  final String debugLabel;

  int _maxWeight;

  // LinkedHashMap insertion order is the LRU order.
  final Map<K, _Entry<V>> _entries = {};
  int _weight = 0;
  bool _disposed = false;
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;

  /// The weight budget (in the [weigher]'s unit). Lowering it trims to the new
  /// budget at once; raising it lets later inserts fill the extra room. Only
  /// meaningful when a weigher was supplied.
  int get maxWeight => _maxWeight;
  set maxWeight(int value) {
    _maxWeight = value;
    if (_hasWeightBudget) _trim();
  }

  /// The count cap, or null when the cache is unbounded by entry count.
  int? get maxEntries => _maxEntries;

  /// Evicts least-recently-used weight-bearing entries until retained weight
  /// is at or under [target] (floored at 0). Like the budget eviction in
  /// [_trim], the most-recently-used entry is protected and weight-0 entries
  /// are skipped (evicting them frees nothing). A no-op without a [weigher].
  ///
  /// This is the [PdfCacheRegistry.maxTotalWeight] rebalance hook: the
  /// coordinated ceiling shrinks caches *below* their individual budgets, so
  /// it needs a target other than [maxWeight].
  void trimToWeight(int target) {
    _trimToWeight(target, protectMostRecent: true);
  }

  /// Registry-only hard trim. A process ceiling is a safety boundary, so it may
  /// drop the final MRU master too; callers already hold independent clones and
  /// can keep painting. Per-cache budgets continue to protect their MRU.
  void _trimToWeightHard(int target) {
    _trimToWeight(target, protectMostRecent: false);
  }

  void _trimToWeight(int target, {required bool protectMostRecent}) {
    if (_disposed || _weigher == null) return;
    final floor = math.max(0, target);
    while (_weight > floor) {
      final victim = _oldestEvictable(
        requireWeight: true,
        protectMostRecent: protectMostRecent,
      );
      if (victim == null) break;
      _removeEntry(victim, eviction: true);
    }
  }

  /// Total weight currently retained (occupancy, not a reservation).
  int get weight => _weight;

  /// Number of retained entries.
  int get length => _entries.length;

  /// The retained values, least-recently used first.
  Iterable<V> get values => _entries.values.map((e) => e.value);

  /// The retained keys, least-recently used first.
  Iterable<K> get keys => _entries.keys;

  /// Lookups served from a retained value.
  int get hits => _hits;

  /// Lookups that missed.
  int get misses => _misses;

  /// Entries dropped by an eviction bound (not counting [evict]/[clear]).
  int get evictions => _evictions;

  /// Whether a value is retained for [key], without touching LRU order.
  bool containsKey(K key) => _entries.containsKey(key);

  /// The weight of the retained entry for [key], or null on a miss. Does not
  /// touch LRU order - a pure peek.
  int? weightOf(K key) => _entries[key]?.weight;

  /// The retained value for [key] without touching LRU order or the hit/miss
  /// counters, or null on a miss. Returns the master itself, never a clone -
  /// for read-only inspection (staleness checks, rebinding), not handing out.
  V? peek(K key) => _entries[key]?.value;

  /// The value for [key] - a clone when a [cloner] was supplied, else the
  /// stored value - moved to most-recently-used, or null on a miss.
  V? take(K key) {
    final entry = _entries.remove(key);
    if (entry == null) {
      _misses++;
      return null;
    }
    _hits++;
    _entries[key] = entry; // touch → most-recently-used
    final cloner = _cloner;
    return cloner == null ? entry.value : cloner(entry.value);
  }

  /// Stores [value] under [key] (the cache takes ownership, disposing any
  /// previous value for that key) and evicts down to the bounds. Returns
  /// [value] itself - the caller has handed it off. Use [putAndClone] when the
  /// caller needs its own independent copy of a shared value.
  ///
  /// After [dispose] the cache stores nothing, so a late completion is dropped;
  /// the caller still owns [value].
  V put(K key, V value) {
    if (_disposed) return value;
    final weight = _weigher?.call(value) ?? 0;
    // An oversize value under rejectOversize is left uncached, and any existing
    // entry for [key] is kept untouched (as the pre-shared record cache did).
    if (_rejectOversize && _hasWeightBudget && weight > _maxWeight) {
      return value;
    }
    _removeEntry(key);
    _entries[key] = _Entry(value, weight);
    _weight += weight;
    _trim();
    if (_clearsUnderMemoryPressure && weight > 0) {
      PdfCacheRegistry.instance.enforceBudget();
    }
    return value;
  }

  /// Stores [value] as the retained master (like [put]) and returns an
  /// independent [cloner] copy for the caller to use and dispose, so a caller
  /// that both populates and paints in one step never shares the exact object
  /// the cache may later evict. Requires a [cloner].
  ///
  /// After [dispose] nothing is cached and [value] is returned uncached - the
  /// caller owns it outright, with no master to stay independent from.
  V putAndClone(K key, V value) {
    assert(_cloner != null, 'putAndClone requires a cloner');
    if (_disposed) return value;
    put(key, value);
    return _cloner!(value);
  }

  /// The value for [key], computing and storing it with [ifAbsent] on a miss.
  /// The compute-once counterpart of [take]/[put] used by caches whose values
  /// are built lazily (text layouts, per-page derived objects). The stored
  /// value is returned directly (no clone) - the master is shared, not handed
  /// out. A hit marks the entry most-recently used and never runs [ifAbsent].
  ///
  /// After [dispose] the built value is returned uncached and the [disposer] is
  /// *not* run on it - the caller is about to use it, so the cache can neither
  /// dispose it (that would hand back a dead value) nor keep it. The caller
  /// therefore owns it. In practice this cache's only [getOrAdd] user (the
  /// process-wide text-layout cache) is never disposed, so this path is a
  /// documented contract rather than a live one.
  V getOrAdd(K key, V Function() ifAbsent) {
    final entry = _entries.remove(key);
    if (entry != null) {
      _hits++;
      _entries[key] = entry;
      return entry.value;
    }
    _misses++;
    final value = ifAbsent();
    if (_disposed) return value;
    final weight = _weigher?.call(value) ?? 0;
    if (_rejectOversize && _hasWeightBudget && weight > _maxWeight) {
      return value;
    }
    _entries[key] = _Entry(value, weight);
    _weight += weight;
    _trim();
    if (_clearsUnderMemoryPressure && weight > 0) {
      PdfCacheRegistry.instance.enforceBudget();
    }
    return value;
  }

  /// Drops (and disposes) the retained value for [key]. A no-op on a miss.
  void evict(K key) => _removeEntry(key);

  /// Drops (and disposes) every retained entry whose key satisfies [test].
  /// Used for targeted, per-page invalidation - a render worker evicting just
  /// the pages an incremental revision changed instead of clearing the whole
  /// cache. Counters and every non-matching entry are untouched.
  void evictWhere(bool Function(K key) test) {
    final doomed = _entries.keys.where(test).toList();
    for (final key in doomed) {
      _removeEntry(key);
    }
  }

  /// Empties the cache, disposing every retained value. Counters survive - a
  /// clear is a cache operation, not a fresh measurement. Any clones already
  /// handed out are unaffected.
  void clear() {
    for (final entry in _entries.values) {
      _disposer?.call(entry.value);
    }
    _entries.clear();
    _weight = 0;
  }

  /// Empties the cache and detaches it from the memory-pressure registry.
  /// Further [put]s are dropped (returning the value uncached).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    clear();
    if (_clearsUnderMemoryPressure) PdfCacheRegistry.instance.unregister(this);
  }

  /// Zeroes the hit/miss/eviction counters (they survive [clear], which is a
  /// cache operation, not a fresh measurement). Used by benchmarks that reuse a
  /// warm cache across measurement passes.
  void resetCounters() {
    _hits = 0;
    _misses = 0;
    _evictions = 0;
  }

  void _removeEntry(K key, {bool eviction = false}) {
    final entry = _entries.remove(key);
    if (entry == null) return;
    _weight -= entry.weight;
    if (eviction) {
      _evictions++;
      _onEvicted?.call(key, entry.value);
    }
    _disposer?.call(entry.value);
  }

  void _trim() {
    // Weight budget: evict the least-recently-used weight-bearing entries until
    // under budget. A weight-0 entry frees nothing, so evicting it here would
    // only cost a re-decode; the count cap below is what bounds those. The
    // most-recently-used entry is never evicted, so a lone entry heavier than
    // the whole budget is still there for the render that just asked for it.
    if (_hasWeightBudget) {
      while (_weight > _maxWeight) {
        final victim = _oldestEvictable(requireWeight: true);
        if (victim == null) break;
        _removeEntry(victim, eviction: true);
      }
    }
    // Count cap: evict the least-recently-used entries - weight-0 or not -
    // until at or under the cap, never the entry just inserted.
    final maxEntries = _maxEntries;
    if (maxEntries != null) {
      while (_entries.length > maxEntries) {
        final oldest = _entries.keys.first;
        if (oldest == _protectedKey) break;
        _removeEntry(oldest, eviction: true);
      }
    }
  }

  /// The most-recently-used key - the one eviction always protects. Null only
  /// when the cache is empty.
  K? get _protectedKey => _entries.isEmpty ? null : _entries.keys.last;

  /// The least-recently-used key eligible for weight eviction: the oldest whose
  /// weight is non-zero (when [requireWeight]) and that is not the protected
  /// most-recently-used entry. Null when no such entry exists.
  K? _oldestEvictable({
    required bool requireWeight,
    bool protectMostRecent = true,
  }) {
    final protikey = protectMostRecent ? _protectedKey : null;
    for (final entry in _entries.entries) {
      if (entry.key == protikey) continue;
      if (requireWeight && entry.value.weight == 0) continue;
      return entry.key;
    }
    return null;
  }
}

class _Entry<V> {
  _Entry(this.value, this.weight);
  final V value;
  final int weight;
}

/// The one place a memory-pressure signal fans out to every in-process cache.
///
/// A [PdfBudgetedCache] created with `clearsUnderMemoryPressure: true` registers
/// here; the platform's `didHaveMemoryPressure` drives [handleMemoryPressure],
/// which clears them all. Before this existed the viewer cleared only the
/// decoded-image cache and previews, leaving the text-layout, render-record, and
/// thumbnail caches deaf to pressure.
///
/// Registrations are held by [WeakReference], so a cache dropped without
/// [PdfBudgetedCache.dispose] (a worker replaced on a document swap, say) is
/// still collectable - a missed dispose is a bounded waste until the next GC,
/// never a permanent leak pinning decoded pixels. [dispose] still unregisters
/// eagerly; the weak ref is only the safety net.
///
/// It is also the seam for a future coordinated budget: [totalWeight] already
/// reports live occupancy across every registered cache, the measurement a
/// single top-level budget would rebalance against.
class PdfCacheRegistry {
  PdfCacheRegistry._();

  /// The process-wide registry the pressure path drives.
  static final PdfCacheRegistry instance = PdfCacheRegistry._();

  final List<WeakReference<PdfBudgetedCache<Object?, Object?>>> _caches = [];

  /// Registers [cache] so its weight is counted in [totalWeight] and it is
  /// cleared on memory pressure. Idempotent; holds only a weak reference.
  void register(PdfBudgetedCache cache) {
    final erased = cache as PdfBudgetedCache<Object?, Object?>;
    _pruneDead();
    for (final ref in _caches) {
      if (identical(ref.target, erased)) return; // already registered
    }
    _caches.add(WeakReference(erased));
  }

  /// Detaches [cache] (its owner was disposed), and prunes any refs whose
  /// target has since been collected.
  void unregister(PdfBudgetedCache cache) => _caches.removeWhere((ref) {
        final target = ref.target;
        return target == null || identical(target, cache);
      });

  /// Approximate total weight retained across every live registered cache - the
  /// measurement a single coordinated budget would rebalance against.
  int get totalWeight {
    var total = 0;
    for (final ref in _caches) {
      total += ref.target?.weight ?? 0;
    }
    return total;
  }

  /// Number of live registered caches - diagnostic hook.
  int get registrationCount {
    _pruneDead();
    return _caches.length;
  }

  /// Diagnostic snapshot of every live registered cache: its [PdfBudgetedCache
  /// .debugLabel], entry count, retained weight, weight budget (0 when the
  /// cache is bounded by entries only), and lifetime lookup/eviction counters.
  /// For devtools-style displays and exported performance traces.
  List<
      ({
        String label,
        int length,
        int weight,
        int maxWeight,
        int hits,
        int misses,
        int evictions,
      })> snapshot() {
    _pruneDead();
    return [
      for (final ref in _caches)
        if (ref.target case final cache?)
          (
            label: cache.debugLabel,
            length: cache.length,
            weight: cache.weight,
            maxWeight: cache.maxWeight,
            hits: cache.hits,
            misses: cache.misses,
            evictions: cache.evictions,
          ),
    ];
  }

  int _maxTotalWeight = 0;
  bool _enforcing = false;

  /// A process-level ceiling across every registered cache, enforced
  /// **proactively** as caches grow (from [PdfBudgetedCache.put]) instead of
  /// only on the platform memory-pressure callback - which desktop OSes
  /// deliver too late, if at all, letting the *sum* of individually-budgeted
  /// caches sit at a multi-hundred-MB sticky baseline (the 2026-07-18 memory
  /// audit). 0 (the default) disables the ceiling; setting a value enforces it
  /// immediately.
  int get maxTotalWeight => _maxTotalWeight;
  set maxTotalWeight(int value) {
    _maxTotalWeight = math.max(0, value);
    enforceBudget();
  }

  /// Trims registered caches until [totalWeight] is at or under
  /// [maxTotalWeight] (no-op when disabled or already under). Each cache is
  /// trimmed **proportionally** - it keeps the same fraction of its weight -
  /// so one hot large cache is not wiped to protect idle small ones, and no
  /// cross-cache LRU clock is needed. Unlike a cache's own performance budget,
  /// this process safety boundary may evict its final MRU master.
  void enforceBudget() {
    if (_maxTotalWeight <= 0 || _enforcing) return;
    final total = totalWeight;
    if (total <= _maxTotalWeight) return;
    _enforcing = true;
    try {
      for (final ref in _caches.toList()) {
        final cache = ref.target;
        if (cache == null || cache.weight == 0) continue;
        cache._trimToWeightHard(cache.weight * _maxTotalWeight ~/ total);
      }
    } finally {
      _enforcing = false;
    }
  }

  /// Clears every live registered cache. Wired to the platform
  /// `didHaveMemoryPressure`. Returns the weight freed.
  int handleMemoryPressure() {
    var freed = 0;
    // Copy: a cache's clear cannot mutate _caches, but a future disposer might.
    for (final ref in _caches.toList()) {
      final cache = ref.target;
      if (cache == null) continue;
      freed += cache.weight;
      cache.clear();
    }
    _pruneDead();
    return freed;
  }

  /// Clears every registered cache whose diagnostic label equals [label].
  ///
  /// This is the targeted counterpart to [handleMemoryPressure]. Hosts use it
  /// when a lifecycle transition makes one reconstructible cache class
  /// expendable (for example, dropping visited-page rasters when a mobile app
  /// backgrounds) without also throwing away decoded images and render records.
  /// Returns the approximate weight freed.
  int clearLabel(String label) {
    var freed = 0;
    for (final ref in _caches.toList()) {
      final cache = ref.target;
      if (cache == null || cache.debugLabel != label) continue;
      freed += cache.weight;
      cache.clear();
    }
    _pruneDead();
    return freed;
  }

  /// Current retained weight across registered caches named [label].
  int weightForLabel(String label) {
    var weight = 0;
    for (final ref in _caches) {
      final cache = ref.target;
      if (cache?.debugLabel == label) weight += cache!.weight;
    }
    return weight;
  }

  void _pruneDead() => _caches.removeWhere((ref) => ref.target == null);
}
