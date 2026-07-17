#include "native_print.h"

#include <commdlg.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <cstring>

using Microsoft::WRL::ComPtr;

namespace {

// ---------------------------------------------------------------------------
// Vector op stream (VPR1) replay onto a printer DC.
//
// The stream is produced by pdf_graphics' encodeVectorPrintPage: geometry is
// in device points (top-left origin, y down, 1 unit = 1 PDF point) with the
// page's /Rotate and crop already folded in. We map points to printer pixels
// with a single fit-and-centre transform and issue GDI paths/text/blits. See
// the format spec on encodeVectorPrintPage.
// ---------------------------------------------------------------------------

// A little-endian cursor over the op stream. Every reader bounds-checks and
// flips `ok` false on overrun, so a truncated/corrupt buffer aborts cleanly.
struct StreamReader {
  const uint8_t* p;
  const uint8_t* end;
  bool ok = true;

  bool Remaining(size_t n) {
    if (static_cast<size_t>(end - p) < n) {
      ok = false;
      return false;
    }
    return true;
  }
  uint8_t U8() {
    if (!Remaining(1)) return 0;
    return *p++;
  }
  uint16_t U16() {
    if (!Remaining(2)) return 0;
    uint16_t v = static_cast<uint16_t>(p[0] | (p[1] << 8));
    p += 2;
    return v;
  }
  uint32_t U32() {
    if (!Remaining(4)) return 0;
    uint32_t v = static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
                 (static_cast<uint32_t>(p[2]) << 16) |
                 (static_cast<uint32_t>(p[3]) << 24);
    p += 4;
    return v;
  }
  float F32() {
    uint32_t bits = U32();
    float v;
    std::memcpy(&v, &bits, sizeof(v));
    return v;
  }
};

// The points->pixels transform: uniform fit scale plus centring offset.
struct DeviceTransform {
  double scale;
  double off_x;
  double off_y;
  LONG X(double x) const { return static_cast<LONG>(std::lround(x * scale + off_x)); }
  LONG Y(double y) const { return static_cast<LONG>(std::lround(y * scale + off_y)); }
};

COLORREF ReadRgb(StreamReader* r, uint8_t* alpha) {
  uint8_t red = r->U8();
  uint8_t green = r->U8();
  uint8_t blue = r->U8();
  *alpha = r->U8();
  return RGB(red, green, blue);
}

// Reads a path and emits it as the current GDI path (BeginPath..EndPath must
// bracket the caller). Coordinates are transformed to pixels.
void ReadPathInto(StreamReader* r, HDC hdc, const DeviceTransform& t) {
  const uint32_t count = r->U32();
  for (uint32_t i = 0; i < count && r->ok; i++) {
    switch (r->U8()) {
      case 0: {  // move
        double x = r->F32();
        double y = r->F32();
        ::MoveToEx(hdc, t.X(x), t.Y(y), nullptr);
        break;
      }
      case 1: {  // line
        double x = r->F32();
        double y = r->F32();
        ::LineTo(hdc, t.X(x), t.Y(y));
        break;
      }
      case 2: {  // cubic
        POINT pts[3];
        for (int k = 0; k < 3; k++) {
          double x = r->F32();
          double y = r->F32();
          pts[k].x = t.X(x);
          pts[k].y = t.Y(y);
        }
        ::PolyBezierTo(hdc, pts, 3);
        break;
      }
      case 3:  // close
        ::CloseFigure(hdc);
        break;
      default:
        r->ok = false;
        break;
    }
  }
}

// Skips a path without drawing (used to stay in sync when we drop an op).
void SkipPath(StreamReader* r) {
  const uint32_t count = r->U32();
  for (uint32_t i = 0; i < count && r->ok; i++) {
    switch (r->U8()) {
      case 0:
      case 1:
        r->F32();
        r->F32();
        break;
      case 2:
        for (int k = 0; k < 6; k++) r->F32();
        break;
      case 3:
        break;
      default:
        r->ok = false;
        break;
    }
  }
}

void ReplayFill(StreamReader* r, HDC hdc, const DeviceTransform& t) {
  uint8_t alpha = 255;
  COLORREF color = ReadRgb(r, &alpha);
  const bool even_odd = r->U8() == 1;
  if (alpha == 0) {  // fully transparent - consume the path, draw nothing
    SkipPath(r);
    return;
  }
  ::SetPolyFillMode(hdc, even_odd ? ALTERNATE : WINDING);
  ::BeginPath(hdc);
  ReadPathInto(r, hdc, t);
  ::EndPath(hdc);
  HBRUSH brush = ::CreateSolidBrush(color);
  HGDIOBJ old = ::SelectObject(hdc, brush);
  ::FillPath(hdc);
  ::SelectObject(hdc, old);
  ::DeleteObject(brush);
}

void ReplayStroke(StreamReader* r, HDC hdc, const DeviceTransform& t) {
  uint8_t alpha = 255;
  COLORREF color = ReadRgb(r, &alpha);
  const double width = r->F32();
  const uint8_t cap = r->U8();
  const uint8_t join = r->U8();
  r->F32();  // miter limit - GDI uses SetMiterLimit; default is fine for print
  const uint16_t dash_count = r->U16();
  for (uint16_t i = 0; i < dash_count; i++) r->F32();  // dashes: solid fallback
  r->F32();                                            // dash phase
  if (alpha == 0) {
    SkipPath(r);
    return;
  }
  ::BeginPath(hdc);
  ReadPathInto(r, hdc, t);
  ::EndPath(hdc);

  DWORD pen_style = PS_GEOMETRIC | PS_SOLID;
  pen_style |= (cap == 1) ? PS_ENDCAP_ROUND
                          : (cap == 2 ? PS_ENDCAP_SQUARE : PS_ENDCAP_FLAT);
  pen_style |= (join == 1) ? PS_JOIN_ROUND
                           : (join == 2 ? PS_JOIN_BEVEL : PS_JOIN_MITER);
  int pixel_width = static_cast<int>(std::lround(width * t.scale));
  if (pixel_width < 1) pixel_width = 1;  // a hairline still prints as one pixel
  LOGBRUSH lb = {};
  lb.lbStyle = BS_SOLID;
  lb.lbColor = color;
  HPEN pen = ::ExtCreatePen(pen_style, static_cast<DWORD>(pixel_width), &lb, 0,
                            nullptr);
  HGDIOBJ old = ::SelectObject(hdc, pen);
  ::StrokePath(hdc);
  ::SelectObject(hdc, old);
  ::DeleteObject(pen);
}

void ReplayClip(StreamReader* r, HDC hdc, const DeviceTransform& t) {
  const bool even_odd = r->U8() == 1;
  ::SetPolyFillMode(hdc, even_odd ? ALTERNATE : WINDING);
  ::BeginPath(hdc);
  ReadPathInto(r, hdc, t);
  ::EndPath(hdc);
  ::SelectClipPath(hdc, RGN_AND);
}

void ReplayText(StreamReader* r, HDC hdc, const DeviceTransform& t) {
  uint8_t alpha = 255;
  COLORREF color = ReadRgb(r, &alpha);
  const uint8_t flags = r->U8();
  double m[6];
  for (int i = 0; i < 6; i++) m[i] = r->F32();
  r->F32();  // nominal font size - we derive the on-page size from the matrix
  const uint16_t len = r->U16();
  if (!r->Remaining(len)) return;
  const char* utf8 = reinterpret_cast<const char*>(r->p);
  const int utf8_len = static_cast<int>(len);
  r->p += len;
  if (alpha == 0 || len == 0) return;

  // The matrix maps em space (1.0 = font size) to device points. The em height
  // on the page is the length of the y-basis; the baseline sits at (e, f), and
  // the run's rotation is the angle of the x-basis.
  const double a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5];
  const double em_height = std::hypot(c, d);
  const double angle = std::atan2(b, a);  // radians, GDI counts anti-clockwise
  int height_px = static_cast<int>(std::lround(em_height * t.scale));
  if (height_px < 1) height_px = 1;

