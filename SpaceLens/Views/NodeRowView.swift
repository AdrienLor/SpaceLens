import SwiftUI

struct NodeRowView: View {
    let node: Node
    let maxSize: Int64
    let isScanning: Bool
    let onOpen: (Node) -> Void
    
    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .short    // ✅ format court : 22/09/25
        df.timeStyle = .none
        return df
    }

    var body: some View {
        HStack {
            // ✅ Icône
            Image(systemName: node.isDir ? "folder.fill" : "doc.fill")
                .foregroundColor(node.isDir ? .blue : .green)

            // Nom
            Text(node.name)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Date
            if let date = node.modified {
                Text(dateFormatter.string(from: date))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .trailing) // largeur réduite
                    .lineLimit(1)
            }

            // Taille / état
            if node.isDir {
                if node.accessDenied {
                    Text("⚠️ Accès refusé")
                        .foregroundColor(.red)
                        .frame(width: 120, alignment: .trailing)
                } else if node.isLoading {
                    // Avoid AppKit constraint warnings by not forcing conflicting frames on ProgressView
                    ProgressView()
                        .scaleEffect(0.8)
                        .controlSize(.regular)
                        .frame(width: 20, height: 20)
                        .padding(.trailing, 100) // total column width ~120
                } else {
                    Text(sizeLabel(node.size, isDir: node.isDir))
                        .frame(width: 120, alignment: .trailing)
                }
            } else {
                Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                    .frame(width: 120, alignment: .trailing)
            }

            // Barre proportionnelle
            GeometryReader { geo in
                let fraction = maxSize > 0 ? Double(node.size) / Double(maxSize) : 0
                Rectangle()
                    .fill(node.isDir ? Color.blue.opacity(0.6) : Color.green.opacity(0.6))
                    .frame(width: geo.size.width * fraction, height: 10)
                    .cornerRadius(3)
            }
            .frame(height: 10)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isDir {
                onOpen(node)
            }
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(node.url) // ✅ double clic → Finder
        }
        .contextMenu {
            Button("Ouvrir dans Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([node.url])
            }
            Button("Copier le chemin") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path, forType: .string)
            }
        }
    }

    private func sizeLabel(_ size: Int64, isDir: Bool) -> String {
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func moveToTrash(_ url: URL) {
        let fm = FileManager.default
        do {
            try fm.trashItem(at: url, resultingItemURL: nil)
        } catch {
            print("❌ Impossible de supprimer \(url.path): \(error)")
        }
    }
}
