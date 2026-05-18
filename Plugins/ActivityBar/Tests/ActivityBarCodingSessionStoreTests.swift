import XCTest
@testable import ActivityBarPlugin

@MainActor
final class ActivityBarCodingSessionStoreTests: XCTestCase {
    func testCodingEventsTrackWordsToolsAndActiveDuration() {
        let storage = ActivityBarMemoryStorage()
        var now = activityBarTestDate(hour: 10)
        let store = ActivityBarCodingSessionStore(
            storage: storage,
            calendar: activityBarTestCalendar(),
            dateProvider: { now }
        )

        store.handleEvent(
            ActivityBarHookEvent(
                sessionID: "session-1",
                cwd: "/tmp/MacTools",
                event: .userPromptSubmit,
                status: .processing,
                userPrompt: "make the plugin work",
                tool: nil,
                interactive: true
            )
        )

        now = now.addingTimeInterval(10)
        store.handleEvent(
            ActivityBarHookEvent(
                sessionID: "session-1",
                cwd: "/tmp/MacTools",
                event: .preToolUse,
                status: .runningTool,
                userPrompt: nil,
                tool: "Read",
                interactive: true
            )
        )

        now = now.addingTimeInterval(5)
        store.handleEvent(
            ActivityBarHookEvent(
                sessionID: "session-1",
                cwd: "/tmp/MacTools",
                event: .stop,
                status: .waitingForInput,
                userPrompt: nil,
                tool: nil,
                interactive: true
            )
        )

        XCTAssertEqual(store.today.wordCount, 4)
        XCTAssertEqual(store.today.toolCallCount, 1)
        XCTAssertEqual(store.today.durationSeconds, 15, accuracy: 0.1)
        XCTAssertEqual(store.today.topProjects.first?.name, "MacTools")
        XCTAssertEqual(store.activeSessionCount, 1)
    }

    func testSessionEndRemovesActiveSession() {
        let storage = ActivityBarMemoryStorage()
        let store = ActivityBarCodingSessionStore(
            storage: storage,
            calendar: activityBarTestCalendar(),
            dateProvider: { activityBarTestDate() }
        )

        store.handleEvent(
            ActivityBarHookEvent(
                sessionID: "session-1",
                cwd: "/tmp/MacTools",
                event: .sessionStart,
                status: .waitingForInput,
                userPrompt: nil,
                tool: nil,
                interactive: true
            )
        )
        store.handleEvent(
            ActivityBarHookEvent(
                sessionID: "session-1",
                cwd: "/tmp/MacTools",
                event: .sessionEnd,
                status: .ended,
                userPrompt: nil,
                tool: nil,
                interactive: true
            )
        )

        XCTAssertEqual(store.activeSessionCount, 0)
    }

    func testCodingEventsAggregateByTool() {
        let storage = ActivityBarMemoryStorage()
        var now = activityBarTestDate(hour: 10)
        let store = ActivityBarCodingSessionStore(
            storage: storage,
            calendar: activityBarTestCalendar(),
            dateProvider: { now }
        )

        store.handleEvent(
            ActivityBarHookEvent(
                sessionID: "cursor-session-1",
                cwd: "/tmp/MacTools",
                event: .userPromptSubmit,
                status: .processing,
                userPrompt: "update the ui",
                tool: nil,
                interactive: true
            )
        )

        now = now.addingTimeInterval(8)
        store.handleEvent(
            ActivityBarHookEvent(
                sessionID: "cursor-session-1",
                cwd: "/tmp/MacTools",
                event: .preToolUse,
                status: .runningTool,
                userPrompt: nil,
                tool: "Read",
                interactive: true
            )
        )

        let cursorStats = try XCTUnwrap(store.today.perTool["Cursor"])
        XCTAssertEqual(cursorStats.wordCount, 3)
        XCTAssertEqual(cursorStats.toolCallCount, 1)
        XCTAssertEqual(cursorStats.durationSeconds, 8, accuracy: 0.1)
        XCTAssertEqual(store.today.topTools.first?.name, "Cursor")
    }
}
