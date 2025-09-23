import SwiftUI

enum HeatmapStyle: String {
    case warm
    case cool
    case aqua
    case viridis
    case magma
    case cividis
}

// MARK: - Color interpolation helper
extension Color {
    func interpolate(to: Color, fraction: Double) -> Color {
        let f = max(0, min(1, fraction))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

        NSColor(self).usingColorSpace(.deviceRGB)?
                    .getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        NSColor(to).usingColorSpace(.deviceRGB)?
                    .getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        return Color(
            red: Double(r1 + (r2 - r1) * f),
            green: Double(g1 + (g2 - g1) * f),
            blue: Double(b1 + (b2 - b1) * f),
            opacity: Double(a1 + (a2 - a1) * f)
        )
    }
}

// MARK: - Palette stops
private let viridisStops: [(Double, Color)] = [
    (0.0, Color(red: 0.267, green: 0.005, blue: 0.329)),
    (0.25, Color(red: 0.283, green: 0.141, blue: 0.458)),
    (0.5, Color(red: 0.254, green: 0.265, blue: 0.530)),
    (0.75, Color(red: 0.207, green: 0.372, blue: 0.553)),
    (1.0, Color(red: 0.993, green: 0.906, blue: 0.144))
]

private let magmaStops: [(Double, Color)] = [
    (0.0, Color(red: 0.001, green: 0.000, blue: 0.015)),
    (0.25, Color(red: 0.190, green: 0.072, blue: 0.232)),
    (0.5, Color(red: 0.498, green: 0.118, blue: 0.345)),
    (0.75, Color(red: 0.804, green: 0.305, blue: 0.231)),
    (1.0, Color(red: 0.987, green: 0.991, blue: 0.749))
]

private let cividisStops: [(Double, Color)] = [
    (0.0, Color(red: 0.000, green: 0.135, blue: 0.304)),
    (0.25, Color(red: 0.173, green: 0.275, blue: 0.462)),
    (0.5, Color(red: 0.391, green: 0.414, blue: 0.566)),
    (0.75, Color(red: 0.627, green: 0.540, blue: 0.544)),
    (1.0, Color(red: 0.902, green: 0.960, blue: 0.596))
]

// MARK: - Interpolation
private func interpolateColor(stops: [(Double, Color)], fraction: Double) -> Color {
    let clamped = max(0, min(1, fraction))
    for i in 0..<(stops.count - 1) {
        let (p1, c1) = stops[i]
        let (p2, c2) = stops[i + 1]
        if clamped >= p1 && clamped <= p2 {
            let t = (clamped - p1) / (p2 - p1)
            return c1.interpolate(to: c2, fraction: t)
        }
    }
    return stops.last!.1
}

// MARK: - Main API
extension HeatmapStyle {
    func color(for fraction: Double) -> Color {
        let clamped = max(0.0, min(1.0, fraction))
        switch self {
        case .warm:
            if clamped < 0.5 {
                let t = clamped / 0.5
                return Color(red: t, green: 1.0, blue: 0.0, opacity: 0.65)
            } else {
                let t = (clamped - 0.5) / 0.5
                return Color(red: 1.0, green: 1.0 - t, blue: 0.0, opacity: 0.65)
            }
        case .cool:
            return Color(
                red: 0.4 + 0.6 * clamped,
                green: 0.4,
                blue: 1.0 - 0.5 * clamped,
                opacity: 0.65
            )
        case .aqua:
            if clamped < 0.5 {
                let t = clamped / 0.5
                return Color(
                    red: 0.0,
                    green: 0.8 - 0.3 * t,
                    blue: 1.0 - 0.2 * t,
                    opacity: 0.65
                )
            } else {
                let t = (clamped - 0.5) / 0.5
                return Color(
                    red: 0.0,
                    green: 0.5 - 0.2 * t,
                    blue: 0.8 - 0.3 * t,
                    opacity: 0.65
                )
            }
        case .viridis:
            return interpolateColor(stops: viridisStops, fraction: clamped)
        case .magma:
            return interpolateColor(stops: magmaStops, fraction: clamped)
        case .cividis:
            return interpolateColor(stops: cividisStops, fraction: clamped)
        }
    }
}
