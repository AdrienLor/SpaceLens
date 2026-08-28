import Foundation

struct FileSystemDiskScanner: DiskScanning {
    private var fileManager: FileManager { FileManager.default }
    private let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isPackageKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey
    ]

    func scan(
        _ root: URL,
        options: ScanOptions
    ) -> AsyncThrowingStream<ScanEvent, Error> {
        let cancellation = ScanCancellation()
        return AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .utility) {
                do {
                    try validate(options)
                    let normalizedRoot = root.standardizedFileURL
                    var isDirectory: ObjCBool = false
                    guard fileManager.fileExists(
                        atPath: normalizedRoot.path,
                        isDirectory: &isDirectory
                    ) else {
                        throw ScanError.rootNotFound(normalizedRoot)
                    }
                    guard isDirectory.boolValue else {
                        throw ScanError.rootIsNotDirectory(normalizedRoot)
                    }

                    continuation.yield(.started(root: normalizedRoot))
                    let reporter = ScanReporter(options: options, continuation: continuation)
                    let result = try scanItem(
                        at: normalizedRoot,
                        parent: nil,
                        depth: 0,
                        exposeChildren: true,
                        options: options,
                        reporter: reporter,
                        cancellation: cancellation
                    )
                    try checkCancellation(cancellation)
                    reporter.emitFinalProgress(currentURL: normalizedRoot)
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                cancellation.cancel()
                task.cancel()
            }
        }
    }

    private func validate(_ options: ScanOptions) throws {
        if let maximumDepth = options.maximumDepth, maximumDepth < 0 {
            throw ScanError.invalidOptions("maximumDepth must be zero or greater")
        }
        if let maximumReportedDepth = options.maximumReportedDepth, maximumReportedDepth < 0 {
            throw ScanError.invalidOptions("maximumReportedDepth must be zero or greater")
        }
        guard options.maximumConcurrentMetadataRequests > 0 else {
            throw ScanError.invalidOptions(
                "maximumConcurrentMetadataRequests must be greater than zero"
            )
        }
    }

    private func scanItem(
        at url: URL,
        parent: URL?,
        depth: Int,
        exposeChildren: Bool,
        options: ScanOptions,
        reporter: ScanReporter,
        cancellation: ScanCancellation
    ) throws -> Node {
        try checkCancellation(cancellation)

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: Set(resourceKeys))
        } catch {
            throw ScanError.metadataUnavailable(url, description: error.localizedDescription)
        }

        if values.isSymbolicLink == true {
            let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path)
            let destinationURL = destination.map {
                URL(fileURLWithPath: $0, relativeTo: url.deletingLastPathComponent())
                    .standardizedFileURL
            }
            let node = Node(
                url: url,
                name: displayName(for: url),
                kind: .symbolicLink(destination: destinationURL),
                logicalSize: 0,
                allocatedSize: 0,
                access: .readable,
                children: []
            )
            reporter.record(node, parent: parent, depth: depth, countBytes: false)
            return node
        }

        guard values.isDirectory == true else {
            let logicalSize = Int64(values.fileSize ?? 0)
            let allocatedSize = Int64(
                values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
            )
            let node = Node(
                url: url,
                name: displayName(for: url),
                kind: values.isRegularFile == true ? .regularFile : .other,
                logicalSize: logicalSize,
                allocatedSize: allocatedSize,
                access: .readable,
                children: []
            )
            reporter.record(node, parent: parent, depth: depth, countBytes: true)
            return node
        }

        let isPackage = values.isPackage == true
        let shouldExposeAtDepth = options.maximumDepth.map { depth < $0 } ?? true
        let shouldExposePackageChildren = !isPackage || options.packageTraversal == .descendants
        let exposeDescendants = exposeChildren && shouldExposeAtDepth && shouldExposePackageChildren
        let directoryOptions: FileManager.DirectoryEnumerationOptions =
            options.includesHiddenFiles ? [] : [.skipsHiddenFiles]

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: resourceKeys,
                options: directoryOptions
            )
        } catch {
            let denied = Node(
                url: url,
                name: displayName(for: url),
                kind: isPackage ? .package : .directory,
                logicalSize: 0,
                allocatedSize: 0,
                access: .denied,
                children: []
            )
            reporter.record(denied, parent: parent, depth: depth, countBytes: false)
            return denied
        }

        let aggregate: ChildScanAggregate
        if depth == 0 && contents.count > 1 {
            aggregate = try scanRootChildren(
                contents,
                parent: url,
                depth: depth + 1,
                exposeChildren: exposeDescendants,
                options: options,
                reporter: reporter,
                cancellation: cancellation
            )
        } else {
            aggregate = try scanChildrenSequentially(
                contents,
                parent: url,
                depth: depth + 1,
                exposeChildren: exposeDescendants,
                options: options,
                reporter: reporter,
                cancellation: cancellation
            )
        }

        let access: FolderAccess = aggregate.deniedItemCount == 0
            ? .readable
            : .partiallyReadable(deniedItemCount: aggregate.deniedItemCount)
        let node = Node(
            url: url,
            name: displayName(for: url),
            kind: isPackage ? .package : .directory,
            logicalSize: aggregate.logicalSize,
            allocatedSize: aggregate.allocatedSize,
            access: access,
            children: aggregate.children.sorted { lhs, rhs in
                let lhsSize = lhs.size(using: options.sizeMetric)
                let rhsSize = rhs.size(using: options.sizeMetric)
                if lhsSize == rhsSize {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhsSize > rhsSize
            }
        )
        reporter.record(node, parent: parent, depth: depth, countBytes: false)
        return node
    }

    private func scanRootChildren(
        _ urls: [URL],
        parent: URL,
        depth: Int,
        exposeChildren: Bool,
        options: ScanOptions,
        reporter: ScanReporter,
        cancellation: ScanCancellation
    ) throws -> ChildScanAggregate {
        let workQueue = ScanWorkQueue(urls: urls)
        let accumulator = ChildScanAccumulator(exposesChildren: exposeChildren)
        let workerCount = min(options.maximumConcurrentMetadataRequests, urls.count)

        DispatchQueue.concurrentPerform(iterations: workerCount) { _ in
            while !cancellation.isCancelled, let url = workQueue.next() {
                do {
                    let child = try scanItem(
                        at: url,
                        parent: parent,
                        depth: depth,
                        exposeChildren: exposeChildren,
                        options: options,
                        reporter: reporter,
                        cancellation: cancellation
                    )
                    accumulator.add(child)
                } catch is CancellationError {
                    return
                } catch {
                    accumulator.recordDeniedItem()
                }
            }
        }

        try checkCancellation(cancellation)
        return accumulator.value
    }

    private func scanChildrenSequentially(
        _ urls: [URL],
        parent: URL,
        depth: Int,
        exposeChildren: Bool,
        options: ScanOptions,
        reporter: ScanReporter,
        cancellation: ScanCancellation
    ) throws -> ChildScanAggregate {
        var aggregate = ChildScanAggregate()
        for url in urls {
            try checkCancellation(cancellation)
            do {
                let child = try scanItem(
                    at: url,
                    parent: parent,
                    depth: depth,
                    exposeChildren: exposeChildren,
                    options: options,
                    reporter: reporter,
                    cancellation: cancellation
                )
                aggregate.add(child, exposesChildren: exposeChildren)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                aggregate.deniedItemCount += 1
            }
        }
        return aggregate
    }

    private func checkCancellation(_ cancellation: ScanCancellation) throws {
        if cancellation.isCancelled || Task.isCancelled {
            throw CancellationError()
        }
    }

    private func displayName(for url: URL) -> String {
        url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
    }
}

