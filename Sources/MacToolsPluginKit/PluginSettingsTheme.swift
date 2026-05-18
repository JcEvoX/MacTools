import AppKit
import SwiftUI

public enum PluginSettingsTheme {
    public enum Typography {
        public static var pageTitle: Font {
            .title2.weight(.semibold)
        }

        public static var pageDescription: Font {
            .subheadline
        }

        public static var sectionTitle: Font {
            .body.weight(.semibold)
        }

        public static var rowTitle: Font {
            .body.weight(.medium)
        }

        public static var emphasizedRowTitle: Font {
            .body.weight(.semibold)
        }

        public static var rowDescription: Font {
            .subheadline
        }

        public static var secondaryLabel: Font {
            .subheadline.weight(.medium)
        }

        public static var statusBadge: Font {
            .caption2.weight(.medium)
        }

        public static var controlLabel: Font {
            .callout
        }

        public static var monospacedValue: Font {
            .system(size: 12, design: .monospaced)
        }
    }

    public enum Spacing {
        public static let pagePadding: CGFloat = 24
        public static let section: CGFloat = 18
        public static let sectionHeaderContent: CGFloat = 10
        public static let cardContent: CGFloat = 16
        public static let rowHorizontal: CGFloat = 16
        public static let rowVertical: CGFloat = 10
        public static let interactiveRowVertical: CGFloat = 12
        public static let rowTitleDescription: CGFloat = 3
        public static let rowContentControl: CGFloat = 12
        public static let controlCluster: CGFloat = 8
    }

    public enum Radius {
        public static let card: CGFloat = 10
        public static let hostCard: CGFloat = 12
        public static let control: CGFloat = 8
        public static let field: CGFloat = 6
    }

    public enum Stroke {
        public static let hairline: CGFloat = 0.5
        public static let standard: CGFloat = 1
    }

    public enum Size {
        public static let pageIcon: CGFloat = 42
        public static let rowIcon: CGFloat = 18
        public static let controlHeight: CGFloat = 30
        public static let metricIcon: CGFloat = 36
    }

    public enum Palette {
        public static var windowBackground: Color {
            dynamic(light: 0xF4F5F7, dark: 0x1E1F22)
        }

        public static var sidebarBackground: Color {
            dynamic(light: 0xEEF0F3, dark: 0x25262A)
        }

        public static var contentBackground: Color {
            dynamic(light: 0xF7F8FA, dark: 0x1F2023)
        }

        public static var cardBackground: Color {
            dynamic(light: 0xFFFFFF, dark: 0x2A2B2F)
        }

        public static var recessedControlBackground: Color {
            dynamic(light: 0xF1F3F6, dark: 0x222327)
        }

        public static var fieldBackground: Color {
            dynamic(light: 0xFFFFFF, dark: 0x1C1D20)
        }

        public static var keycapBackground: Color {
            dynamic(light: 0xF8F9FB, dark: 0x2F3035)
        }

        public static var separator: Color {
            dynamic(light: 0xD9DDE4, dark: 0x3A3B40)
        }

        public static var cardBorder: Color {
            dynamic(light: 0xDDE1E7, dark: 0x3B3C42)
        }

        public static var sidebarHoverBackground: Color {
            Color.primary.opacity(0.05)
        }

        public static var sidebarSelectionBackground: Color {
            Color.accentColor.opacity(0.12)
        }

        public static var activeControlBackground: Color {
            Color.accentColor.opacity(0.12)
        }

        public static var recordingBackground: Color {
            Color.accentColor.opacity(0.08)
        }

        public static var nativeCardBackground: Color {
            Color(nsColor: .controlBackgroundColor)
        }

        public static var nativeFieldBackground: Color {
            Color(nsColor: .textBackgroundColor)
        }

        public static var nativeSeparator: Color {
            Color(nsColor: .separatorColor)
        }

        private static func dynamic(light lightHex: UInt32, dark darkHex: UInt32) -> Color {
            Color(
                nsColor: NSColor(
                    name: nil,
                    dynamicProvider: { appearance in
                        appearance.pluginSettingsThemeIsDark
                            ? .pluginSettingsThemeRGB(darkHex)
                            : .pluginSettingsThemeRGB(lightHex)
                    }
                )
            )
        }
    }
}

public enum PluginSettingsCardBackgroundStyle {
    case host
    case plugin
    case recessed
}

public struct PluginSettingsCardBackground: ViewModifier {
    private let style: PluginSettingsCardBackgroundStyle

    public init(_ style: PluginSettingsCardBackgroundStyle = .host) {
        self.style = style
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: strokeWidth)
            )
    }

    private var radius: CGFloat {
        switch style {
        case .host:
            return PluginSettingsTheme.Radius.hostCard
        case .plugin, .recessed:
            return PluginSettingsTheme.Radius.card
        }
    }

    private var background: Color {
        switch style {
        case .host:
            return PluginSettingsTheme.Palette.cardBackground
        case .plugin:
            return PluginSettingsTheme.Palette.nativeCardBackground
        case .recessed:
            return PluginSettingsTheme.Palette.recessedControlBackground
        }
    }

    private var border: Color {
        switch style {
        case .host, .recessed:
            return PluginSettingsTheme.Palette.cardBorder
        case .plugin:
            return PluginSettingsTheme.Palette.nativeSeparator
        }
    }

    private var strokeWidth: CGFloat {
        switch style {
        case .host, .recessed:
            return PluginSettingsTheme.Stroke.standard
        case .plugin:
            return PluginSettingsTheme.Stroke.hairline
        }
    }
}

public extension View {
    func pluginSettingsCardBackground(
        _ style: PluginSettingsCardBackgroundStyle = .host
    ) -> some View {
        modifier(PluginSettingsCardBackground(style))
    }
}

private extension NSAppearance {
    var pluginSettingsThemeIsDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private extension NSColor {
    static func pluginSettingsThemeRGB(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}
