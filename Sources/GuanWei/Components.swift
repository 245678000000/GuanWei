import AppKit
import SwiftUI

enum Theme {
    /// 根据当前外观（浅色 / 深色）自动解析的颜色
    private static func dyn(_ light: (Double, Double, Double, Double), _ dark: (Double, Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
    }

    static let bgTop = dyn((0.965, 0.969, 0.976, 1), (0.075, 0.085, 0.115, 1))
    static let bgBottom = dyn((0.925, 0.933, 0.948, 1), (0.045, 0.05, 0.07, 1))
    static let card = dyn((1, 1, 1, 0.92), (1, 1, 1, 0.045))
    static let stroke = dyn((0, 0, 0, 0.06), (1, 1, 1, 0.07))
    static let track = dyn((0, 0, 0, 0.07), (1, 1, 1, 0.08))
    static let baseline = dyn((0, 0, 0, 0.12), (1, 1, 1, 0.15))
    static let text = dyn((0.07, 0.08, 0.10, 0.92), (1, 1, 1, 0.92))
    static let dim = dyn((0, 0, 0, 0.5), (1, 1, 1, 0.5))
    static let faint = dyn((0, 0, 0, 0.35), (1, 1, 1, 0.3))
    static let cyan = dyn((0.0, 0.60, 0.82, 1), (0.31, 0.82, 0.94, 1))
    static let red = dyn((0.94, 0.27, 0.31, 1), (1.0, 0.37, 0.40, 1))
    static let purple = dyn((0.45, 0.36, 0.96, 1), (0.56, 0.47, 1.0, 1))
    static let green = dyn((0.18, 0.70, 0.38, 1), (0.36, 0.86, 0.52, 1))
    static let orange = dyn((0.96, 0.55, 0.10, 1), (1.0, 0.66, 0.27, 1))
    static let shadow = dyn((0, 0, 0, 0.05), (0, 0, 0, 0))
    static let gray = dyn((0, 0, 0, 0.2), (1, 1, 1, 0.28))
}

struct Card<Content: View>: View {
    let title: String?
    let icon: String?
    let trailing: String?
    let content: Content
    @Environment(\.cardFillsHeight) private var fills

    init(_ title: String? = nil, icon: String? = nil, trailing: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 6) {
                    if let icon {
                        Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.cyan)
                    }
                    Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.cyan)
                    Spacer()
                    if let trailing {
                        Text(trailing).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.faint)
                            .lineLimit(1)
                    }
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card)
            .shadow(color: Theme.shadow, radius: 6, y: 2))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

// MARK: - Rings

struct Ring: View {
    var segments: [(Double, Color)]
    var lineWidth: CGFloat = 8

    init(_ value: Double, color: Color, lineWidth: CGFloat = 8) {
        segments = [(value, color)]
        self.lineWidth = lineWidth
    }

    init(segments: [(Double, Color)], lineWidth: CGFloat = 8) {
        self.segments = segments
        self.lineWidth = lineWidth
    }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            ForEach(Array(segments.enumerated()), id: \.offset) { i, seg in
                let start = segments.prefix(i).reduce(0) { $0 + $1.0 }
                Circle()
                    .trim(from: min(1, start), to: min(1, start + max(0.002, seg.0)))
                    .stroke(seg.1, style: StrokeStyle(lineWidth: lineWidth, lineCap: segments.count == 1 ? .round : .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(lineWidth / 2)
        .animation(.easeOut(duration: 0.6), value: segments.map(\.0))
    }
}

struct RingGauge: View {
    var segments: [(Double, Color)]
    var title: String
    var value: Double
    var size: CGFloat = 92
    var lineWidth: CGFloat = 8

    init(_ value: Double, color: Color, title: String, size: CGFloat = 92, lineWidth: CGFloat = 8) {
        segments = [(value, color)]
        self.value = value
        self.title = title
        self.size = size
        self.lineWidth = lineWidth
    }

    init(segments: [(Double, Color)], title: String, size: CGFloat = 92, lineWidth: CGFloat = 8) {
        self.segments = segments
        self.value = segments.reduce(0) { $0 + $1.0 }
        self.title = title
        self.size = size
        self.lineWidth = lineWidth
    }

    var body: some View {
        ZStack {
            Ring(segments: segments, lineWidth: lineWidth)
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(Fmt.pct(value)).font(.system(size: size * 0.29, weight: .medium)).monospacedDigit()
                    Text("%").font(.system(size: size * 0.14, weight: .medium))
                }
                .foregroundStyle(Theme.text)
                Text(title).font(.system(size: max(9, size * 0.105), weight: .semibold)).foregroundStyle(Theme.dim)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Text helpers

struct BigValue: View {
    var value: String
    var unit: String
    var size: CGFloat = 22

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value).font(.system(size: size, weight: .medium)).monospacedDigit()
            Text(unit).font(.system(size: size * 0.55, weight: .medium)).foregroundStyle(Theme.dim)
        }
        .foregroundStyle(Theme.text)
    }
}

struct Dot: View {
    var color: Color
    var body: some View { Circle().fill(color).frame(width: 7, height: 7) }
}

struct LegendRow: View {
    var color: Color?
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 7) {
            if let color { Dot(color: color) }
            Text(label).foregroundStyle(Theme.text.opacity(0.85))
            Spacer(minLength: 4)
            Text(value).monospacedDigit().foregroundStyle(Theme.text)
        }
        .font(.system(size: 12))
    }
}

