#!/usr/bin/env bash
# Compiles the flutter_gpu shader bundle for the experimental GPU render
# backend (lib/src/gpu/). Run from packages/dart_pdf_editor:
#
#   tool/gpu_shaders/build.sh
#
# Writes assets/shaders/pdf_gpu.shaderbundle, which is checked in so
# consumers never need impellerc. Targets the Metal runtime stage (the
# experiment runs on macOS); add --runtime-stage-gles/--runtime-stage-vulkan
# here if the backend ever leaves the lab.
set -euo pipefail

cd "$(dirname "$0")/../.."
src=tool/gpu_shaders
out=assets/shaders/pdf_gpu.shaderbundle

if [[ -z "${FLUTTER_ROOT:-}" ]]; then
  fvm_version=$(sed -n 's/.*"flutter": *"\([0-9.]*\)".*/\1/p' ../../.fvmrc)
  FLUTTER_ROOT="$HOME/fvm/versions/$fvm_version"
fi
impellerc="$FLUTTER_ROOT/bin/cache/artifacts/engine/darwin-x64/impellerc"
if [[ ! -x "$impellerc" ]]; then
  echo "impellerc not found at $impellerc (set FLUTTER_ROOT)" >&2
  exit 1
fi

bundle=$(cat <<EOF
{
  "PdfStencilVertex":  {"type": "vertex",   "file": "$src/pdf_stencil.vert"},
  "PdfStencilFragment":{"type": "fragment", "file": "$src/pdf_stencil.frag"},
  "PdfSolidVertex":    {"type": "vertex",   "file": "$src/pdf_solid.vert"},
  "PdfSolidFragment":  {"type": "fragment", "file": "$src/pdf_solid.frag"},
  "PdfTextureVertex":  {"type": "vertex",   "file": "$src/pdf_texture.vert"},
  "PdfTextureFragment":{"type": "fragment", "file": "$src/pdf_texture.frag"},
  "PdfGradientVertex": {"type": "vertex",   "file": "$src/pdf_gradient.vert"},
  "PdfGradientFragment":{"type": "fragment","file": "$src/pdf_gradient.frag"},
  "PdfStripVertex":    {"type": "vertex",   "file": "$src/pdf_strip.vert"},
  "PdfStripFragment":  {"type": "fragment", "file": "$src/pdf_strip.frag"}
}
EOF
)

"$impellerc" --runtime-stage-metal --sl="$out" --shader-bundle="$bundle"
echo "wrote $out"
