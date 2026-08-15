#ifndef DARTPDF_NATIVE_WINDOWING_BOOTSTRAP_H_
#define DARTPDF_NATIVE_WINDOWING_BOOTSTRAP_H_

#ifndef DARTPDF_WINDOWING_ENABLED
#define DARTPDF_WINDOWING_ENABLED 0
#endif

namespace dart_pdf {

inline bool FlutterWindowingEnabled() {
  return DARTPDF_WINDOWING_ENABLED != 0;
}

}  // namespace dart_pdf

#endif  // DARTPDF_NATIVE_WINDOWING_BOOTSTRAP_H_
