import SwiftUI
import MacToolsPluginKit

/// Launcher settings. Host renders the page header; this view starts at the first
/// group (per the settings spec). Bindings write straight through to the persisted
/// `LaunchpadPreferences`.
struct LaunchpadSettingsView: View {
    @ObservedObject var preferences: LaunchpadPreferences

    private var isAutoColumns: Binding<Bool> {
        Binding(
            get: { preferences.columns == LaunchpadPreferences.autoColumns },
            set: { preferences.columns = $0 ? LaunchpadPreferences.autoColumns : 7 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
            windowSection
            gridSection
        }
    }

    private var windowSection: some View {
        section(title: "窗口", icon: "macwindow") {
            row(
                title: "唤出方式",
                description: preferences.windowMode == .fullscreen
                    ? "铺满当前屏幕，点击空白处关闭"
                    : "屏幕中央的浮窗，点击窗外关闭"
            ) {
                Picker("", selection: $preferences.windowMode) {
                    ForEach(LaunchpadPreferences.WindowMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 168)
            }
        }
    }

    private var gridSection: some View {
        section(title: "网格", icon: "square.grid.3x3") {
            VStack(spacing: PluginSettingsTheme.Spacing.rowVertical) {
                row(title: "自动列数", description: "按窗口宽度自动排布") {
                    Toggle("", isOn: isAutoColumns)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                if preferences.columns != LaunchpadPreferences.autoColumns {
                    Divider()
                    row(title: "每行图标", description: "固定每行的应用数量") {
                        Stepper(
                            value: $preferences.columns,
                            in: LaunchpadPreferences.minColumns...LaunchpadPreferences.maxColumns
                        ) {
                            Text("\(preferences.columns) 个")
                                .font(PluginSettingsTheme.Typography.monospacedValue)
                                .frame(width: 40, alignment: .trailing)
                        }
                        .fixedSize()
                    }
                }
            }
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            Label(title, systemImage: icon)
                .font(PluginSettingsTheme.Typography.sectionTitle)
                .foregroundStyle(.secondary)
            content()
                .padding(.horizontal, PluginSettingsTheme.Spacing.rowHorizontal)
                .padding(.vertical, PluginSettingsTheme.Spacing.rowVertical)
                .background(
                    RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.card)
                        .fill(PluginSettingsTheme.Palette.nativeCardBackground)
                )
        }
    }

    private func row<Control: View>(
        title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                Text(title).font(PluginSettingsTheme.Typography.rowTitle)
                Text(description)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: PluginSettingsTheme.Spacing.rowContentControl)
            control()
        }
    }
}
