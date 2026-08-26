# dart_pdf_editor_flutter_gpu

Opt-in retained-scene tile backend for `dart_pdf_editor`. It compiles supported
PDF commands and uploads decoded images once per retained scene, then renders
LoD tile slabs directly with Impeller's `package:flutter_gpu` API.

This is an experimental `0.x` companion package: its public API may evolve as
Flutter's GPU API matures. Unsupported content and platforms fall back to the
stable Canvas renderer instead of approximating PDF output.

```sh
flutter pub add dart_pdf_editor dart_pdf_editor_flutter_gpu
```

This companion deliberately stays outside `dart_pdf_editor`'s dependency graph.
The core viewer keeps its Flutter 3.24 minimum and Canvas/web behavior; apps that
choose this backend use Flutter 3.44 or newer and pass it explicitly:

```dart
PdfReader(
  bytes: bytes,
  // Keep one instance: its byte-budgeted image textures are reusable across
  // retained scenes, pages, workers, and LoDs.
  tileRasterBackend: FlutterGpuTileRasterBackend(
    maxTextureBytes: 256 << 20,
    maxGeometryBytes: 256 << 20,
    // Ordinary filled outlines use a scale-independent curve atlas by
    // default. Sparse native substitution runs stay on cheaper retained
    // stencil geometry; dense text still amortizes the atlas setup.
    analyticText: true,
    // Optional: retain simple substituted text using the native faces that
    // Canvas normally selects. Leave false if the app registers replacements
    // under these family names.
    systemTextOutlines: true,
  ),
)
```

Unembedded text remains on the conservative Canvas fallback by default because
Flutter does not expose the glyph paths selected by `TextPainter`. A host that
owns its font registrations can pass a `FlutterGpuTrueTypeTextOutliner` whose
resolver returns `FlutterGpuFontFace` instances built from those exact bytes,
including `FlutterGpuTrueTypeFontFace` and `FlutterGpuOpenTypeCffFontFace`.
`systemTextOutlines: true` is the native convenience adapter: it probes
known Helvetica/Arial, Times, Courier, Symbol, and platform-equivalent font
files. On macOS it also resolves the exact Songti, Heiti, Hiragino Sans, and
Hiragino Mincho faces selected by the Canvas CJK substitution stack, including
OpenType CFF faces inside font collections. It declines a run when the
requested face, glyph, or simple horizontal placement cannot be proved. It is
deliberately opt-in because an app may have registered different bytes under
the same Flutter family name. Web keeps the Canvas path.

Flutter GPU must also be enabled by the host. Add
`<key>FLTEnableFlutterGPU</key><true/>` to the iOS/macOS Info.plist (and
`FLTEnableImpeller` where Impeller is not already the platform default), or
this inside the Android `<application>` element:

```xml
<meta-data
  android:name="io.flutter.embedding.android.EnableFlutterGPU"
  android:value="true" />
```

For a desktop development launch, pass both engine opt-ins:

```sh
flutter run -d windows --enable-impeller --enable-flutter-gpu
flutter run -d linux --enable-impeller --enable-flutter-gpu
```

Packaged desktop applications must arrange the equivalent engine settings
before the engine starts. The DartPDF PR preview workflow demonstrates this
with profile-mode Windows/Linux bundles and also publishes a macOS DMG.

No master SDK, native-assets hook, or runtime shader compiler is required. The
Metal, GLES/GLES3, and Vulkan runtime stages are compiled offline and checked in
as a package asset. Unsupported platforms, disabled contexts, and unsupported
PDF features return to the Canvas tile backend automatically. Web gets a
compile-time stub and therefore preserves the all-platform host surface.

