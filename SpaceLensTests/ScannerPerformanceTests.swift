import Foundation
import XCTest
@testable import SpaceLens

final class ScannerPerformanceTests: XCTestCase {
    func testSyntheticTreeThroughput() async throws {
        guard ProcessInfo.processInfo.environment["SPACELENS_BENCHMARK"] == "1" else {
            throw XCTSkip("Set SPACELENS_BENCHMARK=1 to run scanner benchmarks")
        }

        let fixture = try PerformanceFixture(directoryCount: 40, filesPerDirectory: 100)
        let clock = ContinuousClock()
        let start = clock.now
        var completedRoot: Node?
        var options = ScanOptions()
        options.maximumReportedDepth = 1
        if let rawConcurrency = ProcessInfo.processInfo.environment["SPACELENS_BENCHMARK_CONCURRENCY"],
           let concurrency = Int(rawConcurrency) {
            options.maximumConcurrentMetadataRequests = concurrency
        }

        for try await event in FileSystemDiskScanner().scan(fixture.url, options: options) {
            if case .completed(let root) = event {
                completedRoot = root
            }
        }

        let duration = start.duration(to: clock.now)
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
        let itemCount = 40 * 100 + 40 + 1
        let itemsPerSecond = Double(itemCount) / seconds

        XCTAssertEqual(completedRoot?.children.count, 40)
        print(
            String(
                format: "SPACELENS_BENCHMARK workers=%d items=%d seconds=%.4f items_per_second=%.0f",
                options.maximumConcurrentMetadataRequests,
                itemCount,
                seconds,
                itemsPerSecond
            )
        )
    }
}

private final class PerformanceFixture {
    let url: URL

    init(directoryCount: Int, filesPerDirectory: Int) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceLensPerformanceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let payload = Data(repeating: 0x41, count: 128)

        for directoryIndex in 0..<directoryCount {
            let directory = url.appendingPathComponent("directory-\(directoryIndex)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            for fileIndex in 0..<filesPerDirectory {
                try payload.write(to: directory.appendingPathComponent("file-\(fileIndex).bin"))
            }
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
