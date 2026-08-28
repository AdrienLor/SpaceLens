import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class DiskViewModel: ObservableObject {
    @Published var currentFolder: URL?
    @Published var nodes: [Node] = []
    @Published var breadcrumb: [URL] = []
    @Published var isScanning = false
    @Published var errorMessage: String?
    @Published var displayLimit = 100
    @Published var cache: [URL: [Node]] = [:]
    @Published var sunburstRoot: Node?
    @Published var isSunburstRefreshing = false
    @Published private(set) var scanningNodeURLs: Set<URL> = []
    @Published private(set) var scanStatistics: ScanStatistics?
    @Published var heatmapStyle: HeatmapStyle = .fileType
    @Published private(set) var sizeMetric: FileSizeMetric = .allocated

    let baseDisplayLimit = 100

    private(set) var rootFolder: URL?
    private let scanner: any DiskScanning
    private var scanTask: Task<Void, Never>?
    private var activeScanID: UUID?
    private var viewStack: [URL] = []
    private var scannedRoots: [URL: Node] = [:]
    private var cacheOrder: [URL] = []
    private let cacheCapacity: Int

    init(scanner: any DiskScanning = FileSystemDiskScanner(), cacheCapacity: Int = 5) {
        self.scanner = scanner
        self.cacheCapacity = max(1, cacheCapacity)
    }

    deinit {
        scanTask?.cancel()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            rootFolder = normalized(url)
            viewStack.removeAll()
            openFolder(url, recordInHistory: true)
        }
    }

    func resetToRoot() {
        guard let rootFolder else {
            clearSelection()
            return
        }
        viewStack.removeAll()
        openFolder(rootFolder, recordInHistory: true)
    }

    func openFolder(_ url: URL, recordInHistory: Bool = true) {
        let target = normalized(url)
        if rootFolder == nil {
            rootFolder = target
        }

        cancelCurrentScan()
        displayLimit = baseDisplayLimit
        currentFolder = target
        breadcrumb = makeBreadcrumb(for: target)
        errorMessage = nil
        scanStatistics = nil

        if let cachedRoot = scannedRoots[target] {
            touchCachedRoot(target)
            present(cachedRoot, for: target)
            if recordInHistory, viewStack.last != target {
                viewStack.append(target)
            }
            return
        }

        nodes = []
        sunburstRoot = nil
        scanningNodeURLs = []
        isScanning = true
        isSunburstRefreshing = true

        let scanID = UUID()
        activeScanID = scanID
        var immediateChildren: [URL: Node] = [:]
        var options = ScanOptions()
        options.maximumDepth = 8
        options.maximumReportedDepth = 1
        options.packageTraversal = .descendants
        options.sizeMetric = sizeMetric

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in scanner.scan(target, options: options) {
                    try Task.checkCancellation()
                    guard activeScanID == scanID, currentFolder == target else { return }

                    switch event {
                    case .started:
                        break
                    case .listed(let listedNode, let parent):
                        if parent == target {
                            immediateChildren[listedNode.url] = listedNode
                            scanningNodeURLs.insert(listedNode.url)
                            let sorted = sort(Array(immediateChildren.values))
                            cache[target] = sorted
                            nodes = Array(sorted.prefix(displayLimit))
                        }
                    case .discovered(let discoveredNode, let parent):
                        if parent == target {
                            let node = discoveredNode
                            immediateChildren[node.url] = node
                            scanningNodeURLs.remove(node.url)
                            let sorted = sort(Array(immediateChildren.values))
                            cache[target] = sorted
                            nodes = Array(sorted.prefix(displayLimit))
                        }
                    case .progress(let statistics):
                        scanStatistics = statistics
                    case .completed(let scannedRoot):
                        let root = scannedRoot
                        storeCachedRoot(root, for: target)
                        present(root, for: target)
                        if recordInHistory, viewStack.last != target {
                            viewStack.append(target)
                        }
                    }
                }
            } catch is CancellationError {
                // A newer navigation request owns the visible state.
            } catch {
                guard activeScanID == scanID, currentFolder == target else { return }
                handleScanFailure(error, target: target)
            }
        }
    }

    /// Compatibility entry point for the existing view. The hierarchy already
    /// comes from the same scan as the list, so this never touches the disk.
    func loadHierarchyForSunburst(maxDepth _: Int = 3) {
        refreshSunburstFromCurrentTree()
    }

    /// Compatibility entry point for depth and view-state changes. Rendering
    /// depth is handled by SunburstView; no filesystem rescan is scheduled.
    func scheduleSunburstRefresh(maxDepth _: Int = 3) {
        refreshSunburstFromCurrentTree()
    }

    func setSizeMetric(_ metric: FileSizeMetric) {
        guard sizeMetric != metric else { return }
        sizeMetric = metric
        guard let currentFolder else { return }
        if let root = scannedRoots[currentFolder] {
            let sortedRoot = sortedTree(root)
            scannedRoots[currentFolder] = sortedRoot
            present(sortedRoot, for: currentFolder)
        } else {
            let sorted = sort(cache[currentFolder] ?? nodes)
            cache[currentFolder] = sorted
            nodes = Array(sorted.prefix(displayLimit))
        }
    }

    func goBackToPreviousView() {
        if let currentFolder, viewStack.last == currentFolder {
            viewStack.removeLast()
        }
        guard let previous = viewStack.last else {
            clearSelection()
            return
        }
        openFolder(previous, recordInHistory: false)
    }

    func cancelScan() {
        guard isScanning else { return }
        cancelCurrentScan()
        isScanning = false
        isSunburstRefreshing = false
        scanningNodeURLs = []
    }

    private func present(_ root: Node, for target: URL) {
        guard currentFolder == target else { return }
        let sorted = sort(root.children)
        nodes = Array(sorted.prefix(displayLimit))
        cache[target] = sorted
        sunburstRoot = root
        isScanning = false
        isSunburstRefreshing = false
        scanningNodeURLs = []
        scanStatistics = nil
        activeScanID = nil
        scanTask = nil
    }

    private func handleScanFailure(_ error: Error, target: URL) {
        isScanning = false
        isSunburstRefreshing = false
        scanningNodeURLs = []
        scanStatistics = nil
        activeScanID = nil
        scanTask = nil
        errorMessage = message(for: error)

        if let previous = viewStack.last, previous != target {
            openFolder(previous, recordInHistory: false)
        } else {
            nodes = []
            sunburstRoot = nil
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case ScanError.accessDenied:
            "Access denied"
        case ScanError.rootNotFound:
            "Folder not found"
        case ScanError.rootIsNotDirectory:
            "The selected item is not a folder"
        case ScanError.invalidOptions(let message):
            message
        case ScanError.metadataUnavailable(_, let description):
            description
        default:
            error.localizedDescription
        }
    }

    private func refreshSunburstFromCurrentTree() {
        guard let currentFolder else { return }
        if let root = scannedRoots[currentFolder] {
            sunburstRoot = root
            isSunburstRefreshing = false
        } else {
            isSunburstRefreshing = isScanning
        }
    }

    private func sortedTree(_ node: Node) -> Node {
        Node(
            url: node.url,
            name: node.name,
            kind: node.kind,
            logicalSize: node.logicalSize,
            allocatedSize: node.allocatedSize,
            access: node.access,
            children: sort(node.children.map(sortedTree)),
            childrenState: node.childrenState
        )
    }

    private func sort(_ nodes: [Node]) -> [Node] {
        nodes.sorted { lhs, rhs in
            let lhsSize = lhs.size(using: sizeMetric)
            let rhsSize = rhs.size(using: sizeMetric)
            if lhsSize == rhsSize {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhsSize > rhsSize
        }
    }

    private func cancelCurrentScan() {
        scanTask?.cancel()
        scanTask = nil
        activeScanID = nil
        if let currentFolder, scannedRoots[currentFolder] == nil {
            cache[currentFolder] = nil
        }
    }

    private func storeCachedRoot(_ root: Node, for target: URL) {
        scannedRoots[target] = root
        cache[target] = root.children
        touchCachedRoot(target)
        while cacheOrder.count > cacheCapacity {
            let evicted = cacheOrder.removeFirst()
            scannedRoots[evicted] = nil
            cache[evicted] = nil
        }
    }

    private func touchCachedRoot(_ target: URL) {
        cacheOrder.removeAll { $0 == target }
        cacheOrder.append(target)
    }

    private func clearSelection() {
        cancelCurrentScan()
        currentFolder = nil
        nodes = []
        breadcrumb = []
        errorMessage = nil
        sunburstRoot = nil
        isScanning = false
        isSunburstRefreshing = false
        scanningNodeURLs = []
    }

    private func normalized(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func makeBreadcrumb(for url: URL) -> [URL] {
        let components = normalized(url).pathComponents
        var breadcrumb: [URL] = []
        var current = URL(fileURLWithPath: "/")
        breadcrumb.append(current)
        for component in components.dropFirst() {
            current.appendPathComponent(component)
            breadcrumb.append(current)
        }
        return breadcrumb
    }
}

extension DiskViewModel {
    var cachedScanCount: Int { scannedRoots.count }

    var currentFolderNode: Node? {
        guard let currentFolder else { return nil }
        if let root = scannedRoots[currentFolder] {
            return root
        }
        let children = cache[currentFolder] ?? nodes
        return Node(
            url: currentFolder,
            name: currentFolder.lastPathComponent.isEmpty ? "/" : currentFolder.lastPathComponent,
            kind: .directory,
            logicalSize: children.reduce(0) { $0 + $1.logicalSize },
            allocatedSize: children.reduce(0) { $0 + $1.allocatedSize },
            access: .readable,
            children: children
        )
    }
}
