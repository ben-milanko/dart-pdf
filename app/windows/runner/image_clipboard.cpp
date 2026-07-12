#include "image_clipboard.h"

#include <objbase.h>
#include <objidl.h>
#include <ocidl.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <cstring>

using Microsoft::WRL::ComPtr;

namespace {

// The registered clipboard format name browsers and Office use to exchange
// lossless PNG images. Registered once; the returned id is stable per session.
UINT PngClipboardFormat() {
  static const UINT format = ::RegisterClipboardFormatW(L"PNG");
  return format;
}

// COM apartment is initialized once per process in wWinMain (COINIT_-
// APARTMENTTHREADED); the channel handler runs on that same UI thread.
ComPtr<IWICImagingFactory> CreateWicFactory() {
  ComPtr<IWICImagingFactory> factory;
  ::CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                     IID_PPV_ARGS(&factory));
  return factory;
}

// Decodes |png| into straight-alpha 32bpp BGRA pixels laid out top-down.
// Returns false on any failure (bad data, unsupported format, OOM).
bool DecodePngToBgra(IWICImagingFactory* factory,
                     const std::vector<uint8_t>& png, UINT* width, UINT* height,
                     std::vector<uint8_t>* pixels) {
  if (factory == nullptr || png.empty()) {
    return false;
  }
  ComPtr<IWICStream> stream;
  if (FAILED(factory->CreateStream(&stream))) {
    return false;
  }
  // InitializeFromMemory wants a non-const buffer but only reads from it.
  if (FAILED(stream->InitializeFromMemory(const_cast<BYTE*>(png.data()),
                                          static_cast<DWORD>(png.size())))) {
    return false;
  }
  ComPtr<IWICBitmapDecoder> decoder;
  if (FAILED(factory->CreateDecoderFromStream(
          stream.Get(), nullptr, WICDecodeMetadataCacheOnDemand, &decoder))) {
    return false;
  }
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(decoder->GetFrame(0, &frame))) {
    return false;
  }
  ComPtr<IWICFormatConverter> converter;
  if (FAILED(factory->CreateFormatConverter(&converter))) {
    return false;
  }
  if (FAILED(converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppBGRA,
                                   WICBitmapDitherTypeNone, nullptr, 0.0,
                                   WICBitmapPaletteTypeMedianCut))) {
    return false;
  }
  if (FAILED(converter->GetSize(width, height)) || *width == 0 ||
      *height == 0) {
    return false;
  }
  const UINT stride = *width * 4;
  const size_t total = static_cast<size_t>(stride) * *height;
  pixels->resize(total);
  return SUCCEEDED(converter->CopyPixels(
      nullptr, stride, static_cast<UINT>(total), pixels->data()));
}

// Builds a CF_DIBV5 global block (BITMAPV5HEADER + bottom-up BGRA rows) from
// the top-down BGRA |pixels|. Returns nullptr on allocation failure.
HGLOBAL BuildDibV5(UINT width, UINT height,
                   const std::vector<uint8_t>& pixels) {
  const UINT stride = width * 4;
  const size_t image_size = static_cast<size_t>(stride) * height;
  const size_t total = sizeof(BITMAPV5HEADER) + image_size;
  HGLOBAL handle = ::GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, total);
  if (handle == nullptr) {
    return nullptr;
  }
  auto* buffer = static_cast<uint8_t*>(::GlobalLock(handle));
  if (buffer == nullptr) {
    ::GlobalFree(handle);
    return nullptr;
  }
  auto* header = reinterpret_cast<BITMAPV5HEADER*>(buffer);
  header->bV5Size = sizeof(BITMAPV5HEADER);
  header->bV5Width = static_cast<LONG>(width);
  header->bV5Height = static_cast<LONG>(height);  // positive => bottom-up rows
  header->bV5Planes = 1;
  header->bV5BitCount = 32;
  header->bV5Compression = BI_BITFIELDS;
  header->bV5SizeImage = static_cast<DWORD>(image_size);
  header->bV5RedMask = 0x00FF0000;
  header->bV5GreenMask = 0x0000FF00;
  header->bV5BlueMask = 0x000000FF;
  header->bV5AlphaMask = 0xFF000000;
  header->bV5CSType = LCS_WINDOWS_COLOR_SPACE;
  header->bV5Intent = LCS_GM_IMAGES;

  uint8_t* dst = buffer + sizeof(BITMAPV5HEADER);
  // Flip the top-down source into the bottom-up rows a DIB expects.
  for (UINT row = 0; row < height; row++) {
    const uint8_t* src =
        pixels.data() + static_cast<size_t>(height - 1 - row) * stride;
    std::memcpy(dst + static_cast<size_t>(row) * stride, src, stride);
  }
  ::GlobalUnlock(handle);
  return handle;
}

// Copies |bytes| into a GMEM_MOVEABLE global block for SetClipboardData, which
// takes ownership on success. Returns nullptr on allocation failure.
HGLOBAL CopyToGlobal(const std::vector<uint8_t>& bytes) {
  HGLOBAL handle = ::GlobalAlloc(GMEM_MOVEABLE, bytes.size());
  if (handle == nullptr) {
    return nullptr;
  }
  void* buffer = ::GlobalLock(handle);
  if (buffer == nullptr) {
    ::GlobalFree(handle);
    return nullptr;
  }
  std::memcpy(buffer, bytes.data(), bytes.size());
  ::GlobalUnlock(handle);
  return handle;
}

