import AppKit
import MacToolsPluginKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// Label-appearance value layer (design 2026-06-13): color / weight / size presets resolve
/// to distinct AppKit values, the defaults anchor the historical rendering (zero migration),
/// and every case carries a localized label. Mirrors `LaunchpadBackgroundStyleTests`.
@MainActor
final class LaunchpadLabelStyleTests: XCTestCase {

    // MARK: - Color

    /// Byte-compat anchor: `.automatic` resolves to `NSColor.labelColor`, the historical
    /// implicit label color — an untouched preference is pixel-identical.
    func testAutomaticColorAnchorsToLabelColor() {
        XCTAssertEqual(LaunchpadLabelColor.automatic.nsColor, NSColor.labelColor)
    }

    func testColorMappingCoversAllCasesDistinctly() {
        let expected: [LaunchpadLabelColor: NSColor] = [
            .automatic: .labelColor,
            .light: .white,
            .dark: .black,
            .accent: .controlAccentColor,
        ]
        XCTAssertEqual(Set(LaunchpadLabelColor.allCases), Set(expected.keys))
        for color in LaunchpadLabelColor.allCases {
            XCTAssertEqual(color.nsColor, expected[color])
        }
        XCTAssertEqual(Set(LaunchpadLabelColor.allCases.map(\.nsColor)).count,
                       LaunchpadLabelColor.allCases.count)
    }

    // MARK: - Weight

    func testWeightMappingCoversAllCasesDistinctly() {
        let expected: [LaunchpadLabelWeight: NSFont.Weight] = [
            .regular: .regular,
            .medium: .medium,
            .semibold: .semibold,
            .bold: .bold,
        ]
        XCTAssertEqual(Set(LaunchpadLabelWeight.allCases), Set(expected.keys))
        for weight in LaunchpadLabelWeight.allCases {
            XCTAssertEqual(weight.nsFontWeight, expected[weight])
        }
        XCTAssertEqual(Set(LaunchpadLabelWeight.allCases.map(\.nsFontWeight.rawValue)).count,
                       LaunchpadLabelWeight.allCases.count)
    }

    /// The folder big title floors the weight at `.semibold` so it is never thinner than
    /// the historical baseline; `.bold` passes through.
    func testEmphasizedWeightFloorsAtSemibold() {
        XCTAssertEqual(LaunchpadLabelWeight.regular.emphasized, .semibold)
        XCTAssertEqual(LaunchpadLabelWeight.medium.emphasized, .semibold)
        XCTAssertEqual(LaunchpadLabelWeight.semibold.emphasized, .semibold)
        XCTAssertEqual(LaunchpadLabelWeight.bold.emphasized, .bold)
        for weight in LaunchpadLabelWeight.allCases {
            XCTAssertGreaterThanOrEqual(weight.emphasized.rawValue, NSFont.Weight.semibold.rawValue)
        }
    }

    // MARK: - Size

    /// Byte-compat anchor: the default `medium` tier derives 12pt at the historical 64pt
    /// icon — `round(64 * 0.18) == 12`, clamped to [11, 15].
    func testMediumSizeAt64PinsHistorical12() {
        XCTAssertEqual(LaunchpadLabelSize.medium.fontSize(iconSide: 64), 12)
    }

    func testSizeMappingDistinctAcrossTiersAtSameIcon() {
        let small = LaunchpadLabelSize.small.fontSize(iconSide: 64)
        let medium = LaunchpadLabelSize.medium.fontSize(iconSide: 64)
        let large = LaunchpadLabelSize.large.fontSize(iconSide: 64)
        XCTAssertEqual(small, 11)
        XCTAssertEqual(medium, 12)
        XCTAssertEqual(large, 13) // round(64 * 0.21) == 13, clamped to [12, 17]
        XCTAssertEqual(Set([small, medium, large]).count, 3)
    }

    /// `small` is a fixed 11pt regardless of icon size; the scaling tiers clamp at the
    /// extremes (48pt floor, 96pt ceiling).
    func testSizeClampingAtIconExtremes() {
        XCTAssertEqual(LaunchpadLabelSize.small.fontSize(iconSide: 48), 11)
        XCTAssertEqual(LaunchpadLabelSize.small.fontSize(iconSide: 96), 11)

        // medium: round(48*0.18)=9 → clamp 11; round(96*0.18)=17 → clamp 15.
        XCTAssertEqual(LaunchpadLabelSize.medium.fontSize(iconSide: 48), 11)
        XCTAssertEqual(LaunchpadLabelSize.medium.fontSize(iconSide: 96), 15)

        // large: round(48*0.21)=10 → clamp 12; round(96*0.21)=20 → clamp 17.
        XCTAssertEqual(LaunchpadLabelSize.large.fontSize(iconSide: 48), 12)
        XCTAssertEqual(LaunchpadLabelSize.large.fontSize(iconSide: 96), 17)
    }

    // MARK: - Localization

    func testColorLabelsCoverAllCases() {
        let localization = PluginLocalization(bundle: Bundle(for: Self.self))
        for color in LaunchpadLabelColor.allCases {
            XCTAssertFalse(color.label(localization: localization).isEmpty)
        }
        XCTAssertEqual(Set(LaunchpadLabelColor.allCases.map { $0.label(localization: localization) }).count,
                       LaunchpadLabelColor.allCases.count)
    }

    func testWeightLabelsCoverAllCases() {
        let localization = PluginLocalization(bundle: Bundle(for: Self.self))
        for weight in LaunchpadLabelWeight.allCases {
            XCTAssertFalse(weight.label(localization: localization).isEmpty)
        }
        XCTAssertEqual(Set(LaunchpadLabelWeight.allCases.map { $0.label(localization: localization) }).count,
                       LaunchpadLabelWeight.allCases.count)
    }

    func testSizeLabelsCoverAllCases() {
        let localization = PluginLocalization(bundle: Bundle(for: Self.self))
        for size in LaunchpadLabelSize.allCases {
            XCTAssertFalse(size.label(localization: localization).isEmpty)
        }
        XCTAssertEqual(Set(LaunchpadLabelSize.allCases.map { $0.label(localization: localization) }).count,
                       LaunchpadLabelSize.allCases.count)
    }
}
