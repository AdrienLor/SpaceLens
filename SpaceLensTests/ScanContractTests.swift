import Foundation
import XCTest
@testable import SpaceLens

final class ScanContractTests: XCTestCase {
    func testDefaultOptionsMatchDiskAnalyzerSemantics() {
        let options = ScanOptions()

        XCTAssertEqual(options.sizeMetric, .allocated)
        XCTAssertTrue(options.includesHiddenFiles)
        XCTAssertEqual(options.packageTraversal, .singleNode)
        XCTAssertFalse(options.followsSymbolicLinks)
        XCTAssertNil(options.maximumDepth)
        XCTAssertGreaterThan(options.maximumConcurrentMetadataRequests, 0)
    }

    func testNodeSelectsRequestedSizeMetric() {
        let node = ScannedNode(
            url: URL(fileURLWithPath: "/fixture.bin"),
            name: "fixture.bin",
            kind: .regularFile,
            logicalSize: 1_024,
            allocatedSize: 4_096,
            access: .readable,
            children: []
        )

        XCTAssertEqual(node.size(using: .logical), 1_024)
        XCTAssertEqual(node.size(using: .allocated), 4_096)
    }

    func testEmptyReadableDirectoryIsNotDenied() {
        let node = ScannedNode(
            url: URL(fileURLWithPath: "/empty"),
            name: "empty",
            kind: .directory,
            logicalSize: 0,
            allocatedSize: 0,
            access: .readable,
            children: []
        )

        XCTAssertEqual(node.access, .readable)
        XCTAssertTrue(node.children.isEmpty)
    }
}
