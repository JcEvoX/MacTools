import Combine
import Foundation
import SwiftUI

@MainActor
final class PluginHost: ObservableObject {
    private struct PluginDescriptor {
        let metadata: PluginMetadata
        var featurePlugin: (any FeaturePlugin)?
        var componentPlugin: (any ComponentPlugin)?

        var presentation: PluginFeaturePresentation {
            switch (featurePlugin, componentPlugin) {
            case (.some, .some):
                return .featureAndComponentPanel
            case (.some, .none):
                return .featurePanel
            case (.none, .some):
                return .componentPanel
            case (.none, .none):
                return .featurePanel
            }
        }
    }

    private struct ShortcutDescriptor {
        let itemID: String
        let pluginID: String
        let pluginTitle: String
        let definition: PluginShortcutDefinition
        let plugin: any PluginCore
    }

    private let plugins: [any FeaturePlugin]
    private let componentPlugins: [any ComponentPlugin]
    private let shortcutStore: ShortcutStore
    private let pluginDisplayPreferencesStore: PluginDisplayPreferencesStore
    private let globalShortcutManager: GlobalShortcutManager
    private let displayConfigurationObserver: (any DisplayConfigurationObserving)?
    private let accessibilityPermissionObserver: (any AccessibilityPermissionObserving)?
    private let displayTopologyRefreshDelay: Duration

    private var shortcutErrors: [String: String] = [:]
    private var componentViewCache: [String: PluginComponentViewItem] = [:]
    private var configurationViewCache: [String: PluginConfigurationViewItem] = [:]
    private var isHandlingPluginAction = false
    private var displayTopologyRefreshTask: Task<Void, Never>?

    @Published private(set) var panelItems: [PluginPanelItem] = []
    @Published private(set) var componentItems: [PluginComponentItem] = []
    @Published private(set) var featureManagementItems: [PluginFeatureManagementItem] = []
    @Published private(set) var pluginConfigurationItems: [PluginConfigurationItem] = []
    @Published private(set) var permissionCards: [PluginPermissionCard] = []
    @Published private(set) var settingsCards: [PluginSettingsCard] = []
    @Published private(set) var shortcutItems: [ShortcutSettingsItem] = []
    @Published private(set) var hasActivePlugin = false
    @Published private(set) var settingsPresentationRequestCount = 0
    @Published var selectedSettingsDestination: SettingsDestination = .general
    @Published var selectedPluginConfigurationID: String?

    convenience init() {
        self.init(
            plugins: [
                AppearancePlugin(),
                DisplayBrightnessPlugin(),
                DisplayResolutionPlugin(),
                HideNotchPlugin(),
                KeepAwakePlugin(),
                MiddleClickPlugin(),
                DiskCleanFeature.shared.makePlugin(),
                LaunchControlFeature.shared.makePlugin(),
                EjectDiskPlugin(),
                PhysicalCleanModePlugin()
            ],
            componentPlugins: [
                SystemStatusPlugin(),
                CalendarPlugin()
            ],
            shortcutStore: ShortcutStore(),
            pluginDisplayPreferencesStore: PluginDisplayPreferencesStore(),
            globalShortcutManager: GlobalShortcutManager(),
            displayConfigurationObserver: SystemDisplayConfigurationObserver(),
            accessibilityPermissionObserver: AccessibilityPermissionObserver()
        )
    }

