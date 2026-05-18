import AppKit
import SwiftUI

struct FixDamagedAppSettingsView: View {
    let onToggle: (Bool) -> Void

    @State private var isEnabled: Bool

    init(isDragDetectionEnabled: Bool, onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        self._isEnabled = State(initialValue: isDragDetectionEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("行为", systemImage: "hand.rays")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text("拖动检测")
                        .font(.system(size: 13, weight: .semibold))

                    Text("拖入 .app 文件后松手，自动弹出修复窗口并开始修复。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: isEnabled) { _, newValue in
                        onToggle(newValue)
                    }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FixDamagedAppSettingsStyle.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(FixDamagedAppSettingsStyle.cardBorder, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// 与 SettingsStyle（Sources/App/）保持完全一致的色值，供插件 target 内使用。
private enum FixDamagedAppSettingsStyle {
    static var cardBackground: Color {
        dynamic(light: 0xFFFFFF, dark: 0x2A2B2F)
    }

    static var cardBorder: Color {
        dynamic(light: 0xDDE1E7, dark: 0x3B3C42)
    }

    private static func dynamic(light lightHex: UInt32, dark darkHex: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? .rgb(darkHex) : .rgb(lightHex)
            }
        )
    }
}

private extension NSColor {
    static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

