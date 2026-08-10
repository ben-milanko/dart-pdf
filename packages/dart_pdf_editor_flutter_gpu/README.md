# dart_pdf_editor_flutter_gpu

Opt-in retained-scene tile backend for `dart_pdf_editor`. It compiles supported
PDF commands and uploads decoded images once per retained scene, then renders
LoD tile slabs directly with Impeller's `package:flutter_gpu` API.

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
  ),
)
```

Flutter GPU must also be enabled by the host. Add
`<key>FLTEnableFlutterGPU</key><true/>` to the iOS/macOS Info.plist, or this
inside the Android `<application>` element:

```xml
<meta-data
  android:name="io.flutter.embedding.android.EnableFlutterGPU"
  android:value="true" />
```

No master SDK, native-assets hook, or runtime shader compiler is required. The
Metal, GLES/GLES3, and Vulkan runtime stages are compiled offline and checked in
as a package asset. Unsupported platforms, disabled contexts, and unsupported
PDF features return to the Canvas tile backend automatically. Web gets a
compile-time stub and therefore preserves the all-platform host surface.

The current exact subset is solid paths and strokes, embedded-outline text,
decoded images/image masks, Gouraud meshes, normal blending, rectangular
clips, and the common isolated single-image soft-mask group. That mask case
keeps the base and mask as two GPU textures and combines them during tile
replay; it never builds an eager full-size RGBA composite or reads pixels back
to the CPU. Worker-retained RGBA uploads directly; locally platform-decoded
images pay at most one readback before entering the shared texture cache. A
backend-wide byte-budgeted LRU preserves decoded texture identity
across scenes, pages, workers, zoom levels, and LoDs.
Pinned scene textures count toward the same ceiling; if no unpinned entry can
make room, that scene falls back to Canvas instead of overshooting the budget.

Pages with other transparency groups or soft masks, non-normal blends,
gradients, tiling cells, unsafe overprint, non-rectangular clips,
substituted/stroked text, hairlines, or missing image pixels are rejected as a
whole rather than approximated. `allowOverprintApproximation` exists only for
controlled benchmarks and defaults to false.

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
`PDF_GPU_BENCHMARK_PAGES`.
