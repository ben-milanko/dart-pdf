# dart-pdf — development session log

Per-session development notes (gotchas, file pointers, design rationale)
accumulated as work lands. The durable project guidance lives in
`CLAUDE.md`; this is reference history. Full history is also in git.

## Why one file per session

These notes used to be appended to a single `doc/dev-log.md`. Every
concurrent branch appended to the same trailing lines, so **every PR
conflicted** on that file. The `.gitattributes` `merge=union` driver
resolves those collisions locally, but GitHub ignores merge drivers when
it computes PR mergeability or merges via the web button — so the PRs
still showed as conflicting.

One file per session sidesteps it entirely: concurrent PRs add *different*
files, so there is nothing to merge. No `merge=union`, no conflicts.

## Convention

- One file per session: `YYYY-MM-DD-short-slug.md`.
- Pick a slug that names the work (`2026-06-22-type0-editor.md`). If two
  sessions land the same day, the slug keeps the names distinct; add
  `-2`, `-3`, … only if the slugs would otherwise collide.
- Lead with an `# Title` line, then the notes. Same content you'd have
  appended to the old log — just in its own file.
- **Never edit another session's file or this README from a feature
  branch** (that reintroduces the conflict). Only add new files.
- Notes written before 2026-06-22 live in the frozen
  [`../dev-log.md`](../dev-log.md) archive.
