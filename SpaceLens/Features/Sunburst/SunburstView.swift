import SwiftUI
import AppKit

struct SunburstView: View {
    let root: Node
    let heatmapStyle: HeatmapStyle
    let maxDepth: Int
    let minFraction: Double = 0.01
    let onTap: (Node) -> Void
    let isRefreshing: Bool

    @State private var displayLimit: Int = 50
    @State private var hoveredNode: Node? = nil
    @State private var hoverLocation: CGPoint? = nil
    @State private var sectors: [(Path, Node)] = []
    @State private var pressedNode: Node? = nil
    @State private var buildProgress: Double = 1.0

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let chartWidth = geo.size.width * 0.66
                let listWidth = geo.size.width * 0.34
                let sortedChildren = root.children.sorted { $0.size > $1.size }

                HStack(spacing: 0) {
                    ZStack {
                        ZStack {
                            TimelineView(.animation) { _ in
                                Canvas(
                                    opaque: false,
                                    colorMode: .nonLinear,
                                    rendersAsynchronously: true,
                                    renderer: { context, size in
                                        var builtSectors: [(Path, Node)] = []
                                        let totalRadius = min(chartWidth, geo.size.height) / 2.0 * 0.95
                                        let center = CGPoint(x: chartWidth / 2, y: geo.size.height / 2)
                                        let centerHole = totalRadius * 0.2

                                        drawLevel(nodes: [root],
                                                  in: &context,
                                                  center: center,
                                                  innerRadius: centerHole,
                                                  outerRadius: totalRadius,
                                                  startAngle: .degrees(0),
                                                  endAngle: .degrees(360),
                                                  depth: 0,
                                                  maxDepth: maxDepth,
                                                  sectorsOut: &builtSectors)

                                        if let hovered = hoveredNode,
                                           let hoveredPath = builtSectors.first(where: { $0.1.id == hovered.id })?.0,
                                           !hovered.children.isEmpty {
                                            context.stroke(hoveredPath, with: .color(.white), lineWidth: 2)
                                        }

                                        DispatchQueue.main.async {
                                            self.sectors = builtSectors
                                        }
                                    }
                                )
                                .id(root.id)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                                .animation(.easeInOut(duration: 0.3), value: root.id)
                                .animation(.easeInOut(duration: 0.15), value: hoveredNode?.id)
                            }
                        }
                        .onChange(of: root.id) {
                            buildProgress = 0.0
                            withAnimation(.easeOut(duration: 0.8)) {
                                buildProgress = 1.0
                            }
                        }
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                if let match = sectors.first(where: { $0.0.contains(location) })?.1 {
                                    hoveredNode = match
                                    hoverLocation = location
                                    if !match.children.isEmpty {
                                        NSCursor.pointingHand.push()
                                    } else {
                                        NSCursor.arrow.push()
                                    }
                                } else {
                                    hoveredNode = nil
                                    hoverLocation = nil
                                    NSCursor.arrow.push()
                                }
                            case .ended:
                                hoveredNode = nil
                                hoverLocation = nil
                                NSCursor.arrow.push()
                            }
                        }
                        .onDisappear {
                            NSCursor.arrow.push()
                        }
                        .onTapGesture {
                            if let node = hoveredNode, !node.children.isEmpty {
                                pressedNode = node
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    pressedNode = nil
                                }
                                onTap(node)
                            }
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            if let hovered = hoveredNode {
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
                        if let hovered = hoveredNode, let loc = hoverLocation {
                            Text("\(hovered.name) – \(ByteCountFormatter.string(fromByteCount: Int64(hovered.size), countStyle: .file))")
                                .font(.caption)
                                .padding(4)
                                .background(Color.black.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(6)
                                .position(x: loc.x + 16, y: loc.y + 28)
                                .allowsHitTesting(false)
                        }
                        VStack {
                            Text(root.name)
                                .font(.headline)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(root.size), countStyle: .file))
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

            if root.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                        .frame(width: 20, height: 20)
                    Text("Building sunburst…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.05))
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

    private func drawLevel(nodes: [Node],
                           in context: inout GraphicsContext,
                           center: CGPoint,
                           innerRadius: CGFloat,
                           outerRadius: CGFloat,
                           startAngle: Angle,
                           endAngle: Angle,
                           depth: Int,
                           maxDepth: Int,
                           sectorsOut: inout [(Path, Node)]) {
        guard depth < maxDepth else { return }
        let totalSize = nodes.map(\.size).reduce(0, +)
        guard totalSize > 0 else { return }

        let totalRings = maxDepth
        let ringThickness = (outerRadius - innerRadius) / CGFloat(totalRings)

        let thisInner = innerRadius + CGFloat(depth) * ringThickness
        let thisOuter = innerRadius + CGFloat(depth + 1) * ringThickness

        var currentAngle = startAngle
        var smallNodes: [Node] = []

        for node in nodes {
            guard node.size > 0 else { continue }
            let fraction = Double(node.size) / Double(totalSize)

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
            let smallTotal = smallNodes.map(\.size).reduce(0, +)
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
                         depth: Int,
                         sectorsOut: inout [(Path, Node)]) {
        let gap: Double = 1.5
        let adjustedStart = startAngle + .degrees(gap / 2)
        let adjustedEnd = endAngle - .degrees(gap / 2)
        guard adjustedEnd > adjustedStart else { return }

        let sweepDegreesFull = adjustedEnd.degrees - adjustedStart.degrees
        let sweepDegrees = sweepDegreesFull * buildProgress
        let animatedEnd = adjustedStart + .degrees(sweepDegrees)

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
            if case .fileType = heatmapStyle {
                // In fileType mode, only darken folders (to preserve color integrity of files)
                if node.url.hasDirectoryPath {
                    let adjustment = 1.0 - Double(depth) * 0.08
                    color = heatmapStyle.color(for: node, fraction: fraction).opacity(adjustment)
                } else {
                    color = heatmapStyle.color(for: node, fraction: fraction)
                }
            } else {
                let adjustment = 1.0 - Double(depth) * 0.08
                color = heatmapStyle.color(for: node, fraction: fraction).opacity(adjustment)
            }
        } else {
            let adjustment = 1.0 - Double(depth) * 0.08
            color = heatmapStyle.color(for: fraction).opacity(adjustment)
        }
        context.fill(path, with: .color(color))
        context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 2)
        if let node = node {
            sectorsOut.append((path, node))
        }
        if let node = node, node.id == pressedNode?.id {
            context.fill(path, with: .color(.white.opacity(0.3)))
        }
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
