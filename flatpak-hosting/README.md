# DartPDF Flatpak repository hosting

The official DartPDF Flatpak remote is hosted independently of the marketing
site at <https://dartpdf-flatpak.web.app>. Keeping it on its own Firebase
Hosting site prevents an ordinary `site/` deployment from deleting OSTree
objects.

`.github/workflows/publish-flatpak.yml` publishes the repository whenever an
`app-v*` GitHub Release becomes public. It can also be dispatched manually for
an already-published version. The workflow:

1. downloads and digest-verifies `dartpdf-linux-x64.tar.gz` from the release;
2. builds the Flatpak from `app/packaging/flatpak/`;
3. signs the app commit and repository summary with the dedicated Flatpak key;
4. installs and smoke-tests the result from a local signed remote; and
5. deploys this Firebase Hosting site; and
6. performs a clean install from the public `.flatpakref`, verifying the
   `stable` branch and published version.

Generated output lives in `flatpak-hosting/public/` and is intentionally not
committed. The public signing key and fingerprint are committed under
`app/packaging/flatpak/`; the private key is stored in the GitHub Actions secret
`FLATPAK_GPG_PRIVATE_KEY`. Ben's backup is in the macOS login keychain under
service `dartpdf-flatpak-gpg-private-key`, with a second ignored backup at
`app/.secrets/flatpak-signing-key.asc`.

Install from the hosted repository:

```sh
flatpak install --from \
  https://dartpdf-flatpak.web.app/dartpdf.flatpakref
```

To republish the latest release, run **Publish Flatpak repository** from GitHub
Actions with the version field empty. To publish a specific existing release,
enter its `X.Y.Z` version.
