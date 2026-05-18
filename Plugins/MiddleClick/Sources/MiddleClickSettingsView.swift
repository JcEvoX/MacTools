import SwiftUI
import MacToolsPluginKit

struct MiddleClickSettingsView: View {
    let selectedCount: Int
    let onCountChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
            Label("设置", systemImage: "gearshape")
                .font(PluginSettingsTheme.Typography.sectionTitle)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("手指数量", systemImage: "hand.tap")
                        .font(PluginSettingsTheme.Typography.emphasizedRowTitle)
                    
                    Text("用指定数量的手指在触控板上轻点，将模拟鼠标中键点击")
                        .font(PluginSettingsTheme.Typography.rowDescription)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
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
            VStack(spacing: 6) {
                Image(systemName: "hand.raised")
                    .font(.system(size: 16, weight: .medium))

                Text("\(count)指")
                    .font(PluginSettingsTheme.Typography.secondaryLabel.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .foregroundStyle(
                isSelected
                    ? Color(nsColor: .systemBlue)
                    : Color(nsColor: .labelColor)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? Color(nsColor: .systemBlue).opacity(0.1)
                        : Color(nsColor: .secondaryLabelColor).opacity(0.08)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color(nsColor: .systemBlue).opacity(0.4)
                        : Color.clear,
                    lineWidth: 1.5
                )
        )
    }
}

#Preview {
    MiddleClickSettingsView(selectedCount: 3) { _ in }
        .frame(width: 400)
        .padding(24)
}
