# Contributing to dart-pdf

Thanks for your interest in contributing! This is a pure-Dart PDF renderer
and editor, structured as a [pub workspace](https://dart.dev/tools/pub/workspaces)
of several packages. A few things about the setup are not obvious from the
code, so please skim this before opening a PR.

## Project layout

The workspace lives at the repo root (`pubspec.yaml` lists the members)
and is split into layered packages:

```
pdf_cos  ←  pdf_document  ←  pdf_graphics  ←  dart_pdf_editor
```

- `pdf_cos` is the COS object model: tokenizer, parser, filters, xref,
  encryption, serializer. Knows nothing about pages or rendering.
- `pdf_document` covers document semantics: page tree, annotations, forms,
  signatures, and the incremental-save editor.
- `pdf_graphics` is the content-stream interpreter, font engine,
  shadings, ICC colour, and text extraction, rendering to an abstract
  `PdfDevice`.
- `dart_pdf_editor` contains the Flutter viewer/editor widgets and the
  Flutter canvas device.
- `pdf_test_fixtures` provides programmatic builders for test PDFs.

### Layering rules (strict)

- `dart:ui` and Flutter imports are allowed **only** in `dart_pdf_editor`.
  Everything else must run on the Dart VM (CLI/server/tests) and on the
  web.
- `dart:io` is not allowed anywhere in `lib/` (web support); use
  `package:archive` for compression.
- Dependencies only flow left-to-right in the diagram above. A lower
  layer must never import a higher one.

### Versioning (lockstep)

The workspace packages are released together at one version. Whenever a
package depends on a sibling, pin the lower bound to that sibling's
**current** version (`pdf_document: ^1.2.3`, not `^1.2.0`). A stale lower
bound makes pub.dev's downgrade analysis fail (0/20 on "compatible with
dependency constraint lower bounds"), because it resolves the sibling to
its minimum and the new APIs don't exist there. CI enforces this via
`dart run tool/check_lockstep_constraints.dart`; bump every inter-package
constraint when you bump versions (or run `dart pub upgrade --tighten`).

## Setup

Flutter is pinned with [fvm](https://fvm.app) (see `.fvmrc`, currently
**3.47.0**). Use `fvm flutter` / `fvm dart`, or the binaries under
`~/fvm/versions/3.47.0/bin/`.

```bash
fvm install            # once, installs the pinned Flutter
fvm flutter pub get    # at the repo root, resolves every workspace package
```

## Running checks

Mirror what CI runs (`.github/workflows/ci.yml`):

```bash
# Format only the files you changed. This wrapper pins the workspace language
# version even before pub get has generated a package config.
fvm dart tool/format.dart path/to/changed_file.dart [...]

# Static analysis (whole workspace, from the repo root)
fvm dart analyze --fatal-infos

# Pure-Dart packages
cd packages/pdf_cos      && fvm dart test
cd packages/pdf_document && fvm dart test
cd packages/pdf_graphics && fvm dart test

# Flutter package
cd packages/dart_pdf_editor && fvm flutter test
```

Use `tool/format.dart` rather than calling `dart format` directly. In a fresh
worktree, the generated package config does not exist yet; the bare SDK command
then assumes its latest language version and can rewrite the Dart 3.5 codebase
into a different formatting style. The wrapper reads the workspace SDK lower
bound from the root `pubspec.yaml` and passes it explicitly.

`dart analyze` must be clean with `--fatal-infos`; CI fails on any info,
warning, or error.

## Test corpora

There are two kinds of corpus. Both are described in detail in `CLAUDE.md`.

- `corpus/` is git-ignored and holds real-world PDFs kept locally. Not needed
  to contribute; it's a personal validation set.
- **`test_corpora/ghent/`** and **`test_corpora/pdfjs/`** are checked in
  (Ghent Output Suite V5.0 and a curated slice of mozilla/pdf.js). Their
  tests have two layers each: a pure-Dart "interprets without throwing"
  pass in `pdf_graphics`, and a rasterize-and-diff-against-baselines pass
  in `dart_pdf_editor`.

If a change intentionally alters rendering, regenerate the affected
baselines and call it out in your PR:

```bash
# Accept intentional Ghent rendering changes
cd packages/dart_pdf_editor && GHENT_UPDATE=1 fvm flutter test test/ghent_render_test.dart
```

A handful of Ghent render-baseline tests can fail locally due to
machine-specific rasterisation differences; if you see baseline diffs,
confirm they're caused by your change (e.g. by stashing it) before
committing new baselines.

## Conventions

- Parsers are **lenient on input** (real-world PDFs are broken) and
  **strict on output**.
- Test fixtures are built programmatically (`test/fixtures.dart` /
  `pdf_test_fixtures`) so byte offsets are always correct. Don't hand-edit
  offsets.
- Match the style, naming, and comment density of the surrounding code.
- Add or update tests for any behaviour change. New parser edge cases
  should come with an inline fixture and a regression test.

### User-facing changes

The [UX vision](doc/ux-vision.md) is the product-quality bar for viewer,
editor, shell, and app work. Describe the user journey being improved, check
the relevant input modes and accessibility states, and validate the committed
and reopened PDF rather than stopping at the live preview. Performance work
should measure the complete journey and report tail latency, not just an
isolated subsystem average.

## Pull requests

1. Branch off `main`.
2. Keep changes focused; one logical change per PR.
3. Make sure `dart analyze --fatal-infos` and the relevant test suites
   pass, and mention any intentional baseline updates.
4. Fill in the PR template.

## Reporting bugs and security issues

- Functional bugs and rendering glitches: open an issue using the
  appropriate template (there's a dedicated **rendering bug** template).
- Security vulnerabilities: **do not** open a public issue. See
  [`SECURITY.md`](SECURITY.md).

## License

By contributing, you agree that your contributions will be licensed under
the project's [Apache-2.0 License](LICENSE).
