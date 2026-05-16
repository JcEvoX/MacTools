import Foundation
import OSLog
import SwiftUI
import AppKit

final class EmptyTrashPlugin: FeaturePlugin {
    let manifest = PluginManifest(
        id: "empty-trash",
        title: "清空废纸篓",
        iconName: "trash",
        iconTint: Color(nsColor: .systemGray),
        controlStyle: .button,
        menuActionBehavior: .keepPresented,
        order: 93,
        defaultDescription: "清空废纸篓中的所有项目",
        buttonTitle: "清空"
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let logger = AppLog.emptyTrashPlugin
    private var itemCount: Int = 0
    private var isEmptying = false
    private var lastErrorMessage: String?
    private var trashObservers: [NSObjectProtocol] = []

    var panelState: PluginPanelState {
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
            setupTrashNotificationObservers()
        }
    }

    func handlePanelAction(_ action: PluginPanelAction) {
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

    @MainActor
    private func setupTrashNotificationObservers() {
        guard trashObservers.isEmpty else { return }
        // NSWorkspace.didTrashItemsNotification is only available in macOS 11+
        // Older notification name for file operations
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSNotification.Name("NSWorkspaceDidPerformFileOperationNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleCountRefresh()
            }
        }
        trashObservers.append(observer)
    }

    private var subtitle: String {
        if isEmptying { return "清空中..." }
        if itemCount == 0 { return "废纸篓为空" }
        return "\(itemCount) 个项目"
    }

    @MainActor
    private func emptyTrash() {
        guard !isEmptying, itemCount > 0 else { return }
        isEmptying = true
        lastErrorMessage = nil
        onStateChange?()

        Task {
            do {
                try await Self.emptyTrashViaAppleScript()
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

    private static func emptyTrashViaAppleScript() async throws {
        let script = "tell application \"Finder\" to empty trash"
        try await Task.detached(priority: .userInitiated) {
             if runOsascriptStandalone(script) == nil {
                throw NSError(
                    domain: "EmptyTrashPlugin",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "清空废纸篓失败，请检查“自动操作”权限"]
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