// Reads all bytes out of an in-memory IStream backed by an HGLOBAL.
bool ReadStreamBytes(IStream* stream, std::vector<uint8_t>* out) {
  HGLOBAL handle = nullptr;
  if (FAILED(::GetHGlobalFromStream(stream, &handle)) || handle == nullptr) {
    return false;
  }
  const SIZE_T size = ::GlobalSize(handle);
  void* buffer = ::GlobalLock(handle);
  if (buffer == nullptr) {
    return false;
  }
  out->assign(static_cast<uint8_t*>(buffer),
              static_cast<uint8_t*>(buffer) + size);
  ::GlobalUnlock(handle);
  return true;
}

// Encodes a WIC bitmap source as PNG bytes.
bool EncodeSourceToPng(IWICImagingFactory* factory, IWICBitmapSource* source,
                       std::vector<uint8_t>* png) {
  ComPtr<IStream> stream;
  if (FAILED(::CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
    return false;
  }
  ComPtr<IWICBitmapEncoder> encoder;
  if (FAILED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                    &encoder))) {
    return false;
  }
  if (FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache))) {
    return false;
  }
  ComPtr<IWICBitmapFrameEncode> frame;
  ComPtr<IPropertyBag2> props;
  if (FAILED(encoder->CreateNewFrame(&frame, &props))) {
    return false;
  }
  if (FAILED(frame->Initialize(props.Get()))) {
    return false;
  }
  if (FAILED(frame->WriteSource(source, nullptr))) {
    return false;
  }
  if (FAILED(frame->Commit()) || FAILED(encoder->Commit())) {
    return false;
  }
  return ReadStreamBytes(stream.Get(), png);
}

// Guard that opens the clipboard in the constructor and closes it in the
// destructor so every early-return path releases it.
class ClipboardGuard {
 public:
  explicit ClipboardGuard(HWND owner) : open_(::OpenClipboard(owner) != FALSE) {}
  ~ClipboardGuard() {
    if (open_) {
      ::CloseClipboard();
    }
  }
  bool open() const { return open_; }

 private:
  bool open_;
};

}  // namespace

bool CopyPngToClipboard(HWND owner, const std::vector<uint8_t>& png) {
  ComPtr<IWICImagingFactory> factory = CreateWicFactory();
  UINT width = 0;
  UINT height = 0;
  std::vector<uint8_t> pixels;
  if (!DecodePngToBgra(factory.Get(), png, &width, &height, &pixels)) {
    return false;
  }
  HGLOBAL dib = BuildDibV5(width, height, pixels);
  if (dib == nullptr) {
    return false;
  }
  HGLOBAL raw_png = CopyToGlobal(png);
  if (raw_png == nullptr) {
    ::GlobalFree(dib);
    return false;
  }

  ClipboardGuard clipboard(owner);
  if (!clipboard.open()) {
    ::GlobalFree(dib);
    ::GlobalFree(raw_png);
    return false;
  }
  ::EmptyClipboard();

  // SetClipboardData takes ownership of the handle only when it succeeds; free
  // whatever it rejects. Success of either format means a paste will work, so
  // only report failure when both were rejected.
  int placed = 0;
  if (::SetClipboardData(CF_DIBV5, dib) != nullptr) {
    placed++;
  } else {
    ::GlobalFree(dib);
  }
  if (::SetClipboardData(PngClipboardFormat(), raw_png) != nullptr) {
    placed++;
  } else {
    ::GlobalFree(raw_png);
  }
  return placed > 0;
}

std::optional<std::vector<uint8_t>> ReadImageFromClipboard(HWND owner) {
  ClipboardGuard clipboard(owner);
  if (!clipboard.open()) {
    return std::nullopt;
  }

  // Prefer a lossless PNG when a source app offered one (browsers, Office).
  const UINT png_format = PngClipboardFormat();
  if (::IsClipboardFormatAvailable(png_format)) {
    HANDLE handle = ::GetClipboardData(png_format);
    if (handle != nullptr) {
      const SIZE_T size = ::GlobalSize(handle);
      void* buffer = ::GlobalLock(handle);
      if (buffer != nullptr && size > 0) {
        std::vector<uint8_t> png(static_cast<uint8_t*>(buffer),
                                 static_cast<uint8_t*>(buffer) + size);
        ::GlobalUnlock(handle);
        return png;
      }
      if (buffer != nullptr) {
        ::GlobalUnlock(handle);
      }
    }
  }

  // Otherwise fall back to a bitmap the system synthesizes from CF_DIB and
  // re-encode it as PNG. Ignore any alpha channel - pasted screenshots and
  // DDB-derived bitmaps carry a zeroed alpha that would render fully clear.
  if (::IsClipboardFormatAvailable(CF_BITMAP)) {
    HBITMAP bitmap =
        static_cast<HBITMAP>(::GetClipboardData(CF_BITMAP));
    if (bitmap != nullptr) {
      ComPtr<IWICImagingFactory> factory = CreateWicFactory();
      if (factory) {
        ComPtr<IWICBitmap> wic_bitmap;
        if (SUCCEEDED(factory->CreateBitmapFromHBITMAP(
                bitmap, nullptr, WICBitmapIgnoreAlpha, &wic_bitmap))) {
          std::vector<uint8_t> png;
          if (EncodeSourceToPng(factory.Get(), wic_bitmap.Get(), &png)) {
            return png;
          }
        }
      }
    }
  }

  return std::nullopt;
}