  int wide_len = ::MultiByteToWideChar(CP_UTF8, 0, utf8, utf8_len, nullptr, 0);
  if (wide_len <= 0) return;
  std::wstring wide(static_cast<size_t>(wide_len), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8, utf8_len, &wide[0], wide_len);

  LOGFONTW lf = {};
  lf.lfHeight = -height_px;  // negative = character height (cell minus leading)
  lf.lfWeight = (flags & 0x01) ? FW_BOLD : FW_NORMAL;
  lf.lfItalic = (flags & 0x02) ? TRUE : FALSE;
  // Escapement/orientation are in tenths of a degree, measured anti-clockwise.
  const int tenths = static_cast<int>(std::lround(-angle * 1800.0 / 3.14159265358979));
  lf.lfEscapement = tenths;
  lf.lfOrientation = tenths;
  lf.lfCharSet = DEFAULT_CHARSET;
  lf.lfOutPrecision = OUT_TT_PRECIS;  // prefer a scalable (TrueType) face
  wcscpy_s(lf.lfFaceName, L"Arial");

  HFONT font = ::CreateFontIndirectW(&lf);
  HGDIOBJ old_font = ::SelectObject(hdc, font);
  const UINT old_align = ::SetTextAlign(hdc, TA_LEFT | TA_BASELINE | TA_NOUPDATECP);
  ::SetBkMode(hdc, TRANSPARENT);
  ::SetTextColor(hdc, color);
  ::TextOutW(hdc, t.X(e), t.Y(f), wide.c_str(), wide_len);
  ::SetTextAlign(hdc, old_align);
  ::SelectObject(hdc, old_font);
  ::DeleteObject(font);
}

