import SwiftUI
import MacToolsPluginKit

/// Launcher settings. Host renders the page header; this view starts at the first
/// group (per the settings spec). Bindings write straight through to the persisted
/// `LaunchpadPreferences`.
struct LaunchpadSettingsView: View {
    @ObservedObject var preferences: LaunchpadPreferences
    /// Observed so the sorting group appears / disappears as the custom layout is created or reset.
    @ObservedObject var layoutStore: LaunchpadLayoutStore
    let localization: PluginLocalization

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
            sortSection
            hiddenSection
        }
    }

    /// Only shown once the user has dragged into a custom order (`layout != nil`); resetting
    /// removes the layout key → back to alphabetical, and the group disappears.
    @ViewBuilder
    private var sortSection: some View {
        if layoutStore.layout != nil {
            section(
                title: localization.string("settings.sorting.title", defaultValue: "排序"),
                icon: "arrow.up.arrow.down"
            ) {
                row(
                    title: localization.string("settings.sorting.customOrder.title", defaultValue: "自定义排序"),
                    description: localization.string(
                        "settings.sorting.customOrder.description",
                        defaultValue: "已手动调整过应用顺序"
                    )
                ) {
                    Button(localization.string("settings.sorting.restoreAlphabetical", defaultValue: "恢复字母序")) {
                        layoutStore.resetToAlphabetical()
                    }
                        .controlSize(.small)
                }
            }
        }
    }

    private var sortedHiddenIDs: [String] {
        preferences.hiddenAppIDs.sorted {
            appName(for: $0).localizedCaseInsensitiveCompare(appName(for: $1)) == .orderedAscending
        }
    }

    /// Hidden ids are absolute paths; derive a display name without needing the catalog
    /// (the app may even be uninstalled).
    private func appName(for id: String) -> String {
        URL(fileURLWithPath: id).deletingPathExtension().lastPathComponent
    }

    @ViewBuilder
    private var hiddenSection: some View {
        if !preferences.hiddenAppIDs.isEmpty {
            let ids = sortedHiddenIDs
            section(title: localization.string("settings.hiddenApps.title", defaultValue: "隐藏的应用"), icon: "eye.slash") {
                VStack(spacing: PluginSettingsTheme.Spacing.rowVertical) {
                    ForEach(ids, id: \.self) { id in
                        HStack(spacing: PluginSettingsTheme.Spacing.rowContentControl) {
                            Text(appName(for: id))
                                .font(PluginSettingsTheme.Typography.rowTitle)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: PluginSettingsTheme.Spacing.rowContentControl)
                            Button(localization.string("settings.hiddenApps.restore", defaultValue: "恢复")) {
                                preferences.unhide(id)
                            }
                                .controlSize(.small)
                        }
                        if id != ids.last { Divider() }
                    }
                    Divider()
                    HStack {
                        Spacer()
                        Button(localization.string("settings.hiddenApps.restoreAll", defaultValue: "全部恢复")) {
                            preferences.unhideAll()
                        }
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private var windowSection: some View {
        section(title: localization.string("settings.window.title", defaultValue: "窗口"), icon: "macwindow") {
            VStack(spacing: PluginSettingsTheme.Spacing.rowVertical) {
                row(
                    title: localization.string("settings.window.mode.title", defaultValue: "唤出方式"),
                    description: preferences.windowMode == .fullscreen
                        ? localization.string(
                            "settings.window.mode.fullscreenDescription",
                            defaultValue: "铺满当前屏幕，点击空白处关闭"
                        )
                        : localization.string(
                            "settings.window.mode.compactDescription",
                            defaultValue: "屏幕中央的浮窗，点击窗外关闭"
                        )
                ) {
                    Picker("", selection: $preferences.windowMode) {
                        ForEach(LaunchpadPreferences.WindowMode.allCases) { mode in
                            Text(mode.label(localization: localization)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 168)
                }
                Divider()
                row(
                    title: localization.string("settings.hotCorner.title", defaultValue: "热区唤起"),
                    description: localization.string(
                        "settings.hotCorner.description",
                        defaultValue: "光标停在所选屏幕角落即唤出启动台"
                    )
                ) {
                    Picker("", selection: $preferences.hotCorner) {
                        ForEach(LaunchpadPreferences.HotCorner.allCases) { corner in
                            Text(corner.label(localization: localization)).tag(corner)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }
        }
    }

    private var gridSection: some View {
        section(title: localization.string("settings.grid.title", defaultValue: "网格"), icon: "square.grid.3x3") {
            VStack(spacing: PluginSettingsTheme.Spacing.rowVertical) {
                row(
                    title: localization.string("settings.grid.autoColumns.title", defaultValue: "自动列数"),
                    description: localization.string(
                        "settings.grid.autoColumns.description",
                        defaultValue: "按窗口宽度自动排布"
                    )
                ) {
                    Toggle("", isOn: isAutoColumns)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                if preferences.columns != LaunchpadPreferences.autoColumns {
                    Divider()
                    row(
                        title: localization.string("settings.grid.columns.title", defaultValue: "每行图标"),
                        description: localization.string(
                            "settings.grid.columns.description",
                            defaultValue: "固定每行的应用数量"
                        )
                    ) {
                        Stepper(
                            value: $preferences.columns,
                            in: LaunchpadPreferences.minColumns...LaunchpadPreferences.maxColumns
                        ) {
                            Text(
                                localization.format(
                                    "settings.grid.columns.value",
                                    defaultValue: "%d 个",
                                    preferences.columns
                                )
                            )
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
                .pluginSettingsListRowPadding()
                .pluginSettingsCardBackground(.host)
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
