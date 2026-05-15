import ApplicationServices
import Foundation
import OSLog

// MARK: - Protocols

/// 辅助功能权限变化事件源。状态变化时调用 `onPermissionChange`。
/// 与 `DisplayConfigurationObserving` 对应，用于跨插件共享权限状态。
@MainActor
protocol AccessibilityPermissionObserving: AnyObject {
    var onPermissionChange: (() -> Void)? { get set }
}

/// 插件声明自身关心辅助功能权限，`PluginHost` 在权限变化时调用 `refreshAccessibilityPermission()`。
/// 与 `DisplayTopologyRefreshing` 对应。
@MainActor
protocol AccessibilityPermissionRefreshing {
    func refreshAccessibilityPermission()
}

// MARK: - Concrete Observer

/// 以 1 秒间隔轮询 `AXIsProcessTrusted()`，状态变化时通知宿主。
/// 整个应用共用一个计时器，避免多个插件各自独立轮询。
@MainActor
final class AccessibilityPermissionObserver: AccessibilityPermissionObserving {
    var onPermissionChange: (() -> Void)?

    private var lastKnownTrust: Bool
    private var pollingTimer: Timer?
    private let logger = AppLog.accessibilityPermissionObserver

    init() {
        lastKnownTrust = AXIsProcessTrusted()
        startPolling()
    }

    deinit {
        MainActor.assumeIsolated {
            pollingTimer?.invalidate()
        }
    }

    // MARK: - Private

    private func startPolling() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    private func poll() {
        let current = AXIsProcessTrusted()
        guard current != lastKnownTrust else { return }
        lastKnownTrust = current
        logger.info("辅助功能权限状态变化: \(current ? "已授权" : "已撤销", privacy: .public)")
        onPermissionChange?()
    }
}
