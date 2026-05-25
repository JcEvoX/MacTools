import Foundation
import OSLog
import ServiceManagement

/// 抽象出 `SMAppService.mainApp` 的最小协议，便于在测试里替换为可控的假实现。
@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var isRegistered: Bool { get }
    func register() throws
    func unregister() throws
}

@MainActor
final class SystemLaunchAtLoginService: LaunchAtLoginServicing {
    private let appService: SMAppService

    init(appService: SMAppService = .mainApp) {
        self.appService = appService
    }

    var isRegistered: Bool {
        appService.status == .enabled
    }

    func register() throws {
        try appService.register()
    }

    func unregister() throws {
        try appService.unregister()
    }
}

/// 维护“开机自启动”开关状态，封装 `SMAppService.mainApp` 的注册与取消注册。
@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var lastErrorMessage: String?

    private let service: LaunchAtLoginServicing
    private let logger: Logger

    init(
        service: LaunchAtLoginServicing = SystemLaunchAtLoginService(),
        logger: Logger = AppLog.launchAtLogin
    ) {
        self.service = service
        self.logger = logger
        self.isEnabled = service.isRegistered
    }

    /// 切换登录项注册状态。状态变化失败时会回滚 `isEnabled` 并设置错误提示。
    func setEnabled(_ enabled: Bool) {
        let currentStatus = service.isRegistered
        guard currentStatus != enabled else {
            if isEnabled != currentStatus {
                isEnabled = currentStatus
            }
            lastErrorMessage = nil
            return
        }

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            lastErrorMessage = nil
        } catch {
            logger.error(
                "Failed to \(enabled ? "register" : "unregister", privacy: .public) login item: \(error.localizedDescription, privacy: .public)"
            )
            lastErrorMessage = enabled
                ? "无法开启开机自启动，请稍后重试或前往系统设置 > 通用 > 登录项中检查权限。"
                : "无法关闭开机自启动，请稍后重试或前往系统设置 > 通用 > 登录项中手动移除。"
        }

        let updated = service.isRegistered
        if isEnabled != updated {
            isEnabled = updated
        }
    }

    /// 重新从系统读取注册状态。比如外部 UI（系统设置）改动后可以调用刷新。
    func refreshStatus() {
        let updated = service.isRegistered
        if isEnabled != updated {
            isEnabled = updated
        }
    }

    func clearError() {
        lastErrorMessage = nil
    }
}
