import SwiftUI

struct HourglassVisual: View {
    let percent: Int?
    let isStale: Bool

    private var progress: Double {
        Double(percent ?? 0) / 100
    }

    private var sandColor: Color {
        guard !isStale, let percent else { return .secondary }
        if percent <= 10 { return Color(red: 0.95, green: 0.30, blue: 0.26) }
        if percent <= 30 { return Color(red: 0.98, green: 0.58, blue: 0.20) }
        return Color(red: 0.98, green: 0.76, blue: 0.32)
    }

    var body: some View {
        ZStack {
            hourglassCanvas
            if percent == 0 && !isStale {
                TimelineView(.animation(minimumInterval: 0.2)) { timeline in
                    reverseParticles(phase: timeline.date.timeIntervalSinceReferenceDate)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(width: 122, height: 154)
        .animation(.easeInOut(duration: 0.8), value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(percent.map { "剩余额度 \($0)%" } ?? "额度不可用")
    }

    private var hourglassCanvas: some View {
        Canvas { context, size in
            let centerX = size.width / 2
            let topY = 22.0
            let bottomY = size.height - 22
            let neckY = size.height / 2
            let left = 21.0
            let right = size.width - 21

            var glass = Path()
            glass.move(to: CGPoint(x: left + 7, y: topY + 8))
            glass.addCurve(
                to: CGPoint(x: centerX, y: neckY),
                control1: CGPoint(x: left + 10, y: topY + 47),
                control2: CGPoint(x: centerX - 23, y: neckY - 13)
            )
            glass.addCurve(
                to: CGPoint(x: left + 7, y: bottomY - 8),
                control1: CGPoint(x: centerX - 23, y: neckY + 13),
                control2: CGPoint(x: left + 10, y: bottomY - 47)
            )
            glass.move(to: CGPoint(x: right - 7, y: topY + 8))
            glass.addCurve(
                to: CGPoint(x: centerX, y: neckY),
                control1: CGPoint(x: right - 10, y: topY + 47),
                control2: CGPoint(x: centerX + 23, y: neckY - 13)
            )
            glass.addCurve(
                to: CGPoint(x: right - 7, y: bottomY - 8),
                control1: CGPoint(x: centerX + 23, y: neckY + 13),
                control2: CGPoint(x: right - 10, y: bottomY - 47)
            )
            context.stroke(glass, with: .color(Color.white.opacity(0.72)), lineWidth: 3)

            var upperChamber = Path()
            upperChamber.move(to: CGPoint(x: left + 11, y: topY + 11))
            upperChamber.addLine(to: CGPoint(x: right - 11, y: topY + 11))
            upperChamber.addCurve(
                to: CGPoint(x: centerX, y: neckY - 2),
                control1: CGPoint(x: right - 15, y: topY + 48),
                control2: CGPoint(x: centerX + 20, y: neckY - 13)
            )
            upperChamber.addCurve(
                to: CGPoint(x: left + 11, y: topY + 11),
                control1: CGPoint(x: centerX - 20, y: neckY - 13),
                control2: CGPoint(x: left + 15, y: topY + 48)
            )

            let upperHeight = neckY - topY - 13
            let fillTop = neckY - 2 - upperHeight * progress
            var upperContext = context
            upperContext.clip(to: upperChamber)
            upperContext.fill(
                Path(CGRect(x: left, y: fillTop, width: right - left, height: neckY - fillTop)),
                with: .linearGradient(
                    Gradient(colors: [sandColor.opacity(0.92), sandColor]),
                    startPoint: CGPoint(x: centerX, y: fillTop),
                    endPoint: CGPoint(x: centerX, y: neckY)
                )
            )

            if progress > 0 && progress < 1 {
                var stream = Path()
                stream.move(to: CGPoint(x: centerX, y: neckY - 1))
                stream.addLine(to: CGPoint(x: centerX, y: bottomY - 20))
                context.stroke(stream, with: .color(sandColor.opacity(0.65)), lineWidth: 2)
            }

            let used = 1 - progress
            if used > 0 {
                let sedimentHeight = 22 * min(used, 0.42)
                let sediment = Path(
                    roundedRect: CGRect(
                        x: left + 14,
                        y: bottomY - 12 - sedimentHeight,
                        width: right - left - 28,
                        height: sedimentHeight
                    ),
                    cornerRadius: 7
                )
                context.fill(sediment, with: .color(sandColor.opacity(0.16)))
            }

            for y in [topY, bottomY] {
                let bar = Path(
                    roundedRect: CGRect(x: 10, y: y - 7, width: size.width - 20, height: 14),
                    cornerRadius: 7
                )
                context.fill(bar, with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.86), Color.white.opacity(0.38)]),
                    startPoint: CGPoint(x: 10, y: y),
                    endPoint: CGPoint(x: size.width - 10, y: y)
                ))
            }
        }
    }

    private func reverseParticles(phase: TimeInterval) -> some View {
        Canvas { context, size in
            for index in 0..<5 {
                let offset = (phase * 0.18 + Double(index) * 0.2).truncatingRemainder(dividingBy: 1)
                let y = size.height * (0.76 - offset * 0.42)
                let x = size.width / 2 + sin(phase * 1.3 + Double(index)) * 7
                let dot = Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2))
                context.fill(dot, with: .color(sandColor.opacity(0.35 + offset * 0.35)))
            }
        }
    }
}
