import Foundation
import OSLog
import SwiftUI
import MacToolsPluginKit

public final class EmptyTrashPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        EmptyTrashPluginProvider(context: context)
    }
}

@MainActor
private struct EmptyTrashPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        [EmptyTrashPlugin(localization: PluginLocalization(bundle: context.resourceBundle))]
    }
}

final class EmptyTrashPlugin: MacToolsPlugin, PluginPrimaryPanel {
    let metadata: PluginMetadata

    let primaryPanelDescriptor: PluginPrimaryPanelDescriptor

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let localization: PluginLocalization
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools", category: "EmptyTrashPlugin")
    private var itemCount: Int = 0
    private var isEmptying = false
    private var lastErrorMessage: String?

    init(localization: PluginLocalization = PluginLocalization(bundle: .main)) {
        self.localization = localization
        self.metadata = PluginMetadata(
            id: "empty-trash",
            title: localization.string("metadata.title", defaultValue: "清空废纸篓"),
            iconName: "trash",
            iconTint: Color(nsColor: .systemGray),
            order: 93,
            defaultDescription: localization.string(
                "metadata.description",
                defaultValue: "清空废纸篓中的所有项目"
            )
        )
        self.primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
            controlStyle: .button,
            menuActionBehavior: .keepPresented,
            buttonTitle: localization.string("panel.button.empty", defaultValue: "清空")
        )
    }

    var primaryPanelState: PluginPanelState {
        PluginPanelState(
            subtitle: subtitle,
            isOn: false,
            isExpanded: false,
            isEnabled: !isEmptying && itemCount > 0,
            isVisible: true,
            detail: nil,
            errorMessage: lastErrorMessage
        )
    }

    var permissionRequirements: [PluginPermissionRequirement] { [] }
    var settingsSections: [PluginSettingsSection] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] { [] }

    func refresh() {
        Task { @MainActor in
            scheduleCountRefresh()
        }
    }

    func handleAction(_ action: PluginPanelAction) {
        Task { @MainActor in
            switch action {
            case let .invokeAction(controlID):
                if controlID == "execute" {
                    emptyTrash()
                }
            default:
                break
            }
        }
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}

    // MARK: - Private

    @MainActor
    private func scheduleCountRefresh() {
        Task {
            let count = await Self.fetchTrashItemCount()
            await MainActor.run {
                if self.itemCount != count {
                    self.itemCount = count
                    self.onStateChange?()
                }
            }
        }
    }

    private var subtitle: String {
        if isEmptying {
            return localization.string("panel.subtitle.emptying", defaultValue: "清空中...")
        }
        if itemCount == 0 {
            return localization.string("panel.subtitle.empty", defaultValue: "废纸篓为空")
        }
        return localization.format("panel.subtitle.countFormat", defaultValue: "%d 个项目", itemCount)
    }

    @MainActor
    private func emptyTrash() {
        guard !isEmptying, itemCount > 0 else { return }
        isEmptying = true
        lastErrorMessage = nil
        onStateChange?()

        Task {
            do {
                try await self.emptyTrashViaAppleScript()
                await MainActor.run {
                    self.isEmptying = false
                    self.itemCount = 0
                    self.onStateChange?()
                    self.scheduleCountRefresh()
                }
            } catch {
                await MainActor.run {
                    self.isEmptying = false
                    self.lastErrorMessage = error.localizedDescription
                    self.onStateChange?()
                    self.scheduleCountRefresh()
                    self.logger.error("Empty trash failed: \(error)")
                }
            }
        }
    }

    // MARK: - AppleScript helpers

    private static func fetchTrashItemCount() async -> Int {
        let script = "tell application \"Finder\" to count items of trash"
        return await Task.detached(priority: .userInitiated) {
            runOsascriptStandalone(script).flatMap { Int($0) } ?? 0
        }.value
    }

    private func emptyTrashViaAppleScript() async throws {
        let script = "tell application \"Finder\" to empty trash"
        let errorMessage = localization.string(
            "error.emptyFailed",
            defaultValue: "清空废纸篓失败，请检查“自动操作”权限"
        )
        try await Task.detached(priority: .userInitiated) {
             if runOsascriptStandalone(script) == nil {
                throw NSError(
                    domain: "EmptyTrashPlugin",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: errorMessage]
                )
            }
        }.value
    }
}

private func runOsascriptStandalone(_ script: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    do {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return nil
    }
}
