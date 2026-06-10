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

    private weak var rootContainer: LaunchpadGridContainerView?
    private var floatingWindow: NSWindow?
    private var floatingSide: CGFloat = 0

    /// The visible root page grid registers itself so the drop slot resolves against live geometry.
    func registerRootContainer(_ container: LaunchpadGridContainerView) { rootContainer = container }

    /// Begin the eject: raise a floating icon at the cursor and signal the folder to close. Safe to
    /// call from a mouse handler — creating an `NSWindow` is pure AppKit (no SwiftUI), and the
    /// `@Published` flip schedules the SwiftUI close asynchronously rather than mutating it inline.
    func beginEject(appID: String, sourceFolderID: String, icon: NSImage?, iconSide: CGFloat,
                    atScreenPoint p: NSPoint, aboveLevel: NSWindow.Level) {
        guard !ejectActive else { return }
        carriedAppID = appID
        carriedSourceFolderID = sourceFolderID
        rootContainer?.beginExternalDrag(appID: appID)   // root grid starts making way / can merge
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

    /// Follow the cursor: move the floating icon (screen space) AND drive the root grid's make-way /
    /// merge classification (window space — same window, so `convert` resolves correctly).
    func moveEject(atScreenPoint screen: NSPoint, atWindowPoint window: NSPoint) {
        positionFloating(atScreenPoint: screen)
        rootContainer?.updateExternalDrag(atWindowPoint: window)
    }

    /// Release after an eject: read the root grid's resolved outcome (merge or reorder), request it,
    /// and drop the float.
    func commitOut(folderID: String, appID: String, atWindowPoint p: NSPoint) {
        let result = rootContainer?.commitExternalDrag() ?? .reorder(rootContainer?.rootDropTarget(atWindowPoint: p))
        pendingEject = EjectRequest(folderID: folderID, appID: appID, result: result)
        tearDownFloating()
        ejectToken += 1
    }

    /// Abort an in-flight eject (launcher closed / torn down) without moving anything.
    func cancelEject() {
        rootContainer?.endExternalDrag()
        tearDownFloating()
    }

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
