#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."
src=tool/gpu_shaders
out=assets/shaders/pdf_tile_gpu.shaderbundle

if [[ -z "${FLUTTER_ROOT:-}" ]]; then
  fvm_version=$(sed -n 's/.*"flutter": *"\([0-9.]*\)".*/\1/p' ../../.fvmrc)
  FLUTTER_ROOT="$HOME/fvm/versions/$fvm_version"
fi

host_arch=$(uname -m)
case "$host_arch" in
  arm64) artifact=darwin-arm64 ;;
  *) artifact=darwin-x64 ;;
esac
impellerc="$FLUTTER_ROOT/bin/cache/artifacts/engine/$artifact/impellerc"
if [[ ! -x "$impellerc" ]]; then
  # FVM installations can carry translated x64 engine tools on Apple Silicon.
  impellerc="$FLUTTER_ROOT/bin/cache/artifacts/engine/darwin-x64/impellerc"
fi
if [[ ! -x "$impellerc" ]]; then
  echo "impellerc not found under $FLUTTER_ROOT/bin/cache/artifacts/engine" >&2
  exit 1
fi

bundle=$(cat <<EOF
{
  "PdfTileStencilVertex":  {"type":"vertex",   "file":"$src/pdf_tile_stencil.vert"},
  "PdfTileStencilFragment":{"type":"fragment", "file":"$src/pdf_tile_stencil.frag"},
  "PdfTileSolidVertex":    {"type":"vertex",   "file":"$src/pdf_tile_solid.vert"},
  "PdfTileSolidFragment":  {"type":"fragment", "file":"$src/pdf_tile_solid.frag"},
  "PdfTileTextureVertex":  {"type":"vertex",   "file":"$src/pdf_tile_texture.vert"},
  "PdfTileTextureFragment":{"type":"fragment", "file":"$src/pdf_tile_texture.frag"},
  "PdfTileSoftMaskVertex":  {"type":"vertex",   "file":"$src/pdf_tile_soft_mask.vert"},
  "PdfTileSoftMaskFragment":{"type":"fragment", "file":"$src/pdf_tile_soft_mask.frag"},
  "PdfTileDestinationBlendVertex":  {"type":"vertex",   "file":"$src/pdf_tile_destination_blend.vert"},
  "PdfTileDestinationBlendFragment":{"type":"fragment", "file":"$src/pdf_tile_destination_blend.frag"}
}
EOF
)

mkdir -p assets/shaders
"$impellerc" \
  --runtime-stage-metal \
  --runtime-stage-gles \
  --runtime-stage-gles3 \
  --runtime-stage-vulkan \
  --sl="$out" \
  --shader-bundle="$bundle"

echo "wrote $out"
