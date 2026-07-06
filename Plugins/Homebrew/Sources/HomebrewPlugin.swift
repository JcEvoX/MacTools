import AppKit
import Foundation
import SwiftUI
import MacToolsPluginKit

public final class HomebrewPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        HomebrewPluginProvider(context: context)
    }
}

@MainActor
private struct HomebrewPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        let localization = PluginLocalization(bundle: context.resourceBundle)
        let controller = HomebrewController()
        return [HomebrewPlugin(
            controller: controller,
            localization: localization
        )]
    }
}

@MainActor
public final class HomebrewPlugin: MacToolsPlugin, PluginPrimaryPanel {
    public enum ControlID {
        static let scan = "homebrew-scan"
        static let upgradeAll = "homebrew-upgrade-all"
        static let cleanup = "homebrew-cleanup"
        static let stop = "homebrew-stop"
    }

    public let metadata: PluginMetadata

    public let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .disclosure,
        menuActionBehavior: .keepPresented
    )

    public var onStateChange: (() -> Void)?
    public var requestPermissionGuidance: ((String) -> Void)?
    public var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let controller: HomebrewController
    private let localization: PluginLocalization
    private var isExpanded = false

    public init(
        controller: HomebrewController,
        localization: PluginLocalization
    ) {
        self.controller = controller
        self.localization = localization
        
        self.metadata = PluginMetadata(
            id: "homebrew",
            title: localization.string("metadata.title", defaultValue: "Homebrew"),
            iconName: "shippingbox.fill",
            iconTint: Color(nsColor: .systemOrange),
            order: 92,
            defaultDescription: localization.string("metadata.description", defaultValue: "Manage Homebrew packages, repositories, and perform diagnostics")
        )

        self.controller.onStateChange = { [weak self] in
            self?.onStateChange?()
        }
    }

    public func activate(context: PluginRuntimeContext) {
        // Auto scan on launch to populate initial count
        if controller.isBrewAvailable && controller.installedPackages.isEmpty {
            controller.scanAll()
        }
    }

    public func deactivate(reason: PluginDeactivationReason) {
        guard reason.requiresStateCleanup else { return }
        controller.cancelCurrentOperation()
    }

    public func refresh() {
        controller.scanAll()
    }

    public var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: subtitleText,
            isOn: controller.isBusy,
            isExpanded: isExpanded,
            isEnabled: true,
            isVisible: true,
            detail: isExpanded ? buildDetail() : nil,
            errorMessage: controller.isBrewAvailable ? nil : localization.string("panel.subtitle.notInstalled", defaultValue: "Homebrew not installed")
        )
    }

    public var permissionRequirements: [PluginPermissionRequirement] { [] }
    public var settingsSections: [PluginSettingsSection] { [] }
    public var shortcutDefinitions: [PluginShortcutDefinition] { [] }

    public var configuration: PluginConfiguration? {
        let controller = self.controller
        let localization = self.localization
        return PluginConfiguration(
            description: metadata.defaultDescription,
            prefersFullHeight: true
        ) { _ in
            HomebrewDetailView(
                controller: controller,
                localization: localization,
                showsHeader: false,
                contentPadding: 0,
                minimumContentHeight: 480
            )
        }
    }

    public func handleAction(_ action: PluginPanelAction) {
        switch action {
        case let .setDisclosureExpanded(value):
            isExpanded = value
            onStateChange?()
        case let .invokeAction(controlID):
            handleInvoke(controlID: controlID)
        default:
            break
        }
    }

    public func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    public func handlePermissionAction(id: String) {}
    public func handleSettingsAction(id: String) {}
    public func handleShortcutAction(id: String) {}

    // MARK: - Private

    private var subtitleText: String {
        guard controller.isBrewAvailable else {
            return localization.string("panel.subtitle.notInstalled", defaultValue: "Homebrew not installed")
        }
        if controller.isBusy {
            return controller.currentOperationName
        }
        let outdatedCount = controller.outdatedPackages.count
        if outdatedCount > 0 {
            return String(format: localization.string("panel.subtitle.upgradable", defaultValue: "%d package(s) upgradable"), outdatedCount)
        }
        return localization.string("panel.subtitle.upToDate", defaultValue: "All packages up to date")
    }

    private func handleInvoke(controlID: String) {
        switch controlID {
        case ControlID.scan:
            controller.scanAll()
        case ControlID.upgradeAll:
            controller.upgradeAll()
        case ControlID.cleanup:
            controller.runCleanup()
        case ControlID.stop:
            controller.cancelCurrentOperation()
        default:
            break
        }
    }

    private func buildDetail() -> PluginPanelDetail {
        var controls: [PluginPanelControl] = []

        controls.append(
            PluginPanelControl(
                id: ControlID.scan,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: nil,
                actionTitle: controller.isBusy ? localization.string("panel.action.scanning", defaultValue: "Scanning...") : localization.string("panel.action.scan", defaultValue: "Check for Updates"),
                actionIconSystemName: "magnifyingglass",
                isEnabled: !controller.isBusy && controller.isBrewAvailable
            )
        )

        let outdatedCount = controller.outdatedPackages.count
        controls.append(
            PluginPanelControl(
                id: ControlID.upgradeAll,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: nil,
                actionTitle: localization.string("panel.action.upgradeAll", defaultValue: "Upgrade All"),
                actionIconSystemName: "arrow.up.circle",
                showsLeadingDivider: true,
                isEnabled: !controller.isBusy && controller.isBrewAvailable && outdatedCount > 0
            )
        )

        controls.append(
            PluginPanelControl(
                id: ControlID.cleanup,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: nil,
                actionTitle: localization.string("panel.action.cleanup", defaultValue: "Cleanup Caches"),
                actionIconSystemName: "trash",
                showsLeadingDivider: true,
                isEnabled: !controller.isBusy && controller.isBrewAvailable
            )
        )

        if controller.isBusy {
            controls.append(
                PluginPanelControl(
                    id: ControlID.stop,
                    kind: .actionRow,
                    options: [],
                    selectedOptionID: nil,
                    dateValue: nil,
                    minimumDate: nil,
                    displayedComponents: nil,
                    datePickerStyle: nil,
                    sectionTitle: nil,
                    actionTitle: localization.string("panel.action.stop", defaultValue: "Cancel"),
                    actionIconSystemName: "xmark.circle",
                    showsLeadingDivider: true,
                    isEnabled: true
                )
            )
        }

        return PluginPanelDetail(primaryControls: controls, secondaryPanel: nil)
    }
}
