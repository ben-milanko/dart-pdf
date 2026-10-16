# iPhone Duo and other foldables

App Store Connect opened iPhone Duo screenshot slots (and an "optimized for
iPhone Duo" badge) with the iOS 27.1 SDK. This session made the editor shell
fold-aware and taught the screenshot pipeline the two Duo displays.

## Displays

- Outer (closed): 466 × 678 pt, compact width - below `pdfShellCompactWidth`
  (700), so the shell already uses the phone layout (bottom sheets, compact
  header). Screenshot 1398 × 2034.
- Inner (open): 951 × 669 pt, regular width, aspect ~1.42 - the wide layout,
  docked panels. Screenshot 2853 × 2007 (the simulator presents it landscape).
- Folding/unfolding is a window resize. `PdfViewer._preserveReadingAnchor`
  already pins the page under the viewport top across a width change, and
  Android's `configChanges` already carries
  `screenSize|smallestScreenSize|screenLayout`, so the activity survives a
  fold without a restart.

## Fold-aware shell (`design/fold.dart`, exported)

- `pdfSeparatingFold(features, size)` / `pdfSeparatingFoldOf(context)`: a
  fold or hinge from `MediaQuery.displayFeatures` that splits the window -
  half open, or a hinge with a physical gap - running edge to edge. Same rule
  as material's `DisplayFeatureSubScreen`, which `showDialog`, bottom sheets
  and menus in material_ui already use, so dialogs needed nothing. A flat,
  gapless fold (an unfolded phone lying open) is one surface and is ignored.
- `PdfFoldAvoid` wraps the viewer in `PdfShellPanelLayout` (editor and
  reader): book posture keeps the page in the wider pane, tabletop in the
  upper pane (content up, controls down, Android's tabletop guidance). The
  floating toolbar is inside the viewer stack, so it moves with it.
  The inset is an always-present `Padding` so a posture change never
  reparents the viewer (that would rewind its scroll - see the comment on
  the drag scopes in `PdfShellPanelLayout.build`). The fold arrives in window
  coordinates, so the widget measures its own origin post-frame; the first
  frame with a new fold straddles, the next one corrects.
- `pdfFloatingToastMargin` keeps the toast on the trailing pane.
- Tests: `test/fold_test.dart`.

## iOS caveats

- Flutter 3.47 does not report the Duo's fold to `displayFeatures` on iOS
  (UIKit exposes it through `reservedRegions(kind:options:)`, iOS 27.1 SDK
  only). Until the engine does, the Duo inner display behaves as one flat
  surface, which is also what it is when fully open. Everything above lights
  up for Android foldables today and for iOS as soon as the engine reports it.
- The full-screen Duo layout needs the binary built with the iOS 27.1 SDK
  (Xcode 27.1). An older SDK runs letterboxed. The release `macos-15` runners
  carry an older Xcode, so a Duo-optimized build has to come from a Mac with
  Xcode 27.1 (or a runner image that has it).
- `Info.plist` already meets Apple's checklist: no `UIRequiresFullScreen`, a
  launch storyboard, all orientations.

## Screenshots

`screenshots.sh` gained `ios-duo-outer`, `ios-duo-inner` and `duo`.
`capture_screenshots.dart` takes `SHOT_PLATFORM_DIR`, `SHOT_IOS_DISPLAY`
(simctl `--display=primary|primary-1`) and `SHOT_EXPECT_SIZES` (a PNG of any
other size is discarded). simctl cannot change the pose, so the script pauses
for Device Hub. See doc/screenshots/README.md.
