#!/usr/bin/env bash
set -euo pipefail

readonly jpeg_version=3.1.2
readonly jpeg_sha256=8f0012234b464ce50890c490f18194f913a7b1f4e6a03d6644179fa0f867d0cf
readonly expected_wasm_sha256=d61ffc6a06e3ae7dd06d60e3eb8625dab58a706320701d53fa0aa8344c1667a5
readonly recipe_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 1 ]]; then
  echo "usage: WASI_SDK_PATH=/path/to/wasi-sdk $0 /path/to/output.wasm" >&2
  exit 64
fi
: "${WASI_SDK_PATH:?Set WASI_SDK_PATH to WASI SDK 30}"

readonly output="$1"
readonly cmake_bin="${CMAKE:-cmake}"
readonly jobs="${JOBS:-4}"
readonly work_dir="$(mktemp -d "${TMPDIR:-/tmp}/dartpdf-jpeg-wasm.XXXXXX")"
trap 'rm -rf "${work_dir}"' EXIT

sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

readonly archive="${work_dir}/libjpeg-turbo.tar.gz"
curl --fail --location --silent --show-error \
  "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/${jpeg_version}/libjpeg-turbo-${jpeg_version}.tar.gz" \
  --output "${archive}"
if [[ "$(sha256 "${archive}")" != "${jpeg_sha256}" ]]; then
  echo "libjpeg-turbo source checksum mismatch" >&2
  exit 1
fi

tar -xzf "${archive}" -C "${work_dir}"
mkdir "${work_dir}/include"
cp "${recipe_dir}/setjmp.h" "${work_dir}/include/setjmp.h"

"${cmake_bin}" \
  -S "${work_dir}/libjpeg-turbo-${jpeg_version}" \
  -B "${work_dir}/build" \
  -DCMAKE_TOOLCHAIN_FILE="${WASI_SDK_PATH}/share/cmake/wasi-sdk.cmake" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_C_FLAGS="-I${work_dir}/include -flto" \
  -DENABLE_SHARED=OFF \
  -DENABLE_STATIC=ON \
  -DWITH_ARITH_ENC=OFF \
  -DWITH_JAVA=OFF \
  -DWITH_SIMD=OFF \
  -DBUILD=20260811
"${cmake_bin}" --build "${work_dir}/build" \
  --target turbojpeg-static --parallel "${jobs}"

readonly clang="${WASI_SDK_PATH}/bin/clang"
readonly sysroot="${WASI_SDK_PATH}/share/wasi-sysroot"
"${clang}" --target=wasm32-wasi --sysroot="${sysroot}" -Oz -flto \
  -c "${recipe_dir}/cmyk.c" -o "${work_dir}/cmyk.o"
"${clang}" --target=wasm32-wasi --sysroot="${sysroot}" -Oz -flto \
  -nostartfiles \
  -Wl,--no-entry \
  -Wl,--export-memory \
  -Wl,--export=malloc \
  -Wl,--export=free \
  -Wl,--export=tjInitDecompress \
  -Wl,--export=tjDecompressHeader3 \
  -Wl,--export=tjDecompress2 \
  -Wl,--export=tjDestroy \
  -Wl,--export=dartpdf_box_downsample \
  -Wl,--export=dartpdf_cmyk_to_rgba \
  -Wl,--allow-undefined \
  -Wl,--gc-sections \
  -Wl,--strip-all \
  -Wl,--lto-O3 \
  -Wl,-z,stack-size=262144 \
  -o "${output}" \
  "${work_dir}/cmyk.o" "${work_dir}/build/libturbojpeg.a"

readonly actual_wasm_sha256="$(sha256 "${output}")"
if [[ "${actual_wasm_sha256}" != "${expected_wasm_sha256}" ]]; then
  echo "WASM checksum mismatch: ${actual_wasm_sha256}" >&2
  exit 1
fi
echo "built ${output} (${actual_wasm_sha256})"
