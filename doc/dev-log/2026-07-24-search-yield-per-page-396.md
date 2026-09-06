# Search yields per page (#396, part 3 — the short-term mitigation)

#396 ("default render worker + off-UI-thread text extraction") has three parts:

1. Ship a default `PdfRenderWorker` so interpretation is off-thread unless the
   host opts out — the headline, a viewer-lifecycle change (its own follow-up).
2. An off-thread `extractText(pageIndex)` worker job for search/hover — needs a
   worker-protocol addition and the web bundle rebuild, so the web half waits on
   the #422/#571 `WORKER_REGEN_TOKEN`.
3. Short-term main-thread mitigation: yield per page in search, and gate the
   hover text probe.

This change is **part 3**, chosen to land first (safe, main-thread only, no
worker/bundle involvement).

## What changed

`_searchAllPages` yielded a `Future.delayed(Duration.zero)` only every fifth page
(`i % 5 == 4`). It now yields after **every** page. Each page still interprets a
full content stream synchronously on the UI thread (100–420 ms on a heavy page —
that is what part 1/2 move off-thread), so the yield does two things: a frame can
paint between pages, and the superseding-search bail at the top of the loop
(`_controller._query != query`) sees a newer keystroke's query one page later
instead of up to five. Net: the worst uninterruptible span drops from five heavy
pages to one, and a keystroke cancels a stale full-document walk that much sooner.

The yield is deliberately a `Duration.zero` **timer**, not a microtask — a
microtask wouldn't let the keystroke event (or rendering) run, so the bail would
never see the new query.

## The hover half was already done

Part 3 also asked to gate the hover text probe. That guard is already in:
`_hoverTextCursorAt` skips extraction for pages over
`hoverTextExtractMaxRawContentBytes` (512 KB raw content) and returns "no text
cursor" unless the page is already cached — so a heavy CAD sheet never triggers
the multi-hundred-ms hover freeze. Pages under the threshold extract in a few ms.
So no hover change was needed here.

## Test fallout

Small-document search tests used `unawaited(controller.search(...))` +
`await tester.pump()`, relying on the search completing within one microtask
drain (a <5-page doc never hit the every-fifth timer). With a per-page timer they
must advance it, so three of them move to `pumpAndSettle(100 ms)` — the same
pattern the sibling option-toggle tests already use. Results are unchanged; only
the number of event-loop turns to complete a search moved.

Files: `packages/dart_pdf_editor/lib/src/pdf_viewer.dart`,
`packages/dart_pdf_editor/test/search_navigation_test.dart`.
