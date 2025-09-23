import SwiftUI
internal import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = DiskViewModel()
    @State private var transientError: String?

    @AppStorage("heatmapStyle") private var heatmapStyleRaw: String = "cool"
    private var heatmapStyle: HeatmapStyle {
        HeatmapStyle(rawValue: heatmapStyleRaw) ?? .warm
    }

    private func gradientForStyle(_ style: HeatmapStyle) -> Gradient {
        switch style {
        case .warm:
            return Gradient(colors: [.green.opacity(0.65), .yellow.opacity(0.65), .red.opacity(0.65)])
        case .cool:
            return Gradient(colors: [.blue.opacity(0.65), .indigo.opacity(0.65), .purple.opacity(0.65)])
        case .aqua:
            return Gradient(colors: [.cyan.opacity(0.65), .teal.opacity(0.65), .blue.opacity(0.65)])
        case .viridis:
            return Gradient(colors: [
                Color(red: 0.267, green: 0.005, blue: 0.329),
                Color(red: 0.283, green: 0.141, blue: 0.458),
                Color(red: 0.254, green: 0.265, blue: 0.530),
                Color(red: 0.207, green: 0.372, blue: 0.553),
                Color(red: 0.993, green: 0.906, blue: 0.144)
            ])
        case .magma:
            return Gradient(colors: [
                Color(red: 0.001, green: 0.000, blue: 0.015),
                Color(red: 0.190, green: 0.072, blue: 0.232),
                Color(red: 0.498, green: 0.118, blue: 0.345),
                Color(red: 0.804, green: 0.305, blue: 0.231),
                Color(red: 0.987, green: 0.991, blue: 0.749)
            ])
        case .cividis:
            return Gradient(colors: [
                Color(red: 0.000, green: 0.135, blue: 0.304),
                Color(red: 0.173, green: 0.275, blue: 0.462),
                Color(red: 0.391, green: 0.414, blue: 0.566),
                Color(red: 0.627, green: 0.540, blue: 0.544),
                Color(red: 0.902, green: 0.960, blue: 0.596)
            ])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let _ = vm.currentFolder {
                // Barre du haut : breadcrumb + heatmap style + reset + choisir dossier
                HStack(spacing: 8) {
                    BreadcrumbView(breadcrumb: vm.breadcrumb) { url in
                        vm.openFolder(url)
                    }

                    Menu {
                        Button("Cool (blue→purple)") { heatmapStyleRaw = "cool" }
                        Button("Warm (green→red)") { heatmapStyleRaw = "warm" }
                        Button("Aqua (cyan→blue)") { heatmapStyleRaw = "aqua" }
                        Button("Viridis (scientific)") { heatmapStyleRaw = "viridis" }
                        Button("Magma (scientific)") { heatmapStyleRaw = "magma" }
                        Button("Cividis (scientific)") { heatmapStyleRaw = "cividis" }
                    } label: {
                        Label("Heatmap", systemImage: "paintpalette")
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button {
                        vm.resetToRoot()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        vm.chooseFolder()
                    } label: {
                        Label("Choisir dossier", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.bottom, 4)

                // Compteur / état de scan
                if vm.isScanning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .controlSize(.regular)
                        Text("Scan")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(6)
                    }
                    .padding(.bottom, 4)
                } else {
                    Text("📦 \(vm.nodes.count) éléments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                // Liste principale
                let maxSize = vm.nodes.map(\.size).max() ?? 1
                List {
                    ForEach(vm.nodes) { node in
                        NodeRowView(node: node, maxSize: maxSize) { tapped in
                            vm.openFolder(tapped.url)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(EdgeInsets())
                    }
                    if let currentFolder = vm.currentFolder,
                       vm.nodes.count < vm.cache[currentFolder]?.count ?? 0 {
                        HStack {
                            Spacer()
                            Button("Charger plus…") {
                                vm.displayLimit += 20
                                if let cachedNodes = vm.cache[currentFolder] {
                                    vm.nodes = Array(cachedNodes.prefix(vm.displayLimit))
                                }
                            }
                            Spacer()
                        }
                    }
                }
                .listStyle(.plain)

                // Légende heatmap
                HStack(spacing: 0) {
                    LinearGradient(
                        gradient: gradientForStyle(heatmapStyle),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 12)
                    .cornerRadius(4)

                    Text(" ← smaller  |  larger → ")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
                .padding(.horizontal)
                .padding(.top, 4)

                if vm.nodes.isEmpty {
                    Text("📂 Dossier vide")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

            } else {
                // Vue initiale
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    Text("Bienvenue dans SpaceLens")
                        .font(.title2)
                        .bold()

                    Text("Analysez facilement l’espace disque de vos dossiers.\nSélectionnez un dossier ou glissez-en un ici.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Button(action: { vm.chooseFolder() }) {
                        Label("Choisir un dossier…", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)

                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .frame(width: 250, height: 100)
                        .foregroundColor(.secondary)
                        .overlay(
                            Text("Glissez un dossier ici")
                                .foregroundColor(.secondary)
                        )
                        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                            for provider in providers {
                                _ = provider.loadObject(ofClass: URL.self) { object, _ in
                                    if let url = object, url.hasDirectoryPath {
                                        DispatchQueue.main.async {
                                            vm.openFolder(url)
                                        }
                                    }
                                }
                            }
                            return true
                        }
                        .padding(.top, 12)

                    Spacer()
                }
            }
        }
        .padding()
        .onChange(of: vm.errorMessage) { oldValue, newValue in
            guard let msg = newValue else { return }
            transientError = msg
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if transientError == msg {
                    withAnimation { transientError = nil }
                }
            }
        }
        .overlay(
            Group {
                if let msg = transientError {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(10)
                        .transition(.opacity)
                        .animation(.easeInOut, value: transientError)
                        .padding(.bottom, 30)
                        .frame(maxWidth: .infinity,
                               maxHeight: .infinity,
                               alignment: .bottom)
                }
            }
        )
    }
}