struct InfoRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(Theme.dim)
            Spacer(minLength: 4)
            Text(value).monospacedDigit().foregroundStyle(Theme.text).lineLimit(1)
        }
        .font(.system(size: 11.5))
    }
}

// MARK: - Charts

struct StackedBars: View {
    var a: [Double]
    var b: [Double]
    var colorA: Color
    var colorB: Color
    var capacity = Monitor.historySize

    var body: some View {
        Canvas { ctx, size in
            let w = size.width / CGFloat(capacity)
            let n = min(a.count, b.count)
            ctx.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                     with: .color(Theme.baseline))
            for i in 0..<n {
                let x = size.width - CGFloat(n - i) * w
                let hb = max(0, min(1, b[i])) * size.height
                let ha = max(0, min(1, a[i])) * size.height
                let bw = max(1, w - 1.2)
                ctx.fill(Path(CGRect(x: x, y: size.height - hb, width: bw, height: hb)), with: .color(colorB))
                ctx.fill(Path(CGRect(x: x, y: size.height - hb - ha, width: bw, height: ha)), with: .color(colorA))
            }
        }
    }
}

struct MirrorBars: View {
    var up: [Double]
    var down: [Double]
    var upColor: Color = Theme.red
    var downColor: Color = Theme.cyan
    var capacity = Monitor.historySize

    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            let w = size.width / CGFloat(capacity)
            let peak = max(up.max() ?? 0, down.max() ?? 0, 1)
            ctx.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1)),
                     with: .color(Theme.baseline))
            let bw = max(1, w - 1.2)
            for (i, v) in up.enumerated() {
                let x = size.width - CGFloat(up.count - i) * w
                let h = CGFloat(v / peak) * (mid - 1)
                ctx.fill(Path(CGRect(x: x, y: mid - 0.5 - h, width: bw, height: h)), with: .color(upColor))
            }
            for (i, v) in down.enumerated() {
                let x = size.width - CGFloat(down.count - i) * w
                let h = CGFloat(v / peak) * (mid - 1)
                ctx.fill(Path(CGRect(x: x, y: mid + 0.5, width: bw, height: h)), with: .color(downColor))
            }
        }
    }
}

struct CoreRings: View {
    var values: [Double]
    var color: Color

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 8), alignment: .leading, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                Ring(v, color: color, lineWidth: 3.5).frame(width: 22, height: 22)
            }
        }
    }
}

// MARK: - Menu bar label

struct MenuBarLabel: View {
    var cpu: Double?
    var mem: Double?
    var net: (Double, Double)?

    var body: some View {
        HStack(spacing: 9) {
            if cpu == nil && mem == nil && net == nil {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 14, weight: .medium))
            }
            if let cpu { stacked("CPU", Fmt.pct(cpu) + "%") }
            if let mem { stacked("内存", Fmt.pct(mem) + "%") }
            if let net {
                VStack(alignment: .trailing, spacing: -1) {
                    Text(Fmt.rateString(net.0) + " ↑")
                    Text(Fmt.rateString(net.1) + " ↓")
                }
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .frame(minWidth: 62, alignment: .trailing)
            }
        }
        .foregroundStyle(.black)
        .frame(height: 22)
        .padding(.horizontal, 1)
    }

    private func stacked(_ title: String, _ value: String) -> some View {
        VStack(spacing: -1) {
            Text(title).font(.system(size: 7.5, weight: .bold))
            Text(value).font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .frame(minWidth: 28)
    }
}
