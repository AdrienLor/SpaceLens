import Foundation

struct Node: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    var size: Int64
    var isDir: Bool
    var modified: Date?         
    var children: [Node] = []
    var accessDenied: Bool = false
    var isLoading: Bool = false
}
