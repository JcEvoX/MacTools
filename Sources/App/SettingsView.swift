import SwiftUI
import MacToolsPluginKit

struct SettingsView: View {
    @ObservedObject var pluginHost: PluginHost
    @ObservedObject var appUpdater: AppUpdater
    @ObservedObject var menuBarIconSettings: MenuBarIconSettings

    var body: some View {
        TabView(selection: $pluginHost.selectedSettingsDestination) {
            GeneralSettingsView(
                menuBarIconSettings: menuBarIconSettings
            )
                .tag(SettingsDestination.general)
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }

            FeatureSettingsView(pluginHost: pluginHost)
                .tag(SettingsDestination.pluginConfiguration)
                .tabItem {
                    Label("插件", systemImage: "slider.horizontal.3")
                }

            AboutSettingsView(appUpdater: appUpdater)
                .tag(SettingsDestination.about)
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
    }
}

private struct PermissionSettingsRow: View {
    let card: PluginPermissionCard
    let statusColor: Color
    let onAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: card.statusSystemImage)
                .font(PluginSettingsTheme.Typography.pageDescription.weight(.semibold))
                .foregroundStyle(statusColor)
                .frame(width: PluginSettingsTheme.Size.rowIcon)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(card.title)
                        .font(PluginSettingsTheme.Typography.emphasizedRowTitle)

                    Text(card.statusText)
                        .font(PluginSettingsTheme.Typography.secondaryLabel)
                        .foregroundStyle(statusColor)
                }

                Text(card.description)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let footnote = card.footnote {
                    Text(footnote)
                        .font(PluginSettingsTheme.Typography.rowDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(card.buttonTitle, action: onAction)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var menuBarIconSettings: MenuBarIconSettings
    @AppStorage(AppAppearancePreference.userDefaultsKey) private var appearancePreferenceRawValue = AppAppearancePreference.system.rawValue

    var body: some View {
        Form {
            Section {
                AppearanceSettingsRow(selection: appearancePreferenceBinding)
            } header: {
                Text("外观")
            }

            Section {
                MenuBarIconSettingsView(iconSettings: menuBarIconSettings)
            } header: {
                Text("状态栏图标")
            }
        }
        .formStyle(.grouped)
    }

    private var appearancePreferenceBinding: Binding<AppAppearancePreference> {
        Binding {
            AppAppearancePreference(rawValue: appearancePreferenceRawValue) ?? .system
        } set: { preference in
            appearancePreferenceRawValue = preference.rawValue
            preference.apply()
        }
    }
}

private struct AppearanceSettingsRow: View {
    @Binding var selection: AppAppearancePreference

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))

                Image(systemName: "circle.lefthalf.filled")
                    .font(PluginSettingsTheme.Typography.pageDescription.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text("应用外观")
                    .font(PluginSettingsTheme.Typography.emphasizedRowTitle)

                Text("自动跟随系统，也可以固定为深色或浅色。")
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("外观", selection: $selection) {
                ForEach(AppAppearancePreference.allCases) { preference in
                    Text(preference.title)
                        .tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
        }
        .frame(minHeight: 38)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .help("设置应用外观")
    }
}

private struct FeatureSettingsView: View {
    @ObservedObject var pluginHost: PluginHost

    var body: some View {
        HStack(spacing: 0) {
            FeatureSettingsSidebar(
                configurationItems: pluginHost.pluginConfigurationItems,
                selection: selectionBinding
            )
            .frame(width: 220)

            Rectangle()
                .fill(SettingsStyle.separator)
                .frame(width: 1)

            FeatureSettingsDetailPane(pluginHost: pluginHost)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SettingsStyle.windowBackground)
    }

    private var selectionBinding: Binding<FeatureSettingsPane> {
        Binding {
            pluginHost.selectedFeatureSettingsPane
        } set: { selection in
            pluginHost.selectFeatureSettingsPane(selection)
        }
    }
}

