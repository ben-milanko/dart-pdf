# Canvas replay paint runs

Issue #226 followed the command-scope compaction work: its pinned CAD page
(`corpus/ly9-far-cad.pdf`, page 4) reached the UI isolate as 34,130 commands,
but constructing the canvas picture still took about 53 ms.

The first implementation tried the issue's most conservative geometry merge:
combine only consecutive, identical, opaque fills or simple strokes whose
1-point-inflated bounds were pairwise disjoint. It was rejected. The page's
bounds overlap heavily, so 29,075 eligible fill commands still produced 29,048
draws and 3,182 simple strokes still produced 3,099 draws. Bounds checks and
buffering regressed construction from 52.8 ms to 60.6 ms.

The shape probe found a safer opportunity in the same compacted runs:

- 29,075 solid fills;
- 3,326 strokes, of which 3,218 are exactly one `moveTo`/`lineTo` pair;
- 1,814 consecutive styles across 32,401 paint commands.

`CanvasPdfDevice` now keeps the last immutable solid fill/stroke `Paint`, keyed
by every field that reaches the engine (color, alpha, effective blend, and
stroke geometry). Flutter snapshots `Paint` at each draw, so reusing the object
does not alter earlier commands. Undashed two-segment strokes use
`Canvas.drawLine` directly instead of constructing a `ui.Path`; every command
remains an independent draw in its original order.

The diagnostic test can switch both optimizations off and measures all variants
in one process. Twelve warmed passes on the pinned page:

- baseline: 53.0 ms;
- prepared Paints: 52.2 ms;
- prepared Paints + direct lines: 49.9 ms (5.8% lower).

On the 326-command first page of
`Flutter_CTO_Report_2024_by_LeanCode.pdf`, 50 warmed passes measured 1.1 ms →
0.5 ms, so the constant last-style checks do not add a light-page tax.

Focused tests compare raw RGBA bytes against the old fresh-Paint/drawPath route
across fill rules, alpha, transforms, line widths/caps, crossings, and a
zero-length round-cap dot. The Ghent baseline and PDF.js render corpus pass
without changes. Strip command replay, binning, flush ordinals, and cancellation
are untouched; delegated canvas operations merely use the equivalent primitive
when their tape is painted.
