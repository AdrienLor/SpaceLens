import SwiftUI

struct BreadcrumbView: View {
    let breadcrumb: [URL]
    let onSelect: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(breadcrumb.indices, id: \.self) { idx in
                    let url = breadcrumb[idx]
                    Button(action: {
                        onSelect(url)
                    }) {
                        Text(displayName(for: url))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)

                    if idx < breadcrumb.count - 1 {
                        Text("›").foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(height: 20)
        .padding(.vertical, 0)
    }

    private func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? "/" : name
    }
}
