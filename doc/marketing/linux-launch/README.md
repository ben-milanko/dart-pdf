# Linux launch kit

Drafts for the Linux launch push. Neutral wording throughout — **no competitor
product names** anywhere public (dashboards, posts, docs headlines); describe
capability gaps, not rivals.

## Files

- [`reddit-rlinux.md`](reddit-rlinux.md) — r/linux (and r/linux_gaming-adjacent
  subs like r/opensource, r/degoogle) self-post.
- [`hackernews.md`](hackernews.md) — Show HN title + body.
- [`press-pitch.md`](press-pitch.md) — one email, lightly tailored per outlet
  (Phoronix, OMG! Ubuntu, It's FOSS).

## Sequencing (do not post until these are true)

1. **The official Flatpak repository is live.** The whole pitch is "one-click
   install, shows up in Open With." Posting before
   `flatpak install --from https://dartpdf-flatpak.web.app/dartpdf.flatpakref`
   works undercuts it and burns the HN/Reddit first-impression (you get one).
2. **The landing page is deployed** at <https://dart-pdf.com/pdf-editor-linux>
   with Flatpak presented as the recommended Linux installation.
3. **You have tested on real hardware** (see
   `doc/dev-log/2026-07-25-linux-test-matrix.md`) — a launch-day crash report on
   Wayland or a no-keyring box is the worst outcome.

Order: publish and clean-install the signed Flatpak → deploy the landing page →
**Show HN in the morning (US Pacific, weekday)** → r/linux same day → press
emails the day it starts getting traction (link the HN thread as proof).

## Honesty guardrails (HN/Reddit will fact-check)

- Don't say "the first" or "the only" PDF editor for Linux. Say what's
  **missing** from the free options: editing on-page text, filling **and saving**
  forms, true redaction, and verifiable (PAdES/keyless) signatures — rarely all
  in one free app.
- Signing: it produces and validates PAdES signatures; it does **not** issue
  certificates or assert signer trust. Say so.
- OCR: on-device, downloads a model once. Not a cloud call.
- Redaction: removes covered text/images from the file; an image only
  *partially* inside a redaction box is painted over, not stripped. Don't
  overclaim pixel-level removal inside partially-redacted images.
- "Local / no uploads" is the strongest true claim — lead with it, keep it exact
  (matches `app/PRIVACY.md`).
