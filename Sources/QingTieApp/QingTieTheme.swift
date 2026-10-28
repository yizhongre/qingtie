import AppKit
import SwiftUI

/// Soft native surfaces with mint selection and a small coral brand accent.
enum QingTieTheme {
    static let canvas = color(light: 0xF8FAF9, dark: 0x20282B)
    static let surface = color(light: 0xFFFFFF, dark: 0x242D30)
    static let sidebar = color(light: 0xF5F8F7, dark: 0x20282B)
    static let preview = color(light: 0xF6F9F8, dark: 0x263033)
    static let ink = color(light: 0x263238, dark: 0xE8F1EE)
    static let secondary = color(light: 0x69767A, dark: 0xA6B6B5)
    static let tertiary = color(light: 0x7A8588, dark: 0x94A6A5)
    static let coral = color(light: 0xFA7569, dark: 0xFF9387)
    static let accent = color(light: 0x078B77, dark: 0x65D6B9)
    static let selection = color(light: 0xE7F8F2, dark: 0x263F39)
    static let selectionBorder = color(light: 0xB8E6D9, dark: 0x3B675A)
    static let selectionInk = color(light: 0x214B43, dark: 0xB5F0D9)
    static let typeAccent = color(light: 0x8871ED, dark: 0xB3A2FF)
    static let typeBackground = color(light: 0xF0ECFF, dark: 0x39314E)
    static let line = ink.opacity(0.08)
    static let hover = ink.opacity(0.045)

    private static func color(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

struct QuietButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        QuietButtonContent(configuration: configuration, active: active)
    }

    private struct QuietButtonContent: View {
        let configuration: ButtonStyle.Configuration
        let active: Bool
        @State private var hovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .foregroundStyle(active ? QingTieTheme.accent : QingTieTheme.secondary)
                .padding(.horizontal, 7)
                .frame(minWidth: 28, minHeight: 28)
                .background(configuration.isPressed ? QingTieTheme.selectionBorder.opacity(0.6)
                            : active ? QingTieTheme.selection : hovered ? QingTieTheme.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
                .animation(reduceMotion ? nil : .easeOut(duration: configuration.isPressed ? 0.08 : 0.18), value: configuration.isPressed)
                .contentShape(Rectangle())
                .onHover { hovered = $0 }
        }
    }
}

struct Hairline: View {
    var vertical = false
    var body: some View {
        Rectangle()
            .fill(QingTieTheme.line)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .accessibilityHidden(true)
    }
}
