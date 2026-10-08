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
  the URL in the English `video.txt` files under `app/fastlane/metadata/android/`
  when it is available, so later metadata uploads preserve it.
- **Snap Store:** the listing's video field takes an external video URL.
- **Linux software centers:** the AppStream metadata in `app/linux/` points at
  `https://dart-pdf.com/assets/promo-app.webm` (AV1/Opus, under 1 MiB), as a
  separate, non-default screenshot entry. Run the Flatpak desktop-asset sync
  script after changing it. Centers that support video can play it; others
  retain the existing screenshots. The change ships with the Linux packages.
- **Apple App Store:** do not upload this sting as an app preview. Guideline
  2.3.4 requires video screen captures of the app itself; the sting is an
  animated illustration.

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
