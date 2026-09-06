#ifndef DARTPDF_NATIVE_WINDOWING_BOOTSTRAP_H_
#define DARTPDF_NATIVE_WINDOWING_BOOTSTRAP_H_

namespace dart_pdf {

inline bool FlutterWindowingEnabled() {
#if defined(__linux__)
  // Linux GTK plugins (such as desktop_drop) assume a non-null FlView during
  // fl_register_plugins. Headless engine bootstrap causes desktop_drop's
  // gtk_drag_dest_set to fail on a null widget and prevents window creation.
  return false;
#else
  // DartPDF enables Flutter's matching framework feature before binding
  // initialization. Desktop runners must therefore start headless every time;
  // attaching an implicit view here would make later dialogs crash.
  return true;
#endif
}

}  // namespace dart_pdf

#endif  // DARTPDF_NATIVE_WINDOWING_BOOTSTRAP_H_
