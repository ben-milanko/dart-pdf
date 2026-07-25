#!/usr/bin/env bash
# CI: regenerate the bundled web render worker and keep it in git in sync with
# the source, instead of failing the build when it drifts. See issue #411.
#
# `packages/dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js` is a
# `dart compile js` bundle that links most of the stack, so any change to
# pdf_cos / pdf_document / pdf_graphics / dart_pdf_editor can make it stale. It
# is a *declared Flutter asset* that ships inside the published pub.dev package
# and is needed for a fresh clone-and-run, so it has to stay checked in - what
# should never happen is a human having to remember to rebuild it.
#
# On a same-repo pull request this rebuilds the bundle and, if it changed,
# commits it to the PR head branch and pushes - but only when a re-triggering
# token (REGEN_TOKEN) is configured, so the pushed head gets its own CI run
# (issue #422, defect 3). Without that token, and on forks / push events, it
# falls back to the old verify-and-fail rather than leaving an unchecked head.
#
# The build runs against the checked-out tree. On a `pull_request` event
# `actions/checkout` checks out the merge ref (the PR head merged with the base
# branch), so the bundle is built from the *merged* source - this is the
# ordering constraint from #411: regenerating against the PR's old base would
# produce a bundle that goes stale again the moment it merges.
#
# Env (set by the workflow):
#   ASSET             path to the checked-in bundle (required)
#   EVENT_NAME        github.event_name
#   IS_SAME_REPO      "true" when the PR head repo is this repo (not a fork)
#   HEAD_REF          github.event.pull_request.head.ref (the PR branch)
#   REGEN_TOKEN       optional PAT/App token whose push re-triggers CI (#422)
#   GITHUB_REPOSITORY owner/repo, used to build the authenticated push URL
set -euo pipefail

ASSET="${ASSET:?ASSET must point at the checked-in bundle}"

TMP1="$(mktemp)"
TMP2="$(mktemp)"
trap 'rm -f "$TMP1" "$TMP2"' EXIT

build() {
  # Same compile the deploy workflows run; also the gate that catches
  # `.toJS`-conversion errors `dart analyze` misses (async message handlers).
  dart run dart_pdf_editor:build_web_worker --out "$1"
}

echo "==> Building the web render worker from the checked-out (merged) source"
build "$TMP1"

# Reproducibility: a second build must byte-match the first. This proves the
# output is stable WITHIN a single runner in a single run (it caught a real
# machine-dependent build on #410) - it does NOT prove determinism ACROSS runs
# or runners (issue #422, defect 2). The loop guard below bounds any residual
# cross-run drift to a single bot commit per human push.
echo "==> Rebuilding to confirm the output is reproducible"
build "$TMP2"
if ! cmp -s "$TMP1" "$TMP2"; then
  echo "::error::Web render worker build is not reproducible (two builds differ)."
  exit 1
fi

if cmp -s "$TMP1" "$ASSET"; then
  echo "==> Bundled web render worker is already up to date."
  exit 0
fi

echo "==> Bundled web render worker is stale (source changed since last build)."

# The actionable failure used whenever we cannot (or must not) auto-push.
fail_stale() {
  echo "::error::Bundled web render worker is stale. Rebuild it with"
  echo "::error::  dart run dart_pdf_editor:build_web_worker --out $ASSET"
  echo "::error::and commit the result. $*"
  exit 1
}

# Auto-push is only possible on a same-repo pull request (forks get a read-only
# GITHUB_TOKEN; we never auto-commit to main on push events).
if [ "${EVENT_NAME:-}" != "pull_request" ] || [ "${IS_SAME_REPO:-}" != "true" ]; then
  fail_stale "(forks and push events cannot be auto-regenerated.)"
fi

# Without a re-triggering token, a GITHUB_TOKEN push would land a bot commit
# that CI never runs against - a silently unchecked PR head (#422, defect 3).
# A visible failure the author can fix is strictly safer, so refuse to push.
if [ -z "${REGEN_TOKEN:-}" ]; then
  fail_stale "(set the WORKER_REGEN_TOKEN secret to let CI regenerate it automatically.)"
fi

: "${HEAD_REF:?HEAD_REF must be set for a same-repo pull request}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set to push}"
echo "==> Regenerating on PR branch '$HEAD_REF' and pushing"

# Move onto the real head branch (the build ran on the detached merge ref) so
# the commit lands on the PR branch. `-f` discards the merge-ref working tree
# and anything `flutter pub get` touched (e.g. pubspec.lock).
git fetch origin "$HEAD_REF"
git checkout -f -B "$HEAD_REF" "origin/$HEAD_REF"

# Overlay the merged-source build onto the head branch. Committing it to head
# alone is correct: it is byte-identical to what the tree produces once the PR
# merges, so it will not re-stale on merge.
cp "$TMP1" "$ASSET"

if git diff --quiet -- "$ASSET"; then
  echo "==> Head branch copy already matches the merged-source build; nothing to commit."
  exit 0
fi

# Loop guard (#422, defect 2). REGEN_TOKEN re-triggers CI, so a build that is not
# stable across runs (base moved, or a residual nondeterminism the within-run
# check can't see) could push A->B->A forever. If the head we are about to amend
# is ALREADY an auto-regen commit, this would be the second consecutive bot push:
# treat that as genuine cross-run drift and fail loudly instead of looping. A new
# human push resets the head to a non-bot commit and re-arms one auto-regen.
readonly REGEN_SUBJECT="chore(editor): rebuild the bundled web render worker"
if [ "$(git log -1 --format='%s')" = "$REGEN_SUBJECT" ] \
   && git log -1 --format='%ae' | grep -q 'github-actions\[bot\]'; then
  echo "::error::Web render worker bundle is still stale immediately after an"
  echo "::error::automated regeneration - the build is not reproducible across"
  echo "::error::runs (issue #422, defect 2). Refusing to push a second bot"
  echo "::error::commit. Investigate the nondeterminism before relying on auto-regen."
  exit 1
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add "$ASSET"
git commit -m "$REGEN_SUBJECT

Regenerated by CI because a source change left the bundle stale. A textual
merge of two dart2js outputs is meaningless, so CI owns the regeneration.
Pushed with WORKER_REGEN_TOKEN so this commit gets its own CI run.
See issues #411 and #422."

# Push with the dedicated token (not the default GITHUB_TOKEN) so the new head
# re-triggers CI. The script is idempotent - the next run finds the bundle fresh
# and no-ops - and the loop guard above bounds it to one bot commit per push.
git push "https://x-access-token:${REGEN_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" \
  "HEAD:$HEAD_REF"
echo "::notice::Regenerated and pushed the bundled web render worker to $HEAD_REF (CI will re-run on the new head)."
exit 0
