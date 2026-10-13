cmake_minimum_required(VERSION 3.14)

# Explorer's "Combine with DartPDF" for the Store MSIX (see combine_menu.cpp).
# msix_config: context_menu in app/pubspec.yaml copies the DLL into the package
# from the fixed path below, so it is built beside the bundle, not installed
# into it: the NSIS/zip builds register a classic verb instead.
add_library(dartpdf_combine_menu SHARED
  "combine_menu.cpp"
  "combine_menu.def"
)
target_compile_features(dartpdf_combine_menu PRIVATE cxx_std_17)
target_compile_options(dartpdf_combine_menu PRIVATE /W4 /EHsc /wd4100)
target_compile_definitions(dartpdf_combine_menu PRIVATE UNICODE _UNICODE)
target_link_libraries(dartpdf_combine_menu PRIVATE runtimeobject.lib shlwapi.lib)
# `$<0:>` keeps multi-config generators from adding a Release/ or Debug/ level.
set_target_properties(dartpdf_combine_menu PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/combine_menu/$<0:>"
)