    init(
        plugins: [any FeaturePlugin],
        componentPlugins: [any ComponentPlugin] = [],
        shortcutStore: ShortcutStore,
        pluginDisplayPreferencesStore: PluginDisplayPreferencesStore,
        globalShortcutManager: GlobalShortcutManager,
        displayConfigurationObserver: (any DisplayConfigurationObserving)? = nil,
        accessibilityPermissionObserver: (any AccessibilityPermissionObserving)? = nil,
        displayTopologyRefreshDelay: Duration = .milliseconds(180)
    ) {
        self.plugins = plugins.sorted {
            if $0.manifest.order == $1.manifest.order {
                return $0.manifest.title.localizedCompare($1.manifest.title) == .orderedAscending
            }

            return $0.manifest.order < $1.manifest.order
        }
        self.componentPlugins = componentPlugins.sorted {
            if $0.metadata.order == $1.metadata.order {
                return $0.metadata.title.localizedCompare($1.metadata.title) == .orderedAscending
            }

            return $0.metadata.order < $1.metadata.order
        }
        self.shortcutStore = shortcutStore
        self.pluginDisplayPreferencesStore = pluginDisplayPreferencesStore
        self.globalShortcutManager = globalShortcutManager
        self.displayConfigurationObserver = displayConfigurationObserver
        self.accessibilityPermissionObserver = accessibilityPermissionObserver
        self.displayTopologyRefreshDelay = displayTopologyRefreshDelay

        for plugin in corePluginsForCallbacks() {
            let pluginID = plugin.metadata.id

            plugin.onStateChange = { [weak self] in
                self?.rebuildDerivedStateAfterPluginChange()
            }
            plugin.requestPermissionGuidance = { [weak self] permissionID in
                self?.requestPermissionGuidance(forPluginID: pluginID, permissionID: permissionID)
            }
            plugin.shortcutBindingResolver = { [weak self] shortcutDefinitionID in
                self?.resolvedBinding(forPluginID: pluginID, shortcutDefinitionID: shortcutDefinitionID)
            }
        }

        self.globalShortcutManager.onShortcutTriggered = { [weak self] shortcutID in
            self?.handleShortcutTrigger(shortcutID: shortcutID)
        }

        self.displayConfigurationObserver?.onConfigurationChange = { [weak self] in
            self?.scheduleDisplayTopologyRefresh()
        }

        self.accessibilityPermissionObserver?.onPermissionChange = { [weak self] in
            self?.refreshAccessibilityPermissionNow()
        }

        refreshAll()
    }

    deinit {
        displayTopologyRefreshTask?.cancel()
    }

    func refreshAll() {
        handlePluginAction {
            for plugin in corePluginsForCallbacks() {
                plugin.refresh()
            }
        }

        syncGlobalShortcuts()
    }

    func refreshDisplayTopology() {
        displayTopologyRefreshTask?.cancel()
        refreshDisplayTopologyNow()
    }

    func isSwitchOn(for pluginID: String) -> Bool {
        panelItems.first(where: { $0.id == pluginID })?.isOn ?? false
    }

    func setSwitchValue(_ isOn: Bool, for pluginID: String) {
        guard let plugin = plugin(for: pluginID) else {
            return
        }

        handlePluginAction {
            plugin.handlePanelAction(.setSwitch(isOn))
        }
    }

    func setDisclosureExpanded(_ isExpanded: Bool, for pluginID: String) {
        guard let plugin = plugin(for: pluginID) else {
            return
        }

        handlePluginAction {
            plugin.handlePanelAction(.setDisclosureExpanded(isExpanded))
        }
    }

    func setPanelSelectionValue(
        _ optionID: String,
        controlID: String,
        for pluginID: String
    ) {
        guard let plugin = plugin(for: pluginID) else {
            return
        }

        handlePluginAction {
            plugin.handlePanelAction(.setSelection(controlID: controlID, optionID: optionID))
        }
    }

    func setPanelNavigationSelectionValue(
        _ optionID: String,
        controlID: String,
        for pluginID: String
    ) {
        guard let plugin = plugin(for: pluginID) else {
            return
        }

        handlePluginAction {
            plugin.handlePanelAction(
                .setNavigationSelection(controlID: controlID, optionID: optionID)
            )
        }
    }

    func clearPanelNavigationSelection(
        controlID: String,
        for pluginID: String
    ) {
        guard let plugin = plugin(for: pluginID) else {
            return
        }

        handlePluginAction {
            plugin.handlePanelAction(.clearNavigationSelection(controlID: controlID))
        }
    }

    func setPanelDateValue(
        _ date: Date,
        controlID: String,
        for pluginID: String
    ) {
        guard let plugin = plugin(for: pluginID) else {
            return
        }

        handlePluginAction {
            plugin.handlePanelAction(.setDate(controlID: controlID, value: date))
        }
    }

