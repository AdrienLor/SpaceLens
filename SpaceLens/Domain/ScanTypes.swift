import Foundation

enum FileSizeMetric: String, Sendable, CaseIterable {
    case logical
    case allocated
}

enum PackageTraversal: String, Sendable, CaseIterable {
    case descendants
    case singleNode
}

struct ScanOptions: Sendable, Equatable {
    var sizeMetric: FileSizeMetric = .allocated
    var includesHiddenFiles = true
    var packageTraversal: PackageTraversal = .singleNode
    var followsSymbolicLinks = false
    var maximumDepth: Int?
    var maximumReportedDepth: Int?
    var maximumConcurrentMetadataRequests = 2
}

enum ScannedItemKind: Sendable, Equatable {
    case regularFile
    case directory
    case package
    case symbolicLink(destination: URL?)
    case other
}

enum FolderAccess: Sendable, Equatable {
    case readable
    case partiallyReadable(deniedItemCount: Int)
    case denied
}

struct Node: Identifiable, Sendable, Equatable {
    var id: URL { url }

    let url: URL
    let name: String
    let kind: ScannedItemKind
    let logicalSize: Int64
    let allocatedSize: Int64
    let access: FolderAccess
    let children: [Node]

    var size: Int64 { allocatedSize }

    var isDir: Bool {
        switch kind {
        case .directory, .package:
            true
        case .regularFile, .symbolicLink, .other:
            false
        }
    }

    var accessDenied: Bool { access == .denied }

    func size(using metric: FileSizeMetric) -> Int64 {
        switch metric {
        case .logical:
            logicalSize
        case .allocated:
            allocatedSize
        }
    }
}

struct ScanStatistics: Sendable, Equatable {
    let discoveredItemCount: Int
    let logicalBytes: Int64
    let allocatedBytes: Int64
    let currentURL: URL?
}

enum ScanEvent: Sendable, Equatable {
    case started(root: URL)
    case listed(Node, parent: URL)
    case discovered(Node, parent: URL?)
    case progress(ScanStatistics)
    case completed(Node)
}

enum ScanError: Error, Sendable, Equatable {
    case rootNotFound(URL)
    case rootIsNotDirectory(URL)
    case accessDenied(URL)
    case metadataUnavailable(URL, description: String)
    case invalidOptions(String)
}