The current exact subset is solid paths and strokes (including zero-width PDF
hairlines that stay one device pixel at every LoD), filled and stroked
embedded-outline text, simple substituted text when an exact
`FlutterGpuTextOutliner` resolves it,
decoded images/image masks, Gouraud meshes, axial gradients, nested-circle
radial gradients, vector and stencil-image tiling cells, normal/Multiply/Screen
blending, solid-black overprint (including inside transparency groups), and
exact destination-sampling Overlay, Darken, Lighten, ColorDodge,
ColorBurn, HardLight, SoftLight, Difference, Exclusion, Hue, Saturation, Color,
and Luminosity blending,
rectangular and arbitrary path clips, and the common isolated single-image
soft-mask group. Isolated transparency groups containing a single vector fill,
stroke, outlined text run, ordinary image, gradient, or Gouraud mesh also stay
on the GPU: their group alpha and page blend mode are retained exactly.
One-element knockout groups are included
because there are no sibling elements for knockout to change. Alpha-one,
normal-blend non-knockout groups may contain multiple ordered fills, strokes,
outlined text runs, images, gradients, and meshes because source-over is
associative, so their isolation layer is an identity operation. Nested
alpha-one identity groups flatten into the same retained parent while keeping
their distinct per-paint clips. Isolated overlapping groups retain those same
paint types in the bounded offscreen tile pass before applying group alpha and
the outer blend once. Opaque non-isolated knockout groups with a declared
uniform backdrop also retain ordered vector fills and strokes: their bounded
attachment is seeded with that color and clipped to the form BBox. The
intermediate group target stays single-sample while
the final page target retains 4x MSAA, avoiding a redundant color/stencil
raster and resolve. Normal, Multiply, and Screen
remain per-paint state inside that attachment rather than being collapsed into
the group's outer blend. Platform-decoded JPEGs whose
`/SMask` remains a companion GPU
surface also keep their base and mask as separate cached textures and combine
them in the same shader path. A single vector fill can use one opaque grayscale
image soft mask directly through retained stencil geometry. Rectangular vector
soft-mask fills, including alpha or luminosity backdrops and linearized
transfer functions, are partitioned into constant-mask stencil cover cells and
need no intermediate texture.
Positive-width vector strokes also retain image and axial-gradient soft masks;
their dashed caps and joins become the same exact stencil geometry used by
ordinary retained strokes before the mask is applied. Masked zero-width
hairlines stay on Canvas because their one-device-pixel geometry is tile-scale
dependent.
An arbitrary content-side path clip around one soft-masked source is retained
as the ordinary GPU stencil clip on the resolved composite. Arbitrary clips
inside a single-image mask transcript use that same exact stencil when the
mask's backdrop and transfer function make its outside value zero. Rectangular
mask clips remain the bounded shader scissor; arbitrary mask clips with a
non-zero outside value still use Canvas.
A single ordinary soft-masked source may itself sit inside a transparency
group: the backend resolves that source in a bounded offscreen target and then
applies the enclosing group alpha once. This exact route requires no explicit
group backdrop, a Normal internal blend, and no enabled overprint; the other
forms remain on Canvas.
Paints behind a degenerate or disjoint rectangular clip are discarded while
capturing a transparency group, including balanced soft-mask content that can
no longer affect a pixel. Save/restore still reinstates the prior clip for any
later visible paint.
Tiles that sit at least one device pixel inside the transformed crop box use
the folded opaque paper color as their render-pass clear, avoiding a separate
transparent clear and full-tile paper draw. Boundary tiles retain the paper
quad so rotated and translucent page colors keep their exact antialiased edge.
When spatial selection finds no retained command for one of those interior
tiles, the backend submits a color-only clear pass. It does not allocate a
stencil or multisample attachment, create a transient host buffer, or bind a
draw pipeline; tiles near the crop edge continue through the ordinary path.
Advanced blend paints use bounded ping-pong tile attachments. Paints whose
bounds prove they cannot affect one another share one destination-sampling
pass; overlapping paints replay sequentially inside their conservative command
bounds to preserve PDF painter order without shading unrelated tile pixels.
Consecutive same-mode straight strokes can also share one transparent source
and one blend when raster-space capsule tests prove that their resolved pixels
are disjoint, even if their diagonal axis-aligned bounds overlap.
When the conservative source union occupies at most half the tile, its
transparent attachment is cropped to page-pixel-aligned bounds and the
blend shader remaps those texels onto the unchanged full-sized backdrop. Thick
offscreen strokes and low-LoD hairlines extend the crop before alignment, so
the optimization cannot trim antialiasing coverage.
Sparse sources also discard exactly transparent texels before the backdrop
lookup and blend arithmetic. The target already contains a native copy of that
destination, so skipping the fragment write produces the same PDF composite.
Each pass preserves the untouched ping-pong destination with a byte-exact GPU
texture blit rather than a full-tile fragment draw.
Offscreen groups can precede or follow those paints in the same exact route:
each group is prepared once in its bounded single-sample target, then sampled
into the ping-pong page at its original painter-order position. The completed
group texture can itself be the source of one advanced outer blend.
The route rejects before allocating when its temporary attachments would
exceed 256 MiB.
Rectangles use hardware scissors; other clip stacks compile once into retained
stencil geometry and preserve nonzero/even-odd plus save/restore semantics. The
mask case keeps the base and mask as two GPU textures and combines them during
tile replay; it never builds an eager full-size RGBA composite or reads pixels
back to the CPU. Worker-retained RGBA uploads directly; locally
platform-decoded images pay at most one readback before entering the shared
texture cache. A
backend-wide byte-budgeted LRU preserves decoded texture identity
across scenes, pages, workers, zoom levels, and LoDs.
Pinned scene textures count toward the same ceiling; if no unpinned entry can
make room, that scene falls back to Canvas instead of overshooting the budget.
Compiled vertices share a second strict byte budget. They are packed into
reusable power-of-two device-buffer size classes from 64 KiB through the 16 MiB
arena chunk size, and returned to the backend-wide pool only after their scene
is disposed and every submitted command buffer completes. This keeps sparse
pages small and command-heavy CAD navigation bounded without relying on
delayed native finalizers; a scene that cannot lease enough geometry also
falls back.

