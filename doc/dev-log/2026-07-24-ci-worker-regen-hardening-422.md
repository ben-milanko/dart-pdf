# CI web-worker auto-regen: concurrency, re-triggering push, loop guard (#422)

The bundled web render worker (`packages/dart_pdf_editor_assets/assets/web/
pdf_render_worker.dart.js`) is a `dart compile js` output that links most of the
stack, so almost any change to pdf_cos/pdf_document/pdf_graphics/dart_pdf_editor
makes it stale. CI regenerates and pushes it back instead of failing (#411/#412).
That mechanism had three defects that hit 4 of 9 PRs in one session; all three
are addressed here.

## Defect 1 — no concurrency group → double push

Two pushes in quick succession left two `worker-bundle` jobs running at once;
both rebuilt and both pushed, producing bot commits five seconds apart.

Fix: a top-level `concurrency` group in `ci.yml`, keyed by PR number on
`pull_request` and by `github.sha` otherwise, with `cancel-in-progress` **only**
for pull requests. Superseded PR runs are cancelled before they can race to
push; every landed main/deploy commit keeps its own run and record.

## Defect 3 — a GITHUB_TOKEN push leaves the head unchecked (the merge-blocker)

A push made with the default `GITHUB_TOKEN` does not re-trigger workflows (the
GitHub anti-loop rule). So the bot's follow-up commit became the PR head with
**zero checks** — `gh pr checks` reported "no checks reported on the branch",
`mergeable` still read `MERGEABLE`, and a rollup that only counts *failures*
saw it as clean. That is a merge-of-unverified-code hazard, not just friction,
and the only known remedy was closing and reopening the PR.

Fix: push with a dedicated token (`secrets.WORKER_REGEN_TOKEN`, a PAT or GitHub
App token) so the regen commit **does** re-trigger CI. The script is idempotent
— the re-triggered run finds the bundle fresh and no-ops — so this cannot loop
on its own. **If the secret is absent the script does not push at all**; it
fails with the exact `dart run dart_pdf_editor:build_web_worker` command. A
visible, actionable failure is strictly safer than a silently unchecked head,
so we never fall back to the bare-headed GITHUB_TOKEN push.

### Required setup (one-time, by a maintainer)

Auto-regen stays *disabled* (verify-and-fail) until the secret exists:

- Create a token that can push to this repo and trigger Actions — a fine-grained
  PAT with `contents: write` on the repo, or (preferred) a GitHub App installation
  token. A classic PAT with `repo` scope also works.
- Add it as the repo/org Actions secret **`WORKER_REGEN_TOKEN`**.

Until then, worker-affecting PRs fail with the rebuild command instead of being
auto-fixed — the pre-existing behavior for forks, now the default everywhere.

## Defect 2 — cross-run drift / ping-pong, and the loop guard

The within-run reproducibility check (build twice, require byte-match) only
proves determinism *within one runner in one run*. Across runs the output was
observed to differ by 3 bytes (976190 vs 976193), so a re-triggering token could
in principle push A→B→A forever. The comment on that check is corrected to say
what it actually proves.

Loop guard: before committing, if the current head is already an auto-regen bot
commit (`%s` equals the fixed regen subject **and** the author is
`github-actions[bot]`) and the bundle is *still* stale, we refuse the second
consecutive bot push and fail loudly — that is genuine cross-run drift to
investigate, not something to paper over. A new human push resets the head to a
non-bot commit and re-arms exactly one auto-regen. Net: at most one bot commit
per human push, and the head always ends with real checks (a green no-op run, or
a visible failure) — never a silent bare head.

## Not done here

The underlying 3-byte nondeterminism is bounded, not root-caused. If it recurs
after the token lands (visible now as the loud loop-guard failure rather than a
silent ping-pong), the real fix is pinning whatever `dart compile js` output
varies on — runner image, environment, or embedded paths.

Files: `.github/workflows/ci.yml`, `tool/ci/regen_web_worker.sh`.
