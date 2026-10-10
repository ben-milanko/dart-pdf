# DartPDF launch sting

A 22-second, 1920x1080 motion graphic with a synthesised soundtrack. All of it
is code: no stock footage, samples or fonts beyond Inter and DejaVu Sans Mono.

| Time | Scene |
| --- | --- |
| 0-3s | **From bytes.** Raw PDF syntax scrolls past, then collapses into a blank page |
| 3-6s | **Rendered in pure Dart.** The page draws itself: band, glyph outlines, chart, form |
| 6-12s | **Edit everything.** Highlight, ink signature, move a text run, fill a form, stamp |
| 12-15s | **Reorder. Insert. Merge.** Thumbnail strip: a page moves up front, an appendix drops in |
| 15-18s | **Signed & sealed.** Ribbon and padlock close; root → intermediate → signer chain verifies |
| 18-22s | The page morphs into the app icon (`doc/logo.svg`), then the wordmark, tagline and URL |

### App-user cut (`?variant=app`)

A 19.8s version for people who use the app and don't care about the library. It
plays the same master timeline from 2.2s, so it opens on the page itself, and its
copy is about the app: **Open any PDF.** (No account. No uploads.), **Edit
everything.**, **Reorder. Insert. Merge.**, **Sign it. Seal it.** (Digital
signatures, checked on your device.). The certificate cards drop CA/PAdES jargon.
Add `--variant app` to every `render.cjs` call below. `soundtrack.py` trims the
same offset, so the music stays on the beat.

## Files

- `dartpdf-sting.html` is the whole animation as one canvas file. `draw(t)` is
  a pure function of time. Open it directly to watch it loop, or add `?t=12.5`
  to freeze on one frame. `CUES`/`MUSIC` hold the sound-design timeline.
- `render.cjs` renders frames in headless Chromium (Playwright) and pipes them
  to ffmpeg. It can also write stills or the cue sheet.
- `soundtrack.py` turns the cue sheet into audio (numpy only): a 120 BPM
  pad/bass/arp bed plus one sound effect per cue. The output is deterministic.

## Build

```sh
cd doc/marketing/motion
export NODE_PATH=$(npm root -g)          # wherever playwright is installed
node render.cjs --cues build/cues.json
python3 soundtrack.py build/cues.json build/soundtrack.wav
node render.cjs --audio build/soundtrack.wav --out build/dartpdf-sting.mp4
```

Spot-check frames without a full render:
`node render.cjs --stills 3.6,8.7,18.6 --outdir build/stills`.

A full 60fps render takes about 7 minutes. Output: H.264 CRF 16 + AAC 256k,
about 6.5 MB, around -14 LUFS. `build/` is git-ignored.

To retime a beat, edit the scene's `seg(t, a, b)` windows and move the matching
`CUES` entry so the sound stays on the frame.

## Website encodes

The site (`site/assets/promo-*`) uses 30fps web encodes of the two masters:

```sh
ffmpeg -i build/dartpdf-sting-app.mp4 -vf fps=30 -c:v libx264 -preset slow -crf 25 \
  -pix_fmt yuv420p -movflags +faststart -c:a aac -b:a 128k ../../../site/assets/promo-app.mp4
ffmpeg -i build/dartpdf-sting-app.mp4 -vf fps=30 -c:v libsvtav1 -crf 38 -preset 6 \
  -c:a libopus -b:a 96k ../../../site/assets/promo-app.webm
ffmpeg -ss 19.0 -i build/dartpdf-sting-app.mp4 -frames:v 1 -vf scale=1600:-1 ../../../site/assets/promo-app-poster.webp
```

Do the same for `dartpdf-sting.mp4` → `promo-sdk.*`, with the poster taken at 21.2s.

## Storefront video

Use the **app-user cut** for app storefronts. The SDK cut contains developer
terminology that does not belong in an app listing.