Ordinary filled outline text uses retained Slug-style quadratic curve streams:
one small nearest-sampled atlas stores each distinct page glyph and each draw
retains only six vertices per placed glyph. The fragment shader derives its
pixels-per-em from the current tile transform, so the same atlas stays sharp
across LoDs and rotated text. Gradient and soft-masked text, malformed or
over-complex outlines, and an atlas over the bounded 8 MiB ceiling retain the
existing stencil-fan path. Atlas creation failure is likewise an optimization
fallback, never a reason to reject the page.

After useful page pixels land and foreground work stays quiet for 750 ms, the
viewer asks the backend to warm its context. The backend submits one transparent
pixel through each tile pipeline and the nonzero stencil-cover state used by
retained fills, moving Impeller/driver compilation out of the first deep-zoom
interaction without delaying initial document paint or competing with an
immediate scroll. This work is coalesced per native view and MSAA mode, even
when several readers share the same process.

Proactive warm-up defaults on for macOS, Windows, and Linux. Android and iOS
stay on-demand by default because merely creating an Impeller GPU context can
reserve significant memory before a page is known to be GPU-compatible. A host
that has validated its mobile device range can opt in with
`enableProactiveWarmUp: true`; normal on-demand GPU tiles remain available when
the option is false.

The same idle gate then prepares the live page's retained tile session: scene
geometry and decoded-image uploads are compiled once and every scene pipeline
is submitted at one-pixel page scale. The real first tile reuses those retained
resources. Starting new foreground work cancels and restarts both delays; page
disposal releases the prepared resources through the ordinary scene lifecycle.

`backend.stats` reports accepted/rejected/active sessions, the latest actual
tile route, runtime fallback reasons, context and scene warm-up outcomes,
scene compile and tile-submit time,
spatially selected command counts, upload/readback paths, cache hits and
evictions, budget fallbacks, retained bytes, and live resource leases.
Clip diagnostics separately report paths compiled and tile-mask rebuilds.
Paper diagnostics report how many tiles used the exact interior clear path and
how many of those were content-free color-only submissions.
Transient-buffer diagnostics report emplaced bytes, allocated buffers/bytes,
and the peak allocation for one tile, making dense dynamic hairline workloads
and ordinary 64 KiB submissions separately visible.
Subpixel-stroke diagnostics report resolution-aware runtime fallbacks for
dense CAD tiles whose positive-width linework falls below one 4x MSAA coverage
quantum; the viewer permanently serves that session through Canvas rather than
displaying incomplete linework.
Advanced-blend diagnostics report destination-sampling passes, destination
blits, cropped-source selections, allocated and peak temporary bytes, and
budget fallbacks.
`backend.stats.toJson()` is suitable for benchmark artifacts. Keep the backend
instance alive when comparing pages so those counters and cross-page caches
describe the real workload rather than one page at a time.

Pages with other transparency groups or soft masks, non-nested radial
gradients, gradient overprint, unsafe overprint, complex
clips around a non-zero soft-mask backdrop, unresolved
substituted text, or missing image pixels are rejected as a whole rather than
approximated.
`allowOverprintApproximation` exists only for controlled experiments and
defaults to false.

## Persistent LoD tiles

`dart_pdf_editor` can also persist accepted or Canvas-fallback tiles through
the existing platform-neutral cache seam. Use a separate byte budget so tiles
cannot evict cold-navigation previews:

```dart
final store = createPersistentCacheStore();
final rasterCache = PdfRasterCache(
  PdfDiskCache(store, namespace: 'page-previews'),
  tiles: PdfDiskCache(
    store,
    namespace: 'lod-tiles',
    maxBytes: 256 << 20,
  ),
);

PdfReader(
  bytes: bytes,
  rasterCache: rasterCache,
  tileRasterBackend: gpuBackend,
)
```

