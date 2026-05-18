import SwiftUI
import MacToolsPluginKit

struct PluginManagementSettingsView: View {
    @ObservedObject var pluginHost: PluginHost
    var appRelauncher: any AppRelaunching = AppRelauncher()

    @State private var alertMessage: String?
    @State private var activeOperationID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
            header

            if pluginHost.pluginManagementItems.isEmpty {
                ContentUnavailableView(
                    "暂无插件",
                    systemImage: "shippingbox",
                    description: Text("刷新插件列表后，可以在这里安装、更新和卸载。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(pluginHost.pluginManagementItems) { item in
                            PluginManagementRow(
                                item: item,
                                isBusy: activeOperationID == item.id,
                                onInstall: { runOperation(id: item.id) { try await pluginHost.installPluginFromCatalog(pluginID: item.id) } },
                                onUpdate: { runOperation(id: item.id) { try await pluginHost.updatePluginFromCatalog(pluginID: item.id) } },
                                onUninstall: { uninstall(item) },
                                onRelaunch: { appRelauncher.relaunch() }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(PluginSettingsTheme.Spacing.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SettingsStyle.contentBackground)
        .task {
            await pluginHost.refreshPluginCatalog()
        }
        .alert(
            "插件操作失败",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        alertMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("市场")
                    .font(PluginSettingsTheme.Typography.pageTitle)

                HStack(spacing: 8) {
                    Text(pluginHost.pluginCatalogStatus.title)
                        .font(PluginSettingsTheme.Typography.pageDescription)
                        .foregroundStyle(.secondary)

                    if let lastUpdatedAt = pluginHost.pluginCatalogStatus.lastUpdatedAt {
                        Text(lastUpdatedAt, style: .time)
                            .font(PluginSettingsTheme.Typography.pageDescription)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(pluginHost.pluginCatalogStatus.detailText)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(pluginHost.pluginCatalogStatus.errorMessage == nil ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                runOperation(id: "catalog.refresh") {
                    await pluginHost.refreshPluginCatalog()
                }
            } label: {
                Label("刷新列表", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(activeOperationID != nil || pluginHost.pluginCatalogStatus.isRefreshing)
        }
    }

    private func runOperation(id: String, _ operation: @escaping () async throws -> Void) {
        activeOperationID = id

        Task {
            do {
                try await operation()
            } catch {
                alertMessage = error.localizedDescription
            }

            activeOperationID = nil
        }
    }

    private func uninstall(_ item: PluginManagementItem) {
        do {
            try pluginHost.uninstallDynamicPlugin(pluginID: item.id)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

private struct PluginManagementRow: View {
    let item: PluginManagementItem
    let isBusy: Bool
    let onInstall: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void
    let onRelaunch: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(statusColor.opacity(0.14))

                Image(systemName: statusImageName)
                    .font(PluginSettingsTheme.Typography.pageDescription.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: PluginSettingsTheme.Size.metricIcon, height: PluginSettingsTheme.Size.metricIcon)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(PluginSettingsTheme.Typography.emphasizedRowTitle)

                    Text(item.version)
                        .font(PluginSettingsTheme.Typography.statusBadge)
                        .foregroundStyle(.secondary)
                }

                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let visibleStatusText {
                Text(visibleStatusText)
                    .font(PluginSettingsTheme.Typography.secondaryLabel.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 58, alignment: .trailing)
            }

            actionButtons
        }
        .padding(PluginSettingsTheme.Spacing.cardContent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pluginSettingsCardBackground(.host)
    }

    private var detail: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(item.detailText)
                .font(PluginSettingsTheme.Typography.rowDescription)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            if item.requiresRelaunchAction {
                Button("立即重启", action: onRelaunch)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .buttonStyle(.link)
                    .disabled(isBusy)
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if item.canInstall {
            Button(action: onInstall) {
                PluginManagementActionLabel(
                    title: "安装",
                    busyTitle: "安装中",
                    isBusy: isBusy,
                    width: actionButtonLabelWidth
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        }

        if item.canUpdate {
            Button(action: onUpdate) {
                PluginManagementActionLabel(
                    title: "更新",
                    busyTitle: "更新中",
                    isBusy: isBusy,
                    width: actionButtonLabelWidth
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        }

        if item.canUninstall {
            Button(role: .destructive, action: onUninstall) {
                Text("卸载")
                    .frame(width: actionButtonLabelWidth)
            }
            .buttonStyle(.bordered)
            .disabled(isBusy)
        }
    }

    private var visibleStatusText: String? {
        switch item.state {
        case .available, .enabled, .disabled:
            return nil
        case .localDevelopment, .updateAvailable, .restartRequired, .failed, .incompatible, .revoked:
            return item.statusText
        }
    }

    private var actionButtonLabelWidth: CGFloat {
        64
    }

    private var statusColor: Color {
        switch item.state {
        case .available, .localDevelopment:
            return .blue
        case .enabled:
            return .green
        case .disabled:
            return .secondary
        case .updateAvailable, .restartRequired:
            return .accentColor
        case .failed, .incompatible, .revoked:
            return .orange
        }
    }

    private var statusImageName: String {
        switch item.state {
        case .available:
            return "arrow.down.circle.fill"
        case .localDevelopment:
            return "hammer.circle.fill"
        case .enabled:
            return "checkmark.seal.fill"
        case .disabled:
            return "pause.circle"
        case .updateAvailable:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .restartRequired:
            return "restart.circle.fill"
        case .failed, .incompatible, .revoked:
            return "exclamationmark.triangle.fill"
        }
    }
}

private extension PluginManagementItem {
    var requiresRelaunchAction: Bool {
        if case .restartRequired = state {
            return true
        }

        return false
    }
}

private struct PluginManagementActionLabel: View {
    let title: String
    let busyTitle: String
    let isBusy: Bool
    let width: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.75)
            }

            Text(isBusy ? busyTitle : title)
        }
        .frame(width: width)
    }
}
