# r/linux self-post

Read the subreddit rules first. r/linux discourages pure self-promotion; frame
it as a project share from the author, engage in the comments, and disclose that
you're the developer. Good secondary subs: r/opensource, r/degoogle,
r/fossdroid (for the mobile angle), r/kde / r/gnome (desktop-integration angle).

## Title

`DartPDF: an open-source, fully-local PDF editor for Linux (edit text, fill forms, redact, sign)`

## Body

> I'm the developer. DartPDF is a PDF editor I've been building in pure Dart —
> it runs natively on Linux (Wayland + X11) and shares one codebase with the
> mac/Windows/mobile/web builds.
>
> I made it because the free options on Linux mostly stop at viewing and
> highlighting. DartPDF does the parts that are usually missing:
>
> - **Edit the text and images already on the page** (not just overlay notes)
> - **Fill forms and save them** — text, checkboxes, radios, dropdowns
> - **Redaction** that removes the covered content from the file, not just hides it
> - **Digital signatures** — PAdES and keyless (Sigstore-style), plus plain drawn
>   signatures
> - **OCR** for scanned PDFs, on device
> - Reorder/extract pages, full-text search, side-by-side compare
>
> Everything runs locally. No account, no uploads — the only network traffic is
> optional signature timestamp/revocation checks and an update check.
> Apache-2.0 licensed.
>
> Desktop integration is done properly: it registers as a PDF handler (shows up
> under "Open With"), takes drag-and-drop and command-line files, and the
> Flatpak uses XDG portals rather than a blanket home-folder grant.
>
> Install: **[Flathub / AUR / AppImage — real links here]**. Source and issues on
> GitHub. I'd genuinely like feedback on how it handles your real-world PDFs —
> the ones that break other tools are the interesting ones.

## Notes

- Flair it appropriately (usually "Software" or per-sub rules).
- Reply to the "does it handle <weird PDF>" comments — the corpus work means it
  usually does, and that's the credibility win.
- Don't cross-post all subs the same hour; stagger over a couple of days and
  tailor the first line (KDE/GNOME subs care about the desktop-integration bit).
- Never name a competing product in the post or replies; talk about capabilities.
