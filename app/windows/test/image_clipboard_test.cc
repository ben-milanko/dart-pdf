// Exercises the real Win32 clipboard and WIC conversion on a Windows runner.
#include "../runner/image_clipboard.h"

#include <objbase.h>

#include <cassert>
#include <cstring>
#include <iostream>

namespace {
const std::vector<uint8_t> kPng = {
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x72, 0xb6, 0x0d, 0x24, 0x00, 0x00, 0x00,
    0x19, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
    0x1f, 0x08, 0x1b, 0x58, 0x18, 0x19, 0xfe, 0x33, 0x72, 0x89, 0xca, 0xfb,
    0x02, 0x00, 0x37, 0x04, 0x05, 0x0e, 0x4e, 0x7a, 0xa3, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82};

void Put(UINT format, const std::vector<uint8_t>& bytes) {
  HGLOBAL handle = ::GlobalAlloc(GMEM_MOVEABLE, bytes.size());
  assert(handle != nullptr);
  void* buffer = ::GlobalLock(handle);
  assert(buffer != nullptr);
  std::memcpy(buffer, bytes.data(), bytes.size());
  ::GlobalUnlock(handle);
  assert(::SetClipboardData(format, handle) != nullptr);
}

void ExternalCopy(HWND owner, const std::vector<uint8_t>& dib,
                  bool offer_alias) {
  assert(::OpenClipboard(owner));
  assert(::EmptyClipboard());
  Put(::RegisterClipboardFormatW(L"PNG"), {1, 2, 3});
  if (offer_alias) Put(::RegisterClipboardFormatW(L"image/png"), kPng);
  if (!dib.empty()) Put(CF_DIBV5, dib);
  assert(::CloseClipboard());
}
}  // namespace

int main() {
  assert(SUCCEEDED(::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)));
  HWND owner = ::CreateWindowExW(0, L"STATIC", L"Clipboard test", 0,
                                 0, 0, 1, 1, nullptr, nullptr, nullptr, nullptr);
  assert(owner != nullptr);
  const std::vector<uint8_t> pdf = {'%', 'P', 'D', 'F', '-', '1', '.', '7'};
  assert(CopySnapshotToClipboard(owner, pdf, kPng));
  assert(!ReadExternalPdfFromClipboard(owner).has_value());
  assert(!ReadImageFromClipboard(owner, true).has_value());
  assert(ReadImageFromClipboard(owner).value() == kPng);

  // Save the generated alpha-preserving DIBV5 for an external-only recopy.
  assert(::OpenClipboard(owner));
  HANDLE handle = ::GetClipboardData(CF_DIBV5);
  assert(handle != nullptr);
  const auto* buffer = static_cast<const uint8_t*>(::GlobalLock(handle));
  assert(buffer != nullptr);
  std::vector<uint8_t> dib(buffer, buffer + ::GlobalSize(handle));
  ::GlobalUnlock(handle);
  assert(::CloseClipboard());

  // A malformed registered PNG must yield to the alias or bitmap fallback.
  ExternalCopy(owner, {}, true);
  assert(ReadImageFromClipboard(owner, true).value() == kPng);
  MarkLocalClipboardCopy();
  assert(!ReadImageFromClipboard(owner, true).has_value());
  ExternalCopy(owner, dib, false);
  const auto converted = ReadImageFromClipboard(owner, true);
  assert(converted.has_value() && !converted->empty());
  ExternalCopy(owner, {}, false);
  assert(!ReadImageFromClipboard(owner, true).has_value());

  assert(::OpenClipboard(owner));
  assert(::EmptyClipboard());
  assert(::CloseClipboard());
  ::DestroyWindow(owner);
  ::CoUninitialize();
  std::cout << "Win32 PNG, DIBV5, fallback and ownership checks passed\n";
}
