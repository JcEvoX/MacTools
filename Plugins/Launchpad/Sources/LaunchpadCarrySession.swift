import AppKit

/// Identity + state machine of ONE cross-page carry (design §1). Owned exclusively by
/// `LaunchpadDragCoordinator`; "session ended" is expressed as `coordinator.carrySession = nil`
/// (no `.ended` enum case — every entry point guards on `session != nil`, so a torn-down session
/// can never be re-driven by a stale reference).
@MainActor
final class LaunchpadCarrySession {
    enum Origin: Equatable {
        case rootPage                        // root-page lift (lands in step 7)
        case folder(sourceFolderID: String)  // in-folder drag that crossed the panel boundary (eject)
    }

    enum Mode: Equatable {
        case tracking                            // feed classification + the edge turner
        case awaitingHandoff(targetPage: Int)    // flip published; classification suspended (step 4 wires this)
    }

    enum State: Equatable {
        case carrying(Mode)                  // floating icon follows the cursor, mouse still down
        case settling(generation: Int)       // mouseUp done, data committed; flight is pure visual (step 8)
    }

    let itemID: String
    let origin: Origin
    /// Whether the carried item is an app (merge-eligible) — a carried folder never arms a merge.
    let isApp: Bool
    /// Editability frozen at lift. The storeApplier gates on THIS, not live `isLayoutEditable`:
    /// a live check would silently drop a commit that lands inside the settle/teardown window
    /// after typing flattened the layout to search (design §1.3 / BR-2).
    let editableAtBegin: Bool
    /// Visible root order frozen when the drag began, carried by the session so the commit
    /// resolves against exactly what the user saw — not a list a mid-carry catalog reload may
    /// have changed (constraint 15 / AR-11).
    let frozenVisibleOrder: [LaunchpadDisplayCell]
    let presenter: LaunchpadFloatingIconPresenting

    private(set) var state: State = .carrying(.tracking)
    var lastScreenPoint: NSPoint?
    var lastWindowPoint: NSPoint?

    /// Edge-hover dwell/cooldown state machine (pure; the coordinator feeds it the same
    /// page-local point classification uses, from both mouse moves and the 30Hz tick).
    var turner = LaunchpadEdgePageTurner()
    /// The stationary-cursor tick driver; owned here so it dies with the session.
    var dwellTimer: Timer?

    var isCarrying: Bool {
        if case .carrying = state { return true }
        return false
    }

    init(
        itemID: String,
        origin: Origin,
        isApp: Bool,
        editableAtBegin: Bool,
        frozenVisibleOrder: [LaunchpadDisplayCell],
        presenter: LaunchpadFloatingIconPresenting
    ) {
        self.itemID = itemID
        self.origin = origin
        self.isApp = isApp
        self.editableAtBegin = editableAtBegin
        self.frozenVisibleOrder = frozenVisibleOrder
        self.presenter = presenter
    }

    /// Flip published → classification suspended until the target page's container takes over.
    /// Defined for step 4 (handoff); nothing enters this mode yet.
    func awaitHandoff(targetPage: Int) {
        state = .carrying(.awaitingHandoff(targetPage: targetPage))
    }

    /// Handoff complete (`containerRegistered` / the currentPage funnel) → back to tracking.
    func resumeTracking() {
        state = .carrying(.tracking)
    }

    /// mouseUp received and data committed; the floating icon is now pure visual flight.
    /// Defined for step 8 (flight settle); the hard-cut commit never enters it.
    func beginSettling(generation: Int) {
        state = .settling(generation: generation)
    }
}
