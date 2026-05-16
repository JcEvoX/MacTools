import Foundation
import OSLog
import SwiftUI

@MainActor
final class EjectDiskPlugin: FeaturePlugin {
    let manifest = PluginManifest(
        id: "eject-disk",
        title: "推出磁盘",
        iconName: "eject.fill",
        iconTint: Color(nsColor: .systemGray),
        controlStyle: .button,
        menuActionBehavior: .keepPresented,
        order: 92,
        defaultDescription: "推出所有可移动磁盘",
        buttonTitle: "推出"
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let logger = AppLog.ejectDiskPlugin
    private var isEjecting = false
    private var hasEjectableDisk = false
    private var lastErrorMessage: String?
    private var volumeMountObservers: [NSObjectProtocol] = []

    var panelState: PluginPanelState {
        PluginPanelState(
            subtitle: subtitle,
            isOn: false,
            isExpanded: false,
            isEnabled: !isEjecting && hasEjectableDisk,
            isVisible: true,
            detail: nil,
            errorMessage: lastErrorMessage
        )
    }

    var permissionRequirements: [PluginPermissionRequirement] { [] }
    var settingsSections: [PluginSettingsSection] { [] }
    var shortcutDefinitions: [PluginShortcutDefinition] { [] }

    func refresh() {
        let hasEjectable = Self.hasEjectableDiskSync()
        if self.hasEjectableDisk != hasEjectable {
            self.hasEjectableDisk = hasEjectable
            self.onStateChange?()
        }
        
        // 设置磁盘挂载/卸载事件监听
        setupVolumeMountObserver()
    }
    
    private func setupVolumeMountObserver() {
        // 如果已经设置了监听，就不再重复设置
        guard volumeMountObservers.isEmpty else { return }
        
        let workspace = NSWorkspace.shared
        let notificationCenter = NSWorkspace.shared.notificationCenter
        
        let mountObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: workspace,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForEjectableDiskAndUpdate()
            }
        }
        
        let unmountObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: workspace,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForEjectableDiskAndUpdate()
            }
        }
        
        volumeMountObservers.append(mountObserver)
        volumeMountObservers.append(unmountObserver)
    }
    
    private func checkForEjectableDiskAndUpdate() {
        let hasEjectable = Self.hasEjectableDiskSync()
        if self.hasEjectableDisk != hasEjectable {
            self.hasEjectableDisk = hasEjectable
            self.onStateChange?()
        }
    }

    func handlePanelAction(_ action: PluginPanelAction) {
        switch action {
        case let .invokeAction(controlID):
            if controlID == "execute" {
                ejectAllDisks()
            }
        default:
            break
        }
    }

    func permissionState(for permissionID: String) -> PluginPermissionState {
        PluginPermissionState(isGranted: true, footnote: nil)
    }

    func handlePermissionAction(id: String) {}
    func handleSettingsAction(id: String) {}
    func handleShortcutAction(id: String) {}

    // MARK: - Private

    private var subtitle: String {
        if isEjecting {
            return "推出中..."
        }
        return manifest.defaultDescription
    }

    nonisolated private static func hasEjectableDiskSync() -> Bool {
        let fileManager = FileManager.default
        let logger = AppLog.ejectDiskPlugin
        
        do {
            let volumesPath = "/Volumes"
            guard fileManager.fileExists(atPath: volumesPath) else {
                return false
            }
            
            let ejectableVolumes = try getEjectableVolumes(from: volumesPath)
            logger.debug("Found \(ejectableVolumes.count) ejectable volumes")
            return !ejectableVolumes.isEmpty
            
        } catch {
            logger.error("Failed to check ejectable disks: \(error)")
            return false
        }
    }
    
    nonisolated private static func getEjectableVolumes(from volumesPath: String) throws -> [String] {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(atPath: volumesPath)
        
        return contents.filter { name in
            // 排除系统卷
            if name == "Macintosh HD" || name.hasPrefix(".") {
                return false
            }
            
            let volumePath = "\(volumesPath)/\(name)"
            var isDir: ObjCBool = false
            let exists = fileManager.fileExists(atPath: volumePath, isDirectory: &isDir)
            
            // 必须是目录
            return exists && isDir.boolValue
        }
    }

    private func ejectAllDisks() {
        guard !isEjecting else { return }

        isEjecting = true
        lastErrorMessage = nil
        onStateChange?()

        Task {
            do {
                try await executeEjectAll()

                await MainActor.run {
                    isEjecting = false
                    lastErrorMessage = nil
                    onStateChange?()
                }
            } catch {
                let errorMessage = error.localizedDescription
                logger.error("Failed to eject disks: \(errorMessage)")

                await MainActor.run {
                    isEjecting = false
                    lastErrorMessage = errorMessage
                    onStateChange?()
                }
            }
        }
    }

    private func executeEjectAll() async throws {
        let fileManager = FileManager.default
        let volumesPath = "/Volumes"
        
        guard fileManager.fileExists(atPath: volumesPath) else {
            throw NSError(domain: "EjectDiskPlugin", code: 1, userInfo: [NSLocalizedDescriptionKey: "/Volumes 目录不可用"])
        }
        
        let ejectableVolumes = try Self.getEjectableVolumes(from: volumesPath)
        
        guard !ejectableVolumes.isEmpty else {
            throw NSError(domain: "EjectDiskPlugin", code: 2, userInfo: [NSLocalizedDescriptionKey: "未找到可推出的磁盘"])
        }
        
        var successCount = 0
        var errorMessages: [String] = []
        
        for volumeName in ejectableVolumes {
            let volumePath = "\(volumesPath)/\(volumeName)"
            
            do {
                try await ejectVolume(at: volumePath)
                successCount += 1
                logger.info("Successfully ejected volume: \(volumeName)")
            } catch {
                errorMessages.append("- \(volumeName): \(error.localizedDescription)")
                logger.error("Failed to eject volume '\(volumeName)': \(error.localizedDescription)")
            }
        }
        
        // 如果有错误，抛出异常
        if !errorMessages.isEmpty {
            let message = "已推出 \(successCount) 个磁盘，\(errorMessages.count) 个失败:\n\(errorMessages.joined(separator: "\n"))"
            throw NSError(domain: "EjectDiskPlugin", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func ejectVolume(at volumePath: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["eject", volumePath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let errorMessage = output.isEmpty ? "推出失败" : output
            throw NSError(domain: "EjectDiskPlugin", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorMessage])
        }
    }
}
