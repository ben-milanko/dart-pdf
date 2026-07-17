#ifndef RUNNER_NATIVE_PRINT_H_
#define RUNNER_NATIVE_PRINT_H_

#include <windows.h>

#include <cstdint>
#include <string>
#include <vector>

// Prints through GDI, bypassing any PDF rasteriser (the `printing` plugin
// rendered through a bundled PDFium that crashes on some broken-but-renderable
// documents). The Dart side streams pages one at a time and End() shows the
// print dialog and spools them onto the printer DC. A page is either:
//
//  * a JPEG/PNG raster (AddPage), decoded with WIC and blitted - the fallback
//    path; or
//  * a **vector op stream** (AddVectorPage; see `pdf_graphics`'
//    `encodeVectorPrintPage`), replayed straight onto the printer DC as GDI
//    paths, text and image blits - crisp, selectable, and small.
//
// One job at a time. Not thread-safe: every method must run on the UI thread
// (the Flutter platform thread), where the method-channel handler runs and
// where the modal print dialog belongs.
class NativePrinter {
 public:
  NativePrinter() = default;

  NativePrinter(const NativePrinter&) = delete;
  NativePrinter& operator=(const NativePrinter&) = delete;

  // Starts (or restarts) a job named |document_name|, discarding any pages
  // held from a previous, unfinished job.
  void Begin(const std::wstring& document_name);

  // Appends one page's encoded image bytes (JPEG or PNG - WIC detects the
  // format at print time). Returns true; pages are decoded lazily in End().
  bool AddPage(const std::vector<uint8_t>& image);

  // Appends one page's vector op stream (the VPR1 format), replayed onto the
  // printer DC in End(). Returns true.
  bool AddVectorPage(const std::vector<uint8_t>& stream);

  // Shows the print dialog (modal to |owner|) and, if confirmed, spools every
  // accumulated page. Returns false when the user cancels, there is nothing to
  // print, or spooling fails. Clears the job either way.
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
};

#endif  // RUNNER_NATIVE_PRINT_H_
