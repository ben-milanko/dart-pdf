# 2026-07-17 — delete the pure style forwarders on `PdfEditingController`

Issue #317 (from the 2026-07-16 architecture review). `PdfEditingController`
carried ~40 members that were pure forwarders to `preferences`
(`double get strokeWidth => preferences.strokeWidth;` and its setter, etc.).
Style state lived in three places — `PdfEditingPreferences` (the real store),
the controller mirror, and the toolbar's field cache — and because a couple of
setters *do* add behaviour, callers couldn't tell the load-bearing ones from
the noise.

## What changed

Deleted the pure get/set forwarder pairs for these 19 preference-backed
properties (38 members):

`strokeWidth`, `cornerRadius`, `eraserRadius`, `fontSize`, `textAlign`,
`opacity`, `lineStyle`, `lineScale`, `lineStartEnding`, `lineEndEnding`,
`textFillColor`, `textBorderColor`, `shapeFillColor`, `author`,
`stampDateFormat`, `stampTimeFormat`, `fingerDrawsInk`, `measurementScale`,
`signature`.

Callers now read/write `controller.preferences.strokeWidth` directly (the
toolbar already did in places). Internally the controller reaches through
`preferences.` too — `author: author` in the `apply` calls became
`author: preferences.author`, the stamp-template resolver reads
`preferences.stampDateFormat`/`stampTimeFormat`, and `calibrateScale` /
`measuredDistance` / the takeoff readouts go through
`preferences.measurementScale`.

### Kept (load-bearing — clearly the point of the exercise)

- `color` — the setter honours the `colorLocked` guard and recolours the
  active stamp under the stamp tool. Doc now spells out why it stays.
- `fontFamily` — the setter clears any embedded `activeFont` (back to base-14)
  before writing through.
- `dashedStroke` — a computed boolean view of `preferences.lineStyle` (kept for
  the drag previews that only distinguish dashed/solid), not a forwarder.
- `hasMeasurementScale` — derived predicate, not a forwarder.
- The signature/measurement *behaviour* (`signaturePlacement`, `placeSignature`,
  `calibrateScale`, `measuredDistance`/`Perimeter`/`Area`, `writeMeasurementScale`)
  stays on the controller; only the value forwarders went.

## Blast radius / gotchas

- Consumers updated: `editing_overlay.dart`, `editing_toolbar.dart`,
  `editing_properties.dart`, `editing_stamps.dart`, `editing_takeoff.dart`,
  `pdf_editor_view.dart`, `pdf_viewer.dart`, plus ~20 test files. All the
  controller variables were a single consistent identifier per file
  (`_controller`, `controller`, `session`, `editing`), so the rewrites were a
  mechanical `X.member` → `X.preferences.member`.
- `editing_signature.dart` was imported by the controller only for the
  `PdfInkSignature` return type on the deleted `signature` forwarder — dropped
  the now-unused import.
- `editing_preferences_test.dart` deliberately asserted the forwarders; those
  assertions now read `editing.preferences.strokeWidth`, which is the point of
  the issue ("style/preference behaviour testable against
  `PdfEditingPreferences` alone").

The controller's public surface now narrows toward what it actually owns —
revisions, apply, selection, page ops. A fuller split into
`revisions`/`selection`/`pageOps` sub-objects is a separate, larger change.
