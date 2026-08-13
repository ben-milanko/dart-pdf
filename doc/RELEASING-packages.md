# Releasing the pub.dev packages

This covers the nine publishable workspace **packages** (`pdf_cos`,
`pdf_test_fixtures`, `pdf_document`, `pdf_graphics`, `dart_pdf_editor`,
`dart_pdf_editor_flutter_gpu`, `dart_pdf_editor_assets`, `pdf_ocr_vlm`,
`pdf_ocr_ondevice`). The eight established packages release in lockstep. The
experimental GPU companion is independently versioned at `0.x` because it has
a newer Flutter requirement and a deliberately evolving API. The standalone
**app** ships separately - see
[`app/RELEASING.md`](../app/RELEASING.md).

The established packages are released **in lockstep** at one version; bump the
GPU companion only when it has changes. Cutting a release is:

1. Bump `version:` in every package's `pubspec.yaml` to the new `X.Y.Z`.
2. Roll each `## Unreleased` changelog section into `## X.Y.Z` (add a
   version-bump line for packages with no unreleased entries).
3. Update inter-package lower bounds to the new version (`pdf_document: ^X.Y.Z`).
   Run `dart pub upgrade --tighten` or edit by hand, then verify with
   `dart run tool/check_lockstep_constraints.dart` (CI enforces this - see
   [Lockstep invariant](#lockstep-invariant)).
4. `flutter pub get` + `dart analyze --fatal-infos` at the root.
5. Publish (below), then tag `<pkg>-v<version>` for each package.

## Publishing

There are two paths. The **automated** path is preferred once the one-time
setup below is in place; the **manual** path is the always-works fallback and
is how 1.1.0–1.2.3 actually shipped.

### Automated (tag-driven OIDC) - preferred

Push the version bumps to `main`, then merge `main` into `deploy` and push it.
`release-pub-tags.yml` runs the test suite, then for each package whose version
isn't yet on pub.dev it pushes a `<pkg>-v<version>` tag. Each tag triggers
`publish-pub.yml`, which publishes that package via pub.dev OIDC (tokenless).
The `dart_pdf_editor_assets` job first generates the real bundled web worker
over the committed placeholder, mirroring `tool/release.sh`, and force-publishes
that prepared archive.
If a deploy push contains no unpublished package versions, the workflow exits
without probing the tag token or running the release suite.

This needs **two one-time configurations**. Both are maintainer-only; CI cannot
self-configure them.

#### 1. Enable automated publishing on pub.dev (per package)

For **each** of the nine packages, on pub.dev → the package → **Admin** tab →
**Automated publishing**:

- Enable **Publishing from GitHub Actions**.
- **Repository:** `ben-milanko/dart-pdf`.
- **Tag pattern:** `<pkg>-v{{version}}` - e.g. `pdf_cos-v{{version}}`,
  `dart_pdf_editor-v{{version}}`. The pattern is per-package because the tags
  are namespaced.
- Leave the **Require GitHub Actions environment** field consistent with the
  workflow. `publish-pub.yml` runs each job with `environment: pub.dev`, so set
  this to `pub.dev` (and create a repo Environment named `pub.dev`), or clear
  both to keep them aligned.

Symptom when missing: the publish job fails with
`The calling GitHub Action is not allowed to publish, because: publishing from
github is not enabled`.

#### 2. Provision the tag-push PAT

`release-pub-tags.yml` pushes tags with a **fine-grained PAT**, not the default
`GITHUB_TOKEN` - tags created by `GITHUB_TOKEN` do **not** trigger
`publish-pub.yml` (GitHub suppresses workflow-on-workflow events).

- Create a fine-grained PAT scoped to `ben-milanko/dart-pdf` with
  **Contents: Read and write**.
- Store it as the repo secret **`PUB_RELEASE_TAG_TOKEN`**.
- Re-create it before it expires. The workflow now preflights the token and
  fails in seconds with a clear message if it's empty or can't push (403),
  instead of after the full test suite.
- To test only the GitHub-side token setup, run **Tag pub.dev releases** from
  GitHub Actions with `setup_check_only=true`. That pushes and deletes a
  throwaway non-release tag and then exits before analysis, tests, or publish.

The tag token is intentionally isolated from repository code. The release
workflow plans and tests in jobs without `PUB_RELEASE_TAG_TOKEN`, then creates
tags in a separate job that does not check out or execute the repo.

The repository also has an active **release tags** ruleset covering every
`<pkg>-v*` tag and `app-v*`: creation, update, and deletion are restricted to
ruleset bypass actors. Keep that ruleset in place before adding or rotating
`PUB_RELEASE_TAG_TOKEN`.

> Note: GitHub does **not** trigger `push` workflows when more than three tags
> are pushed at once. `release-pub-tags.yml` pushes one tag at a time (waiting
> for each to appear on pub.dev), so it's unaffected - but if you ever tag by
> hand, push in batches of ≤3.

### Manual (`tool/release.sh`) - fallback

Always works; needs a pub.dev login on the machine.

```bash
fvm dart pub login                 # once, OAuth in a browser
tool/release.sh                    # dry-run every package (no publishing)
tool/release.sh --publish --yes    # publish all 9 in dependency order
```

The script publishes dependencies first and waits for each version to be
visible on pub.dev before the next (so `^X.Y.Z` inter-package constraints
resolve). Afterwards, push the tags for the record:

```bash
for p in pdf_cos pdf_test_fixtures pdf_document pdf_graphics \
         dart_pdf_editor dart_pdf_editor_flutter_gpu \
         dart_pdf_editor_assets pdf_ocr_vlm \
         pdf_ocr_ondevice; do
  git tag -a "$p-v<version>" -m "Release $p <version>"
done
git push origin --tags        # or in batches of <=3 if any are unpushed
```

`publish-pub.yml` checks pub.dev before calling the reusable publish workflow.
If a tag points at a version that is already hosted, the workflow exits
successfully as a no-op instead of trying to republish the immutable version.

## Lockstep invariant

Because the packages release together and call each other's newest APIs, every
**runtime** inter-package dependency must pin its lower bound to the current
release version (`pdf_document: ^X.Y.Z`, not `^X.Y.0`). A stale lower bound
makes pub.dev's "compatible with dependency constraint lower bounds" downgrade
analysis fail (0/20): it resolves the sibling to its minimum and the new APIs
don't exist there.

`dart run tool/check_lockstep_constraints.dart` enforces this and runs in
`ci.yml` (every push/PR) and `release-pub-tags.yml` (before publishing).
`dev_dependencies` are intentionally exempt - they don't reach consumers, aren't
part of downgrade analysis, and pinning them would create a publish-ordering
cycle (`pdf_cos` dev-depends on `pdf_test_fixtures`, which depends on `pdf_cos`).

## Troubleshooting

| Symptom                                 | Cause                                                      | Fix                                                                                                                 |
| --------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `publishing from github is not enabled` | pub.dev automated publishing off for that package          | [Setup 1](#1-enable-automated-publishing-on-pubdev-per-package)                                                     |
| Tag push step `403 denied`              | `PUB_RELEASE_TAG_TOKEN` expired / missing Contents:write   | [Setup 2](#2-provision-the-tag-push-pat)                                                                            |
| Tag pushed but never publishes          | `publish-pub.yml` job missing for the package, or OIDC off | confirm a job + trigger exist in `publish-pub.yml`; [Setup 1](#1-enable-automated-publishing-on-pubdev-per-package) |
| `…-v…` not visible after 10 min         | publish failed upstream                                    | open the package's "Publish to pub.dev" run                                                                         |
| 0/20 lower-bounds score                 | stale inter-package lower bound                            | `dart pub upgrade --tighten`; the lockstep check catches it                                                         |