    func setPanelSliderValue(
        _ value: Double,
        controlID: String,
        for pluginID: String,
        phase: PluginPanelAction.SliderPhase
    ) {
        guard let plugin = plugin(for: pluginID) else {
            return
        }

        handlePluginAction {
            plugin.handlePanelAction(.setSlider(controlID: controlID, value: value, phase: phase))
        }
    }

    func invokePanelAction(controlID: String, for pluginID: String) {
        guard let plugin = plugin(for: pluginID) else {
            return
        }

        handlePluginAction {
            plugin.handlePanelAction(.invokeAction(controlID: controlID))
        }
    }

    func performSettingsAction(pluginID: String, actionID: String) {
        guard let plugin = corePlugin(for: pluginID) else {
            return
        }

        handlePluginAction {
            plugin.handleSettingsAction(id: actionID)
        }
    }

    func performPermissionAction(pluginID: String, permissionID: String) {
        guard let plugin = corePlugin(for: pluginID) else {
            return
        }

        handlePluginAction {
            plugin.handlePermissionAction(id: permissionID)
        }
    }

    func setShortcutBinding(_ binding: ShortcutBinding, for shortcutID: String) {
        guard let descriptor = shortcutDescriptor(for: shortcutID) else {
            return
        }

        applyShortcutCustomization(.custom(binding), for: descriptor)
    }

    func clearShortcut(for shortcutID: String) {
        guard let descriptor = shortcutDescriptor(for: shortcutID) else {
            return
        }

        applyShortcutCustomization(.cleared, for: descriptor)
    }

    func resetShortcut(for shortcutID: String) {
        guard let descriptor = shortcutDescriptor(for: shortcutID) else {
            return
        }

        applyShortcutCustomization(.inheritDefault, for: descriptor)
    }

    func presentPluginConfiguration(pluginID: String) {
        rebuildDerivedState()

        guard pluginConfigurationItems.contains(where: { $0.id == pluginID }) else {
            return
        }

        selectedSettingsDestination = .pluginConfiguration
        selectedPluginConfigurationID = pluginID
        settingsPresentationRequestCount += 1
    }

    func clearShortcutError(for shortcutID: String) {
        guard shortcutErrors.removeValue(forKey: shortcutID) != nil else {
            return
        }

        rebuildDerivedState()
    }

    func setFeatureVisibility(_ isVisible: Bool, for pluginID: String) {
        pluginDisplayPreferencesStore.setVisibility(
            isVisible,
            for: pluginID,
            defaultPluginIDs: defaultPluginIDs
        )
        rebuildDerivedState()
    }

    func canMoveFeatureManagementItem(id pluginID: String, by offset: Int) -> Bool {
        let orderedPluginIDs = orderedPluginIDs()

        guard let currentIndex = orderedPluginIDs.firstIndex(of: pluginID) else {
            return false
        }

        let targetIndex = currentIndex + offset
        return orderedPluginIDs.indices.contains(targetIndex)
    }

    func moveFeatureManagementItem(id pluginID: String, by offset: Int) {
        var orderedPluginIDs = orderedPluginIDs()

        guard let currentIndex = orderedPluginIDs.firstIndex(of: pluginID) else {
            return
        }

        let targetIndex = currentIndex + offset

        guard orderedPluginIDs.indices.contains(targetIndex) else {
            return
        }

        let movedPluginID = orderedPluginIDs.remove(at: currentIndex)
        orderedPluginIDs.insert(movedPluginID, at: targetIndex)

        pluginDisplayPreferencesStore.setOrderedPluginIDs(
            orderedPluginIDs,
            defaultPluginIDs: defaultPluginIDs
        )
        rebuildDerivedState()
    }

    func moveFeatureManagementItem(id pluginID: String, toOffset targetOffset: Int) {
        var orderedPluginIDs = orderedPluginIDs()

        guard let currentIndex = orderedPluginIDs.firstIndex(of: pluginID) else {
            return
        }

        let clampedOffset = min(max(targetOffset, 0), orderedPluginIDs.count)

        guard currentIndex != clampedOffset, currentIndex + 1 != clampedOffset else {
            return
        }

        orderedPluginIDs.move(
            fromOffsets: IndexSet(integer: currentIndex),
            toOffset: clampedOffset
        )

        pluginDisplayPreferencesStore.setOrderedPluginIDs(
            orderedPluginIDs,
            defaultPluginIDs: defaultPluginIDs
        )
        rebuildDerivedState()
    }

