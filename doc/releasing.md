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

## Attach retained Android assets to a draft app release

Use **Publish retained Android release assets** when the native AAB and portable
APK already exist as retained CI artifacts. This workflow verifies and uploads
`app-release.aab` and the already-signed `app-release.apk`. It does not rebuild,
load signing keys, write to stores, create tags, or publish the draft release.
The repository, application ID, signing certificate and archive member names
remain fixed in the publisher.

Dispatch requires `manifest_json` and `manifest_sha256`. The digest is lowercase
SHA-256 of the exact UTF-8 JSON string, including any whitespace. The script reads
these fields from `GITHUB_EVENT_PATH`; inputs never enter a shell command or URL.
Only an explicit `workflow_dispatch` is accepted. There is no default manifest,
URL download, asset indirection, or fallback to the old release.

### Manifest schema version 1

Every field below is required. Unknown fields and duplicate JSON keys fail.

| Field | JSON type and constraint | Verification |
|---|---|---|
| `schema_version` | integer, exactly `1` | Reject unsupported versions |
| `source` | string, 40 lowercase hex characters | Exact draft `target_commitish`, both CI artifacts' run head SHA, native ledger source |
| `version` | string, `major.minor.patch`, decimal components without leading zeroes | Native ledger `version` must equal `version+build`; APK versionName |
| `build` | integer, 1 through 2100000000 | Native ledger version suffix; APK versionCode |
| `tag` | string, exactly `app-v` followed by `version` | Exact existing draft tag |
| `release_id` | positive integer | Exact existing draft release ID, checked before and after each upload |
| `native_run` | positive integer | Native artifact workflow run ID |
| `native_artifact` | positive integer | Native artifact ID, not expired |
| `native_digest` | string, 64 lowercase hex characters | Native artifact metadata SHA-256 and downloaded ZIP SHA-256 |
| `native_ledger_id` | string, 24 lowercase hex characters | Exact ledger and AAB member paths below |
| `portable_run` | positive integer | Portable artifact workflow run ID |
| `portable_artifact` | positive integer | Portable artifact ID, not expired |
| `portable_digest` | string, 64 lowercase hex characters | Portable artifact metadata SHA-256 and downloaded ZIP SHA-256 |
| `aab_sha` | string, 64 lowercase hex characters | Native ledger AAB digest and retained AAB bytes |
| `apk_sha` | string, 64 lowercase hex characters | Retained portable unsigned APK bytes |
| `signed_apk_sha` | string, 64 lowercase hex characters | Signed APK bytes inside transfer ZIP |
| `transfer_sha` | string, 64 lowercase hex characters | Draft transfer asset metadata SHA-256 and downloaded ZIP SHA-256 |

All integers must be JSON integers, not strings, floats or booleans, and at most
9007199254740991. The manifest must fit in 16384 UTF-8 bytes. Digests omit the
`sha256:` prefix.

The native ZIP must contain
`app/.storeflight/releases/<native_ledger_id>.json` and
`app/.storeflight/artifacts/<native_ledger_id>/android/app-release.aab`.
The ledger must record `build.android` as `succeeded`. The portable ZIP member
is `flutter-apk/app-release.apk`. Upload the externally signed APK beforehand as
the sole `app-release.apk` member of `android-signed-apk-transfer.zip` on the same
draft. The publisher checks the pinned production certificate, application and
version identity, and byte-identical APK payload members apart from signatures.
Conflicting existing release assets are preserved and stop publication; matching
assets are reused. Review the retained publication report after completion.

### Dispatch example

These are the historical 16.1.1+55 bindings, shown as a complete schema example.
Do not reuse them for a new release. Obtain each new ID and digest from the
retained artifacts, native ledger and source-bound draft; prepare and review the
manifest before dispatch. A new release needs no changes to the publisher code.

```json
{
  "schema_version": 1,
  "source": "36a14db31bf2483378e5fde3591a46899146cd21",
  "version": "16.1.1",
  "build": 55,
  "tag": "app-v16.1.1",
  "release_id": 446767344,
  "native_run": 43788575735,
  "native_artifact": 14191637652,
  "native_digest": "c24cb64ad70181312c38bd6bfcb3a9cec4e2e9cf5864f0e39f3755973dd1e5c2",
  "native_ledger_id": "20cbec6556de4f5be5463123",
  "portable_run": 43792481026,
  "portable_artifact": 14192658425,
  "portable_digest": "941a68ec2cc6de330d7293a895829c3159cdc217dd4bc13c6b33ea678c374b21",
  "aab_sha": "f7553f036ca8aed7ddbebd35d3a3e150f2d3a4a33b87cf3c6b77345a07231d0d",
  "apk_sha": "7a37f2b3d772ebb6913bd7cbc7cfda075e0ddbf2210bdb2e223481963b4586b6",
  "signed_apk_sha": "30211dc7815dc28579e9ed2314092a4c1f5a3f62d2b9997309ac1c911a371c0b",
  "transfer_sha": "74c694df22c1bc7fce9ad58243484ece0095e7bcc7be2c61dad45a9db2b48320"
}
```

Save the reviewed manifest as `manifest.json`. This command builds the dispatch
payload without shell interpolation of manifest values and sends it to the
workflow on `main`:

```sh
python3 - <<'PY' | gh workflow run publish-retained-android-assets.yml --repo ben-milanko/dart-pdf --ref main --json
import hashlib, json
from pathlib import Path
raw = Path('manifest.json').read_bytes()
print(json.dumps({'manifest_json': raw.decode('utf-8'),
                  'manifest_sha256': hashlib.sha256(raw).hexdigest()}))
PY
```

Run the offline boundary suite before changing this workflow:

```sh
python3 -m unittest discover -s .github/scripts -p 'test_retained_android_assets.py'
```
