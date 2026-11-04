# Nightly What's new follows the latest release

A nightly's bundled `app/CHANGELOG.md` is frozen at the commit it was built
from, so an older nightly showed release notes as of its own build - missing
any release published since - even though its ticket list (fetched from the
rolling `app-nightly` release) already counted from the latest release.

- `app/lib/whats_new.dart`: `fetchLatestReleaseChangelog` reads GitHub's
  `releases/latest` (drafts and prereleases, the nightly among them, excluded -
  the same endpoint `nightly-desktop.yml` uses for the ticket base) and fetches
  `app/CHANGELOG.md` at that tag from raw.githubusercontent.com.
  `showWhatsNew(releaseChangelog:)` is the seam; it defaults to the fetcher
  only when `AppInfo.isNightly`. A failed fetch or an empty parse falls back
  to the bundled changelog.
- A nightly no longer puts the Installed badge on a release section: it shares
  a package version with a release but is not that release. The nightly ticket
  section keeps its own Installed / "from a newer nightly" marker.