private struct FeatureSettingsSidebar: View {
    let configurationItems: [PluginConfigurationItem]
    @Binding var selection: FeatureSettingsPane

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                FeatureSettingsSidebarSectionTitle("插件市场")
                    .padding(.top, 14)

                FeatureSettingsSidebarRow(
                    title: "已安装",
                    systemImage: "checkmark.circle",
                    iconTint: .green,
                    isSelected: selection == .installed
                ) {
                    selection = .installed
                }

                FeatureSettingsSidebarRow(
                    title: "市场",
                    systemImage: "shippingbox",
                    iconTint: .blue,
                    isSelected: selection == .marketplace
                ) {
                    selection = .marketplace
                }

                FeatureSettingsSidebarSectionTitle("插件设置")
                    .padding(.top, 16)

                if configurationItems.isEmpty {
                    Text("暂无可设置插件")
                        .font(PluginSettingsTheme.Typography.secondaryLabel)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                } else {
                    ForEach(configurationItems) { item in
                        FeatureSettingsSidebarRow(
                            title: item.title,
                            systemImage: item.iconName,
                            iconTint: item.iconTint,
                            isSelected: selection == .configuration(item.id)
                        ) {
                            selection = .configuration(item.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SettingsStyle.sidebarBackground)
    }
}

private struct FeatureSettingsSidebarSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(PluginSettingsTheme.Typography.statusBadge)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
    }
}

private struct FeatureSettingsSidebarRow: View {
    let title: String
    let systemImage: String
    let iconTint: Color
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(PluginSettingsTheme.Typography.sectionTitle)
                    .foregroundStyle(isSelected ? Color.accentColor : iconTint)
                    .frame(width: 18, height: 18)

                Text(title)
                    .font(PluginSettingsTheme.Typography.sectionTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(rowBackground)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(title)
    }

    private var rowBackground: Color {
        if isSelected {
            return SettingsStyle.sidebarSelectionBackground
        }

        return isHovered ? SettingsStyle.sidebarHoverBackground : .clear
    }
}

private struct FeatureSettingsDetailPane: View {
    @ObservedObject var pluginHost: PluginHost

    var body: some View {
        switch pluginHost.selectedFeatureSettingsPane {
        case .installed:
            InstalledFeaturesSettingsView(pluginHost: pluginHost)
        case .marketplace:
            PluginManagementSettingsView(pluginHost: pluginHost)
        case let .configuration(pluginID):
            PluginConfigurationDetailPane(
                pluginHost: pluginHost,
                item: configurationItem(for: pluginID)
            )
        }
    }

    private func configurationItem(for pluginID: String) -> PluginConfigurationItem? {
        pluginHost.pluginConfigurationItems.first { $0.id == pluginID }
    }
}

private struct InstalledFeaturesSettingsView: View {
    @ObservedObject var pluginHost: PluginHost

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                SettingsPageHeader(
                    title: "已安装",
                    description: "启用、隐藏并拖拽调整插件在菜单栏里的显示顺序。",
                    systemImage: "checkmark.circle",
                    iconTint: .green
                )

                SettingsCardContainer {
                    if pluginHost.featureManagementItems.isEmpty {
                        ContentUnavailableView(
                            "暂无已安装插件",
                            systemImage: "checkmark.circle",
                            description: Text("安装插件后，会显示在这里。")
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        FeatureManagementTableView(
                            items: pluginHost.featureManagementItems,
                            onVisibilityChange: { pluginID, isVisible in
                                pluginHost.setFeatureVisibility(isVisible, for: pluginID)
                            },
                            onMove: { pluginID, targetOffset in
                                pluginHost.moveFeatureManagementItem(id: pluginID, toOffset: targetOffset)
                            }
                        )
                        .frame(height: featureManagementListHeight)
                    }
                }
            }
            .padding(PluginSettingsTheme.Spacing.pagePadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(SettingsStyle.contentBackground)
    }

    private var featureManagementListHeight: CGFloat {
        FeatureManagementTableView.preferredHeight(for: pluginHost.featureManagementItems.count)
    }
}

