# Nightly tickets in What's new

A nightly build's What's new dialog now lists the tickets merged since the last
published release, above the bundled changelog. Before this the list only
existed in the `app-nightly` GitHub release body (#1131), which the update
checker downloaded but never showed.

- `app/lib/whats_new.dart`: `parseNightlyTickets` reads the
  `## Tickets since [DartPDF x.y.z](...)` section written by
  `.github/scripts/nightly-release-tickets.py` (bullets
  `- title ([#N](url))`, `\[`/`\]` unescaped) plus the `<!-- main-sha -->`
  marker. `fetchNightlyReleaseNotes` GETs the rolling release from the GitHub
  API. `showWhatsNew(nightlyNotes:)` is the seam; it defaults to the fetcher
  only when `AppInfo.isNightly`.
- The format is a contract with the Python script: change one, change the
  other. A "different histories" note (no bullets, no "No new merged tickets")
  parses as null and shows the unavailable line, never "no tickets".
- The rolling release is always the newest nightly, so when its `main-sha`
  doesn't match `AppInfo.buildCommit` the section says it is from a newer
  nightly; when it matches it gets the Installed badge.
- Offline / HTTP errors only replace the nightly section; the changelog still
  renders.