void ReplayImage(StreamReader* r, HDC hdc, const DeviceTransform& t) {
  double m[6];
  for (int i = 0; i < 6; i++) m[i] = r->F32();
  const uint32_t w = r->U32();
  const uint32_t h = r->U32();
  const size_t pixels = static_cast<size_t>(w) * h * 4;
  if (w == 0 || h == 0 || !r->Remaining(pixels)) {
    return;  // Remaining() has flagged any overrun; nothing safe to draw
  }
  const uint8_t* rgba = r->p;
  r->p += pixels;

  // The transform maps the unit square (image space, y-up) to device points.
  // Map its four corners; when it is axis-aligned (the common case) we blit
  // into the bounding rectangle, honouring a vertical flip.
  auto mapX = [&](double x, double y) { return m[0] * x + m[2] * y + m[4]; };
  auto mapY = [&](double x, double y) { return m[1] * x + m[3] * y + m[5]; };
  double xs[4] = {mapX(0, 0), mapX(1, 0), mapX(1, 1), mapX(0, 1)};
  double ys[4] = {mapY(0, 0), mapY(1, 0), mapY(1, 1), mapY(0, 1)};
  double min_x = xs[0], max_x = xs[0], min_y = ys[0], max_y = ys[0];
  for (int i = 1; i < 4; i++) {
    min_x = std::min(min_x, xs[i]);
    max_x = std::max(max_x, xs[i]);
    min_y = std::min(min_y, ys[i]);
    max_y = std::max(max_y, ys[i]);
  }
  const LONG dst_x = t.X(min_x);
  const LONG dst_y = t.Y(min_y);
  const LONG dst_w = t.X(max_x) - dst_x;
  const LONG dst_h = t.Y(max_y) - dst_y;
  if (dst_w == 0 || dst_h == 0) return;

  // Our rows are top-down RGBA; StretchDIBits wants BGRA. Repack into a scratch
  // buffer (also drops premultiplication is unnecessary - printers are opaque).
  std::vector<uint8_t> bgra(pixels);
  for (size_t i = 0; i < static_cast<size_t>(w) * h; i++) {
    bgra[i * 4 + 0] = rgba[i * 4 + 2];
    bgra[i * 4 + 1] = rgba[i * 4 + 1];
    bgra[i * 4 + 2] = rgba[i * 4 + 0];
    bgra[i * 4 + 3] = rgba[i * 4 + 3];
  }
  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = static_cast<LONG>(w);
  bmi.bmiHeader.biHeight = -static_cast<LONG>(h);  // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;
  ::SetStretchBltMode(hdc, HALFTONE);
  ::SetBrushOrgEx(hdc, 0, 0, nullptr);
  ::StretchDIBits(hdc, dst_x, dst_y, dst_w, dst_h, 0, 0, static_cast<int>(w),
                  static_cast<int>(h), bgra.data(), &bmi, DIB_RGB_COLORS,
                  SRCCOPY);
}

