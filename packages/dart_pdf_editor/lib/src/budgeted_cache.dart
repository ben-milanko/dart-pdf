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
///    still available for the render that just asked for it.
///  * an **entry count** ([maxEntries]), which *does* see weight-0 entries -
///    the bound that stops image-free / vector-first buffers piling up one per
///    page on a long scroll (issue #283, the weight-0 unbounded-growth bug).
///
/// Values that outlive their cache slot are handled by two hooks:
///
///  * [cloner] - when a value is handed out while a master stays cached (a
///    [ui.Image] shared by clone), [take] and [putAndClone] return
///    `cloner(value)` so a caller disposing its copy, or eviction dropping the
///    master, can never pull pixels out from under a picture still painting.
///  * [disposer] - run on every value the cache drops (eviction, [evict],
///    [clear], [dispose], or a same-key overwrite), so retained engine
///    resources are released deterministically.
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
    bool clearsUnderMemoryPressure = false,
    this.debugLabel = 'cache',
  })  : _weigher = weigher,
        _maxWeight = maxWeight ?? 0,
        _hasWeightBudget = weigher != null && maxWeight != null,
        _maxEntries = maxEntries == null ? null : math.max(1, maxEntries),
        _disposer = disposer,
        _cloner = cloner,
        _clearsUnderMemoryPressure = clearsUnderMemoryPressure {
    if (_clearsUnderMemoryPressure) PdfCacheRegistry.instance.register(this);
  }

  final int Function(V value)? _weigher;
  final bool _hasWeightBudget;
  final int? _maxEntries;
  final void Function(V value)? _disposer;
  final V Function(V value)? _cloner;
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
    _removeEntry(key);
    final weight = _weigher?.call(value) ?? 0;
    _entries[key] = _Entry(value, weight);
    _weight += weight;
    _trim();
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
    _entries[key] = _Entry(value, weight);
    _weight += weight;
    _trim();
    return value;
  }

  /// Drops (and disposes) the retained value for [key]. A no-op on a miss.
  void evict(K key) => _removeEntry(key);

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

  void _removeEntry(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return;
    _weight -= entry.weight;
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
        _removeEntry(victim);
        _evictions++;
      }
    }
    // Count cap: evict the least-recently-used entries - weight-0 or not -
    // until at or under the cap, never the entry just inserted.
    final maxEntries = _maxEntries;
    if (maxEntries != null) {
      while (_entries.length > maxEntries) {
        final oldest = _entries.keys.first;
        if (oldest == _protectedKey) break;
        _removeEntry(oldest);
        _evictions++;
      }
    }
  }

  /// The most-recently-used key - the one eviction always protects. Null only
  /// when the cache is empty.
  K? get _protectedKey => _entries.isEmpty ? null : _entries.keys.last;

  /// The least-recently-used key eligible for weight eviction: the oldest whose
  /// weight is non-zero (when [requireWeight]) and that is not the protected
  /// most-recently-used entry. Null when no such entry exists.
  K? _oldestEvictable({required bool requireWeight}) {
    final protikey = _protectedKey;
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
/// Caches (or the owners that must run extra work on clear - a preview cache
/// that also notifies listeners, a thumbnail cache bound to disk) register a
/// clear callback here; the platform's `didHaveMemoryPressure` drives
/// [handleMemoryPressure], which fires them all. Before this existed the viewer
/// cleared only the decoded-image cache and previews, leaving the text-layout,
/// render-record, and thumbnail caches deaf to pressure.
///
/// It is also the seam for a future coordinated budget: [totalWeight] already
/// reports live occupancy across every registered [PdfBudgetedCache], the
/// measurement a single top-level budget would rebalance against.
class PdfCacheRegistry {
  PdfCacheRegistry._();

  /// The process-wide registry the pressure path drives.
  static final PdfCacheRegistry instance = PdfCacheRegistry._();

  final List<PdfBudgetedCache<Object?, Object?>> _caches = [];
  final List<_Member> _members = [];

  /// Registers [cache] so its weight is counted in [totalWeight] and it is
  /// cleared on memory pressure. Idempotent.
  void register(PdfBudgetedCache cache) {
    final erased = cache as PdfBudgetedCache<Object?, Object?>;
    if (!_caches.contains(erased)) _caches.add(erased);
  }

  /// Detaches [cache] (its owner was disposed).
  void unregister(PdfBudgetedCache cache) => _caches.remove(cache);

  /// Registers a clear [callback] for a cache whose clear must do more than
  /// drop entries (notify listeners, keep a disk mirror). Returns a token to
  /// pass to [removeCallback] when the owner is disposed.
  Object addCallback(void Function() callback, {int Function()? weight}) {
    final member = _Member(callback, weight);
    _members.add(member);
    return member;
  }

  /// Detaches a callback registered with [addCallback].
  void removeCallback(Object token) => _members.remove(token);

  /// Approximate total weight retained across every registered
  /// [PdfBudgetedCache] plus any callback-reported weights - the measurement a
  /// single coordinated budget would rebalance against.
  int get totalWeight {
    var total = 0;
    for (final cache in _caches) {
      total += cache.weight;
    }
    for (final member in _members) {
      total += member.weight?.call() ?? 0;
    }
    return total;
  }

  /// Number of registered caches plus callbacks - diagnostic hook.
  int get registrationCount => _caches.length + _members.length;

  /// Clears every registered cache and fires every registered callback. Wired
  /// to the platform `didHaveMemoryPressure`. Returns the weight freed from the
  /// [PdfBudgetedCache] members (callback weights are owner-defined and not
  /// summed here).
  int handleMemoryPressure() {
    var freed = 0;
    for (final cache in _caches) {
      freed += cache.weight;
      cache.clear();
    }
    // Copy: a callback may unregister itself (owner disposal) mid-fan-out.
    for (final member in _members.toList()) {
      member.callback();
    }
    return freed;
  }
}

class _Member {
  _Member(this.callback, this.weight);
  final void Function() callback;
  final int Function()? weight;
}
