# CI: auto-regenerate the bundled web render worker (issue #411)

## Problem

`packages/dart_pdf_editor/assets/web/pdf_render_worker.dart.js` is a ~970 KB
`dart compile js` bundle that links most of the stack, so nearly any change to
`pdf_cos` / `pdf_document` / `pdf_graphics` / `dart_pdf_editor` makes it stale.
The old CI step ("Verify bundled web render worker") rebuilt it to `/tmp` and
failed the build on any drift. Two recurring failure modes on the perf PR queue:

1. **Staleness** - a `pdf_cos`-only change fails CI on a `dart_pdf_editor`
   asset, with no obvious coupling in the diff.
2. **Merge conflict** - a textual 3-way merge of two dart2js outputs is
   meaningless; git can synthesize a bundle matching neither source tree, and it
   would still pass review (nobody reads 970 KB of minified JS). The only correct
   resolution is "throw both sides away and regenerate."

The bundle must stay in git: it is a declared Flutter asset that ships in the
pub.dev package and a fresh clone-and-run needs it. So the fix is to make a human
never have to think about it.

## What landed (A + B from the issue)

**A. `.gitattributes`** - `packages/dart_pdf_editor/assets/web/pdf_render_worker.dart.js -merge -diff`.
`-merge` makes git keep our side and flag a conflict instead of interleaving
compiler-output hunks (kills the silent-corruption risk); `-diff` keeps the
minified JS out of diffs/PR views. Mirrors the existing `merge=union` pattern for
the append-only dev-log/changelogs.

**B. `tool/ci/regen_web_worker.sh`** + a dedicated `worker-bundle` CI job.
Replaces verify-and-fail with regenerate-and-push on same-repo PRs:

- Build the worker twice and `cmp` the outputs - **reproducibility** check
  (byte-stable across macOS arm64 and CI Linux x64 on SDK 3.44.4; caught a real
  problem on #410).
- If the build matches the checked-in copy, exit 0.
- If it differs and this is a **same-repo pull request**, move onto the PR head
  branch, overlay the freshly built bundle, and commit + push it.
- On **forks and push events** (no push back available), fall back to the old
  verify-and-fail with an actionable message.

### Ordering constraint (the subtle bit)

The bundle must be built from the **rebased/merged** source, not the PR's old
base - regenerating against the old base produces a bundle that re-stales the
moment it merges. This falls out for free: on a `pull_request` event
`actions/checkout` checks out the merge ref (head merged with base), so the build
is already merged-source. The script then commits that merged-source bundle onto
the head branch (it is byte-identical to what the post-merge tree produces).

### Why a separate job

The compile also catches `.toJS`-conversion errors `dart analyze` misses (async
message handlers only fail at `dart compile js`), which the old step in `test`
provided. Moving it to its own job with `permissions: contents: write` keeps the
`test` job least-privilege and lets the two run in parallel.

### Gotchas

- Pushes made with the default `GITHUB_TOKEN` do **not** re-trigger workflows, so
  the auto-commit cannot loop. The tradeoff: the follow-up commit carries no CI
  run of its own; the reproducible build in the same run is the evidence. Swap in
  a PAT/App token if you want the follow-up commit to re-run checks - the script
  is idempotent (no-ops once the bundle is fresh), so that stays safe.
- `-diff` does not break change detection: `git diff --quiet -- <asset>` still
  sets a non-zero exit on a content change (verified).
- The build ran on the detached merge ref, so the script does
  `git checkout -f -B "$HEAD_REF" origin/$HEAD_REF` (the `-f` discards the merge-
  ref tree and anything `flutter pub get` touched) before overlaying + committing.
