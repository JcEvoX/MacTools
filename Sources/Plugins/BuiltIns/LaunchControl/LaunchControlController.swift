import AppKit
import Foundation

@MainActor
final class LaunchControlController: ObservableObject {
    @Published private(set) var snapshot = LaunchControlSnapshot()

    var onStateChange: (() -> Void)?

    private let scanner: LaunchControlScanner
    private let runner: any LaunchControlCommandRunning
    private let favoritesStore: LaunchControlFavoritesStore
    private var refreshTask: Task<Void, Never>?

    init(
        scanner: LaunchControlScanner? = nil,
        runner: any LaunchControlCommandRunning = ProcessLaunchControlCommandRunner(),
        favoritesStore: LaunchControlFavoritesStore = LaunchControlFavoritesStore()
    ) {
        self.runner = runner
        self.favoritesStore = favoritesStore
        self.scanner = scanner ?? LaunchControlScanner(runner: runner)
    }

    deinit {
        refreshTask?.cancel()
    }

    func refresh() {
        guard !snapshot.isRefreshing else { return }

        snapshot.isRefreshing = true
        snapshot.items = []
        snapshot.selectedItemID = nil
        snapshot.errorMessage = nil
        snapshot.operationMessage = nil
        snapshot.scanLogEntries = ["开始扫描 LaunchAgent / LaunchDaemon"]
        snapshot.currentScanTarget = nil
        onStateChange?()

        let progressStream = AsyncStream<LaunchControlScanEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(120)
        )
        let progressTask = Task { @MainActor [weak self] in
            for await event in progressStream.stream {
                self?.handleScanEvent(event)
            }
        }

