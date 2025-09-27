import SwiftUI
internal import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var vm = DiskViewModel()
    @State private var transientError: String?
    @State private var viewMode: String = "list"
    @AppStorage("sunburstDepth") private var sunburstDepth: Int = 4

    @AppStorage("heatmapStyle") private var heatmapStyleRaw: String = "fileType"
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
        case .fileType:
            return Gradient(colors: [.gray.opacity(0.5), .gray.opacity(0.8)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let _ = vm.currentFolder {
                // Barre du haut : options/actions + breadcrumb
                VStack(spacing: 4) {
                    // First row: options and actions
                    HStack(spacing: 4) {
                        Picker("", selection: $viewMode) {
                            Text("List").tag("list")
                            Text("Sunburst").tag("sunburst")
                        }
                        .pickerStyle(.segmented)

                        Menu {
                            Button("File type (by extension)") { heatmapStyleRaw = "fileType" }
                            Button("Cool (blue→purple)") { heatmapStyleRaw = "cool" }
                            Button("Warm (green→red)") { heatmapStyleRaw = "warm" }
                            Button("Aqua (cyan→blue)") { heatmapStyleRaw = "aqua" }
                            Button("Viridis (scientific)") { heatmapStyleRaw = "viridis" }
                            Button("Magma (scientific)") { heatmapStyleRaw = "magma" }
                            Button("Cividis (scientific)") { heatmapStyleRaw = "cividis" }
                        } label: {
                            Label("\(heatmapStyle.displayName)", systemImage: "paintpalette")
                        }
                        .buttonStyle(.borderless)
                        .frame(minWidth: 160)

                        if viewMode == "sunburst" {
                            HStack(spacing: 4) {
                                Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1, height: 12)
                                Text("Depth:")
                                    .font(.caption)
                                    .frame(minWidth: 38, alignment: .trailing)
                                Picker("", selection: $sunburstDepth) {
                                    ForEach(3..<9) { depth in
                                        Text("\(depth)").tag(depth)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .onChange(of: sunburstDepth) { _, newDepth in
                                    vm.scheduleSunburstRefresh(maxDepth: newDepth)
                                }
                            }
                        }

                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                vm.resetToRoot()
                            }
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .frame(minWidth: 60)

                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                vm.chooseFolder()
                            }
                        } label: {
                            Label("Select folder", systemImage: "folder")
                        }
                        .buttonStyle(.borderless)
                        .frame(minWidth: 100)
                    }
                    .controlSize(.small)

                    ScrollView(.horizontal, showsIndicators: false) {
                        BreadcrumbView(breadcrumb: vm.breadcrumb) { url in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                vm.openFolder(url)
                            }
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
                }

                // Compteur / état de scan
                if vm.isScanning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.6)
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
                    .frame(height: 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                else {
                    Text("")
                        .frame(height: 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Liste principale or SunburstView
                if viewMode == "list" {
                    let maxSize = vm.nodes.map(\.size).max() ?? 1
                    List {
                        ForEach(vm.nodes) { node in
                            NodeRowView(node: node, maxSize: maxSize) { tapped in
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    vm.openFolder(tapped.url)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .listRowInsets(EdgeInsets())
                        }
                        if let currentFolder = vm.currentFolder,
                           vm.nodes.count < vm.cache[currentFolder]?.count ?? 0 {
                            HStack {
                                Spacer()
                                Button("Load up to 100 more…") {
                                    vm.displayLimit += 100
                                    if let cachedNodes = vm.cache[currentFolder] {
                                        vm.nodes = Array(cachedNodes.prefix(vm.displayLimit))
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                    .listStyle(.plain)
                    .padding(.bottom, 8)
                } else {
                    Group {
                        if let root = vm.sunburstRoot {
                            SunburstView(
                                root: root,
                                heatmapStyle: heatmapStyle,
                                maxDepth: sunburstDepth,
                                onTap: { tapped in
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        vm.openFolder(tapped.url)
                                    }
                                },
                                isRefreshing: vm.isSunburstRefreshing
                            )
                            .onChange(of: sunburstDepth) { _, newDepth in
                                vm.scheduleSunburstRefresh(maxDepth: newDepth)
                            }
                        } else {
                            Spacer()
                            VStack(spacing: 2) {
                                ProgressView()
                                Text("Building sunburst…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .onAppear {
                                vm.scheduleSunburstRefresh(maxDepth: sunburstDepth)
                            }
                            Spacer()
                        }
                    }
                    .onChange(of: vm.isScanning) { _, _ in
                        vm.scheduleSunburstRefresh(maxDepth: sunburstDepth)
                    }
                    .onChange(of: vm.nodes.count) { _, _ in
                        vm.scheduleSunburstRefresh(maxDepth: sunburstDepth)
                    }
                    .padding(.top, 8)
                }
                
                Text("")
                    .frame(height: 12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Légende heatmap
                if heatmapStyle == .fileType {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .firstTextBaseline, spacing: 20) {
                            // Group 1: Media
                            HStack(spacing: 12) {
                                HStack(spacing: 6) { Circle().fill(Color.blue.opacity(0.6)).frame(width: 10, height: 10); Text("Folders") }
                                HStack(spacing: 6) { Circle().fill(Color(red: 0.0, green: 0.7, blue: 0.8)).frame(width: 10, height: 10); Text("Images") }
                                HStack(spacing: 6) { Circle().fill(Color(red: 0.6, green: 0.2, blue: 0.7)).frame(width: 10, height: 10); Text("Videos") }
                                HStack(spacing: 6) { Circle().fill(Color.orange.opacity(0.9)).frame(width: 10, height: 10); Text("Audio") }
                            }

                            Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1, height: 12)

                            // Group 2: Documents
                            HStack(spacing: 12) {
                                HStack(spacing: 6) { Circle().fill(Color.green).frame(width: 10, height: 10); Text("Docs") }
                                HStack(spacing: 6) { Circle().fill(Color(red: 0.89, green: 0.0, blue: 0.0)).frame(width: 10, height: 10); Text("PDF") }
                                HStack(spacing: 6) { Circle().fill(Color.mint).frame(width: 10, height: 10); Text("Spreadsheets") }
                                HStack(spacing: 6) { Circle().fill(Color(red: 0.86, green: 0.35, blue: 0.01)).frame(width: 10, height: 10); Text("Presentations") }
                                HStack(spacing: 6) { Circle().fill(Color.brown).frame(width: 10, height: 10); Text("Archives") }
                            }

                            Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1, height: 12)

                            // Group 3: Development
                            HStack(spacing: 12) {
                                HStack(spacing: 6) { Circle().fill(Color(red: 0.0, green: 0.6, blue: 1.0)).frame(width: 10, height: 10); Text("Code") }
                                HStack(spacing: 6) { Circle().fill(Color.yellow.opacity(0.8)).frame(width: 10, height: 10); Text("Data") }
                            }

                            Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1, height: 12)

                            // Group 4: System
                            HStack(spacing: 12) {
                                HStack(spacing: 6) { Circle().fill(Color.gray).frame(width: 10, height: 10); Text("Disk") }
                                HStack(spacing: 6) { Circle().fill(Color.indigo.opacity(0.7)).frame(width: 10, height: 10); Text("Other") }
                            }
                        }
                        .font(.caption2)
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }
                } else {
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
                }
                
                if vm.nodes.isEmpty {
                    Text("📂 empty folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                    

            } else {
                // Vue initiale
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    Text("Welcome to SpaceLens")
                        .font(.title2)
                        .bold()

                    Text("Easily analyze the disk space of your folders.\nSelect a folder or drag one here.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    Button(action: { vm.chooseFolder() }) {
                        Label("Select folder…", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)

                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .frame(width: 250, height: 100)
                        .foregroundColor(.secondary)
                        .overlay(
                            Text("Drag a folder here")
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
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(minWidth: 960, minHeight: 400)
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


extension HeatmapStyle {
    var displayName: String {
        switch self {
        case .cool: return "Cool (blue→purple)"
        case .warm: return "Warm (green→red)"
        case .aqua: return "Aqua (cyan→blue)"
        case .viridis: return "Viridis"
        case .magma: return "Magma"
        case .cividis: return "Cividis"
        case .fileType: return "By file type"
        }
    }
}

import AppKit

struct WindowMinSizeEnforcer: NSViewRepresentable {
    let minSize: NSSize
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { v.window?.minSize = minSize }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.minSize = minSize }
    }
}
