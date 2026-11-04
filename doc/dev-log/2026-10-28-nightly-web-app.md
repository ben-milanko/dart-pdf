# Nightly web app at app-nightly.dart-pdf.com

- `.github/workflows/deploy-app-web-nightly.yml`: nightly (16:20 UTC, same slot
  as nightly-desktop.yml) web build from `main` with
  `PDF_BUILD_CHANNEL=nightly`, deployed to the `dartpdf-app-nightly` Firebase
  site. It reuses `app/firebase.json` and rewrites `.hosting.site` with `jq` at
  deploy time instead of keeping a second config, so header/COOP/COEP changes
  can't drift between the two sites. It also adds `X-Robots-Tag: noindex` and a
  `robots.txt` so the nightly doesn't compete with app.dart-pdf.com in search.
- Change gate: each deploy publishes `build-commit.txt` (uncached); the next run
  curls it and skips when it equals `main`'s HEAD. Don't move this check to
  `nightly-desktop.yml`'s release-body marker: the desktop and web nightlies
  fail independently, and a desktop success would hide a failed web deploy.
- Branding happens in the runner only: the nightly `Icon-512.png`, manifest
  `name`/`short_name`, and the `<title>`/apple title in `web/index.html`.
- `app/lib/web_channel.dart`: `WebChannelSwitchTile` (Settings → System, web
  only) opens the other channel's site in a **new tab**. Navigating the current
  tab would leave its open documents behind on an origin the new site can't
  read (IndexedDB, recents, the unsaved-changes mirror are all per origin).
- One-time setup outside the repo: create the `dartpdf-app-nightly` site and
  add the `app-nightly.dart-pdf.com` custom domain + DNS records. The deploy
  fails until the site exists.
