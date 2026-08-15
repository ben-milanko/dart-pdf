import Cocoa
import Darwin
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {

  func testWindowingBootstrapReadsGeneratedFlag() {
    XCTAssertTrue(DartPdfWindowingBootstrap.isEnabled(flag: "1"))
    XCTAssertTrue(DartPdfWindowingBootstrap.isEnabled(flag: " 1\n"))
  }

  func testWindowingBootstrapRejectsMissingOrDisabledFlag() {
    XCTAssertFalse(DartPdfWindowingBootstrap.isEnabled(flag: nil))
    XCTAssertFalse(DartPdfWindowingBootstrap.isEnabled(flag: ""))
    XCTAssertFalse(DartPdfWindowingBootstrap.isEnabled(flag: "0\n"))
    XCTAssertFalse(DartPdfWindowingBootstrap.isEnabled(flag: "true"))
  }

  func testFileRangeReaderReturnsRequestedBytesAndShortReadsAtEOF() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("fixture.pdf")
    try Data((0..<10).map(UInt8.init)).write(to: file)

    XCTAssertEqual(
      try FileRangeReader.read(url: file, offset: 3, length: 4),
      Data([3, 4, 5, 6]))
    XCTAssertEqual(
      try FileRangeReader.read(url: file, offset: 8, length: 8),
      Data([8, 9]))
    XCTAssertEqual(
      try FileRangeReader.read(url: file, offset: 20, length: 8),
      Data())
  }

  func testFileRangeReaderClampsNegativeAndEmptyRanges() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("fixture.pdf")
    try Data([1, 2, 3]).write(to: file)

    XCTAssertEqual(
      try FileRangeReader.read(url: file, offset: -5, length: 2),
      Data([1, 2]))
    XCTAssertEqual(
      try FileRangeReader.read(url: file, offset: 0, length: -1),
      Data())
  }

  func testFileRangeReaderThrowsSwiftErrorForReadFailure() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    XCTAssertThrowsError(
      try FileRangeReader.read(url: directory, offset: 0, length: 1)
    ) { error in
      guard let readError = error as? FileRangeReadError else {
        return XCTFail("Expected FileRangeReadError, got \(error)")
      }
      XCTAssertEqual(readError.operation, "read")
      XCTAssertEqual(readError.code, EISDIR)
      XCTAssertEqual(readError.offset, 0)
      XCTAssertEqual(readError.length, 1)
    }
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)
    return directory
  }
}
