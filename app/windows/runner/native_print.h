#ifndef RUNNER_NATIVE_PRINT_H_
#define RUNNER_NATIVE_PRINT_H_

#include <windows.h>

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

// Prints through GDI, bypassing any PDF rasteriser (the `printing` plugin
// rendered through a bundled PDFium that crashes on some broken-but-renderable
// documents). The Dart side streams pages one at a time and End() spools
// them onto the selected printer DC. A page is either:
//
//  * a JPEG/PNG raster (AddPage), decoded with WIC and blitted - the fallback
//    path; or
//  * a **vector op stream** (AddVectorPage; see `pdf_graphics`'
//    `encodeVectorPrintPage`), replayed straight onto the printer DC as GDI
//    paths, text and image blits - crisp, selectable, and small.
//
// One job at a time per instance. Not thread-safe: keep each instance on one
// thread. Interactive printing and driver properties run on the platform/UI
// thread; non-prompting background queries use their own separate instances.
class NativePrinter {
 public:
  struct Destination {
    std::wstring name;
    bool is_default = false;
  };

  struct Options {
    std::wstring printer;
    std::optional<bool> color;
    std::optional<short> duplex;
    std::optional<short> tray;
  };

  struct Tray {
    int id;
    std::wstring name;
  };

  struct Settings {
    bool color = false;
    short duplex = DMDUP_SIMPLEX;
    int tray = DMBIN_AUTO;
    bool supports_color = false;
    bool supports_duplex = false;
    std::vector<Tray> trays;
  };

  NativePrinter() = default;

  NativePrinter(const NativePrinter&) = delete;
  NativePrinter& operator=(const NativePrinter&) = delete;

  // Starts (or restarts) a job named |document_name|, discarding any pages
  // held from a previous, unfinished job.
  bool Begin(const std::wstring& document_name,
             bool use_document_page_size, const Options& options);

  bool ListPrinters(std::vector<Destination>* printers);

  // Reads this application's saved driver settings, optionally showing only
  // the selected driver's advanced preferences. Cancel returns false with no
  // error. The whole DEVMODE, including its private tail, persists per printer.
  bool PrinterSettings(HWND owner, const Options& options, bool show_properties,
                       Settings* settings);

  const std::string& error() const { return error_; }

  // Appends one page's encoded image bytes (JPEG or PNG - WIC detects the
  // format at print time). Returns true; pages are decoded lazily in End().
  bool AddPage(const std::vector<uint8_t>& image);

  // Appends one page's vector op stream (the VPR1 format), replayed onto the
  // printer DC in End(). Returns true.
  bool AddVectorPage(const std::vector<uint8_t>& stream);

  // Spools directly when Begin received a printer, otherwise preserves the
  // legacy system dialog. False with an empty error means user cancellation;
  // failures set error(). Clears the job either way.
  bool End(HWND owner);

  // Discards the accumulated pages without printing.
  void Cancel();

 private:
  // One accumulated page: raster bytes to decode, or a vector op stream.
  struct Page {
    std::vector<uint8_t> bytes;
    bool is_vector = false;
  };

  std::wstring doc_name_;
  std::vector<Page> pages_;
  bool use_document_page_size_ = false;
  std::wstring printer_;
  std::vector<uint8_t> driver_mode_;
  std::string error_;
};

#endif  // RUNNER_NATIVE_PRINT_H_
