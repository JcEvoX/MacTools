import Foundation

// MARK: - Fan Preset

struct FanPreset: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var strategy: FanControlStrategy
    /// Built-in presets (auto / full-speed) cannot be deleted or renamed.
    let isBuiltIn: Bool

    init(id: String, name: String, strategy: FanControlStrategy, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.strategy = strategy
        self.isBuiltIn = isBuiltIn
    }
}

enum FanControlStrategy: Codable, Equatable {
    /// Restore macOS automatic fan management.
    case auto
    /// Set all fans to their hardware-reported maximum speed.
    case fullSpeed
    /// Set all fans to a fixed RPM (clamped to hardware limits at write time).
    case fixed(rpm: Int)
}

// MARK: - Built-in Preset IDs

enum FanPresetBuiltInID {
    static let auto = "builtin-auto"
    static let fullSpeed = "builtin-full-speed"
}

// MARK: - Fan Snapshot

struct FanSnapshot: Equatable {
    var fanCount: Int
    var fanSpeeds: [Int]
    var fanMinSpeeds: [Int]
    var fanMaxSpeeds: [Int]
    var cpuTemperature: Double?

    var averageSpeed: Int? {
        guard !fanSpeeds.isEmpty else { return nil }
        return fanSpeeds.reduce(0, +) / fanSpeeds.count
    }

    var globalMaxSpeed: Int {
        fanMaxSpeeds.max() ?? FanRPMLimits.fallbackMax
    }

    static let empty = FanSnapshot(
        fanCount: 0,
        fanSpeeds: [],
        fanMinSpeeds: [],
        fanMaxSpeeds: [],
        cpuTemperature: nil
    )
}

// MARK: - RPM Limits

enum FanRPMLimits {
    static let absoluteMin = 500
    static let absoluteMax = 8000
    static let fallbackMin = 1000
    static let fallbackMax = 5200
    static let defaultCustomRPM = 3000
}

// MARK: - Write Error

enum FanWriteError: Error, LocalizedError {
    case helperNotFound
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperNotFound:
            return "未找到 smc-helper 工具。请先按照说明安装它。"
        case .writeFailed(let msg):
            return "写入风扇速度失败：\(msg)"
        }
    }
}

// MARK: - SMC Protocols

protocol FanControlSMCReading: AnyObject {
    @MainActor func readSnapshot() -> FanSnapshot
}

protocol FanControlSMCWriting: AnyObject {
    @MainActor var isHelperAvailable: Bool { get }
    @MainActor @discardableResult
    func apply(strategy: FanControlStrategy, snapshot: FanSnapshot) -> FanWriteError?
}
