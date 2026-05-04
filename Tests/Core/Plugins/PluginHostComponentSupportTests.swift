import AppKit
import SwiftUI
import XCTest
@testable import MacTools

@MainActor
final class PluginHostComponentSupportTests: XCTestCase {
    private let suiteName = "PluginHostComponentSupportTests"

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testComponentPluginOnlyAppearsInComponentItems() {
        let componentPlugin = MockComponentPlugin(id: "component")
        let host = makeHost(componentPlugins: [componentPlugin])

        XCTAssertTrue(host.panelItems.isEmpty)
        XCTAssertEqual(host.componentItems.map(\.id), ["component"])
        XCTAssertEqual(host.featureManagementItems.map(\.presentation), [.componentPanel])
    }

    func testComponentVisibilityUsesSharedDisplayPreferences() {
        let componentPlugin = MockComponentPlugin(id: "component")
        let host = makeHost(componentPlugins: [componentPlugin])

        host.setFeatureVisibility(false, for: "component")

        XCTAssertTrue(host.componentItems.isEmpty)
        XCTAssertEqual(host.featureManagementItems.first?.isVisible, false)
    }

    func testComponentOrderUsesSharedDisplayPreferences() {
        let first = MockComponentPlugin(id: "first", order: 1)
        let second = MockComponentPlugin(id: "second", order: 2)
        let host = makeHost(componentPlugins: [first, second])

        host.moveFeatureManagementItem(id: "second", toOffset: 0)

        XCTAssertEqual(host.componentItems.map(\.id), ["second", "first"])
        XCTAssertEqual(host.featureManagementItems.map(\.id), ["second", "first"])
    }

    func testComponentOnlyPluginContributesSettingsPermissionsAndShortcuts() {
        let componentPlugin = MockComponentPlugin(
            id: "component",
            permissionRequirements: [
                PluginPermissionRequirement(
                    id: "accessibility",
                    kind: .accessibility,
                    title: "辅助功能",
                    description: "需要辅助功能权限。"
                )
            ],
            settingsSections: [
                PluginSettingsSection(
                    id: "settings",
                    title: "组件设置",
                    description: "组件设置说明。",
                    status: .init(text: "正常", systemImage: "checkmark", tone: .positive),
                    footnote: nil,
                    buttonTitle: "执行",
                    actionID: "settings-action"
                )
            ],
            shortcutDefinitions: [
                PluginShortcutDefinition(
                    id: "shortcut",
                    title: "组件快捷键",
                    description: "触发组件动作。",
                    actionID: "shortcut-action",
                    scope: .whilePluginActive,
                    defaultBinding: nil,
                    isRequired: false
                )
            ]
        )
        let host = makeHost(componentPlugins: [componentPlugin])

        XCTAssertEqual(host.permissionCards.map(\.pluginID), ["component"])
        XCTAssertEqual(host.settingsCards.map(\.pluginID), ["component"])
        XCTAssertEqual(host.shortcutItems.map(\.pluginID), ["component"])
        XCTAssertEqual(host.pluginConfigurationItems.map(\.id), ["component"])
        XCTAssertEqual(host.pluginConfigurationItems.first?.settingsCards.map(\.id), ["component.settings"])
        XCTAssertEqual(host.pluginConfigurationItems.first?.permissionCards.map(\.permissionID), ["accessibility"])
        XCTAssertEqual(host.pluginConfigurationItems.first?.shortcutItems.map(\.pluginID), ["component"])
    }

    func testPluginsWithoutConfigurationSurfaceAreHiddenFromConfigurationList() {
        let featurePlugin = MockFeaturePlugin(id: "feature")
        let componentPlugin = MockComponentPlugin(id: "component")
        let host = makeHost(
            plugins: [featurePlugin],
            componentPlugins: [componentPlugin]
        )

        XCTAssertTrue(host.pluginConfigurationItems.isEmpty)
        XCTAssertNil(host.selectedPluginConfigurationID)
    }

    func testConfigurationListUsesSharedPluginOrderAndSelectsFirstItem() {
        let first = MockComponentPlugin(
            id: "first",
            order: 1,
            permissionRequirements: [
                PluginPermissionRequirement(
                    id: "first-permission",
                    kind: .accessibility,
                    title: "辅助功能",
                    description: "需要辅助功能权限。"
                )
            ]
        )
        let second = MockComponentPlugin(
            id: "second",
            order: 2,
            shortcutDefinitions: [
                PluginShortcutDefinition(
                    id: "second-shortcut",
                    title: "快捷键",
                    description: "触发动作。",
                    actionID: "shortcut-action",
                    scope: .whilePluginActive,
                    defaultBinding: nil,
                    isRequired: false
                )
            ]
        )
        let host = makeHost(componentPlugins: [first, second])

        XCTAssertEqual(host.pluginConfigurationItems.map(\.id), ["first", "second"])
        XCTAssertEqual(host.selectedPluginConfigurationID, "first")

        host.moveFeatureManagementItem(id: "second", toOffset: 0)

        XCTAssertEqual(host.pluginConfigurationItems.map(\.id), ["second", "first"])
        XCTAssertEqual(host.selectedPluginConfigurationID, "first")
    }

    func testCustomPluginConfigurationContributesConfigurationItemAndCachesView() {
        let configurationCounter = ConfigurationRenderCounter()
        let componentPlugin = MockComponentPlugin(
            id: "component",
            configuration: PluginConfiguration(description: "自定义配置") { context in
                configurationCounter.makeView(context: context)
            }
        )
        let host = makeHost(componentPlugins: [componentPlugin])

        XCTAssertEqual(host.pluginConfigurationItems.map(\.id), ["component"])
        XCTAssertEqual(host.pluginConfigurationItems.first?.description, "自定义配置")
        XCTAssertEqual(host.pluginConfigurationItems.first?.hasCustomConfiguration, true)

        _ = host.pluginConfigurationViewItem(for: "component")
        _ = host.pluginConfigurationViewItem(for: "component")

        XCTAssertEqual(configurationCounter.callCount, 1)
    }

