## Summary

<!-- What changed, and why? Keep this focused on behavior and API impact. -->

## Affected packages

<!-- Check every package touched by this PR. -->

- [ ] `pdf_cos`
- [ ] `pdf_document`
- [ ] `pdf_graphics`
- [ ] `dart_pdf_editor`
- [ ] `pdf_test_fixtures`
- [ ] Example app
- [ ] Documentation / CI / repository metadata only

## Change type

- [ ] Bug fix
- [ ] Feature
- [ ] Rendering change
- [ ] Editing behavior change
- [ ] Performance change
- [ ] Refactor / cleanup
- [ ] Tests / fixtures only
- [ ] Documentation only

## Validation

<!-- Check the commands you ran. Leave unchecked if not applicable. -->

- [ ] `fvm flutter pub get`
- [ ] `fvm dart analyze`
- [ ] `cd packages/pdf_cos && fvm dart test`
- [ ] `cd packages/pdf_document && fvm dart test`
- [ ] `cd packages/pdf_graphics && fvm dart test`
- [ ] `cd packages/dart_pdf_editor && fvm flutter test`
- [ ] Ghent corpus test or baseline update
- [ ] Real PDF corpus parse/render smoke test
- [ ] Example app smoke test

If any relevant check was not run, explain why:

## User experience

<!-- For user-facing changes. Leave unchecked when not applicable and explain material omissions. -->

- [ ] The affected user journey and expected outcome are described above.
- [ ] Completion, cancellation, disabled, loading, and error states were considered.
- [ ] Relevant keyboard, mouse, trackpad, touch, stylus, focus, and accessibility paths were checked.
- [ ] Preview, commit, undo/redo, save, and reopen behavior agree where applicable.
- [ ] Any journey-level latency, frame-time, or memory impact was measured or ruled out.

## PDF fixtures and screenshots

<!--
Attach minimal PDFs, screenshots, or before/after images when they help review.
Do not upload private or confidential PDFs. Prefer programmatic fixtures in
tests, or minimized documents that reproduce the behavior.
-->

## Compatibility checklist

- [ ] No `dart:ui` or Flutter imports outside `packages/dart_pdf_editor`.
- [ ] No `dart:io` imports in any `lib/` directory.
- [ ] Layering is preserved: `pdf_cos` <- `pdf_document` <- `pdf_graphics` <- `dart_pdf_editor`.
- [ ] Parsers remain lenient on real-world input and writers remain strict on output.
- [ ] Raw PDF stream bytes stay lazy/raw until decoding is required.
- [ ] Test fixtures use builders/programmatic generation instead of hand-edited byte offsets.

## Notes for reviewers

<!-- Known limitations, intentional baseline changes, migration notes, or follow-up work. -->
