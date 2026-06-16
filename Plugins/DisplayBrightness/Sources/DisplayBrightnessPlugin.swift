import CoreGraphics
import Foundation
import SwiftUI
import MacToolsPluginKit

public final class DisplayBrightnessPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        DisplayBrightnessPluginProvider()
    }
}

@MainActor
private struct DisplayBrightnessPluginProvider: PluginProvider {
    func makePlugins() -> [any MacToolsPlugin] {
        [DisplayBrightnessPlugin()]
    }
}

@MainActor
final class DisplayBrightnessPlugin: MacToolsPlugin, PluginPrimaryPanel, DisplayTopologyRefreshing {
    private enum Constants {
        static let displayControlPrefix = "display."
        static let brightnessControlSuffix = ".brightness"
        static let disableBuiltInDisplayControlID = "built-in-display-disable"
        static let restoreBuiltInDisplayControlID = "built-in-display-restore"
    }

    let metadata = PluginMetadata(
        id: "display-brightness",
        title: "显示器亮度",
        iconName: "sun.max",
        iconTint: Color(nsColor: .systemYellow),
        order: 20,
        defaultDescription: "快速调节每个显示器的亮度"
    )

    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .disclosure,
        menuActionBehavior: .keepPresented
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let controller: DisplayBrightnessControlling
    private let displayDisableCoordinator: any DisplayDisableCoordinating
    private let showsDisplayDisableControls: Bool
    private var isExpanded = false
    private var displayDisableTask: Task<Void, Never>?

    init(
        controller: DisplayBrightnessControlling = DisplayBrightnessController(),
        displayDisableCoordinator: (any DisplayDisableCoordinating)? = nil,
        showsDisplayDisableControls: Bool = true
    ) {
        self.controller = controller
        self.displayDisableCoordinator = displayDisableCoordinator ?? DisplayDisableCoordinator(
            service: Self.defaultDisplayDisableService(),
            store: UserDefaultsDisplayDisableStateStore()
        )
        self.showsDisplayDisableControls = showsDisplayDisableControls
        self.controller.onStateChange = { [weak self] in
            self?.onStateChange?()
        }
    }

    var primaryPanelState: PluginPanelState {
        let snapshot = controller.snapshot()

        guard !snapshot.displays.isEmpty else {
            isExpanded = false
            return PluginPanelState(
                subtitle: "未检测到可调节亮度的显示器",
                isOn: false,
                isExpanded: false,
                isEnabled: false,
                isVisible: true,
                detail: nil,
                errorMessage: snapshot.errorMessage
            )
        }

        return PluginPanelState(
            subtitle: subtitle(for: snapshot.displays),
            isOn: false,
            isExpanded: isExpanded,
            isEnabled: true,
            isVisible: true,
            detail: isExpanded ? buildDetail(for: snapshot.displays) : nil,
            errorMessage: snapshot.errorMessage
        )
    }

