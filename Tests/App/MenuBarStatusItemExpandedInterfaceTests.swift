import AppKit
import XCTest
@testable import MacTools

@MainActor
final class MenuBarStatusItemExpandedInterfaceTests: XCTestCase {
    private typealias Adapter = MenuBarStatusItemExpandedInterfaceAdapter

    func testSelectorConstantsMatchRuntimeLiterals() {
        XCTAssertEqual(Adapter.delegateSetterSelectorName, "setExpandedInterfaceDelegate:")
        XCTAssertEqual(Adapter.delegateGetterKey, "expandedInterfaceDelegate")
        XCTAssertEqual(Adapter.sessionDidBeginSelectorName, "statusItem:didBeginExpandedInterfaceSession:")
        XCTAssertEqual(Adapter.sessionDidEndSelectorName, "statusItemDidEndExpandedInterfaceSession:animated:")
        XCTAssertEqual(Adapter.sessionCancelSelectorName, "cancel")
    }

    func testAdapterRespondsToCallbackSelectors() {
        let adapter = Adapter()
        XCTAssertTrue(adapter.responds(to: NSSelectorFromString(Adapter.sessionDidBeginSelectorName)))
        XCTAssertTrue(adapter.responds(to: NSSelectorFromString(Adapter.sessionDidEndSelectorName)))
    }

    func testDidBeginCallbackForwardsSameSessionObject() {
        let adapter = Adapter()
        let item = makeDetachedStatusItem()
        let session = NSObject()
        var receivedSession: NSObject?
        adapter.onSessionBegin = { receivedSession = $0 }

        _ = adapter.perform(
            NSSelectorFromString(Adapter.sessionDidBeginSelectorName),
            with: item,
            with: session
        )

        XCTAssertTrue(receivedSession === session)
    }

    func testDidEndCallbackForwardsAnimatedFlag() {
        typealias DidEndFunction = @convention(c) (NSObject, Selector, NSStatusItem, ObjCBool) -> Void

        let adapter = Adapter()
        let item = makeDetachedStatusItem()
        var receivedAnimated: [Bool] = []
        adapter.onSessionEnd = { receivedAnimated.append($0) }

        let selector = NSSelectorFromString(Adapter.sessionDidEndSelectorName)
        let implementation = adapter.method(for: selector)
        let callback = unsafeBitCast(implementation, to: DidEndFunction.self)
        callback(adapter, selector, item, ObjCBool(true))
        callback(adapter, selector, item, ObjCBool(false))

        XCTAssertEqual(receivedAnimated, [true, false])
    }

    func testCancelInvokesCancelWhenSessionResponds() {
        let session = RecordingCancellableSession()
        Adapter.cancel(session: session)
        XCTAssertEqual(session.cancelCount, 1)
    }

    func testCancelOnNonRespondingSessionDoesNotCrash() {
        Adapter.cancel(session: NSObject())
    }

    func testIsSupportedMatchesSetterSelectorProbe() {
        let item = makeDetachedStatusItem()

        XCTAssertEqual(
            Adapter.isSupported(by: item),
            item.responds(to: NSSelectorFromString(Adapter.delegateSetterSelectorName))
        )
    }

    func testAttachRollsBackDelegateOnReadBackMismatch() {
        let item = ReadBackMismatchStatusItem()
        let adapter = Adapter()

        XCTAssertFalse(adapter.attach(to: item))
        XCTAssertEqual(item.recordedDelegateWrites.count, 2)
        XCTAssertTrue(item.recordedDelegateWrites[0] === adapter)
        XCTAssertNil(item.recordedDelegateWrites[1])
    }

    func testRequestCloseWithActiveSessionClearsBeforeCancelAndSkipsDirectDismiss() {
        let coordinator = MenuBarExpandedSessionCoordinator()
        let session = NSObject()
        coordinator.sessionDidBegin(session)

        var cancelledSession: NSObject?
        coordinator.requestClose(
            cancel: { cancelled in
                XCTAssertNil(coordinator.activeSession)
                cancelledSession = cancelled
            },
            directDismiss: {
                XCTFail("active expanded-interface sessions must close through cancel")
            }
        )

        XCTAssertTrue(cancelledSession === session)
    }

    func testRequestCloseWithoutActiveSessionUsesDirectDismiss() {
        let coordinator = MenuBarExpandedSessionCoordinator()
        var directDismissCount = 0

        coordinator.requestClose(
            cancel: { _ in XCTFail("no expanded-interface session should be cancelled") },
            directDismiss: { directDismissCount += 1 }
        )

        XCTAssertEqual(directDismissCount, 1)
    }

    func testSessionDidEndDismissesOnceAndPreventsReentry() {
        let coordinator = MenuBarExpandedSessionCoordinator()
        coordinator.sessionDidBegin(NSObject())

        var dismissCount = 0
        coordinator.sessionDidEnd {
            dismissCount += 1
            XCTAssertNil(coordinator.activeSession)
            coordinator.sessionDidEnd { dismissCount += 1 }
        }

        XCTAssertEqual(dismissCount, 1)
    }

    private func makeDetachedStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        NSStatusBar.system.removeStatusItem(item)
        return item
    }
}

private final class RecordingCancellableSession: NSObject {
    private(set) var cancelCount = 0

    @objc func cancel() {
        cancelCount += 1
    }
}

private final class ReadBackMismatchStatusItem: NSStatusItem {
    private(set) var recordedDelegateWrites: [NSObject?] = []
    private let mismatchedReadBack = NSObject()

    @objc(setExpandedInterfaceDelegate:)
    func recordExpandedInterfaceDelegate(_ delegate: NSObject?) {
        recordedDelegateWrites.append(delegate)
    }

    @objc(expandedInterfaceDelegate)
    func mismatchedExpandedInterfaceDelegate() -> NSObject? {
        mismatchedReadBack
    }
}
