# 2026-07-22 — Dividers for large context menus

The annotation and form-field context menus (`editing_menu.dart`) had
grown long enough to read as one undifferentiated column: on a plain
rectangle the annotation menu is copy / cut / apply-to-pages / paste /
bring-to-front / send-to-back / delete, and a polygon or a pasted vector
snapshot adds node editing and recolour on top of that. Nothing ruled the
clusters apart, so users scanned the whole list every time.

## What changed

Both stock menus now build their entries as **groups** and hand them to a
shared `_menuRowsWithDividers(List<List<PdfAnnotationMenuItem>>)`, which:

- drops empty groups, and
- inserts a single `PopupMenuDivider` between the groups that survive.

Annotation menu groups, in order: **clipboard** (copy/cut/apply-to-pages/
paste) · **arrange** (bring-to-front/send-to-back) · **nodes** (add/remove
vertex) · **recolour** · **delete** · then the host's `customActions`.
Form-field menu groups: **edit** (edit value + text style) · **structure**
(rename + convert-to-{text,checkbox,button}) · **destructive**
(delete-field + flatten-form).

Because empty groups draw no divider, a small menu still reads tight:

- a **paste-only** menu (empty-area right-click with a clipboard) is one
  group → **no** dividers;
- a **plain rectangle** is clipboard | arrange | delete → **two** dividers;
- a **text form field** is edit | structure | destructive → **two**.

The host `customActions` divider that already existed falls out of the same
mechanism (custom is just the last non-empty group), so
`PdfAnnotationMenuBuilder`'s "divider before the custom ones" contract is
unchanged — it's now one code path instead of a special case.

## Tests

`editing_menu_test.dart` gained divider-count assertions for the plain
rectangle, the paste-only menu, and (via a direct `showPdfFormFieldMenu`
pump) a text form field. The existing "host actions ride below a divider"
test was updated from `findsOneWidget` to the grouped count. No menu-item
keys moved, so the longpress / clipboard / iPad / form suites were
unaffected.