    var permissionRequirements: [PluginPermissionRequirement] { [] }
    var settingsSections: [PluginSettingsSection] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] { [] }

    func refresh() {
        controller.refresh()
        displayDisableCoordinator.refreshSnapshot()
    }

    func refreshDisplayTopology() {
        controller.refresh()
        displayDisableTask?.cancel()
        displayDisableTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await displayDisableCoordinator.reconcileTopology()
            onStateChange?()
        }
    }

    func deactivate(reason: PluginDeactivationReason) {
        displayDisableTask?.cancel()
        displayDisableTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await displayDisableCoordinator.restoreBuiltInDisplay()
            onStateChange?()
        }
    }

    func handleAction(_ action: PluginPanelAction) {
        switch action {
        case let .setDisclosureExpanded(value):
            isExpanded = value
            onStateChange?()
        case let .setSlider(controlID, value, phase):
            guard let displayID = Self.parseDisplayID(from: controlID) else {
                DisplayBrightnessLog.plugin.error(
                    "invalid slider control id \(controlID, privacy: .public)"
                )
                return
            }

            controller.setBrightness(value, for: displayID, phase: phase)
            onStateChange?()
        case let .invokeAction(controlID):
            handleInvokeAction(controlID: controlID)
        case .setSwitch,
             .setSelection,
             .setNavigationSelection,
             .clearNavigationSelection,
             .setDate:
            return
        }
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}

    static func parseDisplayID(from controlID: String) -> CGDirectDisplayID? {
        guard
            controlID.hasPrefix(Constants.displayControlPrefix),
            controlID.hasSuffix(Constants.brightnessControlSuffix)
        else {
            return nil
        }

        let startIndex = controlID.index(
            controlID.startIndex,
            offsetBy: Constants.displayControlPrefix.count
        )
        let endIndex = controlID.index(
            controlID.endIndex,
            offsetBy: -Constants.brightnessControlSuffix.count
        )
        return CGDirectDisplayID(controlID[startIndex..<endIndex])
    }

    private func subtitle(for displays: [DisplayBrightnessDisplay]) -> String {
        if displays.count == 1, let display = displays.first {
            return "\(display.display.name) \(Self.percentText(for: display.brightness))"
        }

        return "\(displays.count) 个显示器"
    }

    private func buildDetail(for displays: [DisplayBrightnessDisplay]) -> PluginPanelDetail {
        let brightnessControls = displays.map { display in
            PluginPanelControl(
                id: "\(Constants.displayControlPrefix)\(display.display.id)\(Constants.brightnessControlSuffix)",
                kind: .slider,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: display.display.name,
                sliderValue: display.brightness,
                sliderBounds: 0...1,
                sliderStep: 0.01,
                valueLabel: Self.percentText(for: display.brightness),
                isEnabled: true
            )
        }

        return PluginPanelDetail(
            primaryControls: brightnessControls + displayDisableControls(),
            secondaryPanel: nil
        )
    }

    private func displayDisableControls() -> [PluginPanelControl] {
        guard showsDisplayDisableControls else {
            return []
        }

        let snapshot = displayDisableCoordinator.snapshot
        switch snapshot.status {
        case .unsupported:
            return [displayDisableActionControl(
                id: Constants.disableBuiltInDisplayControlID,
                title: "关闭内建显示屏",
                iconName: "display",
                isEnabled: false
            )]
        case .unavailable:
            var controls = [displayDisableActionControl(
                id: Constants.disableBuiltInDisplayControlID,
                title: "关闭内建显示屏",
                iconName: "display",
                isEnabled: false
            )]
            if snapshot.isRestoreAllowed {
                controls.append(displayDisableActionControl(
                    id: Constants.restoreBuiltInDisplayControlID,
                    title: "恢复内建显示屏",
                    iconName: "display",
                    isEnabled: true
                ))
            }
            return controls
        case .disabled:
            return [displayDisableActionControl(
                id: Constants.restoreBuiltInDisplayControlID,
                title: "恢复内建显示屏",
                iconName: "display",
                isEnabled: snapshot.isRestoreAllowed
            )]
        case .available, .failed, .busy:
            var controls: [PluginPanelControl] = []
            controls.append(displayDisableActionControl(
                id: Constants.disableBuiltInDisplayControlID,
                title: "关闭内建显示屏",
                iconName: "display",
                isEnabled: snapshot.isDisableAllowed
            ))
            if snapshot.isRestoreAllowed {
                controls.append(displayDisableActionControl(
                    id: Constants.restoreBuiltInDisplayControlID,
                    title: "恢复内建显示屏",
                    iconName: "display",
                    isEnabled: true
                ))
            }
            return controls
        }
    }

    private func displayDisableActionControl(
        id: String,
        title: String,
        iconName: String,
        isEnabled: Bool
    ) -> PluginPanelControl {
        PluginPanelControl(
            id: id,
            kind: .actionRow,
            options: [],
            selectedOptionID: nil,
            dateValue: nil,
            minimumDate: nil,
            displayedComponents: nil,
            datePickerStyle: nil,
            sectionTitle: nil,
            actionTitle: title,
            actionIconSystemName: iconName,
            showsLeadingDivider: true,
            isEnabled: isEnabled
        )
    }

    private func handleInvokeAction(controlID: String) {
        switch controlID {
        case Constants.disableBuiltInDisplayControlID:
            displayDisableTask?.cancel()
            displayDisableTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await displayDisableCoordinator.disableBuiltInDisplay()
                onStateChange?()
            }
        case Constants.restoreBuiltInDisplayControlID:
            displayDisableTask?.cancel()
            displayDisableTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await displayDisableCoordinator.restoreBuiltInDisplay()
                onStateChange?()
            }
        default:
            return
        }
    }

    private static func percentText(for brightness: Double) -> String {
        "\(Int((brightness * 100).rounded()))%"
    }

    private static func defaultDisplayDisableService() -> any DisplayDisableServicing {
        SystemDisplayDisableService()
    }
}
