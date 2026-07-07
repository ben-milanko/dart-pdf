# Threaded comments + transport-agnostic annotation sync

`resolveThread`/`reopenThread` (stamp `author`, go through `apply(pages:
const [])` - thread edits change no page graphics, so const [] skips the
re-raster while still diffing all pages for the change feed, the same
metadata-edit contract author/contents use) and `commentThreads(page)`.
Sidebar (editing_sidebar.dart): reply/state annotations drop out of the
flat list (shown nested); each markup root renders a thread section - a
review-state pill (`_Pill`), the indented reply tree (`_replyTile`,
depth-indented), and Reply / Resolve(Reopen) controls; the inline reply
field (`pdf-reply-field`/`-send`, `_replyingTo` = root /NM, cleared on the
next revision = the sent reply). Action rows are `Wrap`s - two icon buttons
overflow the ~200px panel as a Row.

PART B - sync session (sync.dart, new export, pure Dart, VM/web, no
networking). `PdfSyncMessage` = a `PdfAnnotationChange` + `origin` +
Lamport `clock` (wire-ready toJson/fromJson). `PdfSyncTransport` is the
injected seam (incoming stream that never echoes the sender, presence
stream + `peers`, send/close) - same shape as the OCR-engine seam; the host
supplies the real socket. `PdfLoopbackSyncHub` is the in-memory reference
transport (connect → endpoint, send fans out to other endpoints on a
microtask, presence on join/leave) for tests and local multi-view.
`PdfSyncSession` owns a byte buffer + reopened document: `apply()` edits
optimistically, diffs, broadcasts each change, and stamps the local write
as newest in `_lastWrite` (per /NM `(clock, origin)`); `_onRemote` merges
with **last-writer-wins keyed on /NM**, accepting only a strictly-newer
`(clock, origin)` (clock first, lexicographic origin tiebreak) - the table
records the winning write even when the apply is a no-op (a remove of
something never held), so a later stale edit is still dropped, and because
the order is total + evaluated identically everywhere, sessions CONVERGE
regardless of delivery order. `annotationBaseline()`/`annotationDigest()`
(NM→snapshot JSON) seed a new peer and prove convergence in tests. Seed
collaborators from the SAME bytes (run nameAnnotations once first) -
independently minted /NMs never reconcile. Tests:
pdf_document/test/comment_test.dart (11 - authoring, model, thread sync
round-trip incl. orphan reply), sync_test.dart (8 - presence, no-echo,
serialization, two sessions converging on independent creates, conflicting
restyles resolving to origin "b", create-vs-remove, stale-drop, a reply
thread reassembling on the peer), dart_pdf_editor/test/editing_thread_test
.dart (3 - sidebar reply, resolve/reopen chip, change-feed emit). Gotcha:
`referenceTo` resolves staged (unsaved) objects, so you can reply to a
just-added annotation in the same editor session without a reopen - the
"fresh annotation throws" guard only bites genuinely inline dicts.
## Orphaned-AcroField reconciliation (macOS 26.5 / Quartz)

Real-world ITF forms saved by a buggy macOS **26.5 (Build 25F71)** Quartz
PDFContext (15.6.1 and the 25F80 patch are fine) leave the `/AcroForm
/Fields` tree and the on-page widget annotations as **two disconnected
copies of the same form**: the `/Fields` entries (merged field+widget
dicts) appear on no page, while the visible page widgets carry the same
fully-qualified `/T` but are absent from `/Fields` and have no `/Parent`.
Read straight, `PdfAcroForm.fields` enumerated the invisible copies and
missed everything the page actually shows, so filling silently updated the
wrong dicts.

Fix is a non-destructive model-level reconciliation in `form.dart`
(`PdfAcroForm._reconcileOrphanWidgets`, run at the end of the cached
`fields` getter - auto, lazy, no byte rewrite on open):

- `_fieldTreeDicts()` = everything reachable from `/Fields` by descending
  `/Kids`. `_orphanWidgetsByName()` = page `Widget` annots **not** in that
  set, grouped by `_widgetFieldName` (own `/T` joined up any `/Parent`
  chain). Both empty for well-formed forms → zero behavior change.
- A `/Fields` terminal whose own widgets show on no page **adopts** the
  matching orphan group (`PdfFormField._reconciled`); `widgets`, `value`,
  and `isChecked` consult it first. Orphan groups with no `/Fields` entry
  become **synthesized** terminal fields (`dict` = the page widget).
- Value rule (user pick): the visible page widget's `/V` wins when set,
  falling back to the `/Fields` copy - the producer split data across both,
  page side is what the user sees. `reconciledWidgets` is public so
  `form_editor`'s `_finishFieldEdit` strips the adopted widgets' stale `/V`
  after a fill (skipping the dict itself for synthesized fields) so the
  canonical value and regenerated appearance stay consistent.

Filling needs no special-casing: `field.widgets` already returns the page
copies, so `_regenerateVariableText` repaints the visible annotation and
`_stageFormDict` stages it (page annots are indirect). The `/Fields` copy
stays off-page so renderers walking page `/Annots` never double-draw.

Tests: `pdf_test_fixtures.buildOrphanedAcroFormPdf()` reproduces the
pattern (off-page `name`/`town` in `/Fields`; on-page `name`/`town`/`extra`
orphans); `pdf_document/test/form_reconcile_test.dart` covers adoption,
synthesis, `describeFields`, the well-formed no-op, and round-trip fills.
`form_admin_test.dart`'s "widget no page lists" case now asserts on the
in-memory editor doc - its old save/reopen relied on an *unstaged* page
mutation, so the saved bytes actually retained an orphan widget that
reconciliation (correctly) re-surfaced.
