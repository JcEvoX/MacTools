import AppKit
import Combine
import OSLog

// MARK: - Floating icon presentation (injectable — tests swap in a spy, design §10-①)

/// The cursor-following floating icon a carry rides in. It lives in its OWN borderless window,
/// NOT in the SwiftUI `NSHostingView` (which froze when mutated mid-drag).
@MainActor
protocol LaunchpadFloatingIconPresenting: AnyObject {
    var isPresenting: Bool { get }
    func present(icon: NSImage?, side: CGFloat, atScreenPoint p: NSPoint, aboveLevel: NSWindow.Level)
    func move(toScreenPoint p: NSPoint)
    /// Fly to the resolved slot, then call `completion`. Hard-cut until step 8: lands instantly.
    func settle(to screenRect: NSRect, completion: @escaping @MainActor () -> Void)
    func dismiss()
}

/// Production presenter: a borderless, mouse-transparent NSWindow one level above the overlay.
@MainActor
final class LaunchpadFloatingIconWindowPresenter: LaunchpadFloatingIconPresenting {
    private var window: NSWindow?
    private var side: CGFloat = 0

    var isPresenting: Bool { window != nil }

    func present(icon: NSImage?, side: CGFloat, atScreenPoint p: NSPoint, aboveLevel: NSWindow.Level) {
        dismiss()
        self.side = side
        let frame = NSRect(x: 0, y: 0, width: side, height: side)
        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.level = NSWindow.Level(rawValue: aboveLevel.rawValue + 1)
        let iconView = NSImageView(frame: frame)
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        win.contentView = iconView
        window = win
        move(toScreenPoint: p)
        win.orderFront(nil)
    }

    func move(toScreenPoint p: NSPoint) {
        window?.setFrameOrigin(NSPoint(x: p.x - side / 2, y: p.y - side / 2))
    }

    func settle(to screenRect: NSRect, completion: @escaping @MainActor () -> Void) {
        window?.setFrame(screenRect, display: false)
        dismiss()
        completion()
    }

    func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}

// MARK: - Commit routing (pure data, design §1.3)

/// An edge-dwell page flip, as data (design §4.4). The token makes consecutive flips to the same
/// page distinct `onChange` values.
struct LaunchpadFlipRequest: Equatable {
    let token: Int
    let targetPage: Int
}

/// A release, as data: what was carried, where it came from, what the container resolved.
struct LaunchpadCarryCommit {
    let itemID: String
    let origin: LaunchpadCarrySession.Origin
    let result: LaunchpadExternalDropResult
}

/// The store mutation a commit maps to. Applied by the injected `storeApplier` — the data path
/// never travels through a SwiftUI `@Published` token, so a torn-down view can't lose it.
enum CarryStoreAction: Equatable {
    case move(id: String, target: LaunchpadDropTarget?)   // nil target = global tail
    case makeFolder(targetAppID: String, draggedID: String)
    case addToFolder(folderID: String, appID: String)
    case moveOutOfFolder(folderID: String, appID: String, result: LaunchpadExternalDropResult)
    case none                                              // no-op: skip the write; visuals settle as usual
}

