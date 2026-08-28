import SwiftUI
import AppKit

struct SunburstView: View {
    private struct OtherSummary {
        let itemCount: Int
        let size: Int64
    }

    private enum SectorPayload {
        case node(Node)
        case other(OtherSummary)
    }

    let root: Node
    let heatmapStyle: HeatmapStyle
    let sizeMetric: FileSizeMetric
    let maxDepth: Int
    let minFraction: Double = 0.01
    let onTap: (Node) -> Void
    let isRefreshing: Bool

    @State private var displayLimit: Int = 50
    @State private var hoveredPayload: SectorPayload?
    @State private var hoverLocation: CGPoint? = nil
    @State private var sectors: [(Path, SectorPayload)] = []
    @State private var sectorCanvasSize: CGSize = .zero
    @State private var sectorConfiguration = ""
    @State private var pressedNode: Node? = nil

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let chartWidth = geo.size.width * 0.66
                let listWidth = geo.size.width * 0.34
                let sortedChildren = root.children.sorted {
                    $0.size(using: sizeMetric) > $1.size(using: sizeMetric)
                }

                HStack(spacing: 0) {
                    ZStack {
                        ZStack {
                            Canvas(
                                    opaque: false,
                                    colorMode: .nonLinear,
                                    rendersAsynchronously: false,
                                    renderer: { context, size in
                                        var builtSectors: [(Path, SectorPayload)] = []
                                        let totalRadius = min(chartWidth, geo.size.height) / 2.0 * 0.95
                                        let center = CGPoint(x: chartWidth / 2, y: geo.size.height / 2)
                                        let centerHole = totalRadius * 0.2

                                        drawLevel(nodes: root.children,
                                                  in: &context,
                                                  center: center,
                                                  innerRadius: centerHole,
                                                  outerRadius: totalRadius,
                                                  startAngle: .degrees(0),
                                                  endAngle: .degrees(360),
                                                  depth: 0,
                                                  maxDepth: maxDepth,
                                                  sectorsOut: &builtSectors)

                                        if case .node(let hovered) = hoveredPayload {
                                            for (path, payload) in builtSectors {
                                                guard case .node(let node) = payload else { continue }
                                                if node.id == hovered.id {
                                                    context.fill(path, with: .color(.white.opacity(0.14)))
                                                    context.stroke(path, with: .color(.white), lineWidth: 2.5)
                                                } else if isAncestor(node, of: hovered) {
                                                    context.stroke(
                                                        path,
                                                        with: .color(.white.opacity(0.55)),
                                                        lineWidth: 1.5
                                                    )
                                                }
                                            }
                                        } else if case .other(let hovered) = hoveredPayload,
                                                  let hoveredPath = builtSectors.first(where: {
                                                      if case .other(let summary) = $0.1 {
                                                          return summary.itemCount == hovered.itemCount
                                                              && summary.size == hovered.size
                                                      }
                                                      return false
                                                  })?.0 {
                                            context.fill(hoveredPath, with: .color(.white.opacity(0.14)))
                                            context.stroke(hoveredPath, with: .color(.white), lineWidth: 2.5)
                                        }

                                        let configuration = "\(root.id.path)|\(maxDepth)|\(sizeMetric.rawValue)|\(heatmapStyle.rawValue)"
                                        if sectorCanvasSize != size || sectorConfiguration != configuration {
                                            DispatchQueue.main.async {
                                                self.sectors = builtSectors
                                                self.sectorCanvasSize = size
                                                self.sectorConfiguration = configuration
                                            }
                                        }
                                    }
                                )
                                .id(root.id)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.3), value: root.id)
                        }
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let match = sectors.first(where: { $0.0.contains(location) })?.1 {
                                    hoveredPayload = match
                                    hoverLocation = location
                                    if case .node(let node) = match, !node.children.isEmpty {
                                        NSCursor.pointingHand.set()
                                    } else {
                                        NSCursor.arrow.set()
                                    }
                                } else {
                                    hoveredPayload = nil
                                    hoverLocation = nil
                                    NSCursor.arrow.set()
                                }
                            case .ended:
                                hoveredPayload = nil
                                hoverLocation = nil
                                NSCursor.arrow.set()
                            }
                        }
                        .onDisappear {
                            NSCursor.arrow.set()
                        }
                        .onTapGesture {
                            if case .node(let node) = hoveredPayload, !node.children.isEmpty {
                                pressedNode = node
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    pressedNode = nil
                                }
                                onTap(node)
                            }
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            if case .node(let hovered) = hoveredPayload {
                                Button("Open in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([hovered.url])
                                }
                                Button("Copy Path") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(hovered.url.path, forType: .string)
                                }
                            } else {
                                Text("No item selected")
                                    .disabled(true)
                            }
                        }
                        if let hoveredPayload, let loc = hoverLocation {
                            Text(tooltip(for: hoveredPayload))
                                .font(.caption)
                                .padding(4)
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                                .position(
                                    x: min(max(loc.x + 16, 110), chartWidth - 110),
                                    y: min(max(loc.y + 28, 20), geo.size.height - 20)
                                )
                                .allowsHitTesting(false)
                        }
                        VStack {
                            Text(root.name)
                                .font(.headline)
                            Text(ByteCountFormatter.string(fromByteCount: root.size(using: sizeMetric), countStyle: .file))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(width: chartWidth, height: geo.size.height, alignment: .center)
                        .position(x: chartWidth / 2, y: geo.size.height / 2)
                        .allowsHitTesting(false)
                    }
                    .frame(width: chartWidth, height: geo.size.height)

                    VStack(alignment: .leading, spacing: 0) {
                        List {
                            ForEach(sortedChildren.prefix(displayLimit), id: \.id) { child in
                                NodeRowView(
                                    node: child,
                                    maxSize: 0,
                                    sizeMetric: sizeMetric,
                                    onOpen: { url in
                                        onTap(child)
                                    }
                                )
                            }
                            if sortedChildren.count > displayLimit {
                                Button("…") {
                                    displayLimit += 50
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.blue)
                            }
                        }
                        .listStyle(.plain)
                    }
                    .frame(width: listWidth)
                }
            }

            if isRefreshing {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                    Text("Refreshing sunburst…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding()
            }
        }
    }

    private func tooltip(for payload: SectorPayload) -> String {
        guard case .node(let node) = payload else {
            if case .other(let summary) = payload {
                let size = ByteCountFormatter.string(fromByteCount: summary.size, countStyle: .file)
                return "Other – \(summary.itemCount) small items – \(size)"
            }
            return "Other"
        }
        let size = ByteCountFormatter.string(fromByteCount: node.size(using: sizeMetric), countStyle: .file)
        let rootSize = root.size(using: sizeMetric)
        let percentage = rootSize > 0
            ? String(format: "%.1f%%", Double(node.size(using: sizeMetric)) / Double(rootSize) * 100)
            : "0%"
        switch node.childrenState {
        case .complete:
            return "\(node.name) – \(size) – \(percentage) of root"
        case .depthLimited:
            return "\(node.name) – \(size) – \(percentage) of root – deeper contents not loaded"
        case .packageBoundary:
            return "\(node.name) – \(size) – \(percentage) of root – package contents grouped"
        }
    }

    private func drawLevel(nodes: [Node],
                           in context: inout GraphicsContext,
                           center: CGPoint,
                           innerRadius: CGFloat,
                           outerRadius: CGFloat,
                           startAngle: Angle,
                           endAngle: Angle,
                           depth: Int,
                           maxDepth: Int,
                           sectorsOut: inout [(Path, SectorPayload)]) {
        guard depth < maxDepth else { return }
        let totalSize = nodes.reduce(0) { $0 + $1.size(using: sizeMetric) }
        guard totalSize > 0 else { return }

        let totalRings = maxDepth
        let ringThickness = (outerRadius - innerRadius) / CGFloat(totalRings)

        let thisInner = innerRadius + CGFloat(depth) * ringThickness
        let thisOuter = innerRadius + CGFloat(depth + 1) * ringThickness

        var currentAngle = startAngle
        var smallNodes: [Node] = []

        for node in nodes {
            let nodeSize = node.size(using: sizeMetric)
            guard nodeSize > 0 else { continue }
            let fraction = Double(nodeSize) / Double(totalSize)

            if fraction < minFraction {
                smallNodes.append(node)
                continue
            }

            let sweepDegrees = (endAngle.degrees - startAngle.degrees) * fraction
            let sweep = Angle(degrees: sweepDegrees)
            let nextAngle = currentAngle + sweep

            drawArc(for: node,
                    fraction: fraction,
                    in: &context,
                    center: center,
                    innerRadius: thisInner,
                    outerRadius: thisOuter,
                    startAngle: currentAngle,
                    endAngle: nextAngle,
                    depth: depth,
                    sectorsOut: &sectorsOut)

            // récursion : enfants → anneau suivant
            if !node.children.isEmpty {
                drawLevel(nodes: node.children,
                          in: &context,
                          center: center,
                          innerRadius: innerRadius,   // keep global hole reference
                          outerRadius: outerRadius,   // keep global total radius
                          startAngle: currentAngle,
                          endAngle: nextAngle,
                          depth: depth + 1,
                          maxDepth: maxDepth,
                          sectorsOut: &sectorsOut)
            }

            currentAngle = nextAngle
        }

        // Regrouper les petits
        if !smallNodes.isEmpty {
            let smallTotal = smallNodes.reduce(0) { $0 + $1.size(using: sizeMetric) }
            let fraction = Double(smallTotal) / Double(totalSize)
            let sweepDegrees = (endAngle.degrees - startAngle.degrees) * fraction
            let sweep = Angle(degrees: sweepDegrees)
            let nextAngle = currentAngle + sweep

            drawArc(for: nil,
                    fraction: fraction,
                    in: &context,
                    center: center,
                    innerRadius: thisInner,
                    outerRadius: thisOuter,
                    startAngle: currentAngle,
                    endAngle: nextAngle,
                    isOther: true,
                    otherSummary: OtherSummary(itemCount: smallNodes.count, size: smallTotal),
                    depth: depth,
                    sectorsOut: &sectorsOut)

            currentAngle = nextAngle
        }
    }

    private func drawArc(for node: Node?,
                         fraction: Double,
                         in context: inout GraphicsContext,
                         center: CGPoint,
                         innerRadius: CGFloat,
                         outerRadius: CGFloat,
                         startAngle: Angle,
                         endAngle: Angle,
                         isOther: Bool = false,
                         otherSummary: OtherSummary? = nil,
                         depth: Int,
                         sectorsOut: inout [(Path, SectorPayload)]) {
        let gap: Double = 1.5
        let adjustedStart = startAngle + .degrees(gap / 2)
        let adjustedEnd = endAngle - .degrees(gap / 2)
        guard adjustedEnd > adjustedStart else { return }

        let animatedEnd = adjustedEnd

        var path = Path()
        path.addArc(center: center,
                    radius: outerRadius,
                    startAngle: adjustedStart,
                    endAngle: animatedEnd,
                    clockwise: false)
        path.addArc(center: center,
                    radius: innerRadius,
                    startAngle: animatedEnd,
                    endAngle: adjustedStart,
                    clockwise: true)
        path.closeSubpath()

        let color: Color
        if isOther {
            color = .gray.opacity(0.4)
        } else if let node = node {
            let adjustment = 1.0 - min(Double(depth) * 0.03, 0.18)
            color = sunburstColor(for: node, fraction: fraction).opacity(adjustment)
        } else {
            let adjustment = 1.0 - min(Double(depth) * 0.03, 0.18)
            color = heatmapStyle.color(for: fraction).opacity(adjustment)
        }
        context.fill(path, with: .color(color))
        context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 2)
        if let node = node {
            sectorsOut.append((path, .node(node)))
        } else if let otherSummary {
            sectorsOut.append((path, .other(otherSummary)))
        }
        if let node = node, node.id == pressedNode?.id {
            context.fill(path, with: .color(.white.opacity(0.3)))
        }
    }

    private func sunburstColor(for node: Node, fraction: Double) -> Color {
        guard heatmapStyle == .fileType, node.isDir else {
            return heatmapStyle.color(for: node, fraction: fraction)
        }
        guard let representative = dominantLeaf(in: node) else {
            return heatmapStyle.color(for: node, fraction: fraction)
        }
        return heatmapStyle.color(for: representative, fraction: fraction)
    }

    private func dominantLeaf(in node: Node) -> Node? {
        guard node.isDir else { return node }
        guard let largest = node.children.max(by: {
            $0.size(using: sizeMetric) < $1.size(using: sizeMetric)
        }) else { return nil }
        return dominantLeaf(in: largest)
    }

    private func isAncestor(_ candidate: Node, of node: Node) -> Bool {
        let candidateComponents = candidate.url.standardizedFileURL.pathComponents
        let nodeComponents = node.url.standardizedFileURL.pathComponents
        return candidate.id != node.id && nodeComponents.starts(with: candidateComponents)
    }

    private func findNode(by id: Node.ID, in node: Node) -> Node? {
        if node.id == id { return node }
        for child in node.children {
            if let found = findNode(by: id, in: child) {
                return found
            }
        }
        return nil
    }
}
