import Foundation
import XCTest
@testable import SpaceLens

final class FileSystemDiskScannerTests: XCTestCase {
    func testIncludesHiddenFilesByDefault() async throws {
        let fixture = try TemporaryScanFixture()
        try fixture.writeFile("visible.bin", count: 100)
        try fixture.writeFile(".hidden.bin", count: 200)

        let result = try await completedResult(for: fixture.url)

        XCTAssertEqual(Set(result.children.map(\.name)), ["visible.bin", ".hidden.bin"])
        XCTAssertEqual(result.logicalSize, 300)
    }

    func testCanExcludeHiddenFilesWithoutChangingTheContract() async throws {
        let fixture = try TemporaryScanFixture()
        try fixture.writeFile("visible.bin", count: 100)
        try fixture.writeFile(".hidden.bin", count: 200)
        var options = ScanOptions()
        options.includesHiddenFiles = false

        let result = try await completedResult(for: fixture.url, options: options)

        XCTAssertEqual(result.children.map(\.name), ["visible.bin"])
        XCTAssertEqual(result.logicalSize, 100)
    }

    func testReadableEmptyDirectoryIsSuccessful() async throws {
        let fixture = try TemporaryScanFixture()

        let result = try await completedResult(for: fixture.url)

        XCTAssertEqual(result.access, .readable)
        XCTAssertTrue(result.children.isEmpty)
        XCTAssertEqual(result.logicalSize, 0)
        XCTAssertEqual(result.allocatedSize, 0)
    }

    func testSymbolicLinkIsNotFollowedByDefault() async throws {
        let fixture = try TemporaryScanFixture()
        let target = try fixture.createDirectory("target")
        try fixture.writeFile("target/payload.bin", count: 512)
        try FileManager.default.createSymbolicLink(
            at: fixture.url.appendingPathComponent("alias"),
            withDestinationURL: target
        )

        let result = try await completedResult(for: fixture.url)
        let alias = try XCTUnwrap(result.children.first { $0.name == "alias" })

        guard case .symbolicLink = alias.kind else {
            return XCTFail("Expected a symbolic-link node")
        }
        XCTAssertTrue(alias.children.isEmpty)
        XCTAssertEqual(result.logicalSize, 512)
    }

    func testDepthLimitDoesNotChangeRootTotals() async throws {
        let fixture = try TemporaryScanFixture()
        _ = try fixture.createDirectory("one/two/three")
        try fixture.writeFile("one/two/three/payload.bin", count: 777)
        var shallowOptions = ScanOptions()
        shallowOptions.maximumDepth = 1
        var deepOptions = ScanOptions()
        deepOptions.maximumDepth = 8

        let shallow = try await completedResult(for: fixture.url, options: shallowOptions)
        let deep = try await completedResult(for: fixture.url, options: deepOptions)

        XCTAssertEqual(shallow.logicalSize, 777)
        XCTAssertEqual(shallow.logicalSize, deep.logicalSize)
        XCTAssertEqual(shallow.allocatedSize, deep.allocatedSize)
        XCTAssertTrue(shallow.children.first?.children.isEmpty == true)
        XCTAssertFalse(deep.children.first?.children.isEmpty == true)
    }

    func testInvalidConcurrencyLimitFailsBeforeScanning() async {
        let fixture = try? TemporaryScanFixture()
        guard let fixture else { return XCTFail("Unable to create fixture") }
        var options = ScanOptions()
        options.maximumConcurrentMetadataRequests = 0

        do {
            _ = try await completedResult(for: fixture.url, options: options)
            XCTFail("Expected invalid options to fail")
        } catch let error as ScanError {
            XCTAssertEqual(
                error,
                .invalidOptions("maximumConcurrentMetadataRequests must be greater than zero")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEmitsDirectChildrenBeforeRootCompletion() async throws {
        let fixture = try TemporaryScanFixture()
        try fixture.writeFile("first.bin", count: 10)
        try fixture.writeFile("second.bin", count: 20)
        var directChildren: [String] = []
        var didComplete = false

        for try await event in FileSystemDiskScanner().scan(fixture.url, options: ScanOptions()) {
            switch event {
            case .discovered(let node, let parent) where parent == fixture.url:
                XCTAssertFalse(didComplete)
                directChildren.append(node.name)
            case .completed:
                didComplete = true
            case .started, .discovered, .progress:
                break
            }
        }

        XCTAssertEqual(Set(directChildren), ["first.bin", "second.bin"])
        XCTAssertTrue(didComplete)
    }

    private func completedResult(
        for url: URL,
        options: ScanOptions = ScanOptions()
    ) async throws -> ScannedNode {
        let scanner = FileSystemDiskScanner()
        for try await event in scanner.scan(url, options: options) {
            if case .completed(let result) = event {
                return result
            }
        }
        throw ScanError.metadataUnavailable(url, description: "Missing completion event")
    }
}

private final class TemporaryScanFixture {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func createDirectory(_ path: String) throws -> URL {
        let directory = url.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func writeFile(_ path: String, count: Int) throws {
        let fileURL = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: count).write(to: fileURL)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
