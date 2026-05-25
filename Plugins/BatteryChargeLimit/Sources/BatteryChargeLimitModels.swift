import Foundation

// MARK: - Charge Mode
//
// The user-facing mode. Once enabled, the plugin always sits in one of these
// three modes. Mode transitions are explicit (user action) except for the
// auto-fallback from `.charging` / `.discharging` back to `.holdAtLimit` when
// the battery reaches the configured limit.

enum BatteryChargeMode: String, Codable, Equatable {
    /// Charging is inhibited at the SMC level. This is the default whenever
    /// the plugin is enabled. Crucially: even if the battery is BELOW the
    /// limit, charging stays inhibited until the user explicitly resumes.
    case holdAtLimit
    /// User explicitly resumed charging. The plugin will auto-transition back
    /// to `.holdAtLimit` once the battery reaches the configured limit.
    case charging
    /// Force-discharge via CH0I. The plugin will auto-transition back to
    /// `.holdAtLimit` once the battery falls to (or below) the configured limit.
    case discharging
}

// MARK: - Limit Range

enum BatteryChargeLimits {
    static let minimumPercent = 20
    static let maximumPercent = 100
    static let defaultPercent = 80
    static let percentStep = 1
}

// MARK: - SMC Capabilities (reported by helper `probe`)

struct BatterySMCCapabilities: Equatable {
    var hasCHIE: Bool
    var hasCH0BC: Bool
    var hasBCLM: Bool
    var hasCH0I: Bool

    /// True when we have at least one writable charge-inhibit key family.
    var canInhibit: Bool { hasCHIE || hasCH0BC || hasBCLM }
    /// True when force-discharge (CH0I) is available on this hardware.
    var canForceDischarge: Bool { hasCH0I }
    /// True when the only inhibit path is Intel's BCLM (soft ceiling that
    /// auto-resumes once battery drops below limit). The plugin surfaces a
    /// caveat in the UI in this case.
    var isBCLMOnly: Bool { hasBCLM && !hasCHIE && !hasCH0BC }

    static let none = BatterySMCCapabilities(
        hasCHIE: false, hasCH0BC: false, hasBCLM: false, hasCH0I: false
    )
}

// MARK: - Battery Snapshot

enum BatteryPowerState: Equatable {
    /// No internal battery (e.g., Mac mini / Mac Studio). Plugin is hidden.
    case unavailable
    /// Battery is currently charging (kIOPSIsChargingKey == true).
    case charging
    /// Battery is full and AC-connected.
    case charged
    /// On adapter but not actively charging — either at limit or inhibited.
    case acPower
    /// Running on battery (no adapter).
    case unplugged
    /// Unknown/error.
    case unknown
}

struct BatterySnapshot: Equatable {
    var isAvailable: Bool
    /// Battery level as a percentage (0–100). nil when unavailable.
    var levelPercent: Int?
    var state: BatteryPowerState
    /// True when the AC adapter is connected (drawing external power).
    var isOnAdapter: Bool

    var hasBattery: Bool { isAvailable }

    static let empty = BatterySnapshot(
        isAvailable: false,
        levelPercent: nil,
        state: .unavailable,
        isOnAdapter: false
    )
}

// MARK: - Write Errors

enum BatteryChargeWriteError: Error, LocalizedError, Equatable {
    case helperNotFound
    case helperInstallFailed(String)
    case helperVerificationFailed
    case noSupportedSMCKey
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperNotFound:
            return "未找到内置电池控制组件。请重新安装电池充电上限插件。"
        case .helperInstallFailed(let msg):
            return "安装电池控制组件失败：\(msg)"
        case .helperVerificationFailed:
            return "电池控制组件校验失败。请重新安装电池充电上限插件。"
        case .noSupportedSMCKey:
            return "当前 Mac 固件未提供可写的充电控制键。可能是 macOS 已升级到不支持的版本。"
        case .writeFailed(let msg):
            return "写入充电控制失败：\(msg)"
        }
    }
}

// MARK: - SMC Protocols (for dependency injection / tests)

protocol BatteryChargeLimitReading: AnyObject {
    @MainActor func readSnapshot() -> BatterySnapshot
}

protocol BatteryChargeLimitWriting: AnyObject {
    @MainActor var isHelperAvailable: Bool { get }
    @MainActor func probeCapabilities() -> BatterySMCCapabilities
    @MainActor @discardableResult func inhibitCharging(limitPercent: Int) -> BatteryChargeWriteError?
    @MainActor @discardableResult func resumeCharging() -> BatteryChargeWriteError?
    @MainActor @discardableResult func setForceDischarge(_ on: Bool) -> BatteryChargeWriteError?
}