A disk lookup races the ordinary tile render, so a cold or slow store cannot
delay first content. A hit may win the race and populate the memory LRU; a
fresh tile is admitted to the compositor before its PNG encoding and disk
write begin. Cache keys include the document, revision/page stamps, page visual
options, tile coordinate, exact region, dimensions, and LoD ratio.

## Validation and measurement

Run native tests with the opt-in flags:

```sh
fvm flutter test --enable-impeller --enable-flutter-gpu
```

`test/gpu_corpus_test.dart` checks every Ghent file and the PDF.js corpus,
comparing every GPU-accepted page against Canvas while treating conservative
rejection as the intended fallback. `test/real_document_benchmark_test.dart`
measures scene recording/image decode, cold and warm 512 px LoDs, forced visual
settle, Canvas parity, upload/cache counters, and RSS. It is opt-in via
`PDF_GPU_BENCHMARK_PDF` and accepts a zero-based comma-separated page list in
`PDF_GPU_BENCHMARK_PAGES`. Set `PDF_GPU_BENCHMARK_OUT` to a directory to save
the center 512 px GPU and Canvas tiles for visual comparison, or
`PDF_GPU_BENCHMARK_MSAA=0` to isolate multisample antialiasing differences.
Set `PDF_GPU_BENCHMARK_WARMUP=1` to measure the viewer's pipeline warm-up before
the first real tile.
Set `PDF_GPU_BENCHMARK_SCENE_WARMUP=1` to additionally compile and submit the
retained scene before measuring that tile.
Set `PDF_GPU_BENCHMARK_SCENARIO` to emit normalized `PdfPerfLog` scenario
markers for each pipeline/scene/tile phase. CI uses those markers to run the
checked-in tiling-pattern, radial-shading, hairline, advanced-blend,
vector-mask transfer, PDF.js knockout soft-mask and isolated-knockout overlap,
GWG168/169 vector
soft-mask, and GWG1610/1611 text soft-mask pages plus the PDF.js Latin and CJK
system-font outline pages and deterministic deferred-mask fixture six times on
macOS Metal. A generated repeated-advanced-blend page adds twelve ordered
destination-sampling passes, giving blend optimizations a higher-signal
measurement than the small PDF.js conformance page alone.
CI compares the exact PR base and candidate on the same runner with balanced
execution order, and publishes both a concise PR headline and a collapsed
detailed trace.
Set `PDF_GPU_BENCHMARK_FIXTURE=deferred-mask` instead of a PDF path to exercise
a deterministic 1024x768 JPEG under a Flate grayscale soft mask. This fixture
emits the same first-tile and Canvas scenarios whether the backend accepts the
scene or production falls back to Canvas, so a backend-routing change remains
a like-for-like comparison. Pipeline and scene warm-up scenario markers are
suppressed for this production-route fixture; the warm-up itself still runs.
An unmeasured Canvas pass immediately before the Canvas control keeps that
reference warm on both the accepted and fallback routes without warming the
cold first-tile measurement.
Set `PDF_GPU_BENCHMARK_ROUTE_CHANGE=1` for the same normalization when a PDF
path, rather than the built-in fixture, changes from Canvas fallback to direct
GPU. Route-change scene warm-up still runs when requested, matching the
viewer's idle-prepared path, but its unmatched timing marker is omitted because
the Canvas base has no GPU session to warm. CI uses it for the checked-in
vector-mask transfer, knockout soft-mask, isolated-knockout overlap, hairline,
advanced-blend, and GWG vector/text soft-mask pages.
Set `PDF_GPU_BENCHMARK_SYSTEM_TEXT=1` to enable the native system-font outline
adapter. For a like-for-like macOS parity control,
`PDF_GPU_BENCHMARK_REGISTER_SYSTEM_FONTS=1` registers those same font bytes
under Canvas's substitution-family names; CI combines both settings for the
system-font and advanced-blend route-change scenarios.
The corpus equivalents are `GPU_CORPUS_SYSTEM_TEXT=1` and
`GPU_CORPUS_REGISTER_SYSTEM_FONTS=1`; the designated macOS GPU lane runs that
full parity matrix on every change.
Set `PDF_GPU_BENCHMARK_ANALYTIC_TEXT=0` or
`GPU_CORPUS_ANALYTIC_TEXT=0` for a same-build comparison against the retained
stencil-fan text path.
Set `PDF_GPU_BENCHMARK_OVERPRINT=0` to exercise the production-default exact
fallback policy; the benchmark otherwise enables its documented source-over
approximation so more of a corpus can be measured on the GPU.
