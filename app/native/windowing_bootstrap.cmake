# Converts Flutter's generated DART_DEFINES into one native compile-time bit.
# Dart receives the defines automatically; the runner needs the windowing bit
# before engine startup to choose between implicit-view and headless modes.
set(DART_PDF_WINDOWING_BOOTSTRAP_DIR "${CMAKE_CURRENT_LIST_DIR}")

function(dart_pdf_embed_flutter_feature_flags target)
  set(generated_config
    "${FLUTTER_MANAGED_DIR}/ephemeral/generated_config.cmake")
  set(encoded_defines "")
  if(EXISTS "${generated_config}")
    file(STRINGS "${generated_config}" define_lines
      REGEX "^[ \t]*\"DART_DEFINES=")
    if(define_lines)
      list(GET define_lines 0 encoded_defines)
      string(REGEX REPLACE "^[ \t]*\"DART_DEFINES=" ""
        encoded_defines "${encoded_defines}")
      string(REGEX REPLACE "\"[ \t]*$" ""
        encoded_defines "${encoded_defines}")
    endif()
  endif()

  if(WIN32)
    execute_process(
      COMMAND powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass
        -File "${DART_PDF_WINDOWING_BOOTSTRAP_DIR}/windowing_feature_flag.ps1"
        "${encoded_defines}"
      RESULT_VARIABLE detector_result
      OUTPUT_VARIABLE windowing_enabled
      ERROR_VARIABLE detector_error)
  else()
    execute_process(
      COMMAND /bin/sh
        "${DART_PDF_WINDOWING_BOOTSTRAP_DIR}/windowing_feature_flag.sh"
        "${encoded_defines}"
      RESULT_VARIABLE detector_result
      OUTPUT_VARIABLE windowing_enabled
      ERROR_VARIABLE detector_error)
  endif()

  string(STRIP "${windowing_enabled}" windowing_enabled)
  if(NOT detector_result EQUAL 0 OR
      NOT windowing_enabled MATCHES "^[01]$")
    message(FATAL_ERROR
      "Could not detect Flutter's windowing feature: ${detector_error}")
  endif()
  target_compile_definitions(${target} PRIVATE
    "DARTPDF_WINDOWING_ENABLED=${windowing_enabled}")
endfunction()
