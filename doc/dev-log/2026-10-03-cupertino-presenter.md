# 7.1: PdfCupertinoPresenter (package:dart_pdf_editor/cupertino.dart)

The material_ui plan's x.1 item (decision 6; planned as 6.1, now 7.1 because
6.0.0 shipped without the material_ui switch, which moved to 7.0.0): a
presenter-only Cupertino library, promoted from the example's
`CupertinoEditorPresenter` once the 5.5 example showed the seams were enough.
Stacked on the 7.0 PRs (library, app).

## What changed

- **`lib/cupertino.dart`** exports `PdfCupertinoPresenter` and
  `pdfCupertinoTextContextMenu` from `lib/src/cupertino/`
  (`cupertino_presenter.dart`: routes, menu, sheet, toast, action bar,
  readout, confirm; `cupertino_prompts.dart`: the prompt widgets). Nothing in
  `dart_pdf_editor.dart` imports it.
- **What each method shows.**
  - `dialog`: a `CupertinoDialogRoute` on the root navigator, the opener's
    themes captured, and the same route content as `showPdfDialog`
    (Enter-to-submit, host re-injection, scope re-injection). That content
    is now `pdfDialogRouteContent` in `dialog.dart` (hidden from the main
    export) so the two routes cannot drift.
  - `confirm`, `text`, `styledText`, `link`, `pageRange`, `splitRanges`,
    `measurementScale`, `measurementInput`: `CupertinoAlertDialog`s on that
    route, with `CupertinoTextField`s, a `CupertinoSlidingSegmentedControl`
    (link kind, base-14 family), `CupertinoSlider` (styled size). Validation
    and results mirror the stock prompts line for line; the submit action is
    wrapped in `PdfDialogSubmit.action`, so Enter submits. They carry the
    stock prompts' `pdf-*` keys (plus a `pdf-cupertino-*` key on the alerts
    that had none), so finders and patrol tests work under either presenter.
  - `menu`: `CupertinoActionSheet` + Cancel on a `CupertinoModalPopupRoute`.
    Not `CupertinoContextMenu`: that lifts a preview of a child it wraps on
    a long press, and the editor's menus are requested at a rectangle with
    no widget to lift. Checkable rows show a check; disabled rows are grey
    no-ops; value-less rows draw their `child` (on a transparent `Material`,
    since embedded controls are Material) or a caption; dividers are dropped.
  - `formChoice`: a `CupertinoPicker` (single-select) or a checklist of
    `CupertinoListTile`s (multi-select) under Cancel / Done; Done returns the
    whole selection (the stock menu toggles one option per open).
  - `sheet`: `CupertinoModalPopupRoute` with a rounded system-background
    surface and a grabber; content gets a transparent `Material` (the stock
    sheets are list tiles and switches).
  - `notice`: an overlay toast (dark capsule, Undo, optional close), one at a
    time with the stock queue/replace semantics.
  - `actionBar` / `readout`: dark iOS edit-menu capsules of `CupertinoButton`s
    keyed by the action ids; groups open as action sheets.
  - **Fallbacks:** `color`, `font`, `signature` stay stock (a full colour
    picker, the searchable font catalogue and the signature pad are not worth
    duplicating). They open on the Cupertino dialog route; `PdfMaterialHost`
    supplies their Material bits under a `CupertinoApp`.
- **Icons.** No `CupertinoIcons` (C6: that font ships only with
  `cupertino_icons`). Its few glyphs (check, close, palette, drop-down
  arrow, the "keep" swatch's block) are material_ui `Icons`, which the stock
  chrome already requires.
- **Text menus** in its prompts: `pdfCupertinoTextContextMenu` - the system
  menu where supported, else `CupertinoAdaptiveTextSelectionToolbar`, re-
  injected through `pdfHostRoute`.
- **Unit lists** (`pdfScaleUnits`, `pdfPageUnits`) moved from private
  constants in `editing_measure.dart` to `models/measurement_scale.dart`
  (not exported: the public export of that file is `show`-limited).
- **`check_design_imports`**: the allowlist grows by the two
  `lib/src/cupertino/` files (hand edit; they are the library's reason to
  exist, importing cupertino_ui by design), and a new rule (e) walks
  `dart_pdf_editor.dart`'s closure (relative + `package:dart_pdf_editor/`
  imports) and fails if it reaches `lib/src/cupertino/`, so Material hosts
  never compile it. Tested in `check_design_imports_test.dart`; a probe
  import from `toast.dart` fails it with the chain.
- **Example**: `cupertino_host.dart` uses `PdfCupertinoPresenter`; its own
  presenter, text prompt and toast (~200 lines) are gone. Its test now finds
  the library's keys.

## Tests

`test/cupertino_presenter_test.dart`: a CupertinoApp host (`pumpPdfHost`,
`PdfTestHost.cupertino`), every test once for iOS and once for macOS via
`TargetPlatformVariant.only` (the cached fallback `ThemeData` gotcha). A
recording subclass notes each method and the last test of each platform
group asserts all 18 were driven, through real entry points: text-menu
right-click -> action sheet -> Add link; flatten -> toast -> Undo; redaction
apply -> destructive alert; annotation library rename (and its Cupertino
text menu, long-press on iOS, right-click on macOS); stamp editor ->
custom colour / add signature (stock fallbacks on the Cupertino route);
Edit text & style -> font row -> stock font picker; combo picker and
multi-select checklist; arming a measure tool -> scale alert -> unit action
sheet; calibration segment; volume depth; thumbnails Export pages / Split;
compact controls sheet; touch selection action bar; text-selection bar;
style readout. Each ends with no FlutterError and no ErrorWidget.

## Gotchas

- **The viewer's double-tap recognizer holds the arena** on a tap over the
  page (the action bar sits on the page): a button there fires only after
  the double-tap timeout, so a test must `pump(400 ms)` after the tap;
  `pumpAndSettle` returns before the timer and the tap looks dead. The stock
  chip test already did this.
- `CupertinoDialogRoute` / `CupertinoModalPopupRoute` capture no themes and
  read `CupertinoLocalizations` for the barrier label; both are passed in
  explicitly (themes captured from the opener, the editor's own "Dismiss").
- The prompts call the presenter's own `dialog`, not the scope's, so a
  prompt asked outside any scope is still Cupertino and a subclass's
  `dialog` override applies.

## Verification

- `fvm dart analyze --fatal-infos` at the root: clean.
- `check_design_imports` (+ its tests, with the new rule), lockstep, ARB
  coverage and English-region checks: OK. No new ARB keys were needed: every
  string comes from existing `pdfL10n` keys.
- Suites vs the base (`12551b35`): editor 3170 passed / 33 skipped (3130/33
  + the 40 new Cupertino cases), example 67 (67), app 680 (680).
- App release web (`flutter build web --release`), base vs branch:
  `main.dart.js` 4,533,262 B both (gzip 1,101,115 vs 1,101,113; the bytes
  differ only in minified names), deferred part 4,233,423 -> 4,233,452
  (+29 B raw, +4 B gzip). No `pdf-cupertino` string or Cupertino presenter
  code is in the output; the 29 bytes are the extracted
  `pdfDialogRouteContent` helper (one more top-level function shifts the
  minified names).
