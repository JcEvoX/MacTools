import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// View-layer config of the glass backdrop (design §5.4): the compact-panel blur mask
/// (behind-window blur can ignore the host layer's corner mask, so the effect view gets
/// its own `maskImage`), the forced-dark scoping (G2) and the mask-caching coordinator.
@MainActor
final class LaunchpadGlassBackdropTests: XCTestCase {

    // MARK: - Rounded-rect mask image (geometry + alpha coverage)

    /// The mask must be a stretch-resizable image whose cap insets pin the corner arcs:
    /// minimal edge = 2r + 1 (a 1pt stretchable center), insets = radius on all sides.
    func testRoundedRectMaskImageGeometry() {
        let radius = LaunchpadCompactPanelMetrics.cornerRadius
        let mask = LaunchpadGlassBackdrop.roundedRectMaskImage(cornerRadius: radius)
        XCTAssertEqual(mask.size, NSSize(width: radius * 2 + 1, height: radius * 2 + 1))
        XCTAssertEqual(mask.resizingMode, .stretch)
        XCTAssertEqual(mask.capInsets.top, radius)
        XCTAssertEqual(mask.capInsets.left, radius)
        XCTAssertEqual(mask.capInsets.bottom, radius)
        XCTAssertEqual(mask.capInsets.right, radius)
    }

    /// Rasterized alpha: corners transparent (blur clipped), center and straight edge
    /// midpoints opaque (no blur loss along flat edges).
    func testRoundedRectMaskImageAlphaCoverage() throws {
        let mask = LaunchpadGlassBackdrop.roundedRectMaskImage(cornerRadius: 22)
        let cgImage = try XCTUnwrap(mask.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let maxX = bitmap.pixelsWide - 1
        let maxY = bitmap.pixelsHigh - 1

        func alpha(_ x: Int, _ y: Int) -> CGFloat {
            bitmap.colorAt(x: x, y: y)?.alphaComponent ?? -1
        }

        // All four extreme corner pixels lie outside the 22pt arc → fully clipped.
        for (x, y) in [(0, 0), (maxX, 0), (0, maxY), (maxX, maxY)] {
            XCTAssertLessThan(alpha(x, y), 0.05, "corner pixel (\(x),\(y)) should be masked out")
        }
        // Center and straight-edge midpoints are inside the shape → fully kept.
        for (x, y) in [(maxX / 2, maxY / 2), (maxX / 2, 0), (maxX / 2, maxY), (0, maxY / 2), (maxX, maxY / 2)] {
            XCTAssertGreaterThan(alpha(x, y), 0.95, "interior pixel (\(x),\(y)) should be kept")
        }
    }

    // MARK: - apply(to:coordinator:) configuration

    /// Compact main backdrop: a positive corner radius installs a maskImage so the
    /// behind-window blur is rounded even if the host layer mask is ignored.
    func testApplyInstallsMaskForPositiveCornerRadius() {
        let backdrop = LaunchpadGlassBackdrop(
            material: .hud,
            blendingMode: .behindWindow,
            forcesDarkAppearance: true,
            cornerRadius: LaunchpadCompactPanelMetrics.cornerRadius
        )
        let view = NSVisualEffectView()
        let coordinator = LaunchpadGlassBackdrop.Coordinator()
        backdrop.apply(to: view, coordinator: coordinator)

        XCTAssertNotNil(view.maskImage)
        XCTAssertEqual(view.material, .hudWindow)
        // G2: forced dark lands on the effect view itself, never the hosting hierarchy.
        XCTAssertEqual(view.appearance?.name, .darkAqua)
    }

    /// Fullscreen / within-window usages (radius 0) must NOT mask the material, and a
    /// non-forced-dark recipe must leave the appearance inherited (nil).
    func testApplyLeavesMaskAndAppearanceUntouchedForZeroRadius() {
        let backdrop = LaunchpadGlassBackdrop(material: .launchpad, blendingMode: .behindWindow)
        let view = NSVisualEffectView()
        backdrop.apply(to: view, coordinator: LaunchpadGlassBackdrop.Coordinator())

        XCTAssertNil(view.maskImage)
        XCTAssertEqual(view.material, .fullScreenUI)
        XCTAssertNil(view.appearance)
    }

    /// Live updates (settings preview re-applies per slider tick) must not rebuild the
    /// mask: same radius → same NSImage instance; radius back to 0 → mask removed.
    func testCoordinatorCachesMaskAcrossReapplies() {
        let view = NSVisualEffectView()
        let coordinator = LaunchpadGlassBackdrop.Coordinator()
        let rounded = LaunchpadGlassBackdrop(
            material: .frosted, blendingMode: .behindWindow, cornerRadius: 22
        )
        rounded.apply(to: view, coordinator: coordinator)
        let firstMask = view.maskImage
        XCTAssertNotNil(firstMask)

        rounded.apply(to: view, coordinator: coordinator)
        XCTAssertTrue(view.maskImage === firstMask, "unchanged radius must not rebuild the mask image")

        let square = LaunchpadGlassBackdrop(material: .frosted, blendingMode: .behindWindow)
        square.apply(to: view, coordinator: coordinator)
        XCTAssertNil(view.maskImage)
    }

    // MARK: - Shared compact geometry anchor

    /// Regression anchor: the compact panel radius is shared between the host layer mask
    /// and the blur maskImage; this pins the historical 22pt so neither clip can drift.
    func testCompactPanelCornerRadiusAnchor() {
        XCTAssertEqual(LaunchpadCompactPanelMetrics.cornerRadius, 22)
    }
}
