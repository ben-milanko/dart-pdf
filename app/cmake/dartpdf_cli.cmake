# Builds the pure-Dart dartpdf CLI/MCP executable beside the Flutter runner.
# The including platform file must set DARTPDF_CLI_TARGET_OS and
# DARTPDF_CLI_OUTPUT_NAME, and must define BINARY_NAME/FLUTTER_MANAGED_DIR.

if(NOT DEFINED DARTPDF_CLI_TARGET_OS OR
   NOT DEFINED DARTPDF_CLI_OUTPUT_NAME)
  message(FATAL_ERROR "dartpdf CLI target OS and output name are required")
endif()

# generated_config.cmake is produced by `flutter build` before CMake configures
# the runner. The Flutter-managed subdirectory includes it in its own scope;
# include it here as well so this parent scope can locate the bundled Dart SDK.
include("${FLUTTER_MANAGED_DIR}/ephemeral/generated_config.cmake")

if(FLUTTER_TARGET_PLATFORM MATCHES "-arm64$")
  set(DARTPDF_CLI_TARGET_ARCH "arm64")
elseif(FLUTTER_TARGET_PLATFORM MATCHES "-x64$")
  set(DARTPDF_CLI_TARGET_ARCH "x64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
  set(DARTPDF_CLI_TARGET_ARCH "arm64")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64|AMD64)$")
  set(DARTPDF_CLI_TARGET_ARCH "x64")
else()
  message(FATAL_ERROR
    "Unsupported dartpdf CLI architecture: ${CMAKE_SYSTEM_PROCESSOR}")
endif()

get_filename_component(DARTPDF_REPOSITORY_ROOT
  "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(DARTPDF_CLI_BUILDER
  "${DARTPDF_REPOSITORY_ROOT}/tool/build_desktop_cli.dart")
set(DARTPDF_CLI_OUTPUT
  "${CMAKE_CURRENT_BINARY_DIR}/dartpdf_cli/${DARTPDF_CLI_OUTPUT_NAME}")
set(DARTPDF_EXECUTABLE
  "${FLUTTER_ROOT}/bin/cache/dart-sdk/bin/dart${CMAKE_EXECUTABLE_SUFFIX}")

# CONFIGURE_DEPENDS makes a changed CLI or engine source invalidate the native
# executable without forcing every no-op desktop build to recompile it.
file(GLOB_RECURSE DARTPDF_CLI_DART_INPUTS CONFIGURE_DEPENDS
  "${DARTPDF_REPOSITORY_ROOT}/packages/dart_pdf_cli/*.dart"
  "${DARTPDF_REPOSITORY_ROOT}/packages/pdf_cos/lib/*.dart"
  "${DARTPDF_REPOSITORY_ROOT}/packages/pdf_document/lib/*.dart"
  "${DARTPDF_REPOSITORY_ROOT}/packages/pdf_graphics/lib/*.dart")

add_custom_command(
  OUTPUT "${DARTPDF_CLI_OUTPUT}"
  COMMAND "${DARTPDF_EXECUTABLE}" "${DARTPDF_CLI_BUILDER}"
    --output "${DARTPDF_CLI_OUTPUT}"
    --target-os "${DARTPDF_CLI_TARGET_OS}"
    --target-arch "${DARTPDF_CLI_TARGET_ARCH}"
  DEPENDS
    "${DARTPDF_CLI_BUILDER}"
    "${DARTPDF_REPOSITORY_ROOT}/pubspec.yaml"
    "${DARTPDF_REPOSITORY_ROOT}/pubspec.lock"
    ${DARTPDF_CLI_DART_INPUTS}
  WORKING_DIRECTORY "${DARTPDF_REPOSITORY_ROOT}"
  COMMENT
    "Building dartpdf CLI (${DARTPDF_CLI_TARGET_OS}/${DARTPDF_CLI_TARGET_ARCH})"
  VERBATIM)

add_custom_target(dartpdf_cli ALL DEPENDS "${DARTPDF_CLI_OUTPUT}")
add_dependencies(${BINARY_NAME} dartpdf_cli)