        refreshTask = Task { [weak self, scanner, progressStream] in
            let result = await Task.detached(priority: .userInitiated) {
                scanner.scan { event in
                    progressStream.continuation.yield(event)
                }
            }.value
            progressStream.continuation.finish()
            await progressTask.value

            guard let self, !Task.isCancelled else { return }
            self.apply(result: result)
        }
    }

    func selectItem(id: String?) {
        snapshot.selectedItemID = id
        onStateChange?()
    }

    func openInFinder(_ item: LaunchControlItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.plistURL])
    }

    func setFavorite(_ isFavorite: Bool, for item: LaunchControlItem) {
        favoritesStore.setFavorite(isFavorite, for: item.id)
        replaceItem(item, isFavorite: isFavorite)
        snapshot.operationMessage = isFavorite ? "已关注 \(item.label)" : "已取消关注 \(item.label)"
        onStateChange?()
    }

    func bootstrap(_ item: LaunchControlItem) {
        performManagedAction(
            item: item,
            title: "加载",
            arguments: ["bootstrap", item.launchctlDomain, item.plistURL.path]
        )
    }

    func bootout(_ item: LaunchControlItem) {
        performManagedAction(
            item: item,
            title: "卸载",
            arguments: ["bootout", item.launchctlDomain, item.plistURL.path]
        )
    }

    func enable(_ item: LaunchControlItem) {
        performManagedAction(
            item: item,
            title: "启用",
            arguments: ["enable", "\(item.launchctlDomain)/\(item.label)"]
        )
    }

    func disable(_ item: LaunchControlItem) {
        performManagedAction(
            item: item,
            title: "禁用",
            arguments: ["disable", "\(item.launchctlDomain)/\(item.label)"]
        )
    }

    func start(_ item: LaunchControlItem) {
        performManagedAction(
            item: item,
            title: "启动",
            arguments: ["kickstart", "\(item.launchctlDomain)/\(item.label)"]
        )
    }

    func stop(_ item: LaunchControlItem) {
        performManagedAction(
            item: item,
            title: "停止",
            arguments: ["kill", "TERM", "\(item.launchctlDomain)/\(item.label)"]
        )
    }

    func restart(_ item: LaunchControlItem) {
        performManagedAction(
            item: item,
            title: "重启",
            arguments: ["kickstart", "-k", "\(item.launchctlDomain)/\(item.label)"]
        )
    }

    private func apply(result: LaunchControlScanResult) {
        let selectedID = snapshot.selectedItemID
        snapshot.items = sortedItems(result.items.map(applyingFavoriteState))
        snapshot.selectedItemID = result.items.contains(where: { $0.id == selectedID })
            ? selectedID
            : result.items.first?.id
        snapshot.isRefreshing = false
        snapshot.lastRefreshDate = Date()
        snapshot.errorMessage = result.warnings.first
        snapshot.currentScanTarget = nil
        appendScanLog("扫描完成：\(result.items.count) 项")
        onStateChange?()
    }

    private func handleScanEvent(_ event: LaunchControlScanEvent) {
        switch event {
        case let .directory(path):
            snapshot.currentScanTarget = path
            appendScanLog("目录：\(path)")
        case let .file(path):
            snapshot.currentScanTarget = path
            appendScanLog("读取：\(URL(fileURLWithPath: path).lastPathComponent)")
        case let .found(item):
            upsertScannedItem(item)
        case let .message(message):
            appendScanLog(message)
        }

        onStateChange?()
    }

    private func upsertScannedItem(_ item: LaunchControlItem) {
        let item = applyingFavoriteState(item)

        if let index = snapshot.items.firstIndex(where: { $0.id == item.id }) {
            snapshot.items[index] = item
        } else {
            snapshot.items.append(item)
        }
        snapshot.items = sortedItems(snapshot.items)
        if snapshot.selectedItemID == nil {
            snapshot.selectedItemID = snapshot.items.first?.id
        }
    }

    private func replaceItem(_ item: LaunchControlItem, isFavorite: Bool) {
        guard let index = snapshot.items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        let updatedItem = LaunchControlItem(
            id: item.id,
            label: item.label,
            plistURL: item.plistURL,
            scope: item.scope,
            origin: item.origin,
            state: item.state,
            pid: item.pid,
            lastExitStatus: item.lastExitStatus,
            programArguments: item.programArguments,
            runAtLoad: item.runAtLoad,
            keepAliveDescription: item.keepAliveDescription,
            startInterval: item.startInterval,
            startCalendarDescription: item.startCalendarDescription,
            rawPlist: item.rawPlist,
            launchctlDomain: item.launchctlDomain,
            isDisabled: item.isDisabled,
            isLoaded: item.isLoaded,
            isFavorite: isFavorite
        )
        snapshot.items[index] = updatedItem
        snapshot.items = sortedItems(snapshot.items)
    }

    private func applyingFavoriteState(_ item: LaunchControlItem) -> LaunchControlItem {
        LaunchControlItem(
            id: item.id,
            label: item.label,
            plistURL: item.plistURL,
            scope: item.scope,
            origin: item.origin,
            state: item.state,
            pid: item.pid,
            lastExitStatus: item.lastExitStatus,
            programArguments: item.programArguments,
            runAtLoad: item.runAtLoad,
            keepAliveDescription: item.keepAliveDescription,
            startInterval: item.startInterval,
            startCalendarDescription: item.startCalendarDescription,
            rawPlist: item.rawPlist,
            launchctlDomain: item.launchctlDomain,
            isDisabled: item.isDisabled,
            isLoaded: item.isLoaded,
            isFavorite: favoritesStore.isFavorite(item.id)
        )
    }

    private func sortedItems(_ items: [LaunchControlItem]) -> [LaunchControlItem] {
        items.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            if lhs.origin != rhs.origin {
                return lhs.origin.rawValue < rhs.origin.rawValue
            }
            if lhs.scope != rhs.scope {
                return lhs.scope.rawValue < rhs.scope.rawValue
            }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private func appendScanLog(_ message: String) {
        snapshot.scanLogEntries.append(message)
        if snapshot.scanLogEntries.count > 80 {
            snapshot.scanLogEntries.removeFirst(snapshot.scanLogEntries.count - 80)
        }
    }

    private func performManagedAction(
        item: LaunchControlItem,
        title: String,
        arguments: [String]
    ) {
        guard item.canManage else {
            snapshot.operationMessage = "系统或全局启动项默认只读，避免误操作。"
            onStateChange?()
            return
        }

        snapshot.operationMessage = "\(title) \(item.label)..."
        snapshot.errorMessage = nil
        onStateChange?()

        Task { [weak self, runner] in
            let result: Result<LaunchControlCommandResult, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    return .success(try runner.runLaunchctl(arguments: arguments))
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self else { return }

            switch result {
            case let .success(commandResult) where commandResult.exitCode == 0:
                self.snapshot.operationMessage = "\(title)完成"
                self.refresh()
            case let .success(commandResult):
                let message = commandResult.combinedOutput
                self.snapshot.operationMessage = "\(title)失败"
                self.snapshot.errorMessage = message.isEmpty
                    ? "launchctl 返回退出码 \(commandResult.exitCode)"
                    : message
                self.onStateChange?()
            case let .failure(error):
                self.snapshot.operationMessage = "\(title)失败"
                self.snapshot.errorMessage = error.localizedDescription
                self.onStateChange?()
            }
        }
    }
}

@MainActor
final class LaunchControlFeature {
    static let shared = LaunchControlFeature()

    let controller: LaunchControlController

    private init(controller: LaunchControlController = LaunchControlController()) {
        self.controller = controller
    }

    func makePlugin() -> LaunchControlPlugin {
        LaunchControlPlugin(controller: controller)
    }
}
