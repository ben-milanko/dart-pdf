#ifndef RUNNER_DIB_PIXELS_H_
#define RUNNER_DIB_PIXELS_H_

// Pure pixel decoding for packed clipboard DIBs (the CF_DIB payload: a
// BITMAPINFOHEADER, optional bitfield masks / colour table, then the rows).
// Kept free of <windows.h> so the logic can be unit-tested on any host.

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

namespace dart_pdf {

struct DibImage {
  uint32_t width = 0;
  uint32_t height = 0;
  // Top-down, straight (non-premultiplied) BGRA.
  std::vector<uint8_t> bgra;
  // False when every pixel is opaque (including DIBs whose alpha byte is
  // all zero - screenshots and DDB-derived bitmaps leave it unused).
  bool has_alpha = false;
};

namespace dib_detail {

inline uint32_t ReadU32(const uint8_t* p) {
  return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) |
         (static_cast<uint32_t>(p[3]) << 24);
}

inline uint16_t ReadU16(const uint8_t* p) {
  return static_cast<uint16_t>(p[0] | (p[1] << 8));
}

}  // namespace dib_detail

// Decodes an uncompressed 32bpp packed DIB in the standard B,G,R,A byte
// order. Returns nullopt for any other layout (the caller falls back to the
// system's CF_BITMAP conversion for those).
//
// Browsers and Office put transparent images on the clipboard as 32bpp DIBs
// whose fourth byte is real alpha, usually premultiplied, with transparent
// pixels stored as 0,0,0,0. Dropping that alpha turns the transparent
// background black, so a dark drawing on a transparent background pastes as
// light-on-black - it looks colour-inverted. This keeps the alpha:
// - all-zero alpha means the byte is unused, so the image is opaque;
// - when every colour channel is <= its alpha the data is premultiplied
//   (straight data with partial alpha almost never satisfies that), and is
//   un-premultiplied so PNG (straight alpha) gets the true colours.
inline std::optional<DibImage> DecodePackedDib32(const uint8_t* data,
                                                 size_t size) {
  using dib_detail::ReadU16;
  using dib_detail::ReadU32;
  constexpr uint32_t kBiRgb = 0;
  constexpr uint32_t kBiBitfields = 3;
  constexpr size_t kInfoHeaderSize = 40;

  if (data == nullptr || size < kInfoHeaderSize) return std::nullopt;
  const uint32_t header_size = ReadU32(data);
  if (header_size < kInfoHeaderSize || header_size > size) return std::nullopt;
  const int32_t width = static_cast<int32_t>(ReadU32(data + 4));
  const int32_t raw_height = static_cast<int32_t>(ReadU32(data + 8));
  const uint16_t bit_count = ReadU16(data + 14);
  const uint32_t compression = ReadU32(data + 16);
  const uint32_t colors_used = ReadU32(data + 32);
  if (bit_count != 32 || width <= 0 || raw_height == 0 ||
      raw_height == INT32_MIN) {
    return std::nullopt;
  }
  if (compression != kBiRgb && compression != kBiBitfields) {
    return std::nullopt;
  }

  size_t offset = header_size;
  if (compression == kBiBitfields) {
    // A plain BITMAPINFOHEADER carries the three masks after it; V2+ headers
    // (52+ bytes) carry them inside.
    const size_t masks_at = header_size >= 52 ? 40 : header_size;
    if (masks_at + 12 > size) return std::nullopt;
    if (ReadU32(data + masks_at) != 0x00FF0000u ||
        ReadU32(data + masks_at + 4) != 0x0000FF00u ||
        ReadU32(data + masks_at + 8) != 0x000000FFu) {
      return std::nullopt;
    }
    if (header_size < 52) offset += 12;
  }
  if (colors_used > (size - offset) / 4) return std::nullopt;
  offset += static_cast<size_t>(colors_used) * 4;

  const bool bottom_up = raw_height > 0;
  const uint32_t w = static_cast<uint32_t>(width);
  const uint32_t h =
      static_cast<uint32_t>(bottom_up ? raw_height : -raw_height);
  const size_t stride = static_cast<size_t>(w) * 4;
  if (stride / 4 != w || offset > size || h > (size - offset) / stride) {
    return std::nullopt;
  }

  DibImage image;
  image.width = w;
  image.height = h;
  image.bgra.resize(stride * h);
  const uint8_t* rows = data + offset;
  for (uint32_t y = 0; y < h; y++) {
    const uint8_t* src = rows + stride * (bottom_up ? h - 1 - y : y);
    std::copy(src, src + stride, image.bgra.begin() + stride * y);
  }

  bool any_alpha = false;
  bool any_translucent = false;
  bool premultiplied = true;
  std::vector<uint8_t>& px = image.bgra;
  for (size_t i = 0; i < px.size(); i += 4) {
    const uint8_t a = px[i + 3];
    if (a != 0) any_alpha = true;
    if (a != 255) any_translucent = true;
    if (px[i] > a || px[i + 1] > a || px[i + 2] > a) premultiplied = false;
  }
  if (!any_alpha) {
    for (size_t i = 3; i < px.size(); i += 4) px[i] = 255;
    return image;
  }
  image.has_alpha = any_translucent;
  if (any_translucent && premultiplied) {
    for (size_t i = 0; i < px.size(); i += 4) {
      const uint32_t a = px[i + 3];
      if (a == 0 || a == 255) continue;
      for (size_t c = 0; c < 3; c++) {
        px[i + c] = static_cast<uint8_t>((px[i + c] * 255u + a / 2) / a);
      }
    }
  }
  return image;
}

}  // namespace dart_pdf

#endif  // RUNNER_DIB_PIXELS_H_
