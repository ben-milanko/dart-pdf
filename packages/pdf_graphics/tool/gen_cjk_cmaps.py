#!/usr/bin/env python3
"""Generate packed (code -> Unicode) tables for predefined CJK CMaps.

Each table is the two-byte character codes a Python charset codec accepts that
decode to a single BMP scalar, stored as big-endian (u16 code, u16 unicode)
pairs sorted by code and base64-encoded -- the same packing ShiftJisCmap uses.

Mirrors tool/gen_shift_jis.dart's recipe; run from packages/pdf_graphics:
    python3 tool/gen_cjk_cmaps.py
"""
import base64, struct, textwrap

# (dart const name, output file, python codec, lead-byte ranges, trail ranges,
#  doc blurb)
CHARSETS = [
    ("eucJpPackedBase64", "_euc_jp_data.dart", "euc_jp",
     # 0x8E + half-width kana, plus the 0xA1..0xFE / 0xA1..0xFE plane.
     [(0x8E, 0x8E), (0xA1, 0xFE)], [(0x00, 0xFF)],
     "EUC-JP (the `EUC-H`/`EUC-V` Adobe-Japan1 CMaps)"),
    ("gbkPackedBase64", "_gbk_data.dart", "gbk",
     [(0x81, 0xFE)], [(0x40, 0xFE)],
     "GBK / GB2312 (the `GB*-EUC` / `GBK*` Adobe-GB1 CMaps)"),
    ("big5PackedBase64", "_big5_data.dart", "big5",
     [(0x81, 0xFE)], [(0x40, 0x7E), (0xA1, 0xFE)],
     "Big5 (the `B5*` / `ETen-B5` / `HKscs-B5` Adobe-CNS1 CMaps)"),
    ("uhcPackedBase64", "_uhc_data.dart", "cp949",
     [(0x81, 0xFE)], [(0x41, 0xFE)],
     "Unified Hangul Code / EUC-KR (the `KSC*` Adobe-Korea1 CMaps)"),
]

def in_ranges(b, ranges):
    return any(lo <= b <= hi for lo, hi in ranges)

def build(codec, leads, trails):
    pairs = []
    for lead in range(0x81 if codec != "euc_jp" else 0x8E, 0xFF):
        if not in_ranges(lead, leads):
            continue
        for trail in range(0x00, 0x100):
            if not in_ranges(trail, trails):
                continue
            try:
                s = bytes([lead, trail]).decode(codec)
            except UnicodeDecodeError:
                continue
            if len(s) != 1:
                continue
            cp = ord(s)
            if cp > 0xFFFF:
                continue
            code = (lead << 8) | trail
            pairs.append((code, cp))
    pairs.sort()
    packed = b"".join(struct.pack(">HH", c, u) for c, u in pairs)
    return pairs, packed

def emit(name, path, codec, leads, trails, blurb):
    pairs, packed = build(codec, leads, trails)
    b64 = base64.b64encode(packed).decode("ascii")
    lines = textwrap.wrap(b64, 90)
    body = "\n".join(f"    '{ln}'" for ln in lines)
    body = body.rstrip("'") + ";" if False else (
        "\n".join(f"    '{ln}'" + ("" if i < len(lines) - 1 else ";")
                  for i, ln in enumerate(lines)))
    out = f"""// GENERATED — do not edit by hand.
//
// {blurb} two-byte code → Unicode scalar table, used to decode non-embedded
// CID text that declares the matching predefined CMap. Generated from Python's
// built-in `{codec}` codec: every byte pair that decodes to a single BMP
// character is stored as a big-endian (code, unicode) u16 pair, sorted by code.
// Regenerate with tool/gen_cjk_cmaps.py.
//
// {len(pairs)} entries, {len(packed)} packed bytes.
library;

/// Base64 of the packed {blurb} two-byte code → Unicode table: big-endian
/// (u16 code, u16 unicode) pairs, sorted by code. Decoded lazily in
/// cjk_cmap.dart.
const String {name} =
{body}
"""
    with open(f"lib/src/fonts/{path}", "w") as f:
        f.write(out)
    print(f"{path}: {len(pairs)} entries, {len(packed)} bytes")

for c in CHARSETS:
    emit(*c)
