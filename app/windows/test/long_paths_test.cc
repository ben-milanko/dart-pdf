// Host-portable unit test for runner/long_paths.h (the path spelling behind
// opening PDFs past MAX_PATH). Built and run by CI's linux job:
//   g++ -std=c++17 app/windows/test/long_paths_test.cc && ./a.out
#include "../runner/long_paths.h"
#undef NDEBUG
#include <cassert>
#include <cstdio>
using namespace dart_pdf;
int main(){
  // drive-letter paths, either slash, either case
  assert(ExtendedLengthPath(L"C:\\Users\\me\\a.pdf") == L"\\\\?\\C:\\Users\\me\\a.pdf");
  assert(ExtendedLengthPath(L"d:/docs/a.pdf") == L"\\\\?\\d:\\docs\\a.pdf");
  // UNC shares
  assert(ExtendedLengthPath(L"\\\\server\\share\\a.pdf") == L"\\\\?\\UNC\\server\\share\\a.pdf");
  assert(ExtendedLengthPath(L"//server/share/a.pdf") == L"\\\\?\\UNC\\server\\share\\a.pdf");
  // left alone: relative, drive-relative, already extended, device paths
  assert(ExtendedLengthPath(L"a.pdf").empty());
  assert(ExtendedLengthPath(L"docs\\a.pdf").empty());
  assert(ExtendedLengthPath(L"C:a.pdf").empty());
  assert(ExtendedLengthPath(L"\\docs\\a.pdf").empty());
  assert(ExtendedLengthPath(L"\\\\?\\C:\\a.pdf").empty());
  assert(ExtendedLengthPath(L"\\\\.\\C:\\a.pdf").empty());
  assert(ExtendedLengthPath(L"\\\\").empty());
  assert(ExtendedLengthPath(L"").empty());
  // a path well past MAX_PATH survives intact
  std::wstring deep = L"C:";
  while (deep.size() < 600) deep += L"\\Very long folder name";
  deep += L"\\a.pdf";
  assert(ExtendedLengthPath(deep) == L"\\\\?\\" + deep);
  assert(StripExtendedLengthPrefix(ExtendedLengthPath(deep)) == deep);
  // round trips and pass-through
  assert(StripExtendedLengthPrefix(L"\\\\?\\C:\\a.pdf") == L"C:\\a.pdf");
  assert(StripExtendedLengthPrefix(L"\\\\?\\UNC\\server\\share\\a.pdf") == L"\\\\server\\share\\a.pdf");
  assert(StripExtendedLengthPrefix(L"C:\\a.pdf") == L"C:\\a.pdf");
  assert(StripExtendedLengthPrefix(L"\\\\server\\share") == L"\\\\server\\share");
  std::puts("long_paths ok");
  return 0;
}
