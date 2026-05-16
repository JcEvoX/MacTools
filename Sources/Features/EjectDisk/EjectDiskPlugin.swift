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
        controlStyle: .switch,
        menuActionBehavior: .keepPresented,
        order: 92,
        defaultDescription: "推出所有可移动磁盘"
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let logger = AppLog.ejectDiskPlugin
    private var isEjecting = false
    private var isEjectedOn = false
    private var hasEjectableDisk = false
    private var lastErrorMessage: String?
    private var diskMonitorTimer: Timer?

    var panelState: PluginPanelState {
        PluginPanelState(
            subtitle: subtitle,
            isOn: isEjectedOn,
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
        if diskMonitorTimer == nil {
            startDiskMonitoring()
        }
    }

    func handlePanelAction(_ action: PluginPanelAction) {
        guard case let .setSwitch(enabled) = action else { return }
        
        if enabled {
            ejectAllDisks()
        } else {
            isEjectedOn = false
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

    private func cleanup() {
        diskMonitorTimer?.invalidate()
        diskMonitorTimer = nil
    }

    private func startDiskMonitoring() {
        guard diskMonitorTimer == nil else { return }

        // 立即检查一次
        checkForEjectableDisk()

        // 每0.5秒检查一次
        diskMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForEjectableDisk()
        }
    }

    private func stopDiskMonitoring() {
        diskMonitorTimer?.invalidate()
        diskMonitorTimer = nil
    }

    private func checkForEjectableDisk() {
        Task.detached(priority: .utility) { [weak self] in
            let hasEjectable = await self?.hasEjectableDiskAsync() ?? false

            await MainActor.run {
                if self?.hasEjectableDisk != hasEjectable {
                    self?.hasEjectableDisk = hasEjectable
                    self?.onStateChange?()
                }
            }
        }
    }

    private func hasEjectableDiskAsync() async -> Bool {
        let fileManager = FileManager.default
        
        do {
            // 检查 /Volumes 下的内容
            let volumesPath = "/Volumes"
            guard fileManager.fileExists(atPath: volumesPath) else {
                return false
            }
            
            let contents = try fileManager.contentsOfDirectory(atPath: volumesPath)
            
            // 过滤掉系统卷，查找可推出的磁盘
            let ejectableVolumes = contents.filter { name in
                // 排除系统卷
                if name == "Macintosh HD" || name.hasPrefix(".") {
                    return false
                }
                
                let volumePath = "\(volumesPath)/\(name)"
                var isDir: ObjCBool = false
                let exists = fileManager.fileExists(atPath: volumePath, isDirectory: &isDir)
                
                // 必须是目录且是符号链接或实际目录
                return exists && isDir.boolValue
            }
            
            logger.debug("Found \(ejectableVolumes.count) ejectable volumes: \(ejectableVolumes)")
            return !ejectableVolumes.isEmpty
            
        } catch {
            logger.error("Failed to check ejectable disks: \(error)")
            return false
        }
    }

    private func ejectAllDisks() {
        guard !isEjecting else { return }

        isEjecting = true
        isEjectedOn = true
        lastErrorMessage = nil
        onStateChange?()

        Task {
            do {
                try await executeEjectAll()

                await MainActor.run {
                    isEjecting = false
                    isEjectedOn = false
                    lastErrorMessage = nil
                    onStateChange?()
                }
            } catch {
                let errorMessage = error.localizedDescription
                logger.error("Failed to eject disks: \(errorMessage)")

                await MainActor.run {
                    isEjecting = false
                    isEjectedOn = false
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
        
        let contents = try fileManager.contentsOfDirectory(atPath: volumesPath)
        
        let ejectableVolumes = contents.filter { name in
            if name == "Macintosh HD" || name.hasPrefix(".") {
                return false
            }
            let volumePath = "\(volumesPath)/\(name)"
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: volumePath, isDirectory: &isDir) && isDir.boolValue
        }
        
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
        
        // 如果有错误但也有成功的，这不算完全失败
        if successCount > 0 && errorMessages.isEmpty {
            return
        }
        
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
