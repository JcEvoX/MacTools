import SwiftUI
import MacToolsPluginKit

struct MouseScrollReverserSettingsView: View {
    @ObservedObject var store: MouseScrollReverserStore
    let localization: PluginLocalization
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
            behaviorSection
            scopeSection
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            sectionHeader(title: localization.string("settings.behavior.title", defaultValue: "滚动翻转"), icon: "arrow.up.arrow.down")

            VStack(spacing: 0) {
                toggleRow(
                    title: localization.string("settings.enabled.title", defaultValue: "启用滚动翻转"),
                    description: localization.string(
                        "settings.enabled.description",
                        defaultValue: "开启后按下方设备和方向设置修改滚动事件。"
                    ),
                    icon: "power",
                    isOn: enabledBinding
                )

                PluginSettingsListDivider()

                toggleRow(
                    title: localization.string("settings.vertical.title", defaultValue: "垂直翻转"),
                    description: localization.string("settings.vertical.description", defaultValue: "反转上下滚动方向。"),
                    icon: "arrow.up.and.down",
                    isOn: verticalBinding
                )

                PluginSettingsListDivider()

                toggleRow(
                    title: localization.string("settings.horizontal.title", defaultValue: "水平翻转"),
                    description: localization.string("settings.horizontal.description", defaultValue: "反转左右滚动方向。"),
                    icon: "arrow.left.and.right",
                    isOn: horizontalBinding
                )
            }
            .pluginSettingsCardBackground(.host)
        }
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            sectionHeader(title: localization.string("settings.scope.title", defaultValue: "作用设备"), icon: "cursorarrow.motionlines")

            VStack(spacing: 0) {
                toggleRow(
                    title: localization.string("settings.mouse.title", defaultValue: "鼠标"),
                    description: localization.string("settings.mouse.description", defaultValue: "翻转滚轮鼠标和大多数第三方鼠标滚动。"),
                    icon: "computermouse",
                    isOn: mouseBinding
                )

                PluginSettingsListDivider()

                toggleRow(
                    title: localization.string("settings.trackpad.title", defaultValue: "触控板"),
                    description: localization.string("settings.trackpad.description", defaultValue: "翻转触控板和 Magic Mouse 的连续滚动。"),
                    icon: "hand.draw",
                    isOn: trackpadBinding
                )
            }
            .pluginSettingsCardBackground(.host)
        }
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(PluginSettingsTheme.Typography.sectionTitle)
            .foregroundStyle(.secondary)
    }

    private func toggleRow(
        title: String,
        description: String,
        icon: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            Image(systemName: icon)
                .pluginSettingsRowIconStyle()

            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                Text(title)
                    .font(PluginSettingsTheme.Typography.emphasizedRowTitle)
                Text(description)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: PluginSettingsTheme.Spacing.rowContentControl)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .pluginSettingsListRowPadding()
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.configuration.isEnabled },
            set: { value in
                store.setEnabled(value)
                onChange()
            }
        )
    }

    private var verticalBinding: Binding<Bool> {
        Binding(
            get: { store.configuration.reverseVertical },
            set: { value in
                store.setReverseVertical(value)
                onChange()
            }
        )
    }

    private var horizontalBinding: Binding<Bool> {
        Binding(
            get: { store.configuration.reverseHorizontal },
            set: { value in
                store.setReverseHorizontal(value)
                onChange()
            }
        )
    }

    private var mouseBinding: Binding<Bool> {
        Binding(
            get: { store.configuration.reverseMouse },
            set: { value in
                store.setReverseMouse(value)
                onChange()
            }
        )
    }

    private var trackpadBinding: Binding<Bool> {
        Binding(
            get: { store.configuration.reverseTrackpad },
            set: { value in
                store.setReverseTrackpad(value)
                onChange()
            }
        )
    }
}

#Preview {
    MouseScrollReverserSettingsView(
        store: MouseScrollReverserStore(storage: UserDefaultsPluginStorage(pluginID: "mouse-scroll-reverser-preview")),
        localization: PluginLocalization(bundle: .main),
        onChange: {}
    )
    .frame(width: 440)
    .padding(24)
}
