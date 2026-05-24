import SwiftUI
import MacToolsPluginKit

struct MiddleClickSettingsView: View {
    let selectedCount: Int
    let onCountChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            Label("设置", systemImage: "gearshape")
                .font(PluginSettingsTheme.Typography.sectionTitle)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowContentControl) {
                VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                    Label("手指数量", systemImage: "hand.tap")
                        .font(PluginSettingsTheme.Typography.emphasizedRowTitle)

                    Text("用指定数量的手指在触控板上轻点，将模拟鼠标中键点击")
                        .font(PluginSettingsTheme.Typography.rowDescription)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
                    ForEach([3, 4, 5], id: \.self) { count in
                        FingerCountButton(
                            count: count,
                            isSelected: selectedCount == count,
                            action: {
                                onCountChange(count)
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PluginSettingsTheme.Spacing.cardContent)
            .pluginSettingsCardBackground(.host)
        }
    }
}

private struct FingerCountButton: View {
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
                Image(systemName: "hand.raised")
                    .pluginSettingsRowIconStyle(
                        isSelected ? Color.accentColor : Color.primary,
                        visualScale: 0.78
                    )

                Text("\(count)指")
                    .font(PluginSettingsTheme.Typography.secondaryLabel.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: PluginSettingsTheme.Size.controlHeight * 2)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.control, style: .continuous)
                .fill(
                    isSelected
                        ? PluginSettingsTheme.Palette.activeControlBackground
                        : PluginSettingsTheme.Palette.recessedControlBackground
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.control, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color.accentColor.opacity(0.35)
                        : Color.clear,
                    lineWidth: PluginSettingsTheme.Stroke.standard
                )
        )
    }
}

#Preview {
    MiddleClickSettingsView(selectedCount: 3) { _ in }
        .frame(width: 400)
        .padding(24)
}
