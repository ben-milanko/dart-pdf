# Direct Windows printing and saved print preferences

The Windows Print action now uses the app's preview as the final confirmation.
Printer selection, color, two-sided printing and paper source are available in
that dialog. An explicit Printer properties button opens the selected driver's
advanced preferences when needed. Pressing Print goes directly to its queue;
there is no second Windows print menu.

`print_printer.dart` wraps printer discovery and driver capabilities on the
existing native-print channel. `PrintPreviewResult.destination` travels through
the editor's progress flow into `beginJob`. An explicit destination skips the
PDF-native dialog probe and selects the direct Windows path. The runner opens
the queue, merges settings through `DocumentPropertiesW`, creates a printer DC
and spools the prepared vector pages. Paper size changes still apply between
sheets; copies, collation, scaling and n-up are already composed by the app.
Failures propagate to the existing print error UI, and a removed printer never
silently redirects to a different queue. Legacy calls without a destination
retain the system dialog; other platforms keep their existing print handoff.
Automatic printer discovery and settings queries run on workers so unavailable
network queues cannot freeze the dialog. Each query owns its native state and
uses Flutter's lifetime-safe reply callback.

Duplex jobs group front/back sides before expanding copies. Odd-length copies
get blank backs, and uncollated copies repeat whole front/back pairs. Changes
of paper size also start a fresh physical sheet. The runner verifies the actual
paper dimensions after applying them, rejecting a driver substitution that
would otherwise clip the prepared output.

`PrintPreferences` saves the app's paper, orientation, scaling, margins,
offsets, rotation, centering, n-up, content/markup choices, copies, collation,
reverse order and page-range choices in SharedPreferences. It also remembers
the selected queue and each queue's color, duplex and tray choices. Changes
persist even when the preview is cancelled. Defaults resets the document
options while retaining the printer. Values are validated on restore, with
current/selected pages resolved against the current document and invalid custom
ranges left editable. Crop rectangles and temporary batch files are specific to
the job and do not carry into another document.

The Windows runner preserves the complete driver DEVMODE, including private
data such as quality and finishing settings, per printer under HKCU. Compatible
preferences from the previous native print dialog migrate when available.
Common settings are carried across driver updates without reusing an
incompatible private-data layout. Opening advanced properties starts with the
app's current common choices and reflects confirmed changes back into the UI.

Virtual printers such as Microsoft Print to PDF can still request an output
filename. That driver-owned save prompt is separate from the removed print
menu. Physical printer output requires a Windows machine and printer; channel
tests verify the app's direct handoff without sending any real jobs.

Validation covers saved preferences, asynchronous printer switching, failures,
the menu-to-job handoff, duplex copy ordering, composed output and existing
print previews. The Windows backend and channel compile as Windows x64 C++17
with strict warnings, and the backend links against the Windows print libraries.
