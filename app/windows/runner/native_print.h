#ifndef RUNNER_NATIVE_PRINT_H_
#define RUNNER_NATIVE_PRINT_H_

#include <windows.h>

#include <cstdint>
#include <string>
#include <vector>

// Prints page rasters through GDI, bypassing any PDF rasteriser (the
// `printing` plugin rendered through a bundled PDFium that crashes on some
// broken-but-renderable documents). The Dart side streams one JPEG-encoded
// page at a time; End() shows the print dialog and spools the accumulated
// pages, decoding each with WIC and blitting it onto the printer DC.
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

  // Shows the print dialog (modal to |owner|) and, if confirmed, spools every
  // accumulated page. Returns false when the user cancels, there is nothing to
  // print, or spooling fails. Clears the job either way.
  bool End(HWND owner);

  // Discards the accumulated pages without printing.
  void Cancel();

 private:
  std::wstring doc_name_;
  std::vector<std::vector<uint8_t>> pages_;
};

#endif  // RUNNER_NATIVE_PRINT_H_
