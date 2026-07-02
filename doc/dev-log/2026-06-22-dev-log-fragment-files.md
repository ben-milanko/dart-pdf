# Dev-log fragment files: end the per-PR conflict on doc/dev-log.md

Every open PR was showing `CONFLICTING` on `doc/dev-log.md`. Diagnosis:
both `main` and each branch append to the end of the file, so a default
3-way merge collides on the trailing lines. PR #154 added
`doc/dev-log.md merge=union` (and `**/CHANGELOG.md merge=union`) to
`.gitattributes`, and that *does* resolve it — but only for local CLI
merges. GitHub does not run `.gitattributes` merge drivers (not even the
built-in `union`) when computing PR mergeability or merging via the web
button, so the PRs still showed conflicts.

Verified against PR #160 / current `origin/main`: with the union driver
active the merge is exit 0 and clean; with it disabled (GitHub's
behavior) the *only* conflict is `doc/dev-log.md`. The code merged fine.

Fix: stop appending to a single shared file. `doc/dev-log.md` is now a
frozen archive (all pre-2026-06-22 notes); new session notes go in one
file per session under `doc/dev-log/` (`YYYY-MM-DD-slug.md`). Concurrent
PRs add distinct files, so there is nothing to merge — no driver needed.
See `doc/dev-log/README.md` for the convention; CLAUDE.md's "Development
session log" section points here.

Left the `merge=union` rules in `.gitattributes` — harmless, still helps
local merges of the frozen archive and CHANGELOGs.

Transition note: the ~12 in-flight PRs that still append to the frozen
`doc/dev-log.md` keep their pre-existing conflict (resolve trivially by
keeping both sides, or merge locally where union handles it). PRs created
after this lands won't touch the file at all.
