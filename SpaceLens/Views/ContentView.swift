import SwiftUI
internal import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = DiskViewModel()
    @State private var transientError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let _ = vm.currentFolder {
                // ✅ Barre du haut : breadcrumb + spinner + bouton reset + bouton choisir dossier
                HStack(spacing: 8) {
                    BreadcrumbView(breadcrumb: vm.breadcrumb) { url in
                        vm.openFolder(url)
                    }

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

                // Compteur live ou résumé final
                if vm.isScanning {
                    // Only global spinner, displayed clearly during scanning
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .controlSize(.regular)
                        Text("Analyse en cours…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        // Add a small red badge for extra scanning visibility
                        Text("Scan en cours")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(6)
                    }
                    .padding(.bottom, 4)
                } else {
                    Text("📦 \(vm.nodes.count) éléments trouvés")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                // Affichage principal : liste toujours visible
                List {
                    let maxSize = vm.nodes.map(\.size).max() ?? 1
                    ForEach(vm.nodes) { node in
                        NodeRowView(node: node, maxSize: maxSize, isScanning: vm.isScanning) { tapped in
                            vm.openFolder(tapped.url)
                        }
                    }
                    // Allows progressive loading of more items when a directory contains many files
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
                
                if vm.nodes.isEmpty {
                    Text("📂 Dossier vide")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

            } else {
                // Vue initiale améliorée
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
                    
                    // ✅ Zone Drop
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
        // ✅ Observe les erreurs et lance un timer de 3s
        .onChange(of: vm.errorMessage) { oldValue, newValue in
            guard let msg = newValue else { return }
            transientError = msg
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if transientError == msg {
                    withAnimation {
                        transientError = nil
                    }
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
        )
    }
}
