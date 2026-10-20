# Stop committing the generated web-worker bundle (#582)

`packages/dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js` (~1 MB,
a `dart compile js` output) changed in 8 of the last 8 substantive commits -
nearly every `pdf_cos`/`pdf_graphics`/`dart_pdf_editor` change regenerates it.
Two `dart2js` outputs can't merge textually, so any two open bundle-touching
PRs went `DIRTY` the moment one landed, and GitHub then couldn't build the
merge-ref, leaving the second PR with no CI. The whole #422/#571 stack
(concurrency group, auto-regen push, `WORKER_REGEN_TOKEN`, loop guard) existed
solely to keep this committed blob in sync - and the token only fixed
auto-regen, never conflicts. The committed `.js.deps` sibling also leaked
absolute local pub-cache paths.

## The constraint the issue missed: a declared asset must exist

The issue proposed gitignoring the bundle entirely and generating it at the
consume points, asserting "VM tests, `dart analyze`, and native builds are
unaffected (they never touch the file)." That is wrong. The worker path is a
**declared Flutter asset** (`flutter: assets:` in the assets package pubspec -
it must be, so it ships in the pub.dev package and loads at the
`assets/packages/dart_pdf_editor_assets/...` URL). Flutter bundles a package's
declared assets on **every** build target, and `dart analyze` validates their
existence. So a fully-absent bundle breaks:

- `dart analyze --fatal-infos` -> `asset_does_not_exist` (the `test` CI job).
- `flutter build linux` and the five other native targets in `release-app.yml`
  (apk/appbundle/linux/windows/macos/ios), plus the CI `linux` job ->
  `No file or variants found for asset ...`.

Pure-gitignore would therefore have to add a generate step to ~7 native build
jobs (fragile: any future build job silently breaks), and every fresh-clone
`analyze`/`flutter build` would fail until you generated the worker.

## What actually shipped: a committed placeholder + generate-over-it

Keep the declared asset **always present** as a tiny (~1.5 KB), stable
placeholder that never changes, and regenerate the real ~1 MB bundle over it at
the web consume points. This solves every problem the issue listed (churn,
unmergeable diffs, `.js.deps` leak) with zero changes to the native-build
matrix.

- **Placeholder** committed at the asset path. It `throw`s on load, so on the
  rare path where it is the file actually served on web (a bare
  `flutter run -d chrome` without `build_web.sh`), the client's worker `onerror`
  handler (`render_worker_web.dart:175-183`) falls back to main-thread rendering
  - the same graceful degradation as an unset worker URL. It is never served in
  production: every web deploy/preview/release and `build_web.sh` regenerate
  first.
- **`.gitignore`** - ignore only the `.js.map` and `.js.deps` build siblings
  (the `.deps` path leak); the `.js` itself is the tracked placeholder
  (`.gitignore` has no effect on a tracked file anyway).
- **`tool/release.sh`** - `build_web_worker` before publishing (so the pub.dev
  archive ships the real worker, not the placeholder), with a `trap` that
  `git checkout`s the placeholder back on exit so a release run never leaves the
  blob in the tree. No `.pubignore` needed - the file is tracked, so `pub
  publish` includes it normally.
- **`.github/workflows/ci.yml`** - deleted the `worker-bundle` regen/verify job,
  its worker-only `concurrency` group, and `tool/ci/regen_web_worker.sh`. Added
  `worker-compiles`: (a) a byte-size guard that the committed asset stays the
  small placeholder (>8 KB fails - catches an accidentally-committed real
  bundle), and (b) `build_web_worker --out $RUNNER_TEMP/...`, discarded, keeping
  the compile gate that catches `.toJS`/dart2js errors `dart analyze` misses.
  `WORKER_REGEN_TOKEN` is no longer referenced anywhere.
- **Docs** - `doc/render_worker_web.md` "Working on this repository" section.

## Costs / gotchas

- Running `build_web.sh` or `release.sh` locally overwrites the placeholder with
  the real ~1 MB bundle, showing as an uncommitted modification. `git checkout`
  the path to restore it; the CI size guard fails if the blob is ever committed.
- `WORKER_REGEN_TOKEN` can be deleted from repo secrets - nothing references it.
- VM tests, `dart analyze`, and native builds are unaffected *because* the
  placeholder exists - that was the whole point of keeping one.
