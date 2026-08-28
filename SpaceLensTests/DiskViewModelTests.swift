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

    private func scannedFile(at url: URL, size: Int64) -> ScannedNode {
        ScannedNode(
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
    private var cancellations: Set<URL> = []

    var requestedRoots: [URL] {
        lock.withLock { requests }
    }

    var cancelledRoots: Set<URL> {
        lock.withLock { cancellations }
    }

    func scan(
        _ root: URL,
        options _: ScanOptions
    ) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                requests.append(root)
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

    func complete(root: URL, children: [ScannedNode]) {
        let completedRoot = ScannedNode(
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
}