    func testComponentActiveStateContributesToHasActivePlugin() {
        let componentPlugin = MockComponentPlugin(id: "component", isActive: true)
        let host = makeHost(componentPlugins: [componentPlugin])

        XCTAssertTrue(host.hasActivePlugin)
        XCTAssertEqual(host.featureManagementItems.first?.isActive, true)
    }

    func testComponentViewsAreCachedForFastPanelPresentation() {
        let componentPlugin = MockComponentPlugin(id: "component")
        let host = makeHost(componentPlugins: [componentPlugin])

        let first = host.componentViewItem(for: "component", dismiss: {})
        let second = host.componentViewItem(for: "component", dismiss: {})

        XCTAssertEqual(first.id, "component")
        XCTAssertEqual(second.id, "component")
        XCTAssertEqual(componentPlugin.makeComponentViewCallCount, 1)
    }

    func testWarmComponentViewsBuildsEachVisibleComponentOnce() {
        let first = MockComponentPlugin(id: "first", order: 1)
        let second = MockComponentPlugin(id: "second", order: 2)
        let host = makeHost(componentPlugins: [first, second])

        host.warmComponentViews(dismiss: {})
        host.warmComponentViews(dismiss: {})

        XCTAssertEqual(first.makeComponentViewCallCount, 1)
        XCTAssertEqual(second.makeComponentViewCallCount, 1)
    }

    func testFeaturePluginStillAppearsOnlyInPanelItems() {
        let featurePlugin = MockFeaturePlugin(id: "feature")
        let host = makeHost(plugins: [featurePlugin])

        XCTAssertEqual(host.panelItems.map(\.id), ["feature"])
        XCTAssertTrue(host.componentItems.isEmpty)
        XCTAssertEqual(host.featureManagementItems.map(\.presentation), [.featurePanel])
    }

    private func makeHost(
        plugins: [any FeaturePlugin] = [],
        componentPlugins: [any ComponentPlugin] = []
    ) -> PluginHost {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        return PluginHost(
            plugins: plugins,
            componentPlugins: componentPlugins,
            shortcutStore: ShortcutStore(userDefaults: defaults),
            pluginDisplayPreferencesStore: PluginDisplayPreferencesStore(userDefaults: defaults),
            globalShortcutManager: GlobalShortcutManager()
        )
    }
}

@MainActor
private final class MockComponentPlugin: ComponentPlugin {
    let metadata: PluginMetadata
    let componentDescriptor: PluginComponentDescriptor
    let permissionRequirements: [PluginPermissionRequirement]
    let settingsSections: [PluginSettingsSection]
    let shortcutDefinitions: [PluginShortcutDefinition]
    let configuration: PluginConfiguration?
    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?
    private let isActive: Bool
    private(set) var makeComponentViewCallCount = 0

    init(
        id: String,
        order: Int = 1,
        span: PluginComponentSpan = .oneByOne,
        isActive: Bool = false,
        permissionRequirements: [PluginPermissionRequirement] = [],
        settingsSections: [PluginSettingsSection] = [],
        shortcutDefinitions: [PluginShortcutDefinition] = [],
        configuration: PluginConfiguration? = nil
    ) {
        self.metadata = PluginMetadata(
            id: id,
            title: id,
            iconName: "sparkles",
            iconTint: Color(nsColor: .systemPurple),
            order: order,
            defaultDescription: "Component \(id)"
        )
        self.componentDescriptor = PluginComponentDescriptor(span: span)
        self.isActive = isActive
        self.permissionRequirements = permissionRequirements
        self.settingsSections = settingsSections
        self.shortcutDefinitions = shortcutDefinitions
        self.configuration = configuration
    }

    var componentState: PluginComponentState {
        PluginComponentState(
            subtitle: "Component subtitle",
            isActive: isActive,
            isEnabled: true,
            isVisible: true,
            errorMessage: nil
        )
    }

    func makeComponentView(context: PluginComponentContext) -> AnyView {
        makeComponentViewCallCount += 1
        return AnyView(Text(context.pluginID))
    }

    func refresh() {}

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}
}

@MainActor
private final class ConfigurationRenderCounter {
    private(set) var callCount = 0

    func makeView(context: PluginConfigurationContext) -> AnyView {
        callCount += 1
        return AnyView(Text(context.pluginID))
    }
}

@MainActor
private final class MockFeaturePlugin: FeaturePlugin {
    let manifest: PluginManifest
    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    init(id: String) {
        self.manifest = PluginManifest(
            id: id,
            title: id,
            iconName: "sparkles",
            iconTint: Color(nsColor: .systemBlue),
            controlStyle: .switch,
            menuActionBehavior: .keepPresented,
            order: 1,
            defaultDescription: "Feature \(id)"
        )
    }

    var panelState: PluginPanelState {
        PluginPanelState(
            subtitle: "Feature subtitle",
            isOn: false,
            isExpanded: false,
            isEnabled: true,
            isVisible: true,
            detail: nil,
            errorMessage: nil
        )
    }

    var permissionRequirements: [PluginPermissionRequirement] { [] }
    var settingsSections: [PluginSettingsSection] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] { [] }

    func refresh() {}
    func handlePanelAction(_ action: PluginPanelAction) {}

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}
}
