#ifndef DARTPDF_NATIVE_WINDOWING_BOOTSTRAP_H_
#define DARTPDF_NATIVE_WINDOWING_BOOTSTRAP_H_

namespace dart_pdf {

inline bool FlutterWindowingEnabled() {
  // DartPDF enables Flutter's matching framework feature before binding
  // initialization. Desktop runners must therefore start headless every time;
  // attaching an implicit view here would make later dialogs crash.
  return true;
}

}  // namespace dart_pdf

#endif  // DARTPDF_NATIVE_WINDOWING_BOOTSTRAP_H_
