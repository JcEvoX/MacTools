import Foundation

enum ActivityBarConstants {
    static let pluginID = "activity-bar"
    static let defaultSocketPath = "/tmp/mactools-activity-bar.sock"
}

enum ActivityBarInputEvent: Equatable, Sendable {
    case keystroke(app: String)
    case pointerClick(app: String)
    case scroll(app: String)
    case screenTime(app: String, seconds: TimeInterval)
}

enum ActivityBarInputMonitorStatus: Equatable, Sendable {
    case idle
    case running
    case inputMonitoringDenied
}

struct ActivityBarAppStats: Codable, Equatable, Sendable {
    var keystrokes: Int = 0
    var pointerClicks: Int = 0
    var scrollEvents: Int = 0
    var screenTimeSeconds: TimeInterval = 0

    var totalInputs: Int {
        keystrokes + pointerClicks + scrollEvents
    }
}

struct ActivityBarDailyStats: Codable, Identifiable, Equatable, Sendable {
    let date: String
    var keystrokes: Int = 0
    var pointerClicks: Int = 0
    var scrollEvents: Int = 0
    var screenTimeSeconds: TimeInterval = 0
    var perApp: [String: ActivityBarAppStats] = [:]

    var id: String { date }

    var totalInputs: Int {
        keystrokes + pointerClicks + scrollEvents
    }

    var topApps: [(name: String, stats: ActivityBarAppStats)] {
        perApp
            .filter { !$0.key.isEmpty && $0.key != "loginwindow" }
            .map { (name: $0.key, stats: $0.value) }
            .sorted {
                if $0.stats.screenTimeSeconds == $1.stats.screenTimeSeconds {
                    return $0.stats.totalInputs > $1.stats.totalInputs
                }
                return $0.stats.screenTimeSeconds > $1.stats.screenTimeSeconds
            }
    }
}

enum ActivityBarHookEventType: String, Codable, Equatable, Sendable {
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case stop = "Stop"
    case subagentStop = "SubagentStop"
    case preCompact = "PreCompact"
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case permissionRequest = "PermissionRequest"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ActivityBarHookEventType(rawValue: rawValue) ?? .unknown
    }
}

enum ActivityBarHookStatus: String, Codable, Equatable, Sendable {
    case processing
    case compacting
    case waitingForInput = "waiting_for_input"
    case ended
    case runningTool = "running_tool"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ActivityBarHookStatus(rawValue: rawValue) ?? .unknown
    }
}

struct ActivityBarHookEvent: Codable, Equatable, Sendable {
    let sessionID: String
    let cwd: String?
    let event: ActivityBarHookEventType
    let status: ActivityBarHookStatus
    let userPrompt: String?
    let tool: String?
    let interactive: Bool?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case cwd
        case event
        case status
        case userPrompt = "user_prompt"
        case tool
        case interactive
    }
}

struct ActivityBarProjectStats: Codable, Equatable, Sendable {
    var durationSeconds: TimeInterval = 0
    var wordCount: Int = 0
    var toolCallCount: Int = 0
}

struct ActivityBarCodingDailyStats: Codable, Identifiable, Equatable, Sendable {
    let date: String
    var durationSeconds: TimeInterval = 0
    var wordCount: Int = 0
    var toolCallCount: Int = 0
    var perProject: [String: ActivityBarProjectStats] = [:]

    var id: String { date }

    var topProjects: [(name: String, stats: ActivityBarProjectStats)] {
        perProject
            .map { (name: $0.key, stats: $0.value) }
            .sorted {
                if $0.stats.durationSeconds == $1.stats.durationSeconds {
                    return $0.stats.wordCount > $1.stats.wordCount
                }
                return $0.stats.durationSeconds > $1.stats.durationSeconds
            }
    }
}

enum ActivityBarFormatting {
    static func count(_ value: Int) -> String {
        if value >= 10_000 {
            return "\(value / 1_000)k"
        }
        return "\(value)"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }
}
