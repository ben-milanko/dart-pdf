# Releasing to pub.dev

Merges to the `deploy` branch run the pub release workflow:

1. Run the normal analysis and package tests.
2. Read each package version from its `pubspec.yaml`.
3. Skip versions already visible on pub.dev.
4. Push one release tag per unpublished package, in dependency order.
5. Let the tag-triggered `Publish to pub.dev` workflow publish each package.

The release tag format is:

| Package | pub.dev tag pattern |
|---|---|
| `pdf_cos` | `pdf_cos-v{{version}}` |
| `pdf_test_fixtures` | `pdf_test_fixtures-v{{version}}` |
| `pdf_document` | `pdf_document-v{{version}}` |
| `pdf_graphics` | `pdf_graphics-v{{version}}` |
| `dart_pdf_editor` | `dart_pdf_editor-v{{version}}` |
| `dart_pdf_editor_flutter_gpu` | `dart_pdf_editor_flutter_gpu-v{{version}}` |
| `dart_pdf_editor_assets` | `dart_pdf_editor_assets-v{{version}}` |
| `pdf_ocr_vlm` | `pdf_ocr_vlm-v{{version}}` |
| `pdf_ocr_ondevice` | `pdf_ocr_ondevice-v{{version}}` |

Configure each package's pub.dev Admin page with repository
`ben-milanko/dart-pdf`, its package-specific tag pattern above, and the
GitHub Actions environment `pub.dev`.

The `Tag pub.dev releases` workflow needs a repository secret named
`PUB_RELEASE_TAG_TOKEN`. Use a fine-grained token or GitHub App token that can
push tags to this repository. The built-in `GITHUB_TOKEN` is intentionally not
used for tag creation because GitHub does not trigger a second workflow from
pushes made with `GITHUB_TOKEN`.

To validate the GitHub-side setup without running the release tests or pushing
tags, run **Tag pub.dev releases** manually with `setup_check_only=true`. That
mode still probes `PUB_RELEASE_TAG_TOKEN` by pushing and deleting a throwaway
non-release tag.

Keep the repository's **release tags** ruleset active for every package
`<pkg>-v*` tag and `app-v*`. The tag token is only exposed in jobs that do not
check out or execute repository code.

The tag-triggered publish workflow first checks whether the tagged version is
already on pub.dev. If it is, the workflow exits successfully without calling
`dart pub publish`, so record tags can be pushed after a manual recovery
release without creating failed publish jobs.