private struct SettingsCardContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .pluginSettingsCardBackground(.host)
    }
}

private struct PluginConfigurationDetailPane: View {
    @ObservedObject var pluginHost: PluginHost
    let item: PluginConfigurationItem?

    var body: some View {
        Group {
            if let item {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        PluginConfigurationHeader(item: item)

                        if !item.settingsCards.isEmpty {
                            PluginSettingsCardSection(
                                pluginHost: pluginHost,
                                cards: item.settingsCards
                            )
                        }

                        if !item.permissionCards.isEmpty {
                            PluginPermissionCardSection(
                                pluginHost: pluginHost,
                                cards: item.permissionCards
                            )
                        }

                        if !item.shortcutItems.isEmpty {
                            PluginShortcutSection(pluginHost: pluginHost, items: item.shortcutItems)
                        }

                        if item.hasCustomConfiguration {
                            pluginHost.pluginConfigurationViewItem(for: item.pluginID).content
                        }
                    }
                    .padding(PluginSettingsTheme.Spacing.pagePadding)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(SettingsStyle.contentBackground)
            } else {
                ContentUnavailableView(
                    "暂无可配置插件",
                    systemImage: "slider.horizontal.3",
                    description: Text("当插件提供权限、快捷键或自定义设置后，会显示在这里。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(SettingsStyle.contentBackground)
    }
}

private struct PluginConfigurationHeader: View {
    let item: PluginConfigurationItem

    var body: some View {
        SettingsPageHeader(
            title: item.title,
            description: item.description,
            systemImage: item.iconName,
            iconTint: item.iconTint
        )
        .padding(.bottom, 2)
    }
}

private struct SettingsPageHeader: View {
    let title: String
    let description: String
    let systemImage: String
    let iconTint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconTint.opacity(0.14))

                Image(systemName: systemImage)
                    .font(PluginSettingsTheme.Typography.pageDescription.weight(.semibold))
                    .foregroundStyle(iconTint)
            }
            .frame(width: PluginSettingsTheme.Size.pageIcon, height: PluginSettingsTheme.Size.pageIcon)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(PluginSettingsTheme.Typography.pageTitle)

                Text(description)
                    .font(PluginSettingsTheme.Typography.pageDescription)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PluginSettingsCardSection: View {
    @ObservedObject var pluginHost: PluginHost
    let cards: [PluginSettingsCard]

    var body: some View {
        PluginConfigurationSection(title: "设置", systemImage: "switch.2") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    PluginSettingsCardRow(
                        card: card,
                        statusColor: statusColor(for: card.statusTone),
                        onAction: {
                            if let actionID = card.actionID {
                                pluginHost.performSettingsAction(pluginID: card.pluginID, actionID: actionID)
                            }
                        }
                    )

                    if index < cards.count - 1 {
                        SettingsSectionDivider()
                    }
                }
            }
        }
    }
}

private struct PluginSettingsCardRow: View {
    let card: PluginSettingsCard
    let statusColor: Color
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            HStack(alignment: .center, spacing: PluginSettingsTheme.Spacing.rowContentControl) {
                VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                    Text(card.title)
                        .font(PluginSettingsTheme.Typography.emphasizedRowTitle)

                    Text(card.description)
                        .font(PluginSettingsTheme.Typography.rowDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Label {
                    Text(card.statusText)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: card.statusSystemImage)
                }
                .font(PluginSettingsTheme.Typography.secondaryLabel.weight(.semibold))
                .foregroundStyle(statusColor)
            }

