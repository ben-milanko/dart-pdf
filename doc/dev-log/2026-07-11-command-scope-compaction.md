# Worker command-scope compaction

Issue #216's remaining main-isolate cost was measured on
`corpus/ly9-far-cad.pdf`, page 4: 98,936 worker-recorded commands, about
53 ms to deserialize and 57 ms to build the initial canvas picture.

The command mix explained the decode cost:

- 32,405 `save` commands;
- 32,405 matching `restore` commands;
- 32,401 paint commands;
- only 2 clip commands.

Recorded geometry is already in page space, every paint command carries its
complete style, images carry their transform, and the interpreter emits an
explicit blend-mode command when `restore` changes it. A `save`/`restore`
scope therefore has no replay effect unless a clip is installed at that same
nesting depth. Nested clip scopes protect themselves and do not make a parent
scope necessary.

Render-worker serialization now opts into a compaction pass that removes only
those clip-free pairs. The public codec remains lossless by default. Unmatched
commands in a command-limited preview are retained, clip-owning scopes are
retained, and soft-mask callback command lists are compacted recursively.

On the CAD page the transferred list fell from 98,936 to 34,130 commands. In
the isolated codec probe, deserialize time fell from 53.3 ms to 28.8 ms (about
46%). The production worker probe (`command_replay_latency_test.dart`, three
warmed samples) measured 34.5 ms for the compacted vector-only buffer and
41.2 ms for the compacted full image-bearing buffer. The latter still pays to
reconstruct the image's detached COS graph; command count is no longer its
only cost.

Canvas picture construction stayed near 53-57 ms, as expected: it is dominated
by converting 539,814 path segments and issuing the paint calls, not by
`canvas.save()` / `canvas.restore()` themselves. The retained command list also
sheds roughly two thirds of its command objects on this page.

Rejected alternatives from the same probe:

- the pre-replay image scan cost about 0.44 ms, too small to justify metadata
  caching;
- fixed-length decode lists were within noise;
- native VM object-graph transfer cost about 151 ms one-way, much slower than
  the binary decoder;
- an earlier color/stroke cache prototype regressed the benchmark and remains
  reverted.

After compaction, the CAD page's 32,401 paints form 1,814 consecutive style
groups across only 18 unique styles. Batching those runs may reduce the
remaining picture-build cost, but it needs its own correctness work: combining
fills can change nonzero/even-odd winding, and combining overlapping strokes
can change antialias coverage. That direction is tracked separately rather
than weakening the wire-compaction patch's exact semantics.
