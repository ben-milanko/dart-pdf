# Auto memory: the background ratchet

Complaint: the app gets slower the longer it is open, just viewing, most
noticeably on Windows after it has sat in the background. Not a leak. The
Auto memory controller (`app/lib/adaptive_memory.dart`) was starving the
page caches and not letting them back.

## What happened

- The Windows runner reported `lowMemory` as `dwMemoryLoad >= 90`
  (`app/windows/runner/platform_channels.cpp`). A desktop with a browser open
  hovers near 90% load - the standby file cache counts as used - so the flag
  flipped on and off every few samples, especially while other apps were in
  front.
- Every false→true flip was a fresh `_applyPressure`: reclaim everything,
  halve the live-raster budget and (when the caches were material) the page
  budget, and restart the five-minute growth block. The only guard was a
  30 s coalesce, shorter than a flicker cycle, so the page budget ratcheted
  down to its 32 MB floor and the cooldown never expired. Every revisited
  page re-rasterized.
- Separately, while the window was hidden the 15 s sampler kept tracking
  `rss + 50% available`, so other apps' memory use shrank our caches
  immediately, and the growth damper (+max(64 MB, 25%) per 45 s) made the
  refill slow after the user came back.

## The fix

- **Windows signal:** the kernel's `LowMemoryResourceNotification`, or less
  than `max(256 MB, 5%)` of RAM available - the Linux runner's threshold.
- **Hysteresis:** a low-memory state ends only after
  `lowMemoryClearSamples` (2) consecutive clear samples.
- **No re-halving inside the cooldown:** a repeat signal within
  `pressureCooldown` of the last one does not halve again or restart the
  cooldown. The polled level only logs (`... again within the cooldown;
  budgets held`); a discrete OS `didHaveMemoryPressure` still reclaims.
- **Hidden apps hold their budgets:** between `hidden`/`paused`/`detached`
  and `resumed`, samples still watch for low memory but skip
  `applySnapshot`. `inactive` (visible, unfocused) is unchanged. The resume
  sample re-derives everything. Mobile still clears visited-page rasters on
  backgrounding, as before.

Tests: `app/test/adaptive_memory_test.dart` - the four new cases fail on the
old controller. The C++ change is not compiled in this Linux environment;
Windows CI builds it.

Not addressed here (found in the same audit, editing-only): the native render
worker allocates a whole-file buffer per edit and cached stream views pin the
old ones (`render_worker_isolate.dart` `'update'`); recovered-xref documents
reopen from scratch on every edit (`startXref == 0`); undo reopens cold.
