import AppKit
import Combine

/// Coordinates the iOS-style "drag an app OUT of a folder" gesture across the separate AppKit grids.
///
/// Flow: while dragging an app inside the open folder, the moment it leaves the folder the folder
/// ZOOMS CLOSED (mid-drag) and a floating icon — hosted in its OWN borderless child window, NOT in
/// the SwiftUI `NSHostingView` (which froze when mutated mid-drag) — follows the cursor over the
/// launcher. On release the app drops at the cursor's root slot.
///
/// It is an `ObservableObject`: the mid-drag close and the final commit are requested from inside an
/// AppKit mouse handler, where mutating the host view's `@State` directly does NOT invalidate the
/// view. Publishing `ejectActive` / `ejectToken` instead routes both back through SwiftUI `.onChange`,
/// where the `@State` mutations (close the folder, move the app) run in a tracked transaction.
@MainActor
final class LaunchpadDragCoordinator: ObservableObject {
    struct EjectRequest {
        let folderID: String
        let appID: String
        let result: LaunchpadExternalDropResult
    }

    /// True from the moment the dragged app leaves the folder until release — the host view watches
    /// this and zooms the folder closed while the drag continues.
    @Published private(set) var ejectActive = false
    /// Bumped on release — the host view performs the move + final close in its `.onChange`.
    @Published private(set) var ejectToken = 0
    private(set) var pendingEject: EjectRequest?

    /// The app currently being carried out + its source folder — used to hide it from that folder's
    /// thumbnail during the carry (transient display only; the data isn't touched until release).
    private(set) var carriedAppID: String?
    private(set) var carriedSourceFolderID: String?

    private struct WeakContainer { weak var value: LaunchpadGridContainerView? }

    /// Every root page container, keyed by page index. The SwiftUI paging `.offset` never enters
    /// the AppKit frame chain, so cross-page work cannot lean on `convert` against these views —
    /// the registry plus the pushed `geometry` snapshot replace it (design §3/§5).
    private var pages: [Int: WeakContainer] = [:]
    /// Mirrors the SwiftUI `currentPage` @State via the single `.onChange` funnel.
    private(set) var currentPage = 0
    /// Viewport/page geometry pushed from the grid (AppKit window space, Equatable-deduped).
    private(set) var geometry = LaunchpadPageGeometry()

    private var floatingWindow: NSWindow?
    private var floatingSide: CGFloat = 0

    /// The container an external drag should classify against — the visible page's grid.
    private var activeContainer: LaunchpadGridContainerView? { pages[currentPage]?.value }

    /// Window-point → page-local arithmetic from the pushed geometry; nil until the first push.
    private var carrySpace: LaunchpadCarrySpace? {
        guard geometry.pageWidth > 0 else { return nil }
        return LaunchpadCarrySpace(viewportMinX: geometry.viewportMinX,
                                   viewportTopY: geometry.viewportTopY,
                                   pageWidth: geometry.pageWidth)
    }

    /// Every page container registers itself (not just the visible one) so the page flipped to
    /// during a carry is already reachable. Pure dictionary write — safe before any cells exist.
    func registerPageContainer(_ container: LaunchpadGridContainerView, page: Int) {
        pages[page] = WeakContainer(value: container)
    }

    /// Containers unregister when leaving the window (page-count shrink, overlay teardown).
    func unregisterPageContainer(_ container: LaunchpadGridContainerView) {
        for (page, boxed) in pages where boxed.value === container || boxed.value == nil {
            pages.removeValue(forKey: page)
        }
    }

    /// Single funnel for page changes (every flip path goes through the `currentPage` @State).
    func currentPageDidChange(_ page: Int) {
        currentPage = page
        scheduleGeometryProbe()
    }

    /// Equatable-deduped push from the grid's viewport relay (AppKit window space).
    func syncGeometry(_ new: LaunchpadPageGeometry) {
        guard new != geometry else { return }
        geometry = new
        scheduleGeometryProbe()
    }

    // Test-facing read-only surface (design §10-④).
    var hasFloatingWindow: Bool { floatingWindow != nil }
    var registeredPageIndices: [Int] { pages.filter { $0.value.value != nil }.keys.sorted() }

    /// Begin the eject: raise a floating icon at the cursor and signal the folder to close. Safe to
    /// call from a mouse handler — creating an `NSWindow` is pure AppKit (no SwiftUI), and the
    /// `@Published` flip schedules the SwiftUI close asynchronously rather than mutating it inline.
    func beginEject(appID: String, sourceFolderID: String, icon: NSImage?, iconSide: CGFloat,
                    atScreenPoint p: NSPoint, aboveLevel: NSWindow.Level) {
        guard !ejectActive else { return }
        carriedAppID = appID
        carriedSourceFolderID = sourceFolderID
        activeContainer?.beginExternalDrag(appID: appID) // visible page starts making way / can merge
        floatingSide = iconSide * 1.1
        let frame = NSRect(x: 0, y: 0, width: floatingSide, height: floatingSide)
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
        floatingWindow = win
        positionFloating(atScreenPoint: p)
        win.orderFront(nil)
        ejectActive = true
    }

    /// Follow the cursor: move the floating icon (screen space) AND drive the visible page's
    /// make-way / merge classification. The window point is mapped to page-local space through the
    /// pushed geometry — NOT through `convert` against the page container, whose frame chain is
    /// blind to the SwiftUI paging `.offset` (off by page×pageWidth on page > 0).
    func moveEject(atScreenPoint screen: NSPoint, atWindowPoint window: NSPoint) {
        positionFloating(atScreenPoint: screen)
        guard let space = carrySpace else {                      // geometry not pushed yet (cold start)
            activeContainer?.updateExternalDrag(atWindowPoint: window)
            return
        }
        crossCheckGeometry(space: space)
        activeContainer?.updateExternalDrag(atContainerPoint: space.local(fromWindow: window))
    }

    /// Release after an eject: read the visible page's resolved outcome (merge or reorder), request
    /// it, and drop the float.
    func commitOut(folderID: String, appID: String, atWindowPoint p: NSPoint) {
        let fallback: LaunchpadDropTarget?
        if let space = carrySpace {
            fallback = activeContainer?.rootDropTarget(atContainerPoint: space.local(fromWindow: p))
        } else {
            fallback = activeContainer?.rootDropTarget(atWindowPoint: p)
        }
        let result = activeContainer?.commitExternalDrag() ?? .reorder(fallback)
        pendingEject = EjectRequest(folderID: folderID, appID: appID, result: result)
        tearDownFloating()
        ejectToken += 1
    }

    /// Abort an in-flight eject (launcher closed / torn down) without moving anything.
    func cancelEject() {
        activeContainer?.endExternalDrag()
        tearDownFloating()
    }

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

    private func positionFloating(atScreenPoint p: NSPoint) {
        floatingWindow?.setFrameOrigin(NSPoint(x: p.x - floatingSide / 2, y: p.y - floatingSide / 2))
    }

    private func tearDownFloating() {
        floatingWindow?.orderOut(nil)
        floatingWindow = nil
        carriedAppID = nil
        carriedSourceFolderID = nil
        ejectActive = false
    }
}
