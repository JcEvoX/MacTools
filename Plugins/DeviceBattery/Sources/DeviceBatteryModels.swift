import Foundation

enum DeviceBatteryLayoutMode: String, CaseIterable, Equatable {
    case grid
    case list

    var title: String {
        switch self {
        case .grid:
            return "列表"
        case .list:
            return "圆环"
        }
    }

    var subtitle: String {
        switch self {
        case .grid:
            return "按设备逐行显示"
        case .list:
            return "多设备圆环"
        }
    }

}

enum DeviceBatteryChargeState: Equatable, Sendable {
    case unknown
    case normal
    case charging
    case charged
    case plugged
    case invalid

    var title: String {
        switch self {
        case .unknown:
            return "未知"
        case .normal:
            return "正常"
        case .charging:
            return "充电中"
        case .charged:
            return "已充满"
        case .plugged:
            return "外接电源"
        case .invalid:
            return "电量无效"
        }
    }

    var isActiveChargingState: Bool {
        switch self {
        case .charging, .charged, .plugged:
            return true
        case .unknown, .normal, .invalid:
            return false
        }
    }
}

enum DeviceBatteryKind: Equatable, Sendable {
    case internalBattery
    case bluetooth
    case magicAccessory
    case rapooMouse
    case airPodsPart
    case other

    var iconName: String {
        switch self {
        case .internalBattery:
            return "laptopcomputer"
        case .bluetooth:
            return "dot.radiowaves.left.and.right"
        case .magicAccessory:
            return "keyboard"
        case .rapooMouse:
            return "computermouse.fill"
        case .airPodsPart:
            return "airpodspro"
        case .other:
            return "battery.75percent"
        }
    }

    var title: String {
        switch self {
        case .internalBattery:
            return "Mac"
        case .bluetooth:
            return "蓝牙"
        case .magicAccessory:
            return "Apple 外设"
        case .rapooMouse:
            return "雷柏鼠标"
        case .airPodsPart:
            return "耳机"
        case .other:
            return "设备"
        }
    }
}

enum DeviceBatteryComponentRole: String, Equatable, Sendable {
    case aggregate
    case left
    case right
    case chargingCase

    var isPart: Bool {
        self != .aggregate
    }
}

struct DeviceBatteryComponentIdentity: Equatable, Sendable {
    let groupID: String
    let role: DeviceBatteryComponentRole
}

struct DeviceBatteryItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let model: String?
    let kind: DeviceBatteryKind
    let level: Int?
    let chargeState: DeviceBatteryChargeState
    let parentName: String?
    let source: String
    let lastUpdated: Date?
    let isConnected: Bool
    let detail: String?
    let componentIdentity: DeviceBatteryComponentIdentity?

    init(
        id: String,
        name: String,
        model: String?,
        kind: DeviceBatteryKind,
        level: Int?,
        chargeState: DeviceBatteryChargeState,
        parentName: String?,
        source: String,
        lastUpdated: Date?,
        isConnected: Bool,
        detail: String?,
        componentIdentity: DeviceBatteryComponentIdentity? = nil
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.kind = kind
        self.level = level
        self.chargeState = chargeState
        self.parentName = parentName
        self.source = source
        self.lastUpdated = lastUpdated
        self.isConnected = isConnected
        self.detail = detail
        self.componentIdentity = componentIdentity
    }

    var clampedLevel: Int? {
        guard let level else {
            return nil
        }

        return min(max(level, 0), 100)
    }
}

enum DeviceBatteryItemNormalizer {
    static func removingRedundantComponentAggregates(
        _ items: [DeviceBatteryItem]
    ) -> [DeviceBatteryItem] {
        let componentGroups = Set(items.compactMap(componentGroupID))
        guard !componentGroups.isEmpty else {
            return items
        }

        return items.filter { item in
            guard let aggregateGroupID = aggregateGroupID(item) else {
                return true
            }

            return !componentGroups.contains(aggregateGroupID)
        }
    }

    private static func aggregateGroupID(_ item: DeviceBatteryItem) -> String? {
        guard let identity = item.componentIdentity,
              identity.role == .aggregate,
              item.clampedLevel != nil
        else {
            return nil
        }

        return identity.groupID
    }

    private static func componentGroupID(_ item: DeviceBatteryItem) -> String? {
        guard let identity = item.componentIdentity,
              identity.role.isPart,
              item.clampedLevel != nil
        else {
            return nil
        }

        return identity.groupID
    }
}

enum DeviceBatteryAccessState: Equatable, Sendable {
    case idle
    case scanning
    case ready
    case noDevices
    case permissionDenied
    case failed(String)

    var isError: Bool {
        switch self {
        case .permissionDenied, .failed:
            return true
        case .idle, .scanning, .ready, .noDevices:
            return false
        }
    }
}

struct DeviceBatterySnapshot: Equatable, Sendable {
    var accessState: DeviceBatteryAccessState
    var items: [DeviceBatteryItem]
    var lastUpdated: Date?
    var rapooState: RapooBatteryAccessState

    static let idle = DeviceBatterySnapshot(
        accessState: .idle,
        items: [],
        lastUpdated: nil,
        rapooState: .idle
    )

    var visibleItems: [DeviceBatteryItem] {
        items.sorted(by: Self.sortItems)
    }

    var primaryItem: DeviceBatteryItem? {
        visibleItems.first
    }

    var lowBatteryCount: Int {
        visibleItems.filter { item in
            guard let level = item.clampedLevel else {
                return false
            }

            return level <= 20 && item.chargeState != .charging && item.chargeState != .charged
        }.count
    }

    var subtitle: String {
        switch accessState {
        case .idle:
            return "等待检测"
        case .scanning:
            return "正在读取设备电量"
        case .ready:
            if lowBatteryCount > 0 {
                return "\(visibleItems.count) 台设备，\(lowBatteryCount) 台低电量"
            }
            return "\(visibleItems.count) 台设备"
        case .noDevices:
            return "未检测到可显示电量"
        case .permissionDenied:
            return "需要输入监控权限"
        case let .failed(message):
            return message
        }
    }

    var errorMessage: String? {
        switch accessState {
        case .permissionDenied:
            return "无法访问雷柏 HID 接口，请在系统设置中允许 MacTools 使用输入监控。"
        case let .failed(message):
            return message
        case .idle, .scanning, .ready, .noDevices:
            return nil
        }
    }

    private static func sortItems(_ left: DeviceBatteryItem, _ right: DeviceBatteryItem) -> Bool {
        let leftRank = itemRank(left)
        let rightRank = itemRank(right)
        if leftRank != rightRank {
            return leftRank < rightRank
        }

        return left.name.localizedCompare(right.name) == .orderedAscending
    }

    private static func itemRank(_ item: DeviceBatteryItem) -> Int {
        if let level = item.clampedLevel,
           level <= 20,
           item.chargeState != .charging,
           item.chargeState != .charged {
            return 0
        }

        switch item.kind {
        case .internalBattery:
            return 1
        case .rapooMouse:
            return 2
        case .magicAccessory:
            return 3
        case .airPodsPart:
            return 4
        case .bluetooth:
            return 5
        case .other:
            return 6
        }
    }
}

enum DeviceBatteryFormatter {
    static func percent(_ level: Int?) -> String {
        guard let level else {
            return "--"
        }

        return "\(min(max(level, 0), 100))%"
    }

    static func time(_ date: Date?) -> String {
        guard let date else {
            return "未更新"
        }

        return timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
