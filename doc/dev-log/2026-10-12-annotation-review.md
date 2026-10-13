# Adversarial annotation review

Reviewed the grouping and annotation-editing changes against mixed selections,
foreign PDFs, asynchronous clipboard reads, document history branches, draft ink,
and annotation replacement. Addressed the following findings:

- New ink after document undo retained the abandoned document redo branch. Drawing
  now invalidates it immediately, and fully restored strokes resume auto-commit.
  A partial undo/redo remains reversible while its redo strokes are pending.
- Restored draft ink could remain uncommitted, be omitted by Save, and not mark a
  tab dirty. Draft ink now enables Save and close protection; Save flushes ink and
  inline text before capturing its bytes.
- A style-only change to a rotated callout scaled and rotated its leaders again.
  Regeneration now returns geometry to the authored appearance frame, preserves
  leader polylines, expands bounds for the new width, then restores the transform.
- Repeated external PDF paste could fall through to its PNG representation.
  Unchanged PDF clipboard tokens now keep the local vector paste path.
- Readers without clipboard ownership tracking could rasterize app-owned vector
  snapshots or override a newer annotation copy. External image precedence is now
  an explicit host capability; the desktop app enables it and mobile/web retain
  local priority.
- Removing or replacing a group leader left its children pointing to the old
  dictionary. Removal re-parents surviving members; same-page sync replacement
  relinks children to the replacement object.
- Bold/italic toggles treated fallback `/DA` styling as additional visible text,
  so fully styled rich runs could never toggle off. Rich runs now determine their
  own effective formatting; plain boxes continue to use their fallback style.
- Composite-font color/size corrections rejected new characters available in the
  embedded program but absent from the original `/ToUnicode`. These edits now use
  the existing Type0 editor's glyph registration and fallback logic.
- A malformed appearance could allow multi-select rotation to move an annotation
  whose appearance could not rotate. Rotation eligibility now requires usable
  appearance geometry and finite, non-degenerate annotation bounds.
- New native PNG validation exposed an allocation/overflow failure path for
  malformed Windows clipboard dimensions. WIC lengths are checked before
  allocation and allocation failures return no image.

Regression tests reproduce the history, save, vector paste, rich text, group
replacement, composite glyph, and rotation failures. Native Windows CI now
compiles and exercises real PNG/DIBV5 reads, malformed PNG fallback, and clipboard
ownership suppression. Local checks include the full pdf_document suite,
focused editor/app suites, analysis, localization/design checks, and the portable
Windows DIB tests. CI results are recorded on the pull request.
