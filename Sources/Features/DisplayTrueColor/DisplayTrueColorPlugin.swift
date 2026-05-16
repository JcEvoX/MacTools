import AppKit
import Foundation
import OSLog
import SwiftUI

/// 通过 CoreBrightness 私有框架的 CBAdaptationClient 控制原彩显示（True Tone）。
@MainActor
final class DisplayTrueColorPlugin: FeaturePlugin {
    let manifest = PluginManifest(
        id: "display-true-color",
        title: "原彩显示",
        iconName: "circle.righthalf.filled",
        iconTint: Color(nsColor: .systemCyan),
        controlStyle: .switch,
        menuActionBehavior: .keepPresented,
        order: 25,
        defaultDescription: "自动调节显示器颜色以适应环境光"
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let logger = AppLog.displayTrueColorPlugin
    private let client: TrueToneClient
    private var isTrueColorEnabled: Bool = false
    private var isSupported: Bool = false

    init(client: TrueToneClient = CoreBrightnessTrueToneClient()) {
        self.client = client
        isSupported = client.isSupported
        isTrueColorEnabled = isSupported ? (client.isEnabled ?? false) : false
    }

    var panelState: PluginPanelState {
        PluginPanelState(
            subtitle: subtitle,
            isOn: isTrueColorEnabled,
            isExpanded: false,
            isEnabled: isSupported,
            isVisible: true,
            detail: nil,
            errorMessage: nil
        )
    }

    var permissionRequirements: [PluginPermissionRequirement] { [] }
    var settingsSections: [PluginSettingsSection] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] { [] }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}

    func refresh() {
        guard isSupported else { return }
        let current = client.isEnabled ?? false
        if current != isTrueColorEnabled {
            isTrueColorEnabled = current
            onStateChange?()
        }
    }

    func handlePanelAction(_ action: PluginPanelAction) {
        guard case let .setSwitch(enable) = action else { return }
        guard isSupported else { return }
        client.setEnabled(enable)
        isTrueColorEnabled = client.isEnabled ?? enable
        onStateChange?()
        logger.info("True Tone set to \(enable ? "enabled" : "disabled")")
    }

    // MARK: - Private

    private var subtitle: String {
        if !isSupported { return "不支持" }
        return isTrueColorEnabled ? "已开启" : "已关闭"
    }
}

// MARK: - TrueToneClient Protocol

protocol TrueToneClient {
    var isSupported: Bool { get }
    var isEnabled: Bool? { get }
    func setEnabled(_ enabled: Bool)
}

// MARK: - CoreBrightness Implementation

final class CoreBrightnessTrueToneClient: TrueToneClient {
    private typealias BoolIMP = @convention(c) (AnyObject, Selector) -> Bool
    private typealias SetBoolIMP = @convention(c) (AnyObject, Selector, Bool) -> Void

    private let adaptationClient: NSObject?
    private let supportedSel = NSSelectorFromString("supported")
    private let getEnabledSel = NSSelectorFromString("getEnabled")
    private let setEnabledSel = NSSelectorFromString("setEnabled:")

    init() {
        let bundle = Bundle(path: "/System/Library/PrivateFrameworks/CoreBrightness.framework")
        _ = bundle?.load()
        guard let cls = NSClassFromString("CBAdaptationClient") as? NSObject.Type else {
            adaptationClient = nil
            return
        }
        adaptationClient = cls.init()
    }

    var isSupported: Bool {
        guard let obj = adaptationClient,
              let imp = class_getMethodImplementation(type(of: obj), supportedSel) else {
            return false
        }
        return unsafeBitCast(imp, to: BoolIMP.self)(obj, supportedSel)
    }

    var isEnabled: Bool? {
        guard let obj = adaptationClient,
              let imp = class_getMethodImplementation(type(of: obj), getEnabledSel) else {
            return nil
        }
        return unsafeBitCast(imp, to: BoolIMP.self)(obj, getEnabledSel)
    }

    func setEnabled(_ enabled: Bool) {
        guard let obj = adaptationClient,
              let imp = class_getMethodImplementation(type(of: obj), setEnabledSel) else {
            return
        }
        unsafeBitCast(imp, to: SetBoolIMP.self)(obj, setEnabledSel, enabled)
    }
}


