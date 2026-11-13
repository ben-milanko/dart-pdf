/// Whether every entry of [indices] addresses one of [vertexCount] vertices.
///
/// Flutter 3.50's web engine runs this check on every `ui.Vertices` (CanvasKit
/// and Skwasm alike) and throws past it; 3.47's CanvasKit accepted indices up
/// to twice the vertex count and Skwasm checked nothing. Our mesh and strip
/// builders stay in range by construction, so callers only `assert` it (#1275).
bool pdfVertexIndicesInRange(List<int> indices, int vertexCount) {
  for (final i in indices) {
    if (i < 0 || i >= vertexCount) return false;
  }
  return true;
}
