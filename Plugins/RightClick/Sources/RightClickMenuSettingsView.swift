import AppKit
import SwiftUI
import MacToolsPluginKit

/// Settings view for the Finder right-click menu, shown via the plugin's
/// `PluginConfiguration`. It writes the shared `RightClickConfiguration` (read by
/// the sandboxed extension through a read-only file exception), so the user
/// controls which items appear when right-clicking in Finder. Changes take effect
/// on the next right-click — the extension reads the config on every menu build.
struct RightClickMenuSettingsView: View {
    @State private var configuration = RightClickConfigurationStore.load()

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
            directorySection
            copySection
            openWithSection
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: configuration) { _, newValue in
            RightClickConfigurationStore.save(newValue)
        }
    }

    private var directorySection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            sectionHeader(title: "目录操作", icon: "folder")

            VStack(spacing: 0) {
                toggleRow(title: "新建文件夹", isOn: $configuration.newFolder)
                PluginSettingsListDivider()
                toggleRow(title: "新建文件", description: "支持 .txt / .md / .json", isOn: $configuration.newFile)
                PluginSettingsListDivider()
                toggleRow(title: "在终端打开", isOn: $configuration.openInTerminal)
            }
            .pluginSettingsCardBackground(.host)
        }
    }

    private var copySection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            sectionHeader(title: "复制菜单项", icon: "doc.on.doc")

            VStack(spacing: 0) {
                toggleRow(title: "复制文件名", isOn: $configuration.copyFileName)
                PluginSettingsListDivider()
                toggleRow(title: "复制绝对路径", isOn: $configuration.copyAbsolutePath)
                PluginSettingsListDivider()
                toggleRow(title: "复制相对路径", isOn: $configuration.copyRelativePath)
                PluginSettingsListDivider()
                toggleRow(title: "复制转义路径", description: "适合终端命令", isOn: $configuration.copyShellEscapedPath)
                PluginSettingsListDivider()
                toggleRow(title: "复制 file:// 链接", isOn: $configuration.copyFileURL)
            }
            .pluginSettingsCardBackground(.host)
        }
    }

    private var openWithSection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            HStack {
                sectionHeader(title: "用应用打开", icon: "app.badge")
                Spacer()
                Button {
                    addApp()
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(PluginSettingsTheme.Typography.controlLabel)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 0) {
                if configuration.openWithApps.isEmpty {
                    emptyOpenWithView
                } else {
                    ForEach($configuration.openWithApps) { $app in
                        RightClickOpenWithAppRow(app: $app) {
                            configuration.openWithApps.removeAll { $0.id == app.id }
                        }
                        if app.id != configuration.openWithApps.last?.id {
                            PluginSettingsListDivider()
                        }
                    }
                }
            }
            .pluginSettingsCardBackground(.host)

            Text("扩展名留空表示对所有文件显示，多个扩展名用逗号分隔。")
                .font(PluginSettingsTheme.Typography.rowDescription)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyOpenWithView: some View {
        HStack(spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            Image(systemName: "app.dashed")
                .pluginSettingsRowIconStyle()
            Text("暂无应用")
                .font(PluginSettingsTheme.Typography.rowDescription)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .pluginSettingsListRowPadding()
    }

    private func toggleRow(
        title: String,
        description: String? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                Text(title)
                    .font(PluginSettingsTheme.Typography.emphasizedRowTitle)

                if let description {
                    Text(description)
                        .font(PluginSettingsTheme.Typography.rowDescription)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .pluginSettingsListRowPadding(interactive: true)
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(PluginSettingsTheme.Typography.sectionTitle)
            .foregroundStyle(.secondary)
    }

    /// Let the user pick a `.app` bundle and append it to the list.
    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // displayName is localized and usually extension-free; strip only a
        // trailing ".app" rather than a global replace.
        let displayName = FileManager.default.displayName(atPath: url.path)
        let name = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
        configuration.openWithApps.append(
            RightClickOpenWithApp(name: name, appPath: url.path, fileExtensions: [])
        )
    }
}

/// One row in the "open with" list: app name + path, an editable comma-separated
/// extension filter, and a delete button.
private struct RightClickOpenWithAppRow: View {
    @Binding var app: RightClickOpenWithApp
    let onDelete: () -> Void

    @State private var extensionsText: String

    init(app: Binding<RightClickOpenWithApp>, onDelete: @escaping () -> Void) {
        _app = app
        self.onDelete = onDelete
        _extensionsText = State(
            initialValue: app.wrappedValue.fileExtensions.joined(separator: ", ")
        )
    }

    var body: some View {
        HStack(spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                Text(app.name)
                    .font(PluginSettingsTheme.Typography.emphasizedRowTitle)
                Text(app.appPath)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: PluginSettingsTheme.Spacing.rowContentControl)
            TextField("扩展名", text: $extensionsText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 108, idealWidth: 120, maxWidth: 140)
                .onChange(of: extensionsText) { _, newValue in
                    // pathExtension values are dotless; strip a leading "." so a
                    // user entering ".txt" still matches.
                    app.fileExtensions = newValue
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                        .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
                        .filter { !$0.isEmpty }
                }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
                    .frame(
                        width: PluginSettingsTheme.Size.controlHeight,
                        height: PluginSettingsTheme.Size.controlHeight
                    )
            }
            .buttonStyle(.plain)
            .help("删除应用")
        }
        .pluginSettingsListRowPadding(interactive: true)
    }
}
