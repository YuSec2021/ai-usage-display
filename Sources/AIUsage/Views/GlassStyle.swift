import SwiftUI

enum GlassAppearance {
    static let transparencyKey = "appearance.glassTransparency"
    static let defaultTransparency = 0.55

    static func backgroundOpacity(transparency: Double, reduceTransparency: Bool) -> Double {
        guard !reduceTransparency else { return 1 }
        let value = transparency.isFinite ? transparency : defaultTransparency
        return 1 - min(max(value, 0), 1)
    }
}

struct AppGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(GlassAppearance.transparencyKey) private var transparency = GlassAppearance.defaultTransparency

    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    private var tint: Color {
        colorScheme == .dark ? Color(red: 0.09, green: 0.105, blue: 0.13) : Color(red: 0.965, green: 0.975, blue: 0.99)
    }

    var body: some View {
        surface
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(colorScheme == .dark ? 0.28 : 0.75), .white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var surface: some View {
        let opacity = GlassAppearance.backgroundOpacity(transparency: transparency, reduceTransparency: reduceTransparency)
        if reduceTransparency {
            shape.fill(tint)
        } else if #available(macOS 26.0, *) {
            shape.fill(.clear)
                .glassEffect(.clear, in: shape)
                .overlay { shape.fill(tint.opacity(opacity)) }
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay { shape.fill(tint.opacity(opacity)) }
        }
    }
}

struct ClearWindowBackground: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.containerBackground(.clear, for: .window)
        } else {
            content
        }
    }
}

private struct GlassCard: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        content
            .background(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.025), in: shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
}
