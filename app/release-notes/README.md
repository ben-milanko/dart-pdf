# Store release notes

The "What's New" text shipped to the stores, one pair of files per release.

| File | Goes to | Limit |
|---|---|---|
| `<version>-stores.txt` | Play Console (internal track release notes) | **500 chars** |
| `<version>-appstore.txt` | App Store Connect `whatsNew`, iOS **and** macOS | 4000 chars |

Two files because Play's 500-character cap is far tighter than the App
Store's. The short text is a strict subset of the long one, so they never
disagree about what shipped.

## Rules for the text

- **Never name another platform.** App Store review rejected 1.1.0 under
  Guideline 2.3.10 for mentioning Android/Windows/Linux/web. Both files are
  written platform-neutral so the same text is safe everywhere.
- **User-facing, not commit-facing.** Engineering detail belongs in the
  package `CHANGELOG.md` files; this text says only what someone would
  notice using the app.
- Keep the short file under 500 characters — Play rejects longer.

## Applying them

Notes are set *after* the binaries are uploaded, and each store needs its own
call - see [`../RELEASING.md`](../RELEASING.md) and the release tooling in
`app/.secrets/release-tools/` (git-ignored).

- **Play:** the upload helper always re-uploads the bundle, so it cannot add
  notes after the fact (duplicate version code). Use a notes-only edit:
  `edits.insert` → `tracks().get(internal)` → find the release whose
  `versionCodes` contains the code (**they come back as strings**) → set
  `releaseNotes` → `tracks().update` → `commit`.
- **App Store:** an altool upload does *not* create a version record. POST an
  `appStoreVersions` entry per platform (`IOS` and `MAC_OS` separately), then
  PATCH the en-US `appStoreVersionLocalizations` `whatsNew`. This leaves the
  version in `PREPARE_FOR_SUBMISSION` - it does **not** submit for review.