private final class ScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

private final class ScanWorkQueue: @unchecked Sendable {
    private let lock = NSLock()
    private let urls: [URL]
    private var nextIndex = 0

    init(urls: [URL]) {
        self.urls = urls
    }

    func next() -> URL? {
        lock.withLock {
            guard nextIndex < urls.count else { return nil }
            defer { nextIndex += 1 }
            return urls[nextIndex]
        }
    }
}

private final class ChildScanAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let exposesChildren: Bool
    private var aggregate = ChildScanAggregate()

    init(exposesChildren: Bool) {
        self.exposesChildren = exposesChildren
    }

    func add(_ node: Node) {
        lock.withLock {
            aggregate.add(node, exposesChildren: exposesChildren)
        }
    }

    func recordDeniedItem() {
        lock.withLock {
            aggregate.deniedItemCount += 1
        }
    }

    var value: ChildScanAggregate {
        lock.withLock { aggregate }
    }
}

private final class ScanReporter: @unchecked Sendable {
    private let lock = NSLock()
    private let options: ScanOptions
    private let continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
    private var state = TraversalState()

    init(
        options: ScanOptions,
        continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
    ) {
        self.options = options
        self.continuation = continuation
    }

    func record(_ node: Node, parent: URL?, depth: Int, countBytes: Bool) {
        lock.withLock {
            if options.maximumReportedDepth.map({ depth <= $0 }) ?? true {
                continuation.yield(.discovered(node, parent: parent))
            }
            state.discoveredItemCount += 1
            if countBytes {
                state.logicalBytes += node.logicalSize
                state.allocatedBytes += node.allocatedSize
            }
            if state.discoveredItemCount.isMultiple(of: 256) {
                emitProgress(currentURL: node.url)
            }
        }
    }

    func emitFinalProgress(currentURL: URL) {
        lock.withLock {
            emitProgress(currentURL: currentURL)
        }
    }

    private func emitProgress(currentURL: URL) {
        continuation.yield(
            .progress(
                ScanStatistics(
                    discoveredItemCount: state.discoveredItemCount,
                    logicalBytes: state.logicalBytes,
                    allocatedBytes: state.allocatedBytes,
                    currentURL: currentURL
                )
            )
        )
    }
}

private struct TraversalState {
    var discoveredItemCount = 0
    var logicalBytes: Int64 = 0
    var allocatedBytes: Int64 = 0
}

private struct ChildScanAggregate {
    var children: [Node] = []
    var logicalSize: Int64 = 0
    var allocatedSize: Int64 = 0
    var deniedItemCount = 0

    mutating func add(_ node: Node, exposesChildren: Bool) {
        logicalSize += node.logicalSize
        allocatedSize += node.allocatedSize
        deniedItemCount += node.deniedItemCount
        if exposesChildren {
            children.append(node)
        }
    }
}

private extension Node {
    var deniedItemCount: Int {
        switch access {
        case .readable:
            0
        case .partiallyReadable(let deniedItemCount):
            deniedItemCount
        case .denied:
            1
        }
    }
}