    func moveFeatureManagementItems(fromOffsets: IndexSet, toOffset: Int) {
        var orderedPluginIDs = orderedPluginIDs()
        orderedPluginIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)

        pluginDisplayPreferencesStore.setOrderedPluginIDs(
            orderedPluginIDs,
            defaultPluginIDs: defaultPluginIDs
        )
        rebuildDerivedState()
    }

    func componentViewItem(for itemID: String, dismiss: @escaping () -> Void) -> PluginComponentViewItem {
        componentViewItem(for: itemID, dismiss: dismiss, isPanelVisible: true)
    }

    func componentViewItem(
        for itemID: String,
        dismiss: @escaping () -> Void,
        isPanelVisible: Bool
    ) -> PluginComponentViewItem {
        if let cachedItem = componentViewCache[itemID] {
            return cachedItem
        }

        guard let plugin = componentPlugin(for: itemID) else {
            let item = PluginComponentViewItem(id: itemID, content: AnyView(EmptyView()))
            componentViewCache[itemID] = item
            return item
        }

        let item = PluginComponentViewItem(
            id: itemID,
            content: plugin.makeComponentView(
                context: PluginComponentContext(
                    pluginID: itemID,
                    dismiss: dismiss,
                    isPanelVisible: isPanelVisible
                )
            )
        )
        componentViewCache[itemID] = item
        return item
    }

    func pluginConfigurationViewItem(for pluginID: String) -> PluginConfigurationViewItem {
        if let cachedItem = configurationViewCache[pluginID] {
            return cachedItem
        }

        let configurations = corePluginsForCallbacks()
            .filter { $0.metadata.id == pluginID }
            .compactMap(\.configuration)

        let context = PluginConfigurationContext(pluginID: pluginID)
        let content: AnyView

        switch configurations.count {
        case 0:
            content = AnyView(EmptyView())
        case 1:
            content = configurations[0].makeView(context)
        default:
            let views = configurations.map { $0.makeView(context) }
            content = AnyView(
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(views.enumerated()), id: \.offset) { entry in
                        entry.element
                    }
                }
            )
        }

        let item = PluginConfigurationViewItem(id: pluginID, content: content)
        configurationViewCache[pluginID] = item
        return item
    }

    func discardComponentViews() {
        componentViewCache.removeAll()
    }

    private func plugin(for pluginID: String) -> (any FeaturePlugin)? {
        plugins.first(where: { $0.manifest.id == pluginID })
    }

    private func componentPlugin(for pluginID: String) -> (any ComponentPlugin)? {
        componentPlugins.first(where: { $0.metadata.id == pluginID })
    }

    private func corePlugin(for pluginID: String) -> (any PluginCore)? {
        plugin(for: pluginID) ?? componentPlugin(for: pluginID)
    }

    private func rebuildDerivedState() {
        let orderedPlugins = orderedPlugins()
        let orderedComponentPlugins = orderedComponentPlugins()
        let orderedDescriptors = orderedPluginDescriptors()
        let panelStatesByID = Dictionary(
            uniqueKeysWithValues: orderedPlugins.map { plugin in
                (plugin.manifest.id, plugin.panelState)
            }
        )
        let componentStatesByID = Dictionary(
            uniqueKeysWithValues: orderedComponentPlugins.map { plugin in
                (plugin.metadata.id, plugin.componentState)
            }
        )

        panelItems = orderedPlugins.compactMap { plugin in
            let manifest = plugin.manifest
            guard let state = panelStatesByID[manifest.id] else {
                return nil
            }

            guard
                state.isVisible,
                pluginDisplayPreferencesStore.isVisible(
                    manifest.id,
                    defaultPluginIDs: defaultPluginIDs
                )
            else {
                return nil
            }

            let description = state.errorMessage ?? state.subtitle

            return PluginPanelItem(
                id: manifest.id,
                title: manifest.title,
                iconName: manifest.iconName,
                iconTint: manifest.iconTint,
                controlStyle: manifest.controlStyle,
                menuActionBehavior: manifest.menuActionBehavior,
                description: description.isEmpty ? manifest.defaultDescription : description,
                helpText: description.isEmpty ? manifest.defaultDescription : description,
                descriptionTone: state.errorMessage == nil ? .secondary : .error,
                isOn: state.isOn,
                isExpanded: state.isExpanded,
                isEnabled: state.isEnabled,
                detail: state.detail
            )
        }

        componentItems = orderedComponentPlugins.compactMap { plugin in
            let metadata = plugin.metadata
            guard let state = componentStatesByID[metadata.id] else {
                return nil
            }

            guard
                state.isVisible,
                pluginDisplayPreferencesStore.isVisible(
                    metadata.id,
                    defaultPluginIDs: defaultPluginIDs
                )
            else {
                return nil
            }

            let description = state.errorMessage ?? state.subtitle

            return PluginComponentItem(
                id: metadata.id,
                title: metadata.title,
                iconName: metadata.iconName,
                iconTint: metadata.iconTint,
                description: description.isEmpty ? metadata.defaultDescription : description,
                helpText: description.isEmpty ? metadata.defaultDescription : description,
                descriptionTone: state.errorMessage == nil ? .secondary : .error,
                span: plugin.componentDescriptor.span,
                isActive: state.isActive,
                isEnabled: state.isEnabled
            )
        }
        trimComponentViewCache(keeping: Set(componentItems.map(\.id)))

        featureManagementItems = orderedDescriptors.map { descriptor in
            let metadata = descriptor.metadata

            return PluginFeatureManagementItem(
                id: metadata.id,
                title: metadata.title,
                description: metadata.defaultDescription,
                iconName: metadata.iconName,
                iconTint: metadata.iconTint,
                isVisible: pluginDisplayPreferencesStore.isVisible(
                    metadata.id,
                    defaultPluginIDs: defaultPluginIDs
                ),
                isActive: descriptor.featurePlugin.flatMap { panelStatesByID[$0.manifest.id] }?.isOn == true
                    || descriptor.componentPlugin.flatMap { componentStatesByID[$0.metadata.id] }?.isActive == true,
                presentation: descriptor.presentation
            )
        }

        settingsCards = orderedCorePlugins().flatMap { plugin in
            plugin.settingsSections.map { section in
                PluginSettingsCard(
                    id: "\(plugin.metadata.id).\(section.id)",
                    pluginID: plugin.metadata.id,
                    title: section.title,
                    description: section.description,
                    statusText: section.status.text,
                    statusSystemImage: section.status.systemImage,
                    statusTone: section.status.tone,
                    footnote: section.footnote,
                    buttonTitle: section.buttonTitle,
                    actionID: section.actionID
                )
            }
        }

        permissionCards = orderedCorePlugins().flatMap { plugin in
            plugin.permissionRequirements.map { requirement in
                let state = plugin.permissionState(for: requirement.id)

                return PluginPermissionCard(
                    id: "\(plugin.metadata.id).permission.\(requirement.id)",
                    pluginID: plugin.metadata.id,
                    permissionID: requirement.id,
                    title: requirement.title,
                    description: requirement.description,
                    statusText: state.statusText ?? (state.isGranted ? "已授权" : "未授权"),
                    statusSystemImage: state.statusSystemImage ?? (state.isGranted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"),
                    statusTone: state.statusTone ?? (state.isGranted ? .positive : .caution),
                    footnote: state.footnote,
                    buttonTitle: permissionActionTitle(
                        for: requirement.kind,
                        isGranted: state.isGranted
                    )
                )
            }
        }

        shortcutItems = shortcutDescriptors().map { descriptor in
            let customization = shortcutStore.customization(for: descriptor.itemID)
            let binding = resolvedBinding(for: descriptor)

            return ShortcutSettingsItem(
                id: descriptor.itemID,
                pluginID: descriptor.pluginID,
                pluginTitle: descriptor.pluginTitle,
                title: descriptor.definition.title,
                description: descriptor.definition.description,
                bindingText: ShortcutFormatter.displayString(for: binding),
                isRequired: descriptor.definition.isRequired,
                canClear: !descriptor.definition.isRequired && binding != nil,
                usesDefaultValue: customization == .inheritDefault,
                errorMessage: shortcutErrors[descriptor.itemID]
            )
        }

        pluginConfigurationItems = buildPluginConfigurationItems(
            settingsCards: settingsCards,
            permissionCards: permissionCards,
            shortcutItems: shortcutItems
        )
        trimConfigurationViewCache(keeping: Set(pluginConfigurationItems.map(\.id)))
        syncSelectedPluginConfigurationID()

        hasActivePlugin = panelStatesByID.values.contains(where: \.isOn)
            || componentStatesByID.values.contains(where: \.isActive)
    }

    private func handlePluginAction(_ action: () -> Void) {
        guard !isHandlingPluginAction else {
            action()
            return
        }

        isHandlingPluginAction = true

        action()

        isHandlingPluginAction = false
        rebuildDerivedState()
    }

    private func rebuildDerivedStateAfterPluginChange() {
        guard !isHandlingPluginAction else {
            return
        }

        rebuildDerivedState()
    }

    private func scheduleDisplayTopologyRefresh() {
        displayTopologyRefreshTask?.cancel()
        let refreshDelay = displayTopologyRefreshDelay
        displayTopologyRefreshTask = Task { @MainActor [weak self, refreshDelay] in
            do {
                try await Task.sleep(for: refreshDelay)
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            self?.refreshDisplayTopologyNow()
        }
    }

    private func refreshDisplayTopologyNow() {
        displayTopologyRefreshTask = nil
        handlePluginAction {
            for plugin in corePluginsForCallbacks() {
                if let displayTopologyRefreshing = plugin as? DisplayTopologyRefreshing {
                    displayTopologyRefreshing.refreshDisplayTopology()
                }
            }
        }
    }

    private func refreshAccessibilityPermissionNow() {
        handlePluginAction {
            for plugin in corePluginsForCallbacks() {
                if let accessibilityRefreshing = plugin as? AccessibilityPermissionRefreshing {
                    accessibilityRefreshing.refreshAccessibilityPermission()
                }
            }
        }
    }

    private func buildPluginConfigurationItems(
        settingsCards: [PluginSettingsCard],
        permissionCards: [PluginPermissionCard],
        shortcutItems: [ShortcutSettingsItem]
    ) -> [PluginConfigurationItem] {
        orderedPluginDescriptors().compactMap { descriptor in
            let pluginID = descriptor.metadata.id
            let matchingSettingsCards = settingsCards.filter { $0.pluginID == pluginID }
            let matchingPermissionCards = permissionCards.filter { $0.pluginID == pluginID }
            let matchingShortcutItems = shortcutItems.filter { $0.pluginID == pluginID }
            let configurations = corePlugins(for: descriptor).compactMap(\.configuration)
            let hasConfigurationSurface = !matchingSettingsCards.isEmpty
                || !matchingPermissionCards.isEmpty
                || !matchingShortcutItems.isEmpty
                || !configurations.isEmpty

            guard hasConfigurationSurface else {
                return nil
            }

            return PluginConfigurationItem(
                id: pluginID,
                pluginID: pluginID,
                title: descriptor.metadata.title,
                description: configurations.first?.description ?? descriptor.metadata.defaultDescription,
                iconName: descriptor.metadata.iconName,
                iconTint: descriptor.metadata.iconTint,
                settingsCards: matchingSettingsCards,
                permissionCards: matchingPermissionCards,
                shortcutItems: matchingShortcutItems,
                hasCustomConfiguration: !configurations.isEmpty
            )
        }
    }

    private func shortcutDescriptors() -> [ShortcutDescriptor] {
        orderedCorePlugins().flatMap { plugin in
            plugin.shortcutDefinitions.map { definition in
                ShortcutDescriptor(
                    itemID: shortcutItemID(
                        pluginID: plugin.metadata.id,
                        shortcutDefinitionID: definition.id
                    ),
                    pluginID: plugin.metadata.id,
                    pluginTitle: plugin.metadata.title,
                    definition: definition,
                    plugin: plugin
                )
            }
        }
    }

    private var defaultPluginIDs: [String] {
        defaultPluginDescriptors().map(\.metadata.id)
    }

    private func orderedPluginIDs() -> [String] {
        pluginDisplayPreferencesStore.orderedPluginIDs(defaultPluginIDs: defaultPluginIDs)
    }

    private func orderedPlugins() -> [any FeaturePlugin] {
        let pluginsByID = Dictionary(uniqueKeysWithValues: plugins.map { ($0.manifest.id, $0) })

        return orderedPluginIDs().compactMap { pluginsByID[$0] }
    }

    private func orderedComponentPlugins() -> [any ComponentPlugin] {
        let pluginsByID = Dictionary(uniqueKeysWithValues: componentPlugins.map { ($0.metadata.id, $0) })

        return orderedPluginIDs().compactMap { pluginsByID[$0] }
    }

    private func orderedCorePlugins() -> [any PluginCore] {
        orderedPluginDescriptors().flatMap { descriptor -> [any PluginCore] in
            corePlugins(for: descriptor)
        }
    }

    private func corePlugins(for descriptor: PluginDescriptor) -> [any PluginCore] {
        var plugins: [any PluginCore] = []

        if let featurePlugin = descriptor.featurePlugin {
            plugins.append(featurePlugin)
        }

        if let componentPlugin = descriptor.componentPlugin {
            plugins.append(componentPlugin)
        }

        return plugins
    }

    private func corePluginsForCallbacks() -> [any PluginCore] {
        var plugins: [any PluginCore] = []
        plugins.append(contentsOf: self.plugins)
        plugins.append(contentsOf: componentPlugins)
        return plugins
    }

    private func orderedPluginDescriptors() -> [PluginDescriptor] {
        let descriptorsByID = Dictionary(
            uniqueKeysWithValues: defaultPluginDescriptors().map { ($0.metadata.id, $0) }
        )

        return orderedPluginIDs().compactMap { descriptorsByID[$0] }
    }

    private func defaultPluginDescriptors() -> [PluginDescriptor] {
        var descriptorsByID: [String: PluginDescriptor] = [:]

        for plugin in plugins {
            let metadata = plugin.metadata
            var descriptor = descriptorsByID[metadata.id]
                ?? PluginDescriptor(metadata: metadata, featurePlugin: nil, componentPlugin: nil)
            descriptor.featurePlugin = plugin
            descriptorsByID[metadata.id] = descriptor
        }

        for plugin in componentPlugins {
            let metadata = plugin.metadata
            var descriptor = descriptorsByID[metadata.id]
                ?? PluginDescriptor(metadata: metadata, featurePlugin: nil, componentPlugin: nil)
            descriptor.componentPlugin = plugin
            descriptorsByID[metadata.id] = descriptor
        }

        return descriptorsByID.values.sorted { lhs, rhs in
            if lhs.metadata.order == rhs.metadata.order {
                return lhs.metadata.title.localizedCompare(rhs.metadata.title) == .orderedAscending
            }

            return lhs.metadata.order < rhs.metadata.order
        }
    }

    private func trimComponentViewCache(keeping visibleComponentIDs: Set<String>) {
        componentViewCache = componentViewCache.filter { visibleComponentIDs.contains($0.key) }
    }

    private func trimConfigurationViewCache(keeping configurationPluginIDs: Set<String>) {
        configurationViewCache = configurationViewCache.filter {
            configurationPluginIDs.contains($0.key)
        }
    }

    private func syncSelectedPluginConfigurationID() {
        let availableIDs = Set(pluginConfigurationItems.map(\.id))

        if let selectedPluginConfigurationID, availableIDs.contains(selectedPluginConfigurationID) {
            return
        }

        selectedPluginConfigurationID = pluginConfigurationItems.first?.id
    }

    private func shortcutDescriptor(for shortcutID: String) -> ShortcutDescriptor? {
        shortcutDescriptors().first(where: { $0.itemID == shortcutID })
    }

    private func shortcutItemID(pluginID: String, shortcutDefinitionID: String) -> String {
        "\(pluginID).shortcut.\(shortcutDefinitionID)"
    }

    private func resolvedBinding(for descriptor: ShortcutDescriptor) -> ShortcutBinding? {
        shortcutStore.resolvedBinding(
            for: descriptor.itemID,
            default: descriptor.definition.defaultBinding
        )
    }

    private func resolvedBinding(forPluginID pluginID: String, shortcutDefinitionID: String) -> ShortcutBinding? {
        guard let descriptor = shortcutDescriptors().first(where: {
            $0.pluginID == pluginID && $0.definition.id == shortcutDefinitionID
        }) else {
            return nil
        }

        return resolvedBinding(for: descriptor)
    }

    private func applyShortcutCustomization(
        _ customization: ShortcutCustomization,
        for descriptor: ShortcutDescriptor
    ) {
        do {
            try validateShortcutCustomization(customization, for: descriptor)
            shortcutStore.setCustomization(customization, for: descriptor.itemID)
            shortcutErrors.removeValue(forKey: descriptor.itemID)
            rebuildDerivedState()
            syncGlobalShortcuts()
        } catch let error as ShortcutValidationError {
            shortcutErrors[descriptor.itemID] = error.localizedDescription
            rebuildDerivedState()
        } catch {
            shortcutErrors[descriptor.itemID] = error.localizedDescription
            rebuildDerivedState()
        }
    }

    private func validateShortcutCustomization(
        _ customization: ShortcutCustomization,
        for descriptor: ShortcutDescriptor
    ) throws {
        let candidate = ShortcutStore.resolve(
            customization: customization,
            defaultBinding: descriptor.definition.defaultBinding
        )

        if descriptor.definition.isRequired && candidate == nil {
            throw ShortcutValidationError.requiredShortcut
        }

        if let candidate {
            guard !candidate.modifiers.isEmpty else {
                throw ShortcutValidationError.missingModifier
            }

            guard !ShortcutKeyCode.isModifier(candidate.keyCode) else {
                throw ShortcutValidationError.modifierOnly
            }

            if let conflict = shortcutDescriptors().first(where: {
                $0.itemID != descriptor.itemID && resolvedBinding(for: $0) == candidate
            }) {
                throw ShortcutValidationError.duplicate(
                    ownerDescription: "\(conflict.pluginTitle) · \(conflict.definition.title)"
                )
            }
        }
    }

    private func syncGlobalShortcuts() {
        let registrations = shortcutDescriptors().compactMap { descriptor -> GlobalShortcutManager.Registration? in
            guard descriptor.definition.scope == .global else {
                return nil
            }

            guard let binding = resolvedBinding(for: descriptor) else {
                return nil
            }

            return GlobalShortcutManager.Registration(
                shortcutID: descriptor.itemID,
                binding: binding
            )
        }

        globalShortcutManager.updateBindings(registrations)
    }

    private func handleShortcutTrigger(shortcutID: String) {
        guard let descriptor = shortcutDescriptor(for: shortcutID) else {
            return
        }

        handlePluginAction {
            descriptor.plugin.handleShortcutAction(id: descriptor.definition.actionID)
        }
    }

    private func requestPermissionGuidance(forPluginID pluginID: String, permissionID: String) {
        guard corePluginsForCallbacks().contains(where: { plugin in
            plugin.metadata.id == pluginID
                && plugin.permissionRequirements.contains(where: { $0.id == permissionID })
        }) else {
            return
        }

        presentPluginConfiguration(pluginID: pluginID)
    }

    private func permissionActionTitle(
        for kind: PluginPermissionKind,
        isGranted: Bool
    ) -> String {
        switch kind {
        case .accessibility:
            return isGranted ? "检查授权状态" : "前往授权"
        case .calendarFullAccess:
            return isGranted ? "检查授权状态" : "请求授权"
        case .automation:
            return "打开设置"
        }
    }
}
