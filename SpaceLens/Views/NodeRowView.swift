import SwiftUI

struct NodeRowView: View {
    let node: Node
    let maxSize: Int64
    let onOpen: (Node) -> Void

    private let nameColumnMinWidth: CGFloat = 140
    private let nameColumnIdealWidth: CGFloat = 220
    private let nameColumnMaxWidth: CGFloat = 320
    private let sizeColumnWidth: CGFloat = 120
    private let barHeight: CGFloat = 14

    @AppStorage("heatmapStyle") private var heatmapStyleRaw: String = "cool"

    private var heatmapStyle: HeatmapStyle {
        HeatmapStyle(rawValue: heatmapStyleRaw) ?? .warm
    }

    var body: some View {
        HStack(spacing: 12) {
            // Colonne 1 : Nom + icône
            HStack(spacing: 6) {
                Image(systemName: node.isDir ? "folder.fill" : "doc.text.fill")
                    .foregroundColor(node.isDir ? .blue : .gray)
                    .frame(width: 20)
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(minWidth: nameColumnMinWidth,
                   idealWidth: nameColumnIdealWidth,
                   maxWidth: nameColumnMaxWidth,
                   alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isDir && !node.accessDenied {
                    onOpen(node)
                }
            }

            // Colonne 2 : Taille / état
            Group {
                if node.accessDenied {
                    Text("⚠️ Access denied")
                        .foregroundColor(.red)
                        .frame(width: sizeColumnWidth, alignment: .trailing)
                } else if node.isLoading {
                    HStack { Spacer(); ProgressView().scaleEffect(0.85).controlSize(.small) }
                        .frame(width: sizeColumnWidth, alignment: .trailing)
                } else {
                    Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                        .font(.footnote).monospacedDigit()
                        .frame(width: sizeColumnWidth, alignment: .trailing)
                }
            }

            // Colonne 3 : Barre heatmap
            ZStack(alignment: .leading) {
                GeometryReader { geo in
                    let fraction = max(0, min(1, maxSize > 0 ? Double(node.size) / Double(maxSize) : 0))
                    let width = max(fraction > 0 ? 2 : 0, geo.size.width * fraction)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(heatmapStyle.color(for: fraction))
                        .frame(width: width, height: barHeight)
                }
            }
            .frame(maxWidth: .infinity,
                   minHeight: barHeight,
                   maxHeight: barHeight,
                   alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Open in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path, forType: .string)
            }
        }
    }
}
