# Annotation panel filter (type / author)

The annotations panel (`PdfAnnotationSidebar`, `editing_sidebar.dart`) gained
a filter (funnel) button beside the search field. Its `MenuAnchor` lists a
`CheckboxMenuButton` per annotation type and per author present in the
document, plus "Clear filters".

- Each axis is an OR over its checked values; the two axes AND together and
  with the search text (`_passesFilter` runs first in `_matches`). An axis
  with nothing checked doesn't filter.
- Type key is `/Subtype`, except every form-field widget folds into one
  `'Widget'` entry (`_typeKey`) - the tile titles split widgets by /FT, but
  one "Form field" entry is what a reviewer wants to hide.
- Author is /T for markup only (`_authorOf`): on widgets /T is the field
  name, and links have none. An author filter therefore hides widgets,
  links and unattributed markup.
- The offered values come from the unfiltered pass over the document, so
  narrowing never removes the entries you'd uncheck. A checked value that no
  longer occurs (its last annotation was deleted) stays listed for the same
  reason.
- Filters live in widget state like the search text: they survive revisions
  (undo/redo/edits), not a remount.
- Checkbox entries use `closeOnActivate: false` so several can be toggled in
  one visit; "Clear filters" closes the menu.
- Tests: `group('filter')` in `test/editing_sidebar_test.dart`. Note the
  `CheckboxMenuButton`'s key is forwarded to its inner `MenuItemButton`, so
  `find.byKey` matches twice - the tests match on the checkbox type.
- The extra 36px button narrows the search field; the panel's 200px minimum
  width already overflowed the header row by 12px before this change.