/// Coordinates carry sessions (an item dragged OUTSIDE any container — ejected from a folder
/// today, lifted from the root page in step 7) across the separate per-page AppKit grids.
///
/// Flow: while dragging an app inside the open folder, the moment it leaves the folder the folder
/// ZOOMS CLOSED (mid-drag) and a floating icon — hosted in its OWN borderless window — follows the
/// cursor over the launcher. On release the data lands SYNCHRONOUSLY in mouseUp through the
/// injected `storeApplier`; the `@Published commitToken` is a pure VISUAL channel (close the
/// folder, re-select, drop the frozen snapshot) that is harmless to lose if the overlay tears
/// down before SwiftUI consumes it (design §1.3 — the fix for the resign-active commit race).
///
/// It is an `ObservableObject` because the mid-drag folder close must still be requested from an
/// AppKit mouse handler, where mutating the host view's `@State` directly does NOT invalidate the
/// view; `@Published` routes it through SwiftUI `.onChange` in a tracked transaction.
@MainActor
final class LaunchpadDragCoordinator: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools",
        category: "LaunchpadCarry"
    )

    enum CarryCancelReason {
        case overlayClosed, anchorUnmounted, searchActivated, geometryChanged, shutdown
    }

    enum CarryEndReason { case committed, cancelled }

    /// What the visual channel needs after a commit. The store mutation already happened.
    struct VisualCommit {
        let itemID: String
        let origin: LaunchpadCarrySession.Origin
        let result: LaunchpadExternalDropResult
        /// Where the selection should follow (the moved app / the new or destination folder);
        /// nil when nothing was written.
        let landingID: String?
    }

    /// True from lift until release/cancel, for ANY carry origin.
    @Published private(set) var carryActive = false
    /// True only while a FOLDER-origin carry is live — drives the mid-drag folder close and the
    /// source folder's thumbnail filter in the host view.
    @Published private(set) var folderEjectActive = false
    /// Bumped on release — VISUAL channel only (close folder / relocate selection / clear the
    /// frozen snapshot). The data was already applied synchronously via `storeApplier`.
    @Published private(set) var commitToken = 0
    private(set) var pendingVisualCommit: VisualCommit?

    /// Edge-dwell page-flip request (design §4.4). Published from the dwell state machine — never
    /// from inside a mouse handler's withAnimation — and consumed by the grid's `.onChange`, which
    /// calls `goToPage` in a tracked transaction. Withdrawn (nil) on release/cancel so a flip
    /// can't land after the carry is gone (AR-5).
    @Published private(set) var flipRequest: LaunchpadFlipRequest?
    private var flipToken = 0

    private(set) var carrySession: LaunchpadCarrySession?
    private(set) var endReason: CarryEndReason?

    /// Synchronous mouseUp data path, injected by the overlay controller (it owns both the
    /// coordinator and the layout store). Returns the landing id for the visual channel.
    var storeApplier: (@MainActor (CarryStoreAction, [LaunchpadDisplayCell]) -> String?)?
    /// Test seam: swap the floating-icon window for a spy (design §10-①).
    var floatingPresenterFactory: @MainActor () -> LaunchpadFloatingIconPresenting =
        { LaunchpadFloatingIconWindowPresenter() }

    /// Injectable clock shared by the dwell state machine (design §10-②).
    var now: @MainActor () -> TimeInterval = { CACurrentMediaTime() }

    /// Test seam for the stationary-cursor tick: production schedules a 30Hz timer on BOTH the
    /// `.eventTracking` (live drag loop) and `.common` run-loop modes (constraint 3 — a default-
    /// mode timer starves during direct drags); tests return nil and pump `tickDwell()` manually.
    var dwellTimerFactory: @MainActor (@escaping @MainActor () -> Void) -> Timer? = { tick in
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { _ in
            MainActor.assumeIsolated(tick)
        }
        RunLoop.main.add(timer, forMode: .eventTracking)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    var isDwellTimerRunning: Bool { carrySession?.dwellTimer != nil }

    /// Visible-order snapshot + editability staged by the host view when a drag begins
    /// (`onDragBegan` fires before any carry can start); adopted by the next session at lift.
    private var pendingFrozenOrder: [LaunchpadDisplayCell] = []
    private var pendingEditable = true
    /// Set when a live carry is cancelled, cleared when the next gesture begins
    /// (`freezeVisibleOrder`). A cancelled gesture's orphan events must STAY orphaned
    /// (design §1.2): without this latch the grid's late-eject fallback (`commitOut` with no
    /// session) could re-open a session from the same mouse gesture — with stale staged
    /// editability — and commit the very drop the cancel aborted.
    private var carryCancelledThisGesture = false

    private struct WeakContainer { weak var value: LaunchpadGridContainerView? }

    /// Every root page container, keyed by page index. The SwiftUI paging `.offset` never enters
    /// the AppKit frame chain, so cross-page work cannot lean on `convert` against these views —
    /// the registry plus the pushed `geometry` snapshot replace it (design §3/§5).
    private var pages: [Int: WeakContainer] = [:]
    /// Mirrors the SwiftUI `currentPage` @State via the single `.onChange` funnel.
    private(set) var currentPage = 0
    /// Viewport/page geometry pushed from the grid (AppKit window space, Equatable-deduped).
    private(set) var geometry = LaunchpadPageGeometry()

    /// The container an external drag should classify against — the visible page's grid.
    private var activeContainer: LaunchpadGridContainerView? { pages[currentPage]?.value }

    /// The container a live carry is ENGAGED with (begin/end pairing). Distinct from
    /// `activeContainer`: the engaged one keeps its make-way gap until a handoff explicitly ends
    /// it, so a mid-carry page flip can never leave a stale gap behind (design §3, gap1).
    private(set) weak var currentTargetContainer: LaunchpadGridContainerView?
    private(set) var currentTargetPage = 0

    /// Window-point → page-local arithmetic from the pushed geometry; nil until the first push.
    private var carrySpace: LaunchpadCarrySpace? {
        guard geometry.pageWidth > 0 else { return nil }
        return LaunchpadCarrySpace(viewportMinX: geometry.viewportMinX,
                                   viewportTopY: geometry.viewportTopY,
                                   pageWidth: geometry.pageWidth)
    }

    /// Every page container registers itself (not just the visible one) so the page flipped to
    /// during a carry is already reachable. Pure dictionary write — safe before any cells exist,
    /// and deliberately called ABOVE the container's deferred-apply guard (design §3.1).
    func registerPageContainer(_ container: LaunchpadGridContainerView, page: Int) {
        pages[page] = WeakContainer(value: container)
        reattachIfNeeded(container, page: page)
    }

    /// Containers unregister when leaving the window (page-count shrink, overlay teardown).
    func unregisterPageContainer(_ container: LaunchpadGridContainerView) {
        for (page, boxed) in pages where boxed.value === container || boxed.value == nil {
            pages.removeValue(forKey: page)
        }
        if container === currentTargetContainer { currentTargetContainer = nil }
    }

    /// Single funnel for page changes (every flip path goes through the `currentPage` @State).
    /// During a carry this is the HANDOFF point: the old page's gap animates closed, the new
    /// page's container takes over and is immediately fed the last cursor point so its make-way
    /// opens without waiting for the next mouse event (design §3.2).
    func currentPageDidChange(_ page: Int) {
        currentPage = page
        scheduleGeometryProbe()
        guard let session = carrySession, session.isCarrying, page != currentTargetPage else { return }
        engage(pages[page]?.value, page: page, session: session)
    }

    /// Fallback handoff keyed on container IDENTITY, not page number — covers a target page whose
    /// container mounts late (virtual tail page) or is swapped for a new instance after a
    /// page-count clamp (design §3.3). Shares the begin/end primitive with the funnel; both ends
    /// are idempotent.
    private func reattachIfNeeded(_ container: LaunchpadGridContainerView, page: Int) {
        guard let session = carrySession, session.isCarrying,
              page == currentTargetPage, container !== currentTargetContainer else { return }
        engage(container, page: page, session: session)
    }

    /// The single begin/end pairing point: at any moment at most ONE container is external-drag
    /// active. Ends the old engagement (gap closes), engages the new container, and replays the
    /// last cursor point so the new page starts making way immediately.
    private func engage(_ container: LaunchpadGridContainerView?, page: Int,
                        session: LaunchpadCarrySession) {
        currentTargetContainer?.endExternalDrag()
        currentTargetPage = page
        currentTargetContainer = container
        container?.beginExternalDrag(appID: session.itemID)
        session.resumeTracking()
        feedLastPoint(session)
    }

    /// A late-mounting target container registers BEFORE its first cells exist (registration sits
    /// above the apply body), so the reattach replay lands on an empty grid and is dropped. The
    /// container calls this after (re)building cells so the engaged page still opens its make-way
    /// without waiting for the next mouse event.
    func containerDidApplyCells(_ container: LaunchpadGridContainerView) {
        guard container === currentTargetContainer,
              let session = carrySession, session.isCarrying else { return }
        feedLastPoint(session)
    }

    /// Replay the carry's last known cursor point into the engaged container's classification.
    private func feedLastPoint(_ session: LaunchpadCarrySession) {
        guard let window = session.lastWindowPoint else { return }
        if let space = carrySpace {
            currentTargetContainer?.updateExternalDrag(atContainerPoint: space.local(fromWindow: window))
        } else {
            currentTargetContainer?.updateExternalDrag(atWindowPoint: window)
        }
    }

    /// Equatable-deduped push from the grid's viewport relay (AppKit window space).
    func syncGeometry(_ new: LaunchpadPageGeometry) {
        guard new != geometry else { return }
        geometry = new
        scheduleGeometryProbe()
    }

    // Test-facing read-only surface (design §10-④).
    var hasFloatingWindow: Bool { carrySession?.presenter.isPresenting ?? false }
    var registeredPageIndices: [Int] { pages.filter { $0.value.value != nil }.keys.sorted() }

    // MARK: - Carry session lifecycle (design §1)

    /// Freeze the visible root order (+ editability) for the NEXT carry. Called from the host
    /// view's `onDragBegan` — the only point with access to `filtered`/`isLayoutEditable` — so
    /// the session can adopt both at lift without the coordinator reaching into the view.
    func freezeVisibleOrder(_ order: [LaunchpadDisplayCell], editable: Bool = true) {
        pendingFrozenOrder = order
        pendingEditable = editable
        carryCancelledThisGesture = false      // a new gesture starts with a clean slate
    }

    /// Begin a carry: raise the floating icon at the cursor and start make-way/merge on the
    /// visible page. Safe to call from a mouse handler — the floating window is pure AppKit, and
    /// the `@Published` flips schedule the SwiftUI folder close asynchronously.
    @discardableResult
    func beginCarry(itemID: String, origin: LaunchpadCarrySession.Origin, isApp: Bool,
                    icon: NSImage?, iconSide: CGFloat,
                    atScreenPoint p: NSPoint, aboveLevel: NSWindow.Level) -> Bool {
        guard carrySession == nil, !carryCancelledThisGesture else { return false }
        let session = LaunchpadCarrySession(
            itemID: itemID,
            origin: origin,
            isApp: isApp,
            editableAtBegin: pendingEditable,
            frozenVisibleOrder: pendingFrozenOrder,
            presenter: floatingPresenterFactory()
        )
        pendingFrozenOrder = []
        pendingEditable = true
        session.presenter.present(icon: icon, side: iconSide * 1.1, atScreenPoint: p, aboveLevel: aboveLevel)
        carrySession = session
        engage(pages[currentPage]?.value, page: currentPage, session: session)  // visible page makes way / can merge
        session.dwellTimer = dwellTimerFactory { [weak self] in self?.tickDwell() }
        endReason = nil
        carryActive = true
        if case .folder = origin { folderEjectActive = true }
        return true
    }

    /// Follow the cursor: move the floating icon (screen space) AND drive the visible page's
    /// make-way / merge classification. The window point is mapped to page-local space through the
    /// pushed geometry — NOT through `convert` against the page container, whose frame chain is
    /// blind to the SwiftUI paging `.offset` (off by page×pageWidth on page > 0).
    func carryMoved(atScreenPoint screen: NSPoint, atWindowPoint window: NSPoint) {
        guard let session = carrySession, session.isCarrying else { return }
        session.lastScreenPoint = screen
        session.lastWindowPoint = window
        session.presenter.move(toScreenPoint: screen)
        guard let space = carrySpace else {                      // geometry not pushed yet (cold start)
            if case .carrying(.tracking) = session.state {
                currentTargetContainer?.updateExternalDrag(atWindowPoint: window)
            }
            return
        }
        let local = space.local(fromWindow: window)
        driveTurner(session, local: local, space: space)         // fed in BOTH carrying modes (§4.2)
        // While a flip is in flight (.awaitingHandoff) only the floating icon follows — the old
        // page slides out clean, classification resumes when the target container takes over.
        guard case .carrying(.tracking) = session.state else { return }
        crossCheckGeometry(space: space)
        currentTargetContainer?.updateExternalDrag(atContainerPoint: local)
    }

    /// Stationary-cursor drive: mouseDragged stops arriving when the cursor holds still, so the
    /// 30Hz tick replays the last point into the dwell machine (never into classification — a
    /// stationary cursor can't change the gap). O(1), no IO (constraint 22).
    func tickDwell() {
        guard let session = carrySession, session.isCarrying,
              let window = session.lastWindowPoint, let space = carrySpace else { return }
        driveTurner(session, local: space.local(fromWindow: window), space: space)
    }

    private func driveTurner(_ session: LaunchpadCarrySession, local: NSPoint, space: LaunchpadCarrySpace) {
        let decision = session.turner.update(point: local, pageWidth: space.pageWidth, now: now())
        guard case .flip(let direction) = decision else { return }
        let target = currentTargetPage + direction
        // Clamp to real pages until step 6 adds the virtual tail index (BT-7). An out-of-range
        // flip is simply dropped — the turner is already in cooldown and will retry on cadence.
        guard target >= 0, target < geometry.pageCount else { return }
        session.awaitHandoff(targetPage: target)
        flipToken += 1
        flipRequest = LaunchpadFlipRequest(token: flipToken, targetPage: target)
    }

    /// mouseUp: resolve the drop, land the DATA synchronously through `storeApplier`, tear the
    /// floating icon down, then bump the visual token (design §1.4, hard-cut subset — the
    /// resolve/freeze split and flight settle arrive in steps 4/8).
    func carryReleased(atWindowPoint p: NSPoint) {
        guard let session = carrySession, session.isCarrying else { return }
        withdrawDwell(session)                               // a flip must never land post-release (§1.4-4)

        // Resolve exactly as the legacy eject commit did: a `.reorder(nil)` means classification
        // never settled (the whole carry stayed in the columns' central dead-band) — re-resolve
        // from the RELEASE point so an in-grid drop never falls back to the tail.
        let releaseTarget: LaunchpadDropTarget?
        if let space = carrySpace {
            releaseTarget = currentTargetContainer?.rootDropTarget(atContainerPoint: space.local(fromWindow: p))
        } else {
            releaseTarget = currentTargetContainer?.rootDropTarget(atWindowPoint: p)
        }
        var result = currentTargetContainer?.resolveExternalDrop() ?? .reorder(releaseTarget)
        if case .reorder(nil) = result { result = .reorder(releaseTarget) }

        // DATA lands here, synchronously in mouseUp. Editability uses the value frozen at lift —
        // a live isLayoutEditable check could drop a commit landing after typing flattened the
        // layout to search (BR-2).
        let action: CarryStoreAction = session.editableAtBegin
            ? Self.resolveCarryCommit(
                LaunchpadCarryCommit(itemID: session.itemID, origin: session.origin, result: result),
                frozenOrder: session.frozenVisibleOrder)
            : .none
        var landingID: String?
        if action != .none {
            if let storeApplier {
                landingID = storeApplier(action, session.frozenVisibleOrder)
            } else {
                // Production always injects the applier in the overlay controller's init. Reaching
                // here means that wiring regressed: the commit's DATA is being dropped while the
                // visual token below still fires — the exact silent-loss class this step exists to
                // kill. Loud, not fatal: the legacy eject shims legitimately run applier-less in
                // tests (token/pendingEject assertions).
                Self.logger.fault("carry commit resolved to a store action but no storeApplier is injected — data dropped")
            }
        }

        pendingVisualCommit = VisualCommit(itemID: session.itemID, origin: session.origin,
                                           result: result, landingID: landingID)
        currentTargetContainer?.endExternalDrag()            // gap settles closed
        currentTargetContainer = nil
        session.presenter.dismiss()                          // hard-cut settle (flight is step 8)
        carrySession = nil
        endReason = .committed
        folderEjectActive = false
        carryActive = false
        commitToken += 1                                     // visual-only; data is already safe
    }

    /// Abort an in-flight carry (launcher closed / source unmounted / search activated) without
    /// moving anything. Fully synchronous — never routed through a `@Published` token, so the
    /// teardown does not depend on the view tree surviving (design §9.2). Nil-safe: a cancel with
    /// no session is ignored. `reason` gains distinct behaviour in later steps (page clamp etc.).
    func cancelCarry(_ reason: CarryCancelReason) {
        guard let session = carrySession else { return }
        carryCancelledThisGesture = true
        withdrawDwell(session)
        currentTargetContainer?.endExternalDrag()
        currentTargetContainer = nil
        session.presenter.dismiss()
        carrySession = nil
        endReason = .cancelled
        folderEjectActive = false
        carryActive = false
    }

    /// Stop the dwell tick and withdraw any unconsumed flip request — shared by every carry exit.
    private func withdrawDwell(_ session: LaunchpadCarrySession) {
        session.dwellTimer?.invalidate()
        session.dwellTimer = nil
        if flipRequest != nil { flipRequest = nil }
    }

    /// Pure mapping: container resolution + origin → store action (design §1.3). Static so unit
    /// tests drive every branch without a session or a window.
    static func resolveCarryCommit(_ commit: LaunchpadCarryCommit,
                                   frozenOrder: [LaunchpadDisplayCell]) -> CarryStoreAction {
        switch commit.origin {
        case .folder(let folderID):
            // The store's moveOutOfFolder family already handles nil-target tail drops and the
            // 2-app dissolve target redirect — pass the result through untouched.
            return .moveOutOfFolder(folderID: folderID, appID: commit.itemID, result: commit.result)
        case .rootPage:
            switch commit.result {
            case .makeFolder(let targetAppID):
                return .makeFolder(targetAppID: targetAppID, draggedID: commit.itemID)
            case .addToFolder(let folderID):
                return .addToFolder(folderID: folderID, appID: commit.itemID)
            case .reorder(let target?):
                let order = frozenOrder.map(\.layoutID)
                guard !target.isNoOp(dragged: commit.itemID, in: order) else { return .none }
                return .move(id: commit.itemID, target: target)
            case .reorder(nil):
                // Out-of-grid release = land at the global tail; already last = no-op. The tail
                // node may be a folder — `move(after: folderID)` is a valid existing operation.
                guard let last = frozenOrder.last, last.layoutID != commit.itemID else { return .none }
                return .move(id: commit.itemID, target: .after(last.layoutID))
            }
        }
    }

    // MARK: - Legacy eject API (thin shims — design §0 naming table; existing tests + the
    // container's call sites keep compiling unchanged)

    struct EjectRequest {
        let folderID: String
        let appID: String
        let result: LaunchpadExternalDropResult
    }

    var ejectActive: Bool { folderEjectActive }
    var ejectToken: Int { commitToken }

    var pendingEject: EjectRequest? {
        guard let visual = pendingVisualCommit,
              case .folder(let folderID) = visual.origin else { return nil }
        return EjectRequest(folderID: folderID, appID: visual.itemID, result: visual.result)
    }

    /// The app currently being carried out of a folder + its source — used to hide it from that
    /// folder's thumbnail during the carry (transient display only; data lands at release).
    var carriedAppID: String? {
        guard let session = carrySession, case .folder = session.origin else { return nil }
        return session.itemID
    }

    var carriedSourceFolderID: String? {
        guard let session = carrySession, case .folder(let folderID) = session.origin else { return nil }
        return folderID
    }

    func beginEject(appID: String, sourceFolderID: String, icon: NSImage?, iconSide: CGFloat,
                    atScreenPoint p: NSPoint, aboveLevel: NSWindow.Level) {
        beginCarry(itemID: appID, origin: .folder(sourceFolderID: sourceFolderID), isApp: true,
                   icon: icon, iconSide: iconSide, atScreenPoint: p, aboveLevel: aboveLevel)
    }

    func moveEject(atScreenPoint screen: NSPoint, atWindowPoint window: NSPoint) {
        carryMoved(atScreenPoint: screen, atWindowPoint: window)
    }

    func commitOut(folderID: String, appID: String, atWindowPoint p: NSPoint) {
        if carrySession == nil {
            // Late eject: the release point itself is the first clearly-outside point (no
            // updateDirectDrag classified in between, e.g. windowless tests or a single fast
            // mouse delta), so no session was begun. Open one and commit it immediately — the
            // floating icon is presented and dismissed within the same runloop turn (never drawn).
            beginCarry(itemID: appID, origin: .folder(sourceFolderID: folderID), isApp: true,
                       icon: nil, iconSide: 0, atScreenPoint: p, aboveLevel: .normal)
        }
        carryReleased(atWindowPoint: p)
    }

    func cancelEject() {
        cancelCarry(.shutdown)
    }

    // MARK: - Debug geometry probe

    #if DEBUG
    /// Lets a runtime session validate the geometry push by just opening the launcher and flipping
    /// pages (no folder-eject choreography needed). Delayed a tick so layout settles first.
    private func scheduleGeometryProbe() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, let space = self.carrySpace else { return }
            self.crossCheckGeometry(space: space)
        }
    }

    /// Cross-checks the pushed viewport against a frame-chain derivation (registered container's
    /// window origin − page×pageWidth). Frame chains ignore the paging offset, which is exactly
    /// why both derivations must agree on the viewport. Discrepancies land in a /tmp log (dev
    /// plugin OSLog isn't capturable) — runtime validation gate for design §5, retire at step 9.
    private var lastProbeAt: CFTimeInterval = 0
    private func crossCheckGeometry(space: LaunchpadCarrySpace) {
        let now = CACurrentMediaTime()
        guard now - lastProbeAt > 0.25 else { return }
        lastProbeAt = now
        guard let container = activeContainer, container.window != nil else { return }
        let origin = container.convert(NSPoint.zero, to: nil)    // container top-left in window space
        let derivedMinX = origin.x - CGFloat(currentPage) * space.pageWidth
        let dx = abs(derivedMinX - space.viewportMinX), dy = abs(origin.y - space.viewportTopY)
        let line = "page=\(currentPage) pushed=(\(space.viewportMinX),\(space.viewportTopY)) " +
                   "derived=(\(derivedMinX),\(origin.y)) d=(\(dx),\(dy))\n"
        Self.probeQueue.async {
            guard let data = line.data(using: .utf8),
                  let handle = FileHandle(forWritingAtPath: Self.probePath) ?? Self.createProbeLog() else { return }
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
    }

    private static let probeQueue = DispatchQueue(label: "launchpad.geometry-probe", qos: .utility)
    private static let probePath = "/tmp/launchpad-geometry-probe.log"
    private static func createProbeLog() -> FileHandle? {
        FileManager.default.createFile(atPath: probePath, contents: nil)
        return FileHandle(forWritingAtPath: probePath)
    }
    #else
    private func scheduleGeometryProbe() {}
    private func crossCheckGeometry(space: LaunchpadCarrySpace) {}
    #endif
}
