import Foundation

enum LaunchControlScope: String, CaseIterable, Identifiable, Sendable {
    case user
    case global
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user:
            return "当前用户"
        case .global:
            return "全局"
        case .system:
            return "系统"
        }
    }
}

enum LaunchControlState: String, CaseIterable, Identifiable, Sendable {
    case running
    case loaded
    case disabled
    case failed
    case unloaded
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running:
            return "运行中"
        case .loaded:
            return "已加载"
        case .disabled:
            return "已禁用"
        case .failed:
            return "异常退出"
        case .unloaded:
            return "未加载"
        case .unknown:
            return "未知"
        }
    }
}

enum LaunchControlOrigin: String, CaseIterable, Identifiable, Sendable {
    case userCreated
    case thirdParty
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userCreated:
            return "用户创建"
        case .thirdParty:
            return "应用创建"
        case .system:
            return "系统内置"
        }
    }
}

enum LaunchControlOriginFilter: String, CaseIterable, Identifiable {
    case all
    case favorite
    case manageable
    case userCreated
    case appCreated
    case system
    case readOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "全部来源"
        case .favorite:
            return "已关注"
        case .manageable:
            return "可操作"
        case .userCreated:
            return LaunchControlOrigin.userCreated.title
        case .appCreated:
            return LaunchControlOrigin.thirdParty.title
        case .system:
            return LaunchControlOrigin.system.title
        case .readOnly:
            return "只读"
        }
    }

    func matches(_ item: LaunchControlItem) -> Bool {
        switch self {
        case .all:
            return true
        case .favorite:
            return item.isFavorite
        case .manageable:
            return item.canManage
        case .userCreated:
            return item.origin == .userCreated
        case .appCreated:
            return item.origin == .thirdParty
        case .system:
            return item.origin == .system
        case .readOnly:
            return !item.canManage
        }
    }
}

enum LaunchControlFilter: String, CaseIterable, Identifiable {
    case all
    case user
    case global
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "全部范围"
        case .user:
            return LaunchControlScope.user.title
        case .global:
            return LaunchControlScope.global.title
        case .system:
            return LaunchControlScope.system.title
        }
    }

    var scope: LaunchControlScope? {
        switch self {
        case .all:
            return nil
        case .user:
            return .user
        case .global:
            return .global
        case .system:
            return .system
        }
    }
}

enum LaunchControlStateFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case loaded
    case disabled
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "全部状态"
        case .running:
            return LaunchControlState.running.title
        case .loaded:
            return LaunchControlState.loaded.title
        case .disabled:
            return LaunchControlState.disabled.title
        case .failed:
            return LaunchControlState.failed.title
        }
    }

    func matches(_ state: LaunchControlState) -> Bool {
        switch self {
        case .all:
            return true
        case .running:
            return state == .running
        case .loaded:
            return state == .loaded || state == .running
        case .disabled:
            return state == .disabled
        case .failed:
            return state == .failed
        }
    }
}

struct LaunchControlItem: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let plistURL: URL
    let scope: LaunchControlScope
    let origin: LaunchControlOrigin
    let state: LaunchControlState
    let pid: Int?
    let lastExitStatus: Int?
    let programArguments: [String]
    let runAtLoad: Bool
    let keepAliveDescription: String?
    let startInterval: Int?
    let startCalendarDescription: String?
    let rawPlist: String
    let launchctlDomain: String
    let isDisabled: Bool
    let isLoaded: Bool
    let isFavorite: Bool

    var commandText: String {
        if !programArguments.isEmpty {
            return programArguments.joined(separator: " ")
        }

        return "未声明 ProgramArguments"
    }

    var triggerSummary: String {
        var parts: [String] = []
        if runAtLoad {
            parts.append("登录/加载时运行")
        }
        if let keepAliveDescription {
            parts.append("KeepAlive: \(keepAliveDescription)")
        }
        if let startInterval {
            parts.append("每 \(startInterval) 秒")
        }
        if let startCalendarDescription {
            parts.append("定时: \(startCalendarDescription)")
        }
        return parts.isEmpty ? "未声明自动触发条件" : parts.joined(separator: " · ")
    }

    var canManage: Bool {
        scope == .user && !label.isEmpty && plistURL.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path)
    }

    var statusText: String {
        if let pid {
            return "\(state.title) · PID \(pid)"
        }
        if let lastExitStatus {
            return "\(state.title) · 退出码 \(lastExitStatus)"
        }
        return state.title
    }
}

struct LaunchControlSnapshot: Equatable {
    var items: [LaunchControlItem] = []
    var selectedItemID: String?
    var isRefreshing = false
    var lastRefreshDate: Date?
    var errorMessage: String?
    var operationMessage: String?
    var scanLogEntries: [String] = []
    var currentScanTarget: String?

    var selectedItem: LaunchControlItem? {
        guard let selectedItemID else {
            return items.first
        }

        return items.first(where: { $0.id == selectedItemID }) ?? items.first
    }
}

@MainActor
final class LaunchControlFavoritesStore {
    private enum StorageKey {
        static let storage = "launch-control.favorite-item-ids"
    }

    private let storage: PluginStorage

    init(
        context: PluginRuntimeContext = PluginRuntimeContext(pluginID: "launch-control"),
        userDefaults: UserDefaults? = nil
    ) {
        self.storage = userDefaults.map {
            UserDefaultsPluginStorage(pluginID: context.pluginID, userDefaults: $0)
        } ?? context.storage
        storage.migrateValueIfNeeded(fromLegacyKey: StorageKey.storage, to: StorageKey.storage)
    }

    func favoriteItemIDs() -> Set<String> {
        Set(storage.stringArray(forKey: StorageKey.storage) ?? [])
    }

    func isFavorite(_ itemID: String) -> Bool {
        favoriteItemIDs().contains(itemID)
    }

    func setFavorite(_ isFavorite: Bool, for itemID: String) {
        var favorites = favoriteItemIDs()
        if isFavorite {
            favorites.insert(itemID)
        } else {
            favorites.remove(itemID)
        }
        storage.set(favorites.sorted(), forKey: StorageKey.storage)
    }
}

enum LaunchControlScanEvent: Sendable {
    case directory(String)
    case file(String)
    case found(LaunchControlItem)
    case message(String)
}

struct LaunchControlPlistSummary: Sendable {
    let label: String
    let programArguments: [String]
    let runAtLoad: Bool
    let keepAliveDescription: String?
    let startInterval: Int?
    let startCalendarDescription: String?
    let rawPlist: String
}
