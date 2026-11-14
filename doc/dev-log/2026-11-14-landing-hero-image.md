# Landing hero image (2026-11-14)

The hero used `editor-screenshot.png`: a dark-theme capture of the developer
feature-showcase page ("Vector graphics & color"), 2208 px wide, shrunk into a
430 px column. Problems with it:

- At about 20% scale the UI and the document could not be read.
- It showed a renderer test page, not anything a user would do with a PDF.
- The dark frame clashed with the light page.
- The "Local" chip hung past the frame's right edge.

The new hero:

- It is a light-theme capture of the real web build with a signed sample
  agreement. It shows filled fields, a highlighted clause with a comment, a
  second highlight, a ticked box, and a handwritten signature. That covers
  "fill, mark up, sign" in one glance.
- A phone capture of the same document overlaps the window, for "every
  device".
- The window chrome and phone bezel are CSS, so they stay crisp at any size.
- The visual column is now `min(620px, 46%)`. The cap keeps the English
  headline on two lines down to about 1180 px.
- The chip says "Stays on your device", with a lock icon, and sits inside
  the visual. The chip and `hero_shotAlt` are re-translated in all 19
  locales. These translations are machine-quality and should get a
  native-speaker pass.
- The two images are about 100 KB of WebP. The old PNG was 566 KB.

Iteration notes:

- With the pages panel open, the page was too small to read. With it closed,
  the viewer refits to width and the floating toolbar hid the signature. The
  fix was to shorten the sample document so the signature lands above the
  toolbar.
- A procedurally generated "cursive" signature looked like a spring. The
  current signature is hand-placed keypoints with Catmull-Rom smoothing.

The pipeline is in `doc/marketing/hero/README.md`. `editor-screenshot.png`
stays on the SDK page and the guides, where the renderer showcase fits.
