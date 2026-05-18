import Foundation
import MacToolsPluginKit

@MainActor
final class ActivityBarStatsStore: ObservableObject {
    private enum StorageKey {
        static let days = "activity-bar.input.days.v1"
    }

    @Published private(set) var days: [String: ActivityBarDailyStats]

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

    var today: ActivityBarDailyStats {
        days[dateKey(for: dateProvider())] ?? ActivityBarDailyStats(date: dateKey(for: dateProvider()))
    }

    func incrementKeystroke(app: String) {
        mutateToday(app: app) { day, appStats in
            day.keystrokes += 1
            appStats.keystrokes += 1
        }
    }

    func incrementPointerClick(app: String) {
        mutateToday(app: app) { day, appStats in
            day.pointerClicks += 1
            appStats.pointerClicks += 1
        }
    }

    func incrementScroll(app: String) {
        mutateToday(app: app) { day, appStats in
            day.scrollEvents += 1
            appStats.scrollEvents += 1
        }
    }

    func addScreenTime(_ seconds: TimeInterval, app: String) {
        guard seconds > 0 else {
            return
        }

        mutateToday(app: app) { day, appStats in
            day.screenTimeSeconds += seconds
            appStats.screenTimeSeconds += seconds
        }
    }

    func record(_ event: ActivityBarInputEvent) {
        switch event {
        case let .keystroke(app):
            incrementKeystroke(app: app)
        case let .pointerClick(app):
            incrementPointerClick(app: app)
        case let .scroll(app):
            incrementScroll(app: app)
        case let .screenTime(app, seconds):
            addScreenTime(seconds, app: app)
        }
    }

    func resetToday() {
        days[dateKey(for: dateProvider())] = ActivityBarDailyStats(date: dateKey(for: dateProvider()))
        persist()
    }

    private func mutateToday(
        app rawApp: String,
        update: (inout ActivityBarDailyStats, inout ActivityBarAppStats) -> Void
    ) {
        let app = sanitizedAppName(rawApp)
        let key = dateKey(for: dateProvider())
        var day = days[key] ?? ActivityBarDailyStats(date: key)
        var appStats = day.perApp[app] ?? ActivityBarAppStats()

        update(&day, &appStats)

        day.perApp[app] = appStats
        days[key] = day
        persist()
    }

    private func sanitizedAppName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
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
            ActivityBarLog.input.error("Failed to persist input stats: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func loadDays(storage: PluginStorage, decoder: JSONDecoder) -> [String: ActivityBarDailyStats] {
        guard let data = storage.data(forKey: StorageKey.days) else {
            return [:]
        }

        do {
            return try decoder.decode([String: ActivityBarDailyStats].self, from: data)
        } catch {
            ActivityBarLog.input.error("Failed to load input stats: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }
}
