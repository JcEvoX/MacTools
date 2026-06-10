import Foundation

/// Pure state machine deciding when a drag hovering at the left/right edge of the
/// grid should flip to the neighbouring page (iOS-style dwell + repeat cadence).
///
/// Time and geometry are injected through `update` so tests drive it with plain
/// number sequences; the caller owns the clock (mouse moves plus an
/// `.eventTracking` timer while the cursor is stationary) and feeds the same
/// page-local point used for drop classification.
///
/// Dwell semantics around the page-snap animation are encoded in time, not in an
/// extra suspended state: after a fire the cooldown window (and, after leaving
/// the zone, the full dwell) is at least `LaunchpadPageAnimation.snapVisualSettle`,
/// so a follow-up flip can never land before the previous snap visually settles.
/// `LaunchpadEdgePageTurnerTests` asserts that invariant against the shared
/// animation constants.
struct LaunchpadEdgePageTurner {
    struct Config {
        var dwell: TimeInterval = 0.7
        var repeatCooldown: TimeInterval = 0.8
        var edgeWidth: CGFloat = 44
    }

    enum Zone: Equatable {
        case left
        case right

        var direction: Int { self == .left ? -1 : 1 }
    }

    enum Decision: Equatable {
        case none
        case flip(direction: Int)
    }

    enum State: Equatable {
        case idle
        case arming(zone: Zone, since: TimeInterval)
        case cooldown(zone: Zone, readyAt: TimeInterval)
    }

    let config: Config
    private(set) var state: State = .idle

    init(config: Config = Config()) {
        self.config = config
    }

    /// `point` is in page-local coordinates; values outside `[0, pageWidth]` are
    /// deliberately classified into the nearer zone — the cursor sitting in the
    /// strip padding or past the screen edge must still count as edge hovering.
    mutating func update(point: CGPoint, pageWidth: CGFloat, now: TimeInterval) -> Decision {
        guard let zone = zone(forX: point.x, pageWidth: pageWidth) else {
            state = .idle
            return .none
        }

        switch state {
        case .idle:
            state = .arming(zone: zone, since: now)
            return .none

        case .arming(let armed, let since):
            guard armed == zone else {
                state = .arming(zone: zone, since: now)   // switching sides restarts the dwell
                return .none
            }
            guard now - since >= config.dwell else { return .none }
            state = .cooldown(zone: zone, readyAt: now + config.repeatCooldown)
            return .flip(direction: zone.direction)

        case .cooldown(let armed, let readyAt):
            guard armed == zone else {
                state = .arming(zone: zone, since: now)
                return .none
            }
            guard now >= readyAt else { return .none }
            state = .cooldown(zone: zone, readyAt: now + config.repeatCooldown)
            return .flip(direction: zone.direction)      // dwell-and-repeat: steady cadence after the first fire
        }
    }

    mutating func reset() {
        state = .idle
    }

    private func zone(forX x: CGFloat, pageWidth: CGFloat) -> Zone? {
        if x < config.edgeWidth { return .left }
        if x > pageWidth - config.edgeWidth { return .right }
        return nil
    }
}
