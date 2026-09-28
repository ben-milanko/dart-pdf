#include "trackpad_signature.h"

// hidusage.h first: MinGW's hidpi.h uses USAGE without including it.
#include <hidusage.h>
#include <hidpi.h>

#include <algorithm>

namespace dart_pdf {

namespace {

constexpr USHORT kDigitizerPage = 0x0D;
constexpr USHORT kTouchPadUsage = 0x05;
constexpr USHORT kTipSwitchUsage = 0x42;
constexpr USHORT kContactIdUsage = 0x51;
constexpr USHORT kContactCountUsage = 0x54;
constexpr USHORT kGenericDesktopPage = 0x01;
constexpr USHORT kXUsage = 0x30;
constexpr USHORT kYUsage = 0x31;

constexpr wchar_t kSinkClassName[] = L"DartPdfTrackpadSignatureSink";

bool IsPrecisionTouchpad(HANDLE device) {
  RID_DEVICE_INFO info{};
  info.cbSize = sizeof(info);
  UINT size = sizeof(info);
  if (::GetRawInputDeviceInfoW(device, RIDI_DEVICEINFO, &info, &size) ==
      static_cast<UINT>(-1)) {
    return false;
  }
  return info.dwType == RIM_TYPEHID &&
         info.hid.usUsagePage == kDigitizerPage &&
         info.hid.usUsage == kTouchPadUsage;
}

double Normalize(ULONG value, LONG min, LONG max) {
  if (max <= min) return 0;
  const double t = (static_cast<double>(value) - min) / (max - min);
  return std::clamp(t, 0.0, 1.0);
}

}  // namespace

TrackpadSignatureCapture::~TrackpadSignatureCapture() { Stop(); }

bool TrackpadSignatureCapture::IsAvailable() {
  UINT count = 0;
  if (::GetRawInputDeviceList(nullptr, &count, sizeof(RAWINPUTDEVICELIST)) !=
          0 ||
      count == 0) {
    return false;
  }
  std::vector<RAWINPUTDEVICELIST> list(count);
  const UINT got =
      ::GetRawInputDeviceList(list.data(), &count, sizeof(RAWINPUTDEVICELIST));
  if (got == static_cast<UINT>(-1)) return false;
  for (UINT i = 0; i < got; ++i) {
    if (list[i].dwType == RIM_TYPEHID && IsPrecisionTouchpad(list[i].hDevice)) {
      return true;
    }
  }
  return false;
}

bool TrackpadSignatureCapture::Start(Listener listener) {
  Stop();
  HINSTANCE instance = ::GetModuleHandleW(nullptr);
  static bool class_registered = false;
  if (!class_registered) {
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = WndProc;
    window_class.hInstance = instance;
    window_class.lpszClassName = kSinkClassName;
    class_registered = ::RegisterClassW(&window_class) != 0;
    if (!class_registered) return false;
  }
  sink_ = ::CreateWindowExW(0, kSinkClassName, L"", 0, 0, 0, 0, 0,
                            HWND_MESSAGE, nullptr, instance, this);
  if (sink_ == nullptr) return false;

  // INPUTSINK: a message-only window is never the foreground window, and
  // the reports must reach it while the app's own window has focus.
  RAWINPUTDEVICE device{};
  device.usUsagePage = kDigitizerPage;
  device.usUsage = kTouchPadUsage;
  device.dwFlags = RIDEV_INPUTSINK;
  device.hwndTarget = sink_;
  if (!::RegisterRawInputDevices(&device, 1, sizeof(device))) {
    ::DestroyWindow(sink_);
    sink_ = nullptr;
    return false;
  }

  listener_ = std::move(listener);
  POINT cursor{};
  if (::GetCursorPos(&cursor)) {
    RECT parked{cursor.x, cursor.y, cursor.x + 1, cursor.y + 1};
    ::ClipCursor(&parked);
  }
  ::ShowCursor(FALSE);
  cursor_hidden_ = true;
  return true;
}

void TrackpadSignatureCapture::Stop() {
  listener_ = nullptr;
  drawing_ = false;
  devices_.clear();
  if (sink_ != nullptr) {
    RAWINPUTDEVICE device{};
    device.usUsagePage = kDigitizerPage;
    device.usUsage = kTouchPadUsage;
    device.dwFlags = RIDEV_REMOVE;
    device.hwndTarget = nullptr;
    ::RegisterRawInputDevices(&device, 1, sizeof(device));
    ::DestroyWindow(sink_);
    sink_ = nullptr;
  }
  if (cursor_hidden_) {
    ::ClipCursor(nullptr);
    ::ShowCursor(TRUE);
    cursor_hidden_ = false;
  }
}

LRESULT CALLBACK TrackpadSignatureCapture::WndProc(HWND hwnd, UINT message,
                                                   WPARAM wparam,
                                                   LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
    ::SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  } else if (message == WM_INPUT) {
    auto* self = reinterpret_cast<TrackpadSignatureCapture*>(
        ::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (self != nullptr && self->sink_ == hwnd) {
      self->OnInput(reinterpret_cast<HRAWINPUT>(lparam));
    }
  }
  // WM_INPUT must still reach DefWindowProc so the system frees the input.
  return ::DefWindowProcW(hwnd, message, wparam, lparam);
}

TrackpadSignatureCapture::Device* TrackpadSignatureCapture::DeviceFor(
    HANDLE handle) {
  auto found = devices_.find(handle);
  if (found != devices_.end()) {
    return found->second.fingers.empty() ? nullptr : &found->second;
  }
  Device& device = devices_[handle];
  if (!IsPrecisionTouchpad(handle)) return nullptr;
  UINT size = 0;
  if (::GetRawInputDeviceInfoW(handle, RIDI_PREPARSEDDATA, nullptr, &size) !=
          0 ||
      size == 0) {
    return nullptr;
  }
  device.preparsed.resize(size);
  if (::GetRawInputDeviceInfoW(handle, RIDI_PREPARSEDDATA,
                               device.preparsed.data(),
                               &size) == static_cast<UINT>(-1)) {
    return nullptr;
  }
  auto preparsed =
      reinterpret_cast<PHIDP_PREPARSED_DATA>(device.preparsed.data());
  HIDP_CAPS caps{};
  if (HidP_GetCaps(preparsed, &caps) != HIDP_STATUS_SUCCESS) return nullptr;
  USHORT value_count = caps.NumberInputValueCaps;
  std::vector<HIDP_VALUE_CAPS> values(value_count);
  if (value_count == 0 ||
      HidP_GetValueCaps(HidP_Input, values.data(), &value_count, preparsed) !=
          HIDP_STATUS_SUCCESS) {
    return nullptr;
  }
  // Each finger is a link collection holding its own X and Y.
  std::map<USHORT, Finger> fingers;
  std::map<USHORT, int> axes;
  for (USHORT i = 0; i < value_count; ++i) {
    const HIDP_VALUE_CAPS& value = values[i];
    if (value.UsagePage != kGenericDesktopPage || value.IsRange) continue;
    const USHORT usage = value.NotRange.Usage;
    if (usage != kXUsage && usage != kYUsage) continue;
    Finger& finger = fingers[value.LinkCollection];
    finger.link = value.LinkCollection;
    if (usage == kXUsage) {
      finger.min_x = value.LogicalMin;
      finger.max_x = value.LogicalMax;
    } else {
      finger.min_y = value.LogicalMin;
      finger.max_y = value.LogicalMax;
    }
    ++axes[value.LinkCollection];
  }
  for (const auto& [link, finger] : fingers) {
    if (axes[link] == 2) device.fingers.push_back(finger);
  }
  return device.fingers.empty() ? nullptr : &device;
}

void TrackpadSignatureCapture::OnInput(HRAWINPUT input) {
  UINT size = 0;
  if (::GetRawInputData(input, RID_INPUT, nullptr, &size,
                        sizeof(RAWINPUTHEADER)) != 0 ||
      size == 0) {
    return;
  }
  std::vector<BYTE> buffer(size);
  if (::GetRawInputData(input, RID_INPUT, buffer.data(), &size,
                        sizeof(RAWINPUTHEADER)) != size) {
    return;
  }
  const auto* raw = reinterpret_cast<const RAWINPUT*>(buffer.data());
  if (raw->header.dwType != RIM_TYPEHID) return;
  HANDLE handle = raw->header.hDevice;
  Device* device = DeviceFor(handle);
  if (device == nullptr) return;
  auto preparsed =
      reinterpret_cast<PHIDP_PREPARSED_DATA>(device->preparsed.data());
  const DWORD report_size = raw->data.hid.dwSizeHid;
  for (DWORD r = 0; r < raw->data.hid.dwCount; ++r) {
    auto report = reinterpret_cast<PCHAR>(
        const_cast<BYTE*>(raw->data.hid.bRawData) + r * report_size);
    // Hybrid-mode touchpads spread one frame over several reports: the
    // first carries the frame's contact count, the rest carry zero. Only
    // that many finger slots hold live contacts.
    ULONG count = 0;
    if (HidP_GetUsageValue(HidP_Input, kDigitizerPage, 0, kContactCountUsage,
                           &count, preparsed, report,
                           report_size) == HIDP_STATUS_SUCCESS &&
        count > 0) {
      device->pending_contacts = count;
    }
    const ULONG slots = std::min<ULONG>(
        device->pending_contacts, static_cast<ULONG>(device->fingers.size()));
    device->pending_contacts -= slots;
    for (ULONG slot = 0; slot < slots; ++slot) {
      const Finger& finger = device->fingers[slot];
      ULONG x = 0, y = 0;
      if (HidP_GetUsageValue(HidP_Input, kGenericDesktopPage, finger.link,
                             kXUsage, &x, preparsed, report,
                             report_size) != HIDP_STATUS_SUCCESS ||
          HidP_GetUsageValue(HidP_Input, kGenericDesktopPage, finger.link,
                             kYUsage, &y, preparsed, report,
                             report_size) != HIDP_STATUS_SUCCESS) {
        continue;
      }
      ULONG id = finger.link;
      HidP_GetUsageValue(HidP_Input, kDigitizerPage, finger.link,
                         kContactIdUsage, &id, preparsed, report, report_size);
      USAGE usages[16];
      ULONG usage_count = 16;
      bool tip = false;
      if (HidP_GetUsages(HidP_Input, kDigitizerPage, finger.link, usages,
                         &usage_count, preparsed, report,
                         report_size) == HIDP_STATUS_SUCCESS) {
        tip = std::find(usages, usages + usage_count, kTipSwitchUsage) !=
              usages + usage_count;
      }
      OnContact(handle, id, tip, Normalize(x, finger.min_x, finger.max_x),
                Normalize(y, finger.min_y, finger.max_y));
      if (listener_ == nullptr) return;
    }
  }
}

void TrackpadSignatureCapture::OnContact(HANDLE device, ULONG id, bool tip,
                                         double x, double y) {
  if (listener_ == nullptr) return;
  if (!drawing_) {
    if (!tip) return;
    drawing_ = true;
    drawing_device_ = device;
    drawing_contact_ = id;
    listener_("down", x, y);
    return;
  }
  if (device != drawing_device_ || id != drawing_contact_) return;
  if (tip) {
    listener_("move", x, y);
  } else {
    drawing_ = false;
    listener_("up", x, y);
  }
}

}  // namespace dart_pdf
