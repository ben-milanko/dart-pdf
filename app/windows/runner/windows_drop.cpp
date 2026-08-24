#include "windows_drop.h"

#include <flutter/standard_method_codec.h>
#include <ole2.h>
#include <shellapi.h>

#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "utils.h"

namespace {

constexpr char kWindowsDropChannelName[] =
    "dev.milanko.dartpdf/windows_drop";

const flutter::EncodableValue* Lookup(const flutter::EncodableMap& map,
                                      const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::optional<int64_t> Integer(const flutter::EncodableValue& value) {
  if (const auto* number = std::get_if<int64_t>(&value)) return *number;
  if (const auto* number = std::get_if<int32_t>(&value)) return *number;
  return std::nullopt;
}

flutter::EncodableMap EventPayload(HWND window, POINTL point) {
  POINT client{point.x, point.y};
  ::ScreenToClient(window, &client);
  return flutter::EncodableMap{
      {flutter::EncodableValue("handle"),
       flutter::EncodableValue(
           static_cast<int64_t>(reinterpret_cast<intptr_t>(window)))},
      {flutter::EncodableValue("x"),
       flutter::EncodableValue(static_cast<double>(client.x))},
      {flutter::EncodableValue("y"),
       flutter::EncodableValue(static_cast<double>(client.y))},
  };
}

}  // namespace

class DartPdfWindowsDropTarget : public IDropTarget {
 public:
  DartPdfWindowsDropTarget(
      HWND window,
      flutter::MethodChannel<flutter::EncodableValue>* channel)
      : window_(window), channel_(channel) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid,
                                           void** object) override {
    if (object == nullptr) return E_INVALIDARG;
    if (iid == IID_IUnknown || iid == IID_IDropTarget) {
      *object = static_cast<IDropTarget*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override {
    return static_cast<ULONG>(::InterlockedIncrement(&references_));
  }

  ULONG STDMETHODCALLTYPE Release() override {
    const LONG references = ::InterlockedDecrement(&references_);
    if (references == 0) delete this;
    return static_cast<ULONG>(references);
  }

  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* data,
                                      DWORD /*key_state*/,
                                      POINTL point,
                                      DWORD* effect) override {
    last_point_ = point;
    SetEffect(data, effect);
    Invoke("entered", EventPayload(window_, point));
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE DragOver(DWORD /*key_state*/,
                                     POINTL point,
                                     DWORD* effect) override {
    last_point_ = point;
    if (effect != nullptr) *effect = DROPEFFECT_COPY;
    Invoke("updated", EventPayload(window_, point));
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE DragLeave() override {
    Invoke("exited", EventPayload(window_, last_point_));
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE Drop(IDataObject* data,
                                 DWORD /*key_state*/,
                                 POINTL point,
                                 DWORD* effect) override {
    last_point_ = point;
    flutter::EncodableMap payload = EventPayload(window_, point);
    flutter::EncodableList paths;
    FORMATETC format{CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    STGMEDIUM medium{};
    if (data != nullptr && data->QueryGetData(&format) == S_OK &&
        data->GetData(&format, &medium) == S_OK) {
      HDROP drop = static_cast<HDROP>(::GlobalLock(medium.hGlobal));
      if (drop != nullptr) {
        const UINT count = ::DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
        for (UINT index = 0; index < count; ++index) {
          const UINT length = ::DragQueryFileW(drop, index, nullptr, 0);
          std::wstring path(static_cast<size_t>(length) + 1, L'\0');
          const UINT copied =
              ::DragQueryFileW(drop, index, path.data(), length + 1);
          path.resize(copied);
          if (!path.empty()) {
            paths.emplace_back(Utf8FromUtf16(path.c_str()));
          }
        }
        ::GlobalUnlock(medium.hGlobal);
      }
      ::ReleaseStgMedium(&medium);
    }
    payload[flutter::EncodableValue("paths")] =
        flutter::EncodableValue(std::move(paths));
    if (effect != nullptr) *effect = DROPEFFECT_COPY;
    Invoke("performOperation", std::move(payload));
    return S_OK;
  }

 private:
  ~DartPdfWindowsDropTarget() = default;

  static void SetEffect(IDataObject* data, DWORD* effect) {
    if (effect == nullptr) return;
    FORMATETC format{CF_HDROP, nullptr, DVASPECT_CONTENT, -1, TYMED_HGLOBAL};
    *effect = data != nullptr && data->QueryGetData(&format) == S_OK
                  ? DROPEFFECT_COPY
                  : DROPEFFECT_NONE;
  }

  void Invoke(const char* method, flutter::EncodableMap payload) {
    channel_->InvokeMethod(
        method,
        std::make_unique<flutter::EncodableValue>(std::move(payload)));
  }

  HWND window_;
  flutter::MethodChannel<flutter::EncodableValue>* channel_;
  LONG references_ = 1;
  POINTL last_point_{};
};

DartPdfWindowsDropService::DartPdfWindowsDropService(
    flutter::BinaryMessenger* messenger) {
  // RegisterDragDrop requires OLE initialization in addition to the runner's
  // regular COM initialization. Balance S_OK and S_FALSE alike per the API.
  ole_initialized_ = SUCCEEDED(::OleInitialize(nullptr));
  channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kWindowsDropChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        const auto* handle_value =
            args == nullptr ? nullptr : Lookup(*args, "handle");
        const auto handle =
            handle_value == nullptr ? std::nullopt : Integer(*handle_value);
        if (!handle.has_value()) {
          result->Error("bad_args", "A native window handle is required");
          return;
        }
        const HWND window = reinterpret_cast<HWND>(
            static_cast<intptr_t>(*handle));
        if (call.method_name() == "register") {
          result->Success(flutter::EncodableValue(Register(window)));
        } else if (call.method_name() == "unregister") {
          Unregister(window);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
}

DartPdfWindowsDropService::~DartPdfWindowsDropService() {
  while (!targets_.empty()) Unregister(targets_.begin()->first);
  if (ole_initialized_) ::OleUninitialize();
}

bool DartPdfWindowsDropService::Register(HWND window) {
  if (window == nullptr || !::IsWindow(window)) return false;
  if (targets_.find(window) != targets_.end()) return true;
  auto* target = new DartPdfWindowsDropTarget(window, channel_.get());
  const HRESULT result = ::RegisterDragDrop(window, target);
  if (FAILED(result)) {
    target->Release();
    return false;
  }
  targets_.emplace(window, target);
  return true;
}

void DartPdfWindowsDropService::Unregister(HWND window) {
  const auto found = targets_.find(window);
  if (found == targets_.end()) return;
  ::RevokeDragDrop(window);
  found->second->Release();
  targets_.erase(found);
}
