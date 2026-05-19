import Foundation
import MacToolsPluginKit

@MainActor
final class ActivityBarCodingSessionStore: ObservableObject {
    private enum StorageKey {
        static let days = "activity-bar.coding.days.v1"
    }

    private struct ActiveSession: Equatable {
        var project: String
        var tool: String
        var status: ActivityBarHookStatus
        var startedAt: Date
        var lastUpdatedAt: Date
    }

    @Published private(set) var days: [String: ActivityBarCodingDailyStats]
    @Published private(set) var activeSessionCount = 0

    private var activeSessions: [String: ActiveSession] = [:]
    private let storage: PluginStorage
    private let calendar: Calendar
    private let dateProvider: () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        storage: PluginStorage,
        calendar: Calendar = .current,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.storage = storage
        self.calendar = calendar
        self.dateProvider = dateProvider
        self.days = Self.loadDays(storage: storage, decoder: decoder)
    }

    var today: ActivityBarCodingDailyStats {
        days[dateKey(for: dateProvider())] ?? ActivityBarCodingDailyStats(date: dateKey(for: dateProvider()))
    }

    var sortedDateKeys: [String] {
        days.keys.sorted()
    }

    func stats(for date: String) -> ActivityBarCodingDailyStats {
        days[date] ?? ActivityBarCodingDailyStats(date: date)
    }

    func recentDays(count: Int, endingAt endDate: Date? = nil) -> [ActivityBarCodingDailyStats] {
        let end = endDate ?? dateProvider()
        let boundedCount = max(count, 1)

        return (0..<boundedCount).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: end) ?? end
            let key = dateKey(for: date)
            return stats(for: key)
        }
    }

    func handleEvent(_ event: ActivityBarHookEvent) {
        let now = dateProvider()
        let project = projectName(from: event.cwd)
        let sessionID = event.sessionID.isEmpty ? "unknown" : event.sessionID
        let tool = ActivityBarCodingTool.displayName(forSessionID: sessionID)

        closeElapsedTime(for: sessionID, now: now)

        if let prompt = event.userPrompt, event.event == .userPromptSubmit {
            addWords(countWords(prompt), project: project, tool: tool)
        }

        if event.event == .preToolUse {
            addToolCall(project: project, tool: tool)
        }

        switch event.event {
        case .sessionEnd:
            activeSessions.removeValue(forKey: sessionID)
        default:
            activeSessions[sessionID] = ActiveSession(
                project: project,
                tool: tool,
                status: event.status,
                startedAt: activeSessions[sessionID]?.startedAt ?? now,
                lastUpdatedAt: now
            )
        }

        activeSessionCount = activeSessions.count
        persist()
    }

    func flushActiveDurations() {
        let now = dateProvider()
        for sessionID in activeSessions.keys {
            closeElapsedTime(for: sessionID, now: now)
            activeSessions[sessionID]?.lastUpdatedAt = now
        }
        persist()
    }

    func resetToday() {
        days[dateKey(for: dateProvider())] = ActivityBarCodingDailyStats(date: dateKey(for: dateProvider()))
        persist()
    }

    private func closeElapsedTime(for sessionID: String, now: Date) {
        guard var session = activeSessions[sessionID] else {
            return
        }

        let elapsed = now.timeIntervalSince(session.lastUpdatedAt)
        if elapsed > 0.5, session.status != .waitingForInput, session.status != .ended {
            addDuration(elapsed, project: session.project, tool: session.tool)
        }

        session.lastUpdatedAt = now
        activeSessions[sessionID] = session
    }

    private func addWords(_ count: Int, project: String, tool: String) {
        guard count > 0 else {
            return
        }

        mutateToday(project: project, tool: tool) { day, projectStats, toolStats in
            day.wordCount += count
            projectStats.wordCount += count
            toolStats.wordCount += count
        }
    }

    private func addToolCall(project: String, tool: String) {
        mutateToday(project: project, tool: tool) { day, projectStats, toolStats in
            day.toolCallCount += 1
            projectStats.toolCallCount += 1
            toolStats.toolCallCount += 1
        }
    }

    private func addDuration(_ seconds: TimeInterval, project: String, tool: String) {
        mutateToday(project: project, tool: tool) { day, projectStats, toolStats in
            day.durationSeconds += seconds
            projectStats.durationSeconds += seconds
            toolStats.durationSeconds += seconds
        }
    }

    private func mutateToday(
        project rawProject: String,
        tool rawTool: String,
        update: (inout ActivityBarCodingDailyStats, inout ActivityBarProjectStats, inout ActivityBarProjectStats) -> Void
    ) {
        let project = rawProject.isEmpty ? "Unknown" : rawProject
        let tool = rawTool.isEmpty ? ActivityBarCodingTool.claudeCode.rawValue : rawTool
        let key = dateKey(for: dateProvider())
        var day = days[key] ?? ActivityBarCodingDailyStats(date: key)
        var projectStats = day.perProject[project] ?? ActivityBarProjectStats()
        var toolStats = day.perTool[tool] ?? ActivityBarProjectStats()

        update(&day, &projectStats, &toolStats)

        day.perProject[project] = projectStats
        day.perTool[tool] = toolStats
        days[key] = day
    }

    private func countWords(_ prompt: String) -> Int {
        prompt
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    private func projectName(from cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else {
            return "Unknown"
        }

        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    private func dateKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func persist() {
        do {
            let data = try encoder.encode(days)
            storage.set(data, forKey: StorageKey.days)
        } catch {
            ActivityBarLog.hooks.error("Failed to persist coding stats: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func loadDays(storage: PluginStorage, decoder: JSONDecoder) -> [String: ActivityBarCodingDailyStats] {
        guard let data = storage.data(forKey: StorageKey.days) else {
            return [:]
        }

        do {
            return try decoder.decode([String: ActivityBarCodingDailyStats].self, from: data)
        } catch {
            ActivityBarLog.hooks.error("Failed to load coding stats: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }
}
