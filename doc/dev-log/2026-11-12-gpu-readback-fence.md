# flutter_gpu: fence the scene warm-up on GPU completion; split the Patrol tile metric

## Why

After the Flutter 3.50 upgrade (#1279), Native Patrol on the Android emulator
showed the GPU first tile going from roughly 55–150 ms to roughly 490–580 ms.
The emulator logs of a 3.47 `main` run and a 3.50 PR run show the cause.

- **Same renderer.** Both versions log
  `Using the Impeller rendering backend (Vulkan)` on SwiftShader. CI forces
  Vulkan with `tool/android_patrol_vulkan_manifest.xml`.
- **Same GPU tile cost.** `tile gpu complete` lands about +73 ms (3.47) and
  about +81 ms (3.50) after the scenario starts.
- **The time went into a readback.** The scenario timed
  `rasterizeRegion` + `image.toByteData(rawRgba)`. On 3.50 that GPU-to-CPU
  copy took about 400 ms on the emulator, and the frames that run during it
  (`JANK raster=20–80ms`) fill the gap.

No on-screen path reads tiles back. Two places did:

1. **The idle scene warm-up**, which used a 1-pixel `toByteData` as its "done"
   fence. On 3.50 this cost 154–244 ms → 473–493 ms in two of three runs.
2. **The benchmark itself**, for its GPU-vs-Canvas pixel parity check.

## What changed

- **A real completion fence.** `_CompiledScene.whenSubmissionsComplete()`
  (`backend_native.dart`) returns a future. It completes when `_inFlight`
  reaches 0, and its value is `false` if any submission failed since the last
  idle point. It is settled from `_completeSubmission` and from the three
  submit-throw paths. `_warmUpScene` awaits it instead of the readback, and a
  failed fence raises `StateError('GPU scene warm-up submission failed')`.
  The image-upload fallback readback (`textureReadbacks`) is unchanged; it
  genuinely needs the pixels.
- **Split benchmark metric.** In `native_perf_e2e_test.dart`,
  `_measureTileThenReadback` times each tile as two scenarios:
  - `gpu-native-page-0-{first,canvas,reused}-tile` runs until the tile is
    finished. For flutter_gpu that is the GPU completion, polled at 1 ms via
    `stats.inFlightSubmissions`. For Canvas it is the returned image.
  - `...-tile-readback` covers the `toByteData` copy only.

  The CI scripts and the workflow now require the three readback scenarios.
  The "first tile vs Canvas" headline matches on `endsWith('-first-tile')`, so
  it now compares render times only.

## Expect on the first CI run

The `main` baseline still measures render + readback under the old names. On
this PR's first comparison the tile scenarios will therefore read as large
improvements, and the readback scenarios will have no baseline. That is the
metric changing meaning, not a speedup. Comparisons become like-for-like once
this lands on `main`.

## Still open

Check `toByteData` latency on a real Android device. If it reproduces off
SwiftShader, report it upstream.
