#include "native_print.h"

#include <commdlg.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>

using Microsoft::WRL::ComPtr;

namespace {

// Decodes encoded |bytes| (JPEG or PNG - WIC detects the container) into
// top-down 32bpp BGRA pixels. Returns false on any failure.
bool DecodeToBgra(const std::vector<uint8_t>& bytes, UINT* width, UINT* height,
                  std::vector<uint8_t>* pixels) {
  if (bytes.empty()) return false;
  ComPtr<IWICImagingFactory> factory;
  if (FAILED(::CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory)))) {
    return false;
  }
  ComPtr<IWICStream> stream;
  if (FAILED(factory->CreateStream(&stream))) return false;
  if (FAILED(stream->InitializeFromMemory(const_cast<BYTE*>(bytes.data()),
                                          static_cast<DWORD>(bytes.size())))) {
    return false;
  }
  ComPtr<IWICBitmapDecoder> decoder;
  if (FAILED(factory->CreateDecoderFromStream(
          stream.Get(), nullptr, WICDecodeMetadataCacheOnDemand, &decoder))) {
    return false;
  }
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(decoder->GetFrame(0, &frame))) return false;
  ComPtr<IWICFormatConverter> converter;
  if (FAILED(factory->CreateFormatConverter(&converter))) return false;
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

// Blits one decoded BGRA page onto the printer DC, scaled to fit the printable
// area, preserving aspect ratio and centred.
bool BlitPage(HDC hdc, UINT width, UINT height,
              const std::vector<uint8_t>& bgra) {
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = static_cast<LONG>(width);
  bmi.bmiHeader.biHeight = -static_cast<LONG>(height);  // negative => top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  const int page_w = ::GetDeviceCaps(hdc, HORZRES);
  const int page_h = ::GetDeviceCaps(hdc, VERTRES);
  const double scale = std::min(static_cast<double>(page_w) / width,
                                static_cast<double>(page_h) / height);
  const int draw_w = std::max(1, static_cast<int>(width * scale));
  const int draw_h = std::max(1, static_cast<int>(height * scale));
  const int off_x = (page_w - draw_w) / 2;
  const int off_y = (page_h - draw_h) / 2;

  if (::StartPage(hdc) <= 0) return false;
  // HALFTONE gives the best downscale; it requires the brush origin reset.
  ::SetStretchBltMode(hdc, HALFTONE);
  ::SetBrushOrgEx(hdc, 0, 0, nullptr);
  const int result = ::StretchDIBits(
      hdc, off_x, off_y, draw_w, draw_h, 0, 0, static_cast<int>(width),
      static_cast<int>(height), bgra.data(), &bmi, DIB_RGB_COLORS, SRCCOPY);
  const bool blitted = result != GDI_ERROR && result != 0;
  const bool page_ok = ::EndPage(hdc) > 0;  // must run to keep the DC sane
  return blitted && page_ok;
}

}  // namespace

void NativePrinter::Begin(const std::wstring& document_name) {
  doc_name_ = document_name;
  pages_.clear();
}

bool NativePrinter::AddPage(const std::vector<uint8_t>& image) {
  pages_.push_back(image);
  return true;
}

bool NativePrinter::End(HWND owner) {
  // Take ownership of the accumulated pages and reset first, so every return
  // path below leaves the printer idle for the next job.
  std::vector<std::vector<uint8_t>> pages;
  pages.swap(pages_);
  std::wstring name = doc_name_;
  doc_name_.clear();
  if (pages.empty()) return false;

  PRINTDLGW pd = {};
  pd.lStructSize = sizeof(pd);
  pd.hwndOwner = owner;
  pd.Flags = PD_RETURNDC | PD_NOPAGENUMS | PD_NOSELECTION |
             PD_USEDEVMODECOPIESANDCOLLATE;
  pd.nCopies = 1;
  // PrintDlg returns 0 both on cancel and on error; nothing to print either
  // way. Free anything it allocated.
  if (!::PrintDlgW(&pd)) {
    if (pd.hDC != nullptr) ::DeleteDC(pd.hDC);
    if (pd.hDevMode != nullptr) ::GlobalFree(pd.hDevMode);
    if (pd.hDevNames != nullptr) ::GlobalFree(pd.hDevNames);
    return false;
  }
  if (pd.hDevMode != nullptr) ::GlobalFree(pd.hDevMode);
  if (pd.hDevNames != nullptr) ::GlobalFree(pd.hDevNames);
  HDC hdc = pd.hDC;
  if (hdc == nullptr) return false;

  DOCINFOW di = {};
  di.cbSize = sizeof(di);
  di.lpszDocName = name.empty() ? L"Document" : name.c_str();
  if (::StartDocW(hdc, &di) <= 0) {
    ::DeleteDC(hdc);
    return false;
  }

  bool ok = true;
  for (const auto& page : pages) {
    UINT w = 0;
    UINT h = 0;
    std::vector<uint8_t> bgra;
    if (!DecodeToBgra(page, &w, &h, &bgra)) {
      ok = false;
      continue;  // skip an undecodable page rather than abort the whole job
    }
    if (!BlitPage(hdc, w, h, bgra)) ok = false;
  }

  const bool ended = ::EndDoc(hdc) > 0;
  ::DeleteDC(hdc);
  return ok && ended;
}

void NativePrinter::Cancel() {
  doc_name_.clear();
  pages_.clear();
}
