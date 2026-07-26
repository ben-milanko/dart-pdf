# Changelog

## 3.1.1

- Lockstep patch release to align the dart-pdf package suite at 3.1.1. No
  fixture API changes since 3.1.0.

## 3.1.0

- Add a scanned-book fixture profile with shared /JBIG2Globals across pages,
  exercising the JBIG2 globals cache and concurrent image decode paths (#557).

## 3.0.0

- Lockstep major release to align with `dart_pdf_editor` 3.0.0. No public API
  changes since 2.1.0.

## 2.1.0

- Add an image-heavy wide CAD sheet fixture in two profiles, for exercising
  extreme-aspect page handling and region-replay culling (#419).
- Add a dense-page fixture profile used by the region-replay grid tests (#383).

## 2.0.0

- Major version bump to keep the dart-pdf package suite aligned at 2.0.0.
- Add an in-process fake Fulcio authority (`test_fulcio.dart`) that verifies
  the proof of possession and issues a short-lived certificate from a test CA,
  for exercising Sigstore/Fulcio keyless signing without a network (#322).

## 1.4.7

- Version bump to keep the dart-pdf package suite aligned at 1.4.7. No fixture
  changes since 1.4.6.

## 1.4.6

- Add a positioned-tashkil Arabic fixture that mirrors Skia's output shape
  (each zero-advance mark painted as its own run before its base glyph), for
  extraction and selection ordering tests.

## 1.4.5

- Add reusable right-to-left text fixtures for Arabic extraction, selection,
  and copy-order regression tests.

## 1.4.4

- Version bump to keep the dart-pdf package suite aligned at 1.4.4. No fixture
  API changes since 1.4.3.

## 1.4.3

- Version bump to keep the dart-pdf package suite aligned at 1.4.3. No fixture
  API changes since 1.4.2.

## 1.4.2

- Version bump to keep the dart-pdf package suite aligned at 1.4.2. No fixture
  API changes since 1.4.1.

## 1.4.1

- Add fixtures for callout annotations, rich content editing, retained page
  rendering, and the expanded viewer/editor regression suite.

## 1.4.0

- Version bump to keep the dart-pdf package suite aligned at 1.4.0. Fixture
  updates support the new color-processing, bookmark, annotation, and app
  workflow tests.

## 1.3.2

- Version bump to keep the dart-pdf package suite aligned at 1.3.2. No
  fixture changes since 1.3.1.

## 1.3.1

- Version bump to keep the dart-pdf package suite aligned at 1.3.1. No
  fixture changes since 1.2.3.

## 1.2.3

- Version bump to keep the dart-pdf package suite aligned at 1.2.3. No
  fixture changes since 1.2.2.

## 1.2.2

- Version bump to keep the dart-pdf package suite aligned at 1.2.2. No
  fixture changes since 1.2.1.

## 1.2.1

- Add a package example for pub.dev scoring.

## 1.2.0

- Version bump to keep the dart-pdf package suite aligned at 1.2.0. No
  fixture changes since 1.1.0.

## 1.1.0

- Version bump to keep the dart-pdf package suite aligned at 1.1.0. No
  fixture changes since 1.0.0.

## 1.0.0

First stable release. Adds fixtures exercising TrueType `post`-table
glyph-name selection (fonts with no usable cmap).

## 0.1.0

Initial release: programmatic builders for structurally-correct PDF test
files. Classic and xref-stream layouts, multi-page and varied-height
documents, annotations, AcroForm fields, encrypted documents, and a test
signer identity.
