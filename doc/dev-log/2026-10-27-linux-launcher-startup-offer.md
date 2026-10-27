# Linux launcher startup offer

The primary Linux window now checks portable launcher registration asynchronously while the editor opens normally. A nonmodal banner offers setup, dismissal for this launch, or a saved do-not-show-again preference. It never changes the default PDF reader. The existing command-line installer remains available after suppression.

The helper exposes read-only JSON status. Owned entries must have valid desktop metadata, the current absolute executable and a copied icon; moved or damaged entries offer repair. GLib also recognizes visible third-party entries launching the exact same executable when Python GI is available. Snap/Flatpak and system layouts do not receive the portable offer. Missing Python/helper or failed detection quietly leaves normal startup alone. Setup reports success only after a fresh registered status; process execution and output collection are bounded.

Independent review identified an overbroad /opt exclusion and malformed-entry acceptance; both were corrected with regressions. Eleven widget tests cover offer/dismissal, restart suppression, success/error verification, async disposal and stateful document preservation while registration is pending. Forty-five Linux Python tests pass. New strings use the existing ARB workflow across all supported languages; translations still need native-speaker review.

Live Ubuntu application-search/icon verification remains unperformed. Tests use temporary homes and synthetic executables; no private documents or experiment settings are involved.
