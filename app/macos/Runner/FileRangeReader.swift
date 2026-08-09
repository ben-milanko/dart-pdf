import Darwin
import Foundation

/// A recoverable failure while opening or reading a file range.
///
/// Foundation's legacy `FileHandle` range APIs raise Objective-C exceptions
/// for I/O failures. Swift cannot catch those exceptions, so a transient File
/// Provider error can abort the process. This error keeps the failing range
/// and POSIX code in the ordinary Swift error path instead.
struct FileRangeReadError: Error, LocalizedError {
  let operation: String
  let fileName: String
  let offset: Int
  let length: Int
  let code: Int32

  var errorDescription: String? {
    let reason = String(cString: strerror(code))
    return "Could not \(operation) \(fileName) at offset \(offset) "
      + "for \(length) bytes: \(reason) (errno \(code))"
  }
}

/// Reads independent file ranges without Foundation's exception-raising
/// `FileHandle` seek/read/close methods.
enum FileRangeReader {
  static func read(url: URL, offset: Int, length: Int) throws -> Data {
    let safeOffset = max(0, offset)
    let safeLength = max(0, length)
    guard safeLength > 0 else { return Data() }
    guard safeOffset <= Int.max - safeLength else {
      throw failure(
        "read", url: url, offset: safeOffset, length: safeLength,
        code: EOVERFLOW)
    }

    var openError = EINVAL
    let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path = path else { return -1 }
      let result = Darwin.open(path, O_RDONLY | O_CLOEXEC)
      if result < 0 { openError = errno }
      return result
    }
    guard descriptor >= 0 else {
      throw failure(
        "open", url: url, offset: safeOffset, length: safeLength,
        code: openError)
    }
    defer { _ = Darwin.close(descriptor) }

    var data = Data(count: safeLength)
    var total = 0
    while total < safeLength {
      let count = data.withUnsafeMutableBytes { bytes -> Int in
        guard let base = bytes.baseAddress else { return 0 }
        return Darwin.pread(
          descriptor,
          base.advanced(by: total),
          safeLength - total,
          off_t(safeOffset + total))
      }
      if count > 0 {
        total += count
        continue
      }
      if count == 0 { break }

      let readError = errno
      if readError == EINTR { continue }
      throw failure(
        "read", url: url, offset: safeOffset + total,
        length: safeLength - total, code: readError)
    }

    if total < data.count {
      data.removeSubrange(total..<data.count)
    }
    return data
  }

  private static func failure(
    _ operation: String,
    url: URL,
    offset: Int,
    length: Int,
    code: Int32
  ) -> FileRangeReadError {
    FileRangeReadError(
      operation: operation,
      fileName: url.lastPathComponent,
      offset: offset,
      length: length,
      code: code)
  }
}
