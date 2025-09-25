import SwiftUI

struct SunburstView: View {
    let root: Node
    let heatmapStyle: HeatmapStyle
    let maxDepth: Int
    let minFraction: Double = 0.01
    let onTap: (Node) -> Void
    let isRefreshing: Bool

    @State private var displayLimit: Int = 10

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let chartWidth = geo.size.width * 0.66
                let listWidth = geo.size.width * 0.34
                let sortedChildren = root.children.sorted { $0.size > $1.size }

                HStack(spacing: 0) {
                    ZStack {
                        Canvas { context, size in
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
                                      maxDepth: maxDepth)
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
                                    displayLimit += 10
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
                           maxDepth: Int) {
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
                    depth: depth)

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
                          maxDepth: maxDepth)
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
                    depth: depth)

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
                         depth: Int) {
        let gap: Double = 1.5
        let adjustedStart = startAngle + .degrees(gap / 2)
        let adjustedEnd = endAngle - .degrees(gap / 2)
        guard adjustedEnd > adjustedStart else { return }

        var path = Path()
        path.addArc(center: center,
                    radius: outerRadius,
                    startAngle: adjustedStart,
                    endAngle: adjustedEnd,
                    clockwise: false)
        path.addArc(center: center,
                    radius: innerRadius,
                    startAngle: adjustedEnd,
                    endAngle: adjustedStart,
                    clockwise: true)
        path.closeSubpath()

        let color: Color
        if isOther {
            color = .gray.opacity(0.4)
        } else {
            var baseColor = heatmapStyle.color(for: fraction)
            let adjustment = 1.0 - Double(depth) * 0.08 // darken progressively
            baseColor = baseColor.opacity(adjustment)
            color = baseColor
        }
        context.fill(path, with: .color(color))
        context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 2)
    }
}
