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

## What changed

The app and example web workers were already gitignored + generated; this makes
the `dart_pdf_editor_assets` copy follow the same pattern.

- **`.gitignore`** - ignore `pdf_render_worker.dart.js{,.map,.deps}` under both
  `dart_pdf_editor/assets/web/` and `dart_pdf_editor_assets/assets/web/`;
  `git rm --cached` the tracked `.js`.
- **`packages/dart_pdf_editor_assets/.pubignore`** - a single `!` negation
  re-including `assets/web/pdf_render_worker.dart.js`. `pub publish` drops every
  gitignored file unless a `.pubignore` overrides, and a negation in the
  package's `.pubignore` wins over the root `.gitignore` for that tree - so the
  published pub.dev archive still ships the declared worker asset.
- **`tool/release.sh`** - runs `dart run dart_pdf_editor:build_web_worker --out
  packages/dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js` right
  after the workspace resolve/analyze, before the release plan. This is the
  publish-side twin of what the deploy workflows already do; it runs before the
  dry-run too so `pub publish --dry-run` sees the declared asset. The assets
  package is publish-only via `release.sh` - it is deliberately absent from
  `publish-pub.yml`'s tag list, so there is no automated tag-publish path to
  also patch.
- **`.github/workflows/ci.yml`** - deleted the `worker-bundle` verify/regen job,
  the `concurrency` group that only existed to serialize its pushes, and
  `tool/ci/regen_web_worker.sh`. Replaced with `worker-compiles`: checkout, pub
  get, `build_web_worker --out $RUNNER_TEMP/...`, discard. Keeps the one real
  value (catching `.toJS`/dart2js errors `dart analyze` misses) with nothing to
  keep in sync and no write permission / token.
- **Docs** - a "Working on this repository" section in
  `doc/render_worker_web.md` explaining the generate-not-commit convention and
  the one-time `build_web_worker` step a bare `flutter run -d chrome` needs.

## The one real cost

A bare `flutter run -d chrome` / `flutter build web` from a fresh clone fails
with "asset not found" because the asset is declared but absent. Mitigation:
route local web work through `app/tool/build_web.sh` (already the norm), or run
`build_web_worker --out packages/dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js`
once. VM tests, `dart analyze`, and native builds never touch the file and are
unaffected. `WORKER_REGEN_TOKEN` can be deleted from repo secrets - nothing
references it anymore.
