#ifndef RUNNER_LONG_PATHS_H_
#define RUNNER_LONG_PATHS_H_

// Spelling conversions for Windows paths longer than MAX_PATH (260 chars).
// Win32 file APIs only accept such paths in the extended-length `\\?\` form
// (unless the user turned on the LongPathsEnabled policy), and Explorer may
// hand a long path to an app as its 8.3 short alias instead. These are the
// pure string halves of turning that alias back into the real path; the
// GetLongPathNameW call lives in main.cpp. Kept free of <windows.h> so the
// logic can be unit-tested on any host.

#include <string>

namespace dart_pdf {

// The `\\?\` form of an absolute |path| (`C:\...` or a `\\server\share` UNC
// path), with forward slashes turned into backslashes because the
// extended-length form does no normalisation of its own. Returns an empty
// string for anything else - a relative path, or one already in a `\\?\` /
// `\\.\` device form - so the caller leaves it alone.
inline std::wstring ExtendedLengthPath(std::wstring path) {
  for (wchar_t& c : path) {
    if (c == L'/') c = L'\\';
  }
  if (path.size() >= 3 && path[1] == L':' && path[2] == L'\\' &&
      ((path[0] >= L'A' && path[0] <= L'Z') ||
       (path[0] >= L'a' && path[0] <= L'z'))) {
    return L"\\\\?\\" + path;
  }
  if (path.size() > 2 && path[0] == L'\\' && path[1] == L'\\' &&
      path[2] != L'?' && path[2] != L'.' && path[2] != L'\\') {
    return L"\\\\?\\UNC\\" + path.substr(2);
  }
  return std::wstring();
}

// Undoes ExtendedLengthPath: `\\?\UNC\server\share` -> `\\server\share`,
// `\\?\C:\...` -> `C:\...`. Anything else comes back unchanged.
inline std::wstring StripExtendedLengthPrefix(const std::wstring& path) {
  static const std::wstring kUnc = L"\\\\?\\UNC\\";
  static const std::wstring kPrefix = L"\\\\?\\";
  if (path.compare(0, kUnc.size(), kUnc) == 0) {
    return L"\\\\" + path.substr(kUnc.size());
  }
  if (path.compare(0, kPrefix.size(), kPrefix) == 0) {
    return path.substr(kPrefix.size());
  }
  return path;
}

}  // namespace dart_pdf

#endif  // RUNNER_LONG_PATHS_H_
