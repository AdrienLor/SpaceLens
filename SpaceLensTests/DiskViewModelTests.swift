import Foundation
import XCTest
@testable import SpaceLens

@MainActor
final class DiskViewModelTests: XCTestCase {
    func testOpeningAnotherFolderCancelsPreviousScanAndPresentsLatestResult() async throws {
        let scanner = ControlledDiskScanner()
        let viewModel = DiskViewModel(scanner: scanner)
        let first = URL(fileURLWithPath: "/tmp/spacelens-first", isDirectory: true)
        let second = URL(fileURLWithPath: "/tmp/spacelens-second", isDirectory: true)

        viewModel.openFolder(first)
        await waitUntil { scanner.requestedRoots.contains(first) }

        viewModel.openFolder(second)
        await waitUntil {
            scanner.cancelledRoots.contains(first) && scanner.requestedRoots.contains(second)
        }

        scanner.complete(root: second, children: [
            scannedFile(at: second.appendingPathComponent("latest.bin"), size: 4_096)
        ])
        await waitUntil { !viewModel.isScanning }

        XCTAssertEqual(viewModel.currentFolder, second)
        XCTAssertEqual(viewModel.nodes.map(\.name), ["latest.bin"])
        XCTAssertEqual(viewModel.sunburstRoot?.url, second)
        XCTAssertTrue(scanner.cancelledRoots.contains(first))
    }

    func testSunburstRefreshReusesCompletedScan() async throws {
        let scanner = ControlledDiskScanner()
        let viewModel = DiskViewModel(scanner: scanner)
        let root = URL(fileURLWithPath: "/tmp/spacelens-root", isDirectory: true)

        viewModel.openFolder(root)
        await waitUntil { scanner.requestedRoots.contains(root) }
        scanner.complete(root: root, children: [
            scannedFile(at: root.appendingPathComponent("payload.bin"), size: 2_048)
        ])
        await waitUntil { !viewModel.isScanning }

        viewModel.loadHierarchyForSunburst(maxDepth: 2)
        viewModel.scheduleSunburstRefresh(maxDepth: 5)

        XCTAssertEqual(scanner.requestedRoots, [root])
        XCTAssertEqual(viewModel.sunburstRoot?.children.map(\.name), ["payload.bin"])
        XCTAssertFalse(viewModel.isSunburstRefreshing)
    }

    func testListedDirectoryAppearsWhileItsSizeIsStillScanning() async throws {
        let scanner = ControlledDiskScanner()
        let viewModel = DiskViewModel(scanner: scanner)
        let root = URL(fileURLWithPath: "/tmp/spacelens-progressive", isDirectory: true)
        let child = Node(
            url: root.appendingPathComponent("large-folder", isDirectory: true),
            name: "large-folder",
            kind: .directory,
            logicalSize: 0,
            allocatedSize: 0,
            access: .readable,
            children: []
        )

        viewModel.openFolder(root)
        await waitUntil { scanner.requestedRoots.contains(root) }
        scanner.list(child, parent: root)
        await waitUntil { viewModel.nodes.first?.url == child.url }

        XCTAssertTrue(viewModel.scanningNodeURLs.contains(child.url))

        scanner.complete(root: root, children: [child])
        await waitUntil { !viewModel.isScanning }

        XCTAssertFalse(viewModel.scanningNodeURLs.contains(child.url))
    }

    func testBrowserRequestsPackageDescendants() async {
        let scanner = ControlledDiskScanner()
        let viewModel = DiskViewModel(scanner: scanner)
        let root = URL(fileURLWithPath: "/tmp/spacelens-package-options", isDirectory: true)

        viewModel.openFolder(root)
        await waitUntil { scanner.requestedOptions[root] != nil }

        XCTAssertEqual(scanner.requestedOptions[root]?.packageTraversal, .descendants)
    }

    func testChangingSizeMetricResortsCachedNodesWithoutRescanning() async {
        let scanner = ControlledDiskScanner()
        let viewModel = DiskViewModel(scanner: scanner)
        let root = URL(fileURLWithPath: "/tmp/spacelens-size-metric", isDirectory: true)
        let allocatedLeader = Node(
            url: root.appendingPathComponent("allocated.bin"),
            name: "allocated.bin",
            kind: .regularFile,
            logicalSize: 10,
            allocatedSize: 100,
            access: .readable,
            children: []
        )
        let logicalLeader = Node(
            url: root.appendingPathComponent("logical.bin"),
            name: "logical.bin",
            kind: .regularFile,
            logicalSize: 200,
            allocatedSize: 20,
            access: .readable,
            children: []
        )

        viewModel.openFolder(root)
        await waitUntil { scanner.requestedRoots.contains(root) }
        scanner.complete(root: root, children: [logicalLeader, allocatedLeader])
        await waitUntil { !viewModel.isScanning }
        XCTAssertEqual(viewModel.nodes.first?.name, "allocated.bin")

        viewModel.setSizeMetric(.logical)

        XCTAssertEqual(viewModel.nodes.first?.name, "logical.bin")
        XCTAssertEqual(scanner.requestedRoots, [root])
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "Condition was not satisfied", file: file, line: line)
    }

    private func scannedFile(at url: URL, size: Int64) -> Node {
        Node(
            url: url,
            name: url.lastPathComponent,
            kind: .regularFile,
            logicalSize: size,
            allocatedSize: size,
            access: .readable,
            children: []
        )
    }
}

private final class ControlledDiskScanner: DiskScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [URL: AsyncThrowingStream<ScanEvent, Error>.Continuation] = [:]
    private var requests: [URL] = []
    private var optionsByRoot: [URL: ScanOptions] = [:]
    private var cancellations: Set<URL> = []

    var requestedRoots: [URL] {
        lock.withLock { requests }
    }

    var cancelledRoots: Set<URL> {
        lock.withLock { cancellations }
    }

    var requestedOptions: [URL: ScanOptions] {
        lock.withLock { optionsByRoot }
    }

    func scan(
        _ root: URL,
        options: ScanOptions
    ) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                requests.append(root)
                optionsByRoot[root] = options
                continuations[root] = continuation
            }
            continuation.onTermination = { [weak self] termination in
                guard case .cancelled = termination else { return }
                self?.lock.withLock {
                    self?.cancellations.insert(root)
                    self?.continuations[root] = nil
                }
            }
            continuation.yield(.started(root: root))
        }
    }

    func complete(root: URL, children: [Node]) {
        let completedRoot = Node(
            url: root,
            name: root.lastPathComponent,
            kind: .directory,
            logicalSize: children.reduce(0) { $0 + $1.logicalSize },
            allocatedSize: children.reduce(0) { $0 + $1.allocatedSize },
            access: .readable,
            children: children
        )
        let continuation = lock.withLock { continuations.removeValue(forKey: root) }
        continuation?.yield(.completed(completedRoot))
        continuation?.finish()
    }

    func list(_ node: Node, parent: URL) {
        let continuation = lock.withLock { continuations[parent] }
        continuation?.yield(.listed(node, parent: parent))
    }
}
