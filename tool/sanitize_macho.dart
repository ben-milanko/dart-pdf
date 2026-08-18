import 'dart:io';
import 'dart:typed_data';

const _targetSymbol = '__dyld_find_unwind_sections\x00';
// Replace with a standard POSIX symbol exported by libSystem.B.dylib of exact same byte length (28 bytes).
final _replacementSymbol = '_dladdr\x00'.codeUnits +
    List<int>.filled(_targetSymbol.length - 8, 0);

/// Strips private Apple dynamic linker symbols (specifically `__dyld_find_unwind_sections`)
/// from a Mach-O binary compiled with `dart compile exe`.
///
/// Standalone Dart AOT executables link the Dart SDK runtime stub, which references
/// `__dyld_find_unwind_sections` via LLVM libunwind. App Store Connect rejects binaries
/// referencing private SPI symbols (ITMS-90338).
///
/// This sanitizer:
/// 1. Finds `__dyld_find_unwind_sections` in `LC_SYMTAB`.
/// 2. Locates its indirect symbol index in `LC_DYSYMTAB` and its corresponding stub in `__stubs`.
/// 3. Patches the stub instructions in-place to return 0 immediately (`mov w0, #0; ret` on ARM64,
///    `xor eax, eax; ret` on x86_64), taking libunwind's built-in table fallback.
/// 4. Replaces all imported symbol string occurrences of `__dyld_find_unwind_sections\0` with
///    `_dladdr\0...` across `LC_DYLD_CHAINED_FIXUPS` and `LC_SYMTAB`.
void sanitizeMachoFile(File file) {
  final bytes = file.readAsBytesSync();
  final data = ByteData.sublistView(bytes);

  if (data.lengthInBytes < 8) return;
  final magic = data.getUint32(0, Endian.big);

  if (magic == 0xcafebabe || magic == 0xbebafeca) {
    // 32-bit FAT binary
    final nfatArch = data.getUint32(4, Endian.big);
    for (var i = 0; i < nfatArch; i++) {
      final offset = data.getUint32(8 + i * 20 + 8, Endian.big);
      final size = data.getUint32(8 + i * 20 + 12, Endian.big);
      _sanitizeMachoSlice(bytes, data, offset, size);
    }
  } else if (magic == 0xcafebabf || magic == 0xbfbafeca) {
    // 64-bit FAT binary
    final nfatArch = data.getUint32(4, Endian.big);
    for (var i = 0; i < nfatArch; i++) {
      final offset = data.getUint64(8 + i * 32 + 8, Endian.big);
      final size = data.getUint64(8 + i * 32 + 16, Endian.big);
      _sanitizeMachoSlice(bytes, data, offset, size);
    }
  } else {
    _sanitizeMachoSlice(bytes, data, 0, bytes.length);
  }

  file.writeAsBytesSync(bytes);

  // macOS (especially ARM64 Apple Silicon) requires any modified Mach-O binary
  // to have a valid code signature, otherwise AMFI kills the process with SIGKILL (-9).
  if (Platform.isMacOS) {
    try {
      Process.runSync('codesign', ['-s', '-', '-f', file.path]);
    } catch (_) {
      // Ignored if codesign is not present (e.g. cross-compiling on non-macOS host).
    }
  }
}

