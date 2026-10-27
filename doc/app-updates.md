# Desktop update checks

DartPDF offers only a newer release with a published HTTPS artifact matching
the running process ABI and desktop platform. It skips missing, empty, unfinished,
wrong-platform and wrong-architecture assets, drafts and stable-channel prereleases.
The newest eligible release in the fetched GitHub release page wins; an incomplete
newer release does not hide an older eligible upgrade, and nothing offers a downgrade.
The release web page is no longer a fallback download. Network/API failures clear
the offered download and show the existing failed-check state. Each API request
has a 15-second timeout. Availability is based on uploaded release metadata, not
a speculative installer URL or a download of every binary; the installer still
checks the actual HTTP response and expected size before applying it.

The historical macOS DMGs are universal (Apple silicon and Intel). Historical
Windows installers and Linux x86_64 AppImages are x64 only. Explicit arm64/x64
DMGs, Windows installers/archives and Linux aarch64 AppImages are selected by name;
unknown ABIs fail closed. The existing nightly channel keeps its commit identity.

**Skip this version** suppresses that release identity across restarts. It does
not suppress a newer eligible version (or a new nightly commit). Settings keeps
the skipped release visible and installable, with an explanation; **Check now**
refreshes it without silently undoing the skip. **Later** keeps its existing
dismissal semantics. If preference storage is unavailable, suppression lasts
only for the current session, matching the existing graceful fallback.

Web and mobile remain excluded. Flatpak/Snap environment markers, macOS App Store
receipts, and packaged Windows AppxManifest markers disable direct updates. Other
managed distributions can set `--dart-define=PDF_STORE_MANAGED=true`. No packaging,
release, store submission or deployment configuration is changed by this feature.