// Replays one page's op stream onto |hdc| between StartPage/EndPage. Returns
// false only when the page could not be started or ended (a decode error in
// the middle still runs EndPage to keep the DC sane).
bool RenderVectorPage(HDC hdc, const std::vector<uint8_t>& stream) {
  StreamReader r{stream.data(), stream.data() + stream.size()};
  // Header: magic 'V' 'P' 'R' 1, then f32 page width/height in points.
  if (r.U8() != 'V' || r.U8() != 'P' || r.U8() != 'R' || r.U8() != 1) {
    return false;
  }
  const double page_w = r.F32();
  const double page_h = r.F32();
  if (!r.ok || page_w <= 0 || page_h <= 0) return false;

  const int res_x = ::GetDeviceCaps(hdc, HORZRES);
  const int res_y = ::GetDeviceCaps(hdc, VERTRES);
  const int dpi_x = ::GetDeviceCaps(hdc, LOGPIXELSX);
  const int dpi_y = ::GetDeviceCaps(hdc, LOGPIXELSY);
  // Page size in printer pixels, then fit into the printable area.
  const double page_px_w = page_w / 72.0 * dpi_x;
  const double page_px_h = page_h / 72.0 * dpi_y;
  const double fit = std::min(res_x / page_px_w, res_y / page_px_h);
  DeviceTransform t;
  t.scale = dpi_x / 72.0 * fit;  // points -> pixels (isotropic; dpi_x≈dpi_y)
  t.off_x = (res_x - page_px_w * fit) / 2.0;
  t.off_y = (res_y - page_px_h * fit) / 2.0;

  if (::StartPage(hdc) <= 0) return false;
  ::SetGraphicsMode(hdc, GM_ADVANCED);
  while (r.ok && r.p < r.end) {
    const uint8_t op = r.U8();
    switch (op) {
      case 0x01:
        ::SaveDC(hdc);
        break;
      case 0x02:
        ::RestoreDC(hdc, -1);
        break;
      case 0x10:
        ReplayFill(&r, hdc, t);
        break;
      case 0x11:
        ReplayStroke(&r, hdc, t);
        break;
      case 0x12:
        ReplayClip(&r, hdc, t);
        break;
      case 0x20:
        ReplayText(&r, hdc, t);
        break;
      case 0x30:
        ReplayImage(&r, hdc, t);
        break;
      default:
        r.ok = false;  // unknown op: stop rather than misread the rest
        break;
    }
  }
  const bool page_ok = ::EndPage(hdc) > 0;
  return page_ok;
}

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
  pages_.push_back(Page{image, false});
  return true;
}

bool NativePrinter::AddVectorPage(const std::vector<uint8_t>& stream) {
  pages_.push_back(Page{stream, true});
  return true;
}

bool NativePrinter::End(HWND owner) {
  // Take ownership of the accumulated pages and reset first, so every return
  // path below leaves the printer idle for the next job.
  std::vector<Page> pages;
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
    if (page.is_vector) {
      if (!RenderVectorPage(hdc, page.bytes)) ok = false;
      continue;
    }
    UINT w = 0;
    UINT h = 0;
    std::vector<uint8_t> bgra;
    if (!DecodeToBgra(page.bytes, &w, &h, &bgra)) {
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
