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
        AsyncThrowingStream { continuation in
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
                    var state = TraversalState()
                    let result = try scanItem(
                        at: normalizedRoot,
                        parent: nil,
                        depth: 0,
                        exposeChildren: true,
                        options: options,
                        state: &state,
                        continuation: continuation
                    )
                    try Task.checkCancellation()
                    emitProgress(state: state, currentURL: normalizedRoot, continuation: continuation)
                    continuation.yield(.completed(result))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
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
        state: inout TraversalState,
        continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
    ) throws -> Node {
        try Task.checkCancellation()

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
            emit(for: node, parent: parent, depth: depth, countBytes: false, options: options, state: &state, continuation: continuation)
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
            emit(for: node, parent: parent, depth: depth, countBytes: true, options: options, state: &state, continuation: continuation)
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
            emit(for: denied, parent: parent, depth: depth, countBytes: false, options: options, state: &state, continuation: continuation)
            return denied
        }

        var scannedChildren: [Node] = []
        var logicalSize: Int64 = 0
        var allocatedSize: Int64 = 0
        var deniedItemCount = 0

        for childURL in contents {
            try Task.checkCancellation()
            do {
                let child = try scanItem(
                    at: childURL,
                    parent: url,
                    depth: depth + 1,
                    exposeChildren: exposeDescendants,
                    options: options,
                    state: &state,
                    continuation: continuation
                )
                logicalSize += child.logicalSize
                allocatedSize += child.allocatedSize
                deniedItemCount += child.deniedItemCount
                if exposeDescendants {
                    scannedChildren.append(child)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                deniedItemCount += 1
            }
        }

        let access: FolderAccess = deniedItemCount == 0
            ? .readable
            : .partiallyReadable(deniedItemCount: deniedItemCount)
        let node = Node(
            url: url,
            name: displayName(for: url),
            kind: isPackage ? .package : .directory,
            logicalSize: logicalSize,
            allocatedSize: allocatedSize,
            access: access,
            children: scannedChildren.sorted { lhs, rhs in
                lhs.size(using: options.sizeMetric) > rhs.size(using: options.sizeMetric)
            }
        )
        emit(for: node, parent: parent, depth: depth, countBytes: false, options: options, state: &state, continuation: continuation)
        return node
    }

    private func displayName(for url: URL) -> String {
        url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
    }

    private func emit(
        for node: Node,
        parent: URL?,
        depth: Int,
        countBytes: Bool,
        options: ScanOptions,
        state: inout TraversalState,
        continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
    ) {
        if options.maximumReportedDepth.map({ depth <= $0 }) ?? true {
            continuation.yield(.discovered(node, parent: parent))
        }
        state.discoveredItemCount += 1
        if countBytes {
            state.logicalBytes += node.logicalSize
            state.allocatedBytes += node.allocatedSize
        }
        if state.discoveredItemCount.isMultiple(of: 256) {
            emitProgress(state: state, currentURL: node.url, continuation: continuation)
        }
    }

    private func emitProgress(
        state: TraversalState,
        currentURL: URL,
        continuation: AsyncThrowingStream<ScanEvent, Error>.Continuation
    ) {
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