- **Microsoft Store:** upload a 1920×1080 MP4 in Partner Center's English
  listing, under Trailers. Title: `DartPDF — Edit, arrange, and sign PDFs`.
  `store-assets/dartpdf-trailer-poster.png` is the required 1920×1080 PNG;
  `store-assets/dartpdf-trailer.vtt` supplies English captions.
  `store-assets/dartpdf-trailer-hero.png` is the text-free 16:9 hero art required
  for the trailer to play at the top of the listing; regenerate it with
  `rsvg-convert store-assets/dartpdf-trailer-hero.svg -o store-assets/dartpdf-trailer-hero.png`.
  Submit the
  listing change for certification; a saved draft is not a published trailer.
- **Google Play:** the preview field requires a YouTube URL. The upload must
  be public or unlisted, embeddable, without ads or an age restriction. Keep
  the URL in the locale `video.txt` files under `app/fastlane/metadata/android/`
  when it is available, so later metadata uploads preserve it.
- **Snap Store:** the listing's video field supports YouTube or Vimeo embeds
  (plus asciinema for terminal recordings). Reuse the Google Play YouTube URL;
  the direct MP4/WebM website URLs will not render in Snapcraft's video template.
- **Linux software centers:** the AppStream metadata in `app/linux/` points at
  `https://dart-pdf.com/assets/promo-app.webm` (AV1/Opus, under 1 MiB), as a
  separate, non-default screenshot entry. Run the Flatpak desktop-asset sync
  script after changing it. Centers that support video can play it; others
  retain the existing screenshots. The change ships with the Linux packages.
- **Apple App Store:** do not upload this sting as an app preview. Guideline
  2.3.4 requires video screen captures of the app itself; the sting is an
  animated illustration. Use the recorded preview below instead.

On 8 October 2026, the Microsoft trailer, poster, captions, and hero artwork
were saved in Partner Center submission **16** (`1152921505702071402`) and
submitted for certification. It passed certification and Partner Center
confirmed it was published on the same day. Submission **17**
(`1152921505702072175`) retains those assets and adds the aligned listing copy;
Partner Center confirmed **In certification**, with automatic publishing after
approval.

The shared Google Play/Snap video is
<https://www.youtube.com/watch?v=jKLzTw32Jd4>, uploaded as **Unlisted** on the
**Ben Milanko** channel on 8 October 2026. Title:
`DartPDF — Edit, arrange, and sign PDFs`. English WebVTT captions are published,
embedding is enabled, and the audience is set to not Made for Kids. YouTube's
copyright check reported no issues. The URL was saved in Snap's listing and
committed to all 21 Google Play listings (edit `13481048941378080280`), with
the existing text and release tracks preserved. Playback and English captions
were verified in the public Snap Store embed. The corresponding `video.txt`
files keep later Play uploads consistent.
Play Console confirmed all 21 video changes **in review**, with managed
publishing off so they publish after approval.

## App Store preview

