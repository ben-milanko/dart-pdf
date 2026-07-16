# Vector snapshot recolour on the context menu

The Snapshot tool captures a page region as detached **vector** graphics and
pastes it back as a `/Stamp` whose appearance draws a captured `/Cap` Form
XObject (`vector_snapshot.dart`). Those pastes keep the source page's own
colours, and the generic restyle path can't touch them: a content-less
`/Stamp` has `canRestyle == false`, and the Stamp restyle branch would rebuild
it as a *text* stamp, destroying the picture. So snapshots had no way to be
recoloured. This adds one, from the annotation context menu.

## What changed

- **`pdf_document/lib/src/vector_snapshot.dart`**
  - `pasteVectorSnapshot` now stamps the annotation with a
    `/DartPdfVectorSnapshot true` marker (mirrors the `DartPdfStampType`
    marker pattern) so a pasted snapshot is distinguishable from an ordinary
    stamp.
  - `isVectorSnapshotStamp(annotation)` - the gate.
  - `recolorVectorSnapshot(pageIndex, annotation, rgb)` - retints the captured
    graphics to a single ink (a monochrome silhouette, the Bluebeam-style
    "recolor a snapshot"). It builds a recoloured **copy** of the `/Cap` form
    and points *this* annotation's appearance at it, so other pastes that
    share the original captured form are untouched. Idempotent - recolouring
    again just retints. The geometry (the appearance's `cm`/`/Matrix`) is left
    alone, so resize/rotate state survives; only the nested `/Cap` reference is
    swapped and the appearance form re-serialized via `_updater.markChanged`.
  - `_recoloredForm` recurses into nested Form XObjects the capture draws
    (copying each once through a `done` map, cycle-guarded by `visiting`) so
    forms that set their own colours recolour too.
  - `_recolorContentBytes` rewrites the content stream: every fill colour op
    (`g`/`rg`/`k`/`sc`/`scn`) → `rg` target, every stroke op
    (`G`/`RG`/`K`/`SC`/`SCN`) → `RG` target, and `cs`/`CS` dropped (moot once
    everything is DeviceRGB). It **prepends** a forced initial ink for both
    paint sides so colour-less paths that rely on the default black recolour
    too - without that, black line art would be a no-op. Reuses
    `ContentStreamParser`/`ContentStreamSerializer` from pdf_cos.

  Documented limitation: embedded raster images, inline images, and shadings
  keep their own colours - they aren't vector fills. Patterns collapse to the
  solid ink (a `scn`/`SCN` with a name operand is replaced too).

- **`dart_pdf_editor` `editing_controller.dart`**: `canRecolorSnapshotSelected`
  (every selected annotation is a vector snapshot) + `recolorSnapshotSelected`
  (one revision, one undo, selection kept), following the `restyleSelected`
  shape.

- **`dart_pdf_editor` `editing_menu.dart`**: a stock **"Recolour…"** entry
  (`pdf-annot-menu-recolor-snapshot`) shown only when
  `canRecolorSnapshotSelected`. It opens `showPdfColorPicker` (persisting the
  format via prefs, like the other pickers) and applies the pick.

## Gotchas

- Recolour deliberately does **not** go through `restyleAnnotation`: for a
  Stamp that path regenerates a *text* appearance and would wipe the vectors.
  The snapshot recolour is its own operator-rewrite over the captured form.
- Copy, don't mutate: pastes of one snapshot share the `/Cap` object, so the
  recolour has to fork a private copy or every sibling paste would change. The
  appearance's own `/Resources /XObject` dict *is* per-paste, so swapping its
  `Cap` entry and `markChanged`-ing the appearance form is enough to isolate.

## Tests

- `pdf_document/test/vector_snapshot_test.dart` (new `recolour` group): marker
  set on paste; ordinary stamps rejected; forced-ink prepend recolours
  default-black text; existing fill/stroke colours rewritten (via a small
  inline colour PDF); recolour isolated from a shared paste; and the
  cross-revision path (paste, save, reopen, recolour).
- `dart_pdf_editor/test/editing_snapshot_test.dart`: controller
  `recolorSnapshotSelected` retints; a non-snapshot selection is rejected.
- `dart_pdf_editor/test/editing_menu_test.dart`: the "Recolour…" entry shows
  only for a snapshot selection, and picking it opens the colour dialog and
  lands a revision.
