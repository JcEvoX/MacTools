import SwiftUI
import MacToolsPluginKit

struct TranslatorSettingsView: View {
    @State private var firstLanguage: TranslatorLanguage
    @State private var secondLanguage: TranslatorLanguage
    @State private var profiles: [TranslatorProviderProfile]
    @State private var apiKeys: [String: String]
    @State private var selectedProfileID: String?
    @State private var message: String?

    private let onSave: ([TranslatorProviderProfile], [String: String], TranslatorLanguagePair) -> String?
    private let onMakeNewProfile: ([TranslatorProviderProfile]) -> TranslatorProviderProfile

    init(
        profiles: [TranslatorProviderProfile],
        apiKeys: [String: String],
        languagePair: TranslatorLanguagePair,
        onSave: @escaping ([TranslatorProviderProfile], [String: String], TranslatorLanguagePair) -> String?,
        onMakeNewProfile: @escaping ([TranslatorProviderProfile]) -> TranslatorProviderProfile
    ) {
        _firstLanguage = State(initialValue: languagePair.first)
        _secondLanguage = State(initialValue: languagePair.second)
        _profiles = State(initialValue: profiles.isEmpty ? [TranslatorProviderProfile.defaultProfile()] : profiles)
        _apiKeys = State(initialValue: apiKeys)
        _selectedProfileID = State(initialValue: profiles.first?.id ?? TranslatorProviderProfile.defaultID)
        self.onSave = onSave
        self.onMakeNewProfile = onMakeNewProfile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
            languageSection
            providerListSection
            providerDetailSection
            actions
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            sectionHeader("偏好语言", icon: "character.book.closed")

            VStack(spacing: 0) {
                fieldRow(title: "第一语言", description: "自动识别为其他语言时翻译到这里。") {
                    languagePicker(selection: messageClearing($firstLanguage))
                }

                PluginSettingsListDivider()

                fieldRow(title: "第二语言", description: "识别为第一语言时翻译到这里。") {
                    languagePicker(selection: messageClearing($secondLanguage))
                }
            }
            .pluginSettingsCardBackground(.host)
        }
    }

    private var providerListSection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            HStack {
                sectionHeader("翻译服务", icon: "network")
                Spacer()
                Button {
                    addProfile()
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 0) {
                ForEach(profiles.indices, id: \.self) { index in
                    providerRow(index: index)
                    if index != profiles.indices.last {
                        PluginSettingsListDivider()
                    }
                }
            }
            .pluginSettingsCardBackground(.host)
        }
    }

    private var providerDetailSection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            sectionHeader("服务详情", icon: "slider.horizontal.3")

            if let index = selectedProfileIndex {
                VStack(spacing: 0) {
                    editableFieldRow(title: "名称", description: "显示在翻译结果卡片上。") {
                        TextField("OpenAI", text: binding(for: index, keyPath: \.name))
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
                    }

                    PluginSettingsListDivider()

                    editableFieldRow(title: "服务地址", description: "OpenAI 或兼容网关地址。") {
                        TextField("https://api.openai.com", text: binding(for: index, keyPath: \.baseURL))
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
                    }

                    PluginSettingsListDivider()

                    editableFieldRow(title: "接口密钥", description: "留空则保留当前钥匙串内容。") {
                        SecureField("sk-...", text: apiKeyBinding(profileID: profiles[index].id))
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
                    }

                    PluginSettingsListDivider()

                    editableFieldRow(title: "模型", description: "用于翻译的模型名称。") {
                        TextField("gpt-5.4-mini", text: binding(for: index, keyPath: \.model))
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
                    }

                    PluginSettingsListDivider()

                    promptEditor(index: index)
                }
                .pluginSettingsCardBackground(.host)
            } else {
                Text("请选择一个翻译服务。")
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
                    .pluginSettingsListRowPadding()
                    .pluginSettingsCardBackground(.host)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
            Button("恢复默认") {
                profiles = [TranslatorProviderProfile.defaultProfile()]
                selectedProfileID = profiles[0].id
                apiKeys = [:]
                message = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            if let message {
                Text(message)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(message == "已保存" ? Color.secondary : Color.red)
            }

            Button("保存") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func providerRow(index: Int) -> some View {
        let profile = profiles[index]

        // 行内的开关与移动/删除按钮各自独立响应，仅名称/模型区域作为选择目标，
        // 避免把交互控件嵌套进同一个行级 Button 造成点击目标冲突。
        return HStack(spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            Toggle("", isOn: binding(for: index, keyPath: \.isEnabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

            Button {
                selectedProfileID = profile.id
            } label: {
                HStack(spacing: PluginSettingsTheme.Spacing.rowContentControl) {
                    VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                        Text(profile.normalizedName.isEmpty ? "未命名服务" : profile.normalizedName)
                            .font(PluginSettingsTheme.Typography.rowTitle)
                        Text(profile.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未设置模型" : profile.model)
                            .font(PluginSettingsTheme.Typography.rowDescription)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: PluginSettingsTheme.Spacing.rowContentControl)

                    if profile.isEnabled, let validationError = profile.validationError {
                        Text(validationError.localizedDescription)
                            .font(PluginSettingsTheme.Typography.statusBadge)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            iconButton("chevron.up", help: "上移") {
                moveProfile(from: index, offset: -1)
            }
            .disabled(index == 0)

            iconButton("chevron.down", help: "下移") {
                moveProfile(from: index, offset: 1)
            }
            .disabled(index == profiles.count - 1)

            iconButton("trash", help: "删除") {
                deleteProfile(at: index)
            }
            .disabled(profiles.count == 1)
        }
        .pluginSettingsListRowPadding(interactive: true)
        .background {
            if selectedProfileID == profile.id {
                RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.field, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
        }
    }

    private func promptEditor(index: Int) -> some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
            Text("提示词")
                .font(PluginSettingsTheme.Typography.rowTitle)
            Text("必须包含 {{text}}。可使用 {{source_language}} 和 {{target_language}}。")
                .font(PluginSettingsTheme.Typography.rowDescription)
                .foregroundStyle(.secondary)

            TextEditor(text: binding(for: index, keyPath: \.promptTemplate))
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 130, idealHeight: 160, maxHeight: 220)
                .background(PluginSettingsTheme.Palette.nativeFieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: PluginSettingsTheme.Radius.field, style: .continuous))
        }
        .pluginSettingsListRowPadding(interactive: true)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(PluginSettingsTheme.Typography.sectionTitle)
            .foregroundStyle(.secondary)
    }

    private func fieldRow<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                Text(title)
                    .font(PluginSettingsTheme.Typography.rowTitle)
                Text(description)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: PluginSettingsTheme.Spacing.rowContentControl)

            content()
        }
        .pluginSettingsListRowPadding(interactive: true)
    }

    private func editableFieldRow<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        fieldRow(title: title, description: description, content: content)
    }

    private func languagePicker(selection: Binding<TranslatorLanguage>) -> some View {
        Picker("", selection: selection) {
            ForEach(TranslatorLanguage.allCases) { language in
                Text("\(language.flag) \(language.displayName)")
                    .tag(language)
            }
        }
        .labelsHidden()
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private var selectedProfileIndex: Int? {
        guard let selectedProfileID,
              let index = profiles.firstIndex(where: { $0.id == selectedProfileID })
        else {
            return profiles.indices.first
        }

        return index
    }

    private func binding<Value>(
        for index: Int,
        keyPath: WritableKeyPath<TranslatorProviderProfile, Value>
    ) -> Binding<Value> {
        Binding(
            get: { profiles[index][keyPath: keyPath] },
            set: {
                profiles[index][keyPath: keyPath] = $0
                message = nil
            }
        )
    }

    private func apiKeyBinding(profileID: String) -> Binding<String> {
        Binding(
            get: { apiKeys[profileID] ?? "" },
            set: {
                apiKeys[profileID] = $0
                message = nil
            }
        )
    }

    /// 包装语言选择 binding，在用户改动时清除“已保存”提示，避免未保存改动看起来已保存。
    private func messageClearing(_ binding: Binding<TranslatorLanguage>) -> Binding<TranslatorLanguage> {
        Binding(
            get: { binding.wrappedValue },
            set: {
                binding.wrappedValue = $0
                message = nil
            }
        )
    }

    private func addProfile() {
        let profile = onMakeNewProfile(profiles)
        profiles.append(profile)
        selectedProfileID = profile.id
        message = nil
    }

    private func deleteProfile(at index: Int) {
        let deletedID = profiles[index].id
        profiles.remove(at: index)
        apiKeys.removeValue(forKey: deletedID)
        selectedProfileID = profiles.indices.contains(index) ? profiles[index].id : profiles.last?.id
        message = nil
    }

    private func moveProfile(from index: Int, offset: Int) {
        let target = index + offset
        guard profiles.indices.contains(index), profiles.indices.contains(target) else {
            return
        }

        profiles.swapAt(index, target)
        selectedProfileID = profiles[target].id
        message = nil
    }

    private func save() {
        let languagePair = TranslatorLanguagePair(first: firstLanguage, second: secondLanguage)

        guard languagePair.first != languagePair.second else {
            message = "两种偏好语言不能相同。"
            return
        }

        message = onSave(profiles, apiKeys, languagePair) ?? "已保存"
    }
}