Apple's previews must be screen recordings of the app, with only captions,
touch indicators, simple fades and a soundtrack added
([guidance](https://developer.apple.com/app-store/app-previews/)). This one is
a recording of the real app, operated by a script:

- `app/tool/preview_main.dart` runs the shipping `EditorScreen` and works it
  with real touch events on the app's own controls, found by widget key. It
  opens a generated proposal (`app/tool/preview_document.dart`), highlights a
  sentence, fills the client-name field, drags the appendix ahead of the
  budget in the page grid, and signs on the signature line. A fingertip dot
  shows each touch, which Apple allows as a touch hotspot. Every edit is
  checked to have committed, so a missed highlight fails the take instead of
  reaching the store. The tour prints caption and sound markers on stdout.
- `app/tool/preview/record_ios.py` boots the iPhone 17 Pro Max simulator with
  the 9:41 status bar and runs the tour, which runs on frame time: each frame
  it draws is exactly 1/30 s after the last. The tour saves every frame as a
  1320×2868 PNG (the app's own pixels), so a simulator that stalls makes the
  recording take longer but never costs the cut a frame. One
  `simctl io screenshot` supplies what iOS draws on top (the status bar,
  Dynamic Island and home indicator). It also writes `tour.log`, the tour's
  markers.
- `app/tool/preview/compose_preview.py` places every frame by the number it
  carries in a thin strip along the bottom edge (then crops the strip), lays
  the system chrome over it, cuts the clip from `start` to `end` and frames
  it under captions on the store screenshots' gradient. The tour's
  `focus` markers drive punch-ins: eased zooms of up to about 1.85× inside the
  phone frame on the sentence, the field, the page drag and the signature.
  Each punch-in is a still shot framed around everything the finger does
  in it; the camera only moves to ease in and out.
  Each frame is cropped from the 1320×2868 capture and downscaled, so a
  close-up stays at or above native resolution and is never upscaled. It adds this
  sting's music bed, offset so the chord hit lands on the closing caption,
  plus a sound per touch. The encode follows
  [Apple's preview spec](https://developer.apple.com/help/app-store-connect/reference/app-preview-specifications):
  886×1920, H.264 High@4.0, 30 fps, about 11 Mbps, and stereo 256 kbps AAC at
  48 kHz. It also writes a poster PNG of the closing frame, which has every
  edit on it.

The clip opens on the highlight already in progress, because viewers give a
listing only a few seconds. Captions carry the story, because previews
autoplay muted. The last caption is the privacy line (no account, no ads, no
uploads); the app has no in-app purchases to disclose.

Run the **Marketing screenshots** workflow with `app_preview_only` checked.
Download the `app-preview-iphone` artifact, then watch the MP4 before
uploading it. Upload it to App Store Connect under the iPhone 6.9" previews;
6.5" and smaller iPhones accept the same 886×1920 file. Set the poster frame
to the time the composer prints, about 0.6 s before the end. Locally on a Mac:

```sh
cd app
python3 tool/preview/record_ios.py --out build/preview-ios
python3 tool/preview/compose_preview.py --device iphone \
  --frames build/preview-ios/frames --chrome build/preview-ios/chrome.png \
  --log build/preview-ios/tour.log --out build/preview-ios/dartpdf-preview-iphone.mp4
```

To draft without a Mac, run the tour in headless Chromium. Software GL draws
far slower than a device, which only makes the recording take longer, because
the tour runs on frame time. The web build needs the real render worker
(`fvm dart run dart_pdf_editor:build_web_worker --out
../packages/dart_pdf_editor_assets/assets/web/pdf_render_worker.dart.js`, then
restore that file with `git checkout`). This draft has no iOS status bar and
is for review only, not for upload:

```sh
cd app
fvm flutter build web -t tool/preview_main.dart --no-tree-shake-icons
npx http-server build/web -p 8765 &
NODE_PATH=$(npm root -g) node tool/preview/record_web.cjs --out build/preview-web
python3 tool/preview/compose_preview.py --video build/preview-web/raw.mp4 \
  --log build/preview-web/tour.log --out build/preview-web/draft.mp4
```

The tour targets the phone layout, with its bottom tool dock and Tools sheet.
An iPad preview (1200×1600, `--device ipad`) needs the tour adapted to the
tablet toolbar first; `--dart-define=PREVIEW_PROBE=true` prints the keyed
controls on screen at each step. Edit the captions in `CAPTIONS` in
`compose_preview.py`, and the storyboard in `_Tour.play`.

Microsoft's mezzanine MP4 can be regenerated from the app cut (prefer the
full-quality master when available). Keep this large upload file outside Git:

```sh
ffmpeg -i ../../../site/assets/promo-app.mp4 \
  -c:v libx264 -preset slow -profile:v high -pix_fmt yuv420p -r 30 \
  -g 15 -keyint_min 15 -bf 2 -sc_threshold 0 \
  -b:v 50M -minrate 50M -maxrate 50M -bufsize 100M \
  -x264-params 'nal-hrd=cbr:force-cfr=1:open-gop=0' \
  -c:a aac -b:a 384k -ar 48000 -ac 2 \
  -movflags +faststart -use_editlist 0 /tmp/dartpdf-msstore-trailer.mp4
```

Store requirements: [Microsoft trailers](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msix/screenshots-and-images#trailers),
[Google Play preview video](https://support.google.com/googleplay/android-developer/answer/9866151),
[Snap listing media](https://forum.snapcraft.io/t/store-listing-and-branding/16397),
[AppStream screenshot/video metadata](https://www.freedesktop.org/software/appstream/docs/chap-Metadata.html#tag-screenshots),
[Apple preview policy](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata).
