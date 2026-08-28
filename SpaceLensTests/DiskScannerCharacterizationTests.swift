import Foundation
import XCTest
@testable import SpaceLens

final class DiskScannerCharacterizationTests: XCTestCase {
    func testRegularFileContributesItsLogicalSize() throws {
        let fixture = try TemporaryDirectory()
        let bytes = Data(repeating: 0x41, count: 4_096)
        try bytes.write(to: fixture.url.appendingPathComponent("payload.bin"))

        let node = DiskScanner.scanFolderHierarchy(at: fixture.url, maxDepth: 2)

        XCTAssertEqual(node.children.count, 1)
        XCTAssertEqual(node.children.first?.size, Int64(bytes.count))
        XCTAssertEqual(node.size, Int64(bytes.count))
    }

    func testReadableEmptyFolderIsRepresentedAsEmpty() throws {
        let fixture = try TemporaryDirectory()

        let node = DiskScanner.scanFolderHierarchy(at: fixture.url, maxDepth: 2)

        XCTAssertTrue(node.isDir)
        XCTAssertTrue(node.children.isEmpty)
        XCTAssertEqual(node.size, 0)
        XCTAssertFalse(node.accessDenied)
    }

    /// Characterizes the legacy behavior documented in issue #1.
    /// This expectation will intentionally change when hidden files are included.
    func testLegacyScannerSkipsHiddenFiles() throws {
        let fixture = try TemporaryDirectory()
        try Data(repeating: 0x41, count: 100).write(to: fixture.url.appendingPathComponent("visible.bin"))
        try Data(repeating: 0x42, count: 200).write(to: fixture.url.appendingPathComponent(".hidden.bin"))

        let node = DiskScanner.scanFolderHierarchy(at: fixture.url, maxDepth: 2)

        XCTAssertEqual(node.children.map(\.name), ["visible.bin"])
        XCTAssertEqual(node.size, 100)
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
