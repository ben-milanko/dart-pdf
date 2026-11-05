# One-off 15.0.0 Android draft upload recovery

Operational branch: `release/15-large-upload-recovery`, based on frozen source
`39935aa10ee9898444d0d2b099a5878749bac3d0`. Do not merge this workflow into the
default branch or move/create a tag. The release owner reviews this staged tree,
then commits and pushes the operational branch normally, and manually dispatches
the already registered workflow:

```sh
gh workflow run release-app.yml --repo ben-milanko/dart-pdf --ref release/15-large-upload-recovery
```

This replaces only the operational branch's `release-app.yml` with a
`workflow_dispatch`-only job on `ubuntu-latest`. It uses the existing job token
(`contents: write`, `actions: read`), not newly created credentials.

The frozen manifest records Android artifact 13393379014 from original successful
run 41979983927, its archive digest, the two exact archive paths and file hashes,
and all nine existing asset IDs/sizes/digests from
`reports/dartpdf-release-2026-11-05/github15-large-upload-incident.json` in the
operator workspace. Artifact metadata comes from the retained
`/home/ben/dartpdf-artifacts-15.0.0/artifact-inventory.json`; file paths, sizes and
hashes also match its `file-manifest.json` and original `transport/android.zip`.

The helper checks source/run provenance, downloads that exact artifact archive,
verifies the ZIP digest and both retained files, then reconciles exact draft
435075074 (`app-v15.0.0`, title `DartPDF 15.0.0+52`, target frozen source).
It uploads only absent APK/AAB assets, serially with `gh release upload` and no
clobber. Partial, unknown, duplicate or mismatched assets stop the run. Already
verified APK/AAB assets are skipped on a fresh manual dispatch. A failed or
ambiguous upload is never automatically retried.

Each upload has a fresh draft/asset read and independent readback. Final success
requires exactly eleven complete assets with expected sizes/digests and the
original nine IDs unchanged. The JSON log records final IDs/hashes. No build,
store operation, release publication or tag creation is performed; the release
stays draft. The release owner still owns the separate publication decision.

Offline checks (no provider calls):

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s .github/recovery -p 'test_*.py' -v
git diff --check
```
