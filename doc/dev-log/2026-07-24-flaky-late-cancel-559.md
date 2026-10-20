# 2026-07-24 — killing the flaky late-cancel test (#559)

`render_worker_strips_test` › *"a late cancel id cannot abort the next worker
request"* failed intermittently (Expected 1, Actual 0), reddening unrelated PRs
and forcing CI reruns. This session made it deterministic by deleting the
wall-clock guess at its heart.

## What it guards

Issue #220: a request-scoped cancel can reach the worker *after* its target
already replied and the next (often urgent) page has taken the slot. The worker
must recognise that stale id and ignore it — comparing against `activeRequestId`
and emitting `cancelIgnored` — rather than aborting the innocent next page. The
test drives exactly that ordering and asserts the ignore fired once.

## Why it flaked

To *stage* the late arrival, the old test hook lived on the **main** isolate.
`_cancelRequest` stashed the cancel id instead of sending it, and after the
cancelled page replied and the next page was dispatched,
`_deliverDeferredCancelToNextRequest` sent it — behind a fixed
`Timer(5 ms)`:

```dart
Timer(const Duration(milliseconds: 5), () {
  if (!_disposed) _toCancelPort?.send(id);
});
```

The 5 ms was a bet that within that window the worker would dequeue the next
request's message and set `activeRequestId` to the new id. On an unloaded box it
always won; on a loaded CI runner the worker sometimes hadn't picked the message
off its `requests` port yet, so when the cancel landed `activeRequestId` was
*still the old id* — the branch matched, no `cancelIgnored` was sent, and the
counter stayed 0. A cross-isolate race decided by wall-clock time: flaky by
construction.

## The fix — move the defer onto the worker's own event loop

The staging now happens **inside the worker**, where message ordering is a hard
guarantee rather than a timing bet. Under the (unchanged) test flag, the
worker's cancel listener, on a cancel that targets the *currently active*
request, stashes it instead of acting:

```dart
cancelPort.listen((message) {
  if (message is! int) return;
  if (deferStaleCancel &&
      deferredStaleCancelId == null &&
      message == activeRequestId) {
    deferredStaleCancelId = message;   // hold it
    return;
  }
  handleCancel(message);
});
```

and replays it the instant the **next** request goes active — right after
`activeRequestId` is reassigned in the request handler:

```dart
activeRequestId = id;
final staleId = deferredStaleCancelId;
if (staleId != null) {
  deferredStaleCancelId = null;
  handleCancel(staleId);   // targets the previous id → reported ignored
}
```

Everything that used to race across two isolates now happens as consecutive
steps on one event loop. The flag rides in via `_WorkerInit.deferStaleCancel`,
read once at spawn — so the test sets the global **before** `startUncached`
(the spawn reads globals synchronously as it runs). The whole main-side
apparatus — `_deferredCancelId`, the defer branch in `_cancelRequest`,
`_deliverDeferredCancelToNextRequest`, and the `Timer` — is gone; `_cancelRequest`
is now just `_toCancelPort?.send(request.id)`.

## Why it is now order-independent

The cancel for page 0 and page 0's own request reach the worker on two
different ports, so their relative processing order is not guaranteed. Both
interleavings now yield the same result:

- **request-then-cancel** (the intended path): page 0 active → cancel stashed →
  page 0 finishes → page 1 active → replay → `page0 != page1` → ignored once.
- **cancel-then-request**: `activeRequestId` is still the warm-up id, so the
  cancel isn't stashed (it doesn't target the active id) and is reported ignored
  immediately — still exactly once.

Either way page 0 is never actually cancelled (its token is only ever touched
when it is *not* the active request), so it completes in full, and
`cancelIgnored` fires exactly once. The assertions hold on every interleaving.

## Scope

Native isolate only. The web twin (`render_worker_web_entry.dart`) has its own
`activeRequestId`/`cancelIgnored` handling but never carried this defer hook and
is not exercised by this VM-only test, so it is untouched.

## Verified

`fvm dart analyze` clean; the full `render_worker_strips_test.dart` (15 tests)
green across repeated back-to-back runs where the old hook was the sole source of
intermittent red.
