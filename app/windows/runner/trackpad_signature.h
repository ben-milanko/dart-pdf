#ifndef RUNNER_TRACKPAD_SIGNATURE_H_
#define RUNNER_TRACKPAD_SIGNATURE_H_

#include <windows.h>

#include <functional>
#include <map>
#include <vector>

namespace dart_pdf {

// Preview-style trackpad signatures on Windows (`PlatformTrackpadSignature
// Capture` in app/lib/trackpad_signature.dart).
//
// Flutter only sees the cursor, never where a finger sits on the touchpad, so
// while a capture runs this registers for Precision Touchpad HID reports
// (usage page 0x0D Digitizer, usage 0x05 Touch Pad) through raw input on a
// private message-only window and reports the first finger down - its
// absolute X/Y normalized by the report's logical range, y down - until it
// lifts. The cursor is clipped in place and hidden for the duration:
// otherwise the drawing finger would also walk it around the screen. Keys,
// clicks, and focus loss are the Dart pad's business.
class TrackpadSignatureCapture {
 public:
  // phase is "down", "move" or "up"; x and y are 0-1 across the surface.
  using Listener = std::function<void(const char* phase, double x, double y)>;

  TrackpadSignatureCapture() = default;
  ~TrackpadSignatureCapture();

  TrackpadSignatureCapture(const TrackpadSignatureCapture&) = delete;
  TrackpadSignatureCapture& operator=(const TrackpadSignatureCapture&) =
      delete;

  // Whether a Precision Touchpad is attached.
  static bool IsAvailable();

  // Starts a capture; false (and no capture) when raw input registration
  // fails. Restarting stops the previous capture first.
  bool Start(Listener listener);

  // Idempotent: unregisters, restores the cursor.
  void Stop();

 private:
  // One finger slot in a touchpad's input report: a HID link collection
  // carrying X and Y.
  struct Finger {
    USHORT link = 0;
    LONG min_x = 0, max_x = 1, min_y = 0, max_y = 1;
  };

  struct Device {
    std::vector<BYTE> preparsed;
    std::vector<Finger> fingers;
    // Contacts still to come in later reports of a hybrid-mode frame.
    ULONG pending_contacts = 0;
  };

  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);
  void OnInput(HRAWINPUT input);
  Device* DeviceFor(HANDLE handle);
  void OnContact(HANDLE device, ULONG id, bool tip, double x, double y);

  HWND sink_ = nullptr;
  Listener listener_;
  std::map<HANDLE, Device> devices_;
  bool drawing_ = false;
  HANDLE drawing_device_ = nullptr;
  ULONG drawing_contact_ = 0;
  bool cursor_hidden_ = false;
};

}  // namespace dart_pdf

#endif  // RUNNER_TRACKPAD_SIGNATURE_H_
