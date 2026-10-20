# The idle ~1 Hz jank was the devtools observer loop (#452)

The mobile-web trace showed the app producing janky frames (`build` 25–110 ms)
roughly twice a second, indefinitely, with the document idle. Ben had already
root-caused it to a self-sustaining loop in the app's devtools panel and landed
two of the three fixes; this closes the last edge.

## The loop

`AppDevTools` (a `ChangeNotifier`, `app/lib/devtools.dart`) both records logs and
watches frame timings. Three notify edges fed the panel:

1. **Perf-sink JANK lines** → `_record(notify: true)`. **Already fixed** — the
   sink records with `notify: false` (a JANK line per janky frame must not
   schedule a rebuild).
2. **Any notify while the panel is closed** → **already fixed** — `_scheduleNotify`
   returns early unless `hasListeners`.
3. **`_onTimings`** → `_scheduleNotify()` on *every* frame-timings batch. Still
   live, and the last self-sustaining edge: a notify rebuilds the panel, a panel
   rebuild is itself a frame, that frame fires `_onTimings` again → notify →
   rebuild → … The 250 ms leading-edge throttle paces it, and each rebuild is a
   25–110 ms build on a throttled phone, so the effective cadence lands at the
   observed ~1–2 Hz. The measurement was driving the thing it measured.

With the panel *closed*, edge 2 already suppressed all of this - so a normal user
never saw it. But the export button lives inside the panel, so every exported
trace was taken with the panel open and the loop running.

## The fix

`_onTimings` no longer notifies. It still accumulates the frame-timing window
(that's what `frameStats()` reads), but the panel's own 1 s `Timer.periodic` poll
(`devtools_panel.dart`, already present for cache/RSS/PdfPerf stats that have no
change notification) is what refreshes the display. So while the panel is open
and idle, it rebuilds once a second from the timer - a controlled tick, not a
frame→notify→frame loop - and log entries still notify immediately via `addLog`.

One line removed, plus a `debugAddTimings` test seam and a guard in
`devtools_notify_test.dart`: a frame-timings batch accumulates the window
(`frameStats().frames == 2`) but fires zero notifies even with a listener
attached.

## What this does and doesn't settle

It definitively removes the observer loop, so exported traces (panel open) are now
trustworthy and the app no longer self-perpetuates frames while idle. What it
can't settle from here is whether any *real* idle-frame source remains underneath
- that needs an on-device capture with the panel **closed** via the `?perf=1`
boot hook (JANK lines go to the browser console, no sink, no panel). With the
loop gone, such a trace would now attribute cleanly. My expectation: panel-closed
was already loop-free (edge 2), so a clean `?perf=1` run should be quiet.

Files: `app/lib/devtools.dart`, `app/test/devtools_notify_test.dart`.