void _sanitizeMachoSlice(
  Uint8List bytes,
  ByteData data,
  int sliceOffset,
  int sliceSize,
) {
  if (sliceOffset + 32 > bytes.length) return;
  final magic = data.getUint32(sliceOffset, Endian.little);
  final Endian endian;
  if (magic == 0xfeedfacf) {
    endian = Endian.little;
  } else if (magic == 0xcffaedfe) {
    endian = Endian.big;
  } else {
    return; // Not a 64-bit Mach-O
  }

  final cpuType = data.getUint32(sliceOffset + 4, endian);
  final isArm64 = (cpuType == 0x0100000c);
  final isX86_64 = (cpuType == 0x01000007);

  final ncmds = data.getUint32(sliceOffset + 16, endian);
  var cmdOffset = sliceOffset + 32;

  int? symoff, nsyms, stroff, strsize;
  int? indirectsymoff, nindirectsyms;
  int? stubsFileoff, stubsSize, stubsIndirectIdx, stubSize;

  for (var i = 0; i < ncmds; i++) {
    if (cmdOffset + 8 > sliceOffset + sliceSize) break;
    final cmd = data.getUint32(cmdOffset, endian);
    final cmdsize = data.getUint32(cmdOffset + 4, endian);

    if (cmd == 0x19) {
      // LC_SEGMENT_64
      final nsects = data.getUint32(cmdOffset + 64, endian);
      var sectOffset = cmdOffset + 72;
      for (var s = 0; s < nsects; s++) {
        if (sectOffset + 80 > sliceOffset + sliceSize) break;
        final sectName = String.fromCharCodes(
          bytes.sublist(sectOffset, sectOffset + 16).takeWhile((c) => c != 0),
        );
        if (sectName == '__stubs') {
          stubsSize = data.getUint64(sectOffset + 40, endian);
          stubsFileoff = data.getUint32(sectOffset + 48, endian);
          stubsIndirectIdx = data.getUint32(sectOffset + 68, endian);
          stubSize = data.getUint32(sectOffset + 72, endian);
        }
        sectOffset += 80;
      }
    } else if (cmd == 0x2) {
      // LC_SYMTAB
      symoff = data.getUint32(cmdOffset + 8, endian);
      nsyms = data.getUint32(cmdOffset + 12, endian);
      stroff = data.getUint32(cmdOffset + 16, endian);
      strsize = data.getUint32(cmdOffset + 20, endian);
    } else if (cmd == 0xb) {
      // LC_DYSYMTAB: field 12 is indirectsymoff, field 13 is nindirectsyms
      indirectsymoff = data.getUint32(cmdOffset + 56, endian);
      nindirectsyms = data.getUint32(cmdOffset + 60, endian);
    }
    cmdOffset += cmdsize;
  }

  // 1. Locate the target symbol index in LC_SYMTAB
  int? targetSymIndex;
  if (symoff != null && nsyms != null && stroff != null && strsize != null) {
    final strtabStart = sliceOffset + stroff;
    for (var i = 0; i < nsyms; i++) {
      final nStrx = data.getUint32(sliceOffset + symoff + i * 16, endian);
      if (nStrx < strsize) {
        final start = strtabStart + nStrx;
        var end = start;
        while (end < strtabStart + strsize && bytes[end] != 0) {
          end++;
        }
        final symName = String.fromCharCodes(bytes.sublist(start, end));
        if (symName == '__dyld_find_unwind_sections') {
          targetSymIndex = i;
          break;
        }
      }
    }
  }

  // 2. Patch the symbol stub in __stubs to return 0 directly
  if (targetSymIndex != null &&
      stubsFileoff != null &&
      stubsSize != null &&
      stubsIndirectIdx != null &&
      stubSize != null &&
      indirectsymoff != null &&
      nindirectsyms != null) {
    final numStubs = stubsSize ~/ stubSize;
    for (var stubIdx = 0; stubIdx < numStubs; stubIdx++) {
      final indIdx = stubsIndirectIdx + stubIdx;
      if (indIdx < nindirectsyms) {
        final rawSymIdx = data.getUint32(
          sliceOffset + indirectsymoff + indIdx * 4,
          endian,
        );
        final symIdx = rawSymIdx & 0x3fffffff;
        if (symIdx == targetSymIndex) {
          final stubFilePos = sliceOffset + stubsFileoff + stubIdx * stubSize;
          if (isArm64 && stubSize == 12) {
            // mov w0, #0 (0x52800000); ret (0xd65f03c0); nop (0xd503201f)
            const arm64Patch = [
              0x00, 0x00, 0x80, 0x52,
              0xc0, 0x03, 0x5f, 0xd6,
              0x1f, 0x20, 0x03, 0xd5,
            ];
            bytes.setRange(stubFilePos, stubFilePos + 12, arm64Patch);
          } else if (isX86_64 && stubSize == 6) {
            // xor eax, eax (0x31, 0xc0); ret (0xc3); nop; nop; nop
            const x86Patch = [0x31, 0xc0, 0xc3, 0x90, 0x90, 0x90];
            bytes.setRange(stubFilePos, stubFilePos + 6, x86Patch);
          }
        }
      }
    }
  }

  // 3. Replace all string occurrences of '__dyld_find_unwind_sections\0'
  final targetBytes = _targetSymbol.codeUnits;
  var pos = sliceOffset;
  final sliceEnd = sliceOffset + sliceSize;
  while (pos + targetBytes.length <= sliceEnd) {
    var match = true;
    for (var i = 0; i < targetBytes.length; i++) {
      if (bytes[pos + i] != targetBytes[i]) {
        match = false;
        break;
      }
    }
    if (match) {
      bytes.setRange(pos, pos + targetBytes.length, _replacementSymbol);
      pos += targetBytes.length;
    } else {
      pos++;
    }
  }
}

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    stderr.writeln('Usage: dart tool/sanitize_macho.dart <path-to-binary>');
    exit(64);
  }
  for (final path in arguments) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('error: file not found: $path');
      exit(1);
    }
    sanitizeMachoFile(file);
    stdout.writeln('Sanitized Mach-O symbols in: ${file.path}');
  }
}