            if let footnote = card.footnote {
                Text(footnote)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let buttonTitle = card.buttonTitle, card.actionID != nil {
                HStack {
                    Spacer()

                    Button(buttonTitle, action: onAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(PluginSettingsTheme.Spacing.cardContent)
    }
}

private struct PluginPermissionCardSection: View {
    @ObservedObject var pluginHost: PluginHost
    let cards: [PluginPermissionCard]

    var body: some View {
        PluginConfigurationSection(title: "权限", systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    PermissionSettingsRow(
                        card: card,
                        statusColor: statusColor(for: card.statusTone),
                        onAction: {
                            pluginHost.performPermissionAction(
                                pluginID: card.pluginID,
                                permissionID: card.permissionID
                            )
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if index < cards.count - 1 {
                        SettingsSectionDivider()
                    }
                }
            }
        }
    }
}

private struct PluginShortcutSection: View {
    @ObservedObject var pluginHost: PluginHost
    let items: [ShortcutSettingsItem]

    var body: some View {
        PluginConfigurationSection(title: "快捷键", systemImage: "command") {
            VStack(alignment: .leading, spacing: 0) {
                ShortcutSettingsRowsView(pluginHost: pluginHost, items: items)
            }
        }
    }
}

private struct PluginConfigurationSection<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            Label(title, systemImage: systemImage)
                .font(PluginSettingsTheme.Typography.sectionTitle)
                .foregroundStyle(.secondary)

            SettingsCardContainer {
                content
            }
        }
    }
}

private struct SettingsSectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsStyle.separator)
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
}

private func statusColor(for tone: PluginStatusTone) -> Color {
    switch tone {
    case .neutral:
        return .secondary
    case .positive:
        return .green
    case .caution:
        return .orange
    }
}

struct AboutSettingsView: View {
    @StateObject private var updateViewModel: AboutUpdateViewModel

    init(appUpdater: AppUpdater) {
        _updateViewModel = StateObject(
            wrappedValue: AboutUpdateViewModel(updater: appUpdater)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            AppIconPreview()

            Text(AppMetadata.appName)
                .font(.system(size: 22, weight: .bold))
                .padding(.top, 18)

            Text("版本 \(AppMetadata.versionDescription)")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            AboutUpdateCard(viewModel: updateViewModel)
                .padding(.top, 28)
                .frame(maxWidth: 420)

            Text(AppMetadata.aboutDescription)
                .font(.title3)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
                .padding(.top, 28)

            VStack(spacing: 0) {
                Link(AppMetadata.repositoryDisplayName, destination: AppMetadata.repositoryURL)
                    .font(.title3)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 28)

            Spacer(minLength: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
    }
}

private struct AboutUpdateCard: View {
    private enum Layout {
        static let verticalSpacing: CGFloat = 12
        static let statusMinHeight: CGFloat = 16
    }

    @ObservedObject var viewModel: AboutUpdateViewModel

    var body: some View {
        VStack(spacing: Layout.verticalSpacing) {
            Button(viewModel.primaryButtonTitle) {
                Task {
                    await viewModel.performPrimaryAction()
                }
            }
            .buttonStyle(AboutUpdatePrimaryButtonStyle())
            .disabled(viewModel.isPrimaryButtonDisabled)

            Text(statusText ?? " ")
                .font(PluginSettingsTheme.Typography.rowDescription)
                .foregroundStyle(viewModel.statusColor)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: Layout.statusMinHeight, alignment: .top)
                .opacity(statusText == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusText: String? {
        switch viewModel.state {
        case .idle:
            return nil
        default:
            return viewModel.statusDetail ?? viewModel.statusHeadline
        }
    }
}

private struct AboutUpdatePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PluginSettingsTheme.Typography.rowTitle)
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.82))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minWidth: 92)
            .background(
                Capsule(style: .continuous)
                    .fill(buttonBackgroundColor(isPressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    private func buttonBackgroundColor(isPressed: Bool) -> Color {
        let baseOpacity: CGFloat = isEnabled ? 1 : 0.45
        let pressedOpacity: CGFloat = isEnabled ? 0.82 : baseOpacity
        return Color.accentColor.opacity(isPressed ? pressedOpacity : baseOpacity)
    }
}

private struct AppIconPreview: View {
    var body: some View {
        Group {
            if let appIcon = AppMetadata.appIcon {
                Image(nsImage: appIcon)
                    .resizable()
            } else {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .foregroundStyle(.secondary)
                    .background(PluginSettingsTheme.Palette.nativeCardBackground)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
