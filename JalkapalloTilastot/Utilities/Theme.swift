import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Värit: yön nurmikenttä + valonheittimen meripihka. Ei sinistä korostusvärinä.
enum Theme {
    static let background = Color(hex: 0x080F12)
    static let backgroundLift = Color(hex: 0x0E1A1E)
    static let panel = Color(hex: 0x0F1A1E)
    static let panelRaised = Color(hex: 0x16252A)
    static let stroke = Color.white.opacity(0.08)
    static let chalk = Color(hex: 0xE9F0EA)
    static let chalkMuted = Color(hex: 0x879A96)
    static let floodlight = Color(hex: 0xFFB547)
    static let positive = Color(hex: 0x4ADE9A)
    static let negative = Color(hex: 0xFF6B6B)
    static let european = Color(hex: 0x5AA9FF)

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    static func number(_ size: CGFloat = 13, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func label(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

/// Taustan tunnusmerkki: himmeä keskipiiri ja keskiviiva kuin valonheittimien valaisemalla nurmella.
struct PitchBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.backgroundLift, Theme.background],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Theme.floodlight.opacity(0.10), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 560)
            Canvas { ctx, size in
                let cx = size.width * 0.86
                let cy = size.height * 0.14
                var circle = Path()
                circle.addEllipse(in: CGRect(x: cx - 170, y: cy - 170, width: 340, height: 340))
                ctx.stroke(circle, with: .color(.white.opacity(0.035)), lineWidth: 2)
                var line = Path()
                line.move(to: CGPoint(x: cx, y: 0))
                line.addLine(to: CGPoint(x: cx, y: size.height))
                ctx.stroke(line, with: .color(.white.opacity(0.03)), lineWidth: 2)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    func panel(radius: CGFloat = 14) -> some View {
        self
            .background(Theme.panel.opacity(0.92), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}
