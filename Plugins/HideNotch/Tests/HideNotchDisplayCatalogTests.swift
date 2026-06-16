import XCTest
@testable import MacTools
@testable import HideNotchPlugin

final class HideNotchDisplayCatalogTests: XCTestCase {
    func testResolverUsesCurrentPlaceholderWhenCurrentDesktopUUIDIsEmpty() {
        let spaces = HideNotchManagedDisplaySpaceResolver.spaces(from: [
            "Current Space": [
                "uuid": "",
                "type": 0
            ],
            "Spaces": [
                [
                    "uuid": "",
                    "type": 0
                ]
            ]
        ])

        XCTAssertEqual(
            spaces,
            [
                HideNotchDisplaySpace(
                    identifier: HideNotchDisplaySpace.currentPlaceholderIdentifier,
                    isCurrent: true
                )
            ]
        )
    }

    func testNotchHeightUsesAuxHeightWhenMenuBarIsShorter() {
        XCTAssertEqual(
            SystemHideNotchDisplayCatalog.notchHeight(
                auxLeftHeight: 32,
                auxRightHeight: 32,
                menuBarHeight: 30,
                isMacOS27OrLater: true
            ),
            32
        )
    }

    func testNotchHeightIgnoresTallerMenuBarWhenAuxHeightExistsOnMacOS27() {
        // macOS 27: the menu bar can be taller than the physical notch, so the
        // mask pins to the auxiliary-area height (32), never the taller menu
        // bar (40) which would overflow below the camera housing.
        XCTAssertEqual(
            SystemHideNotchDisplayCatalog.notchHeight(
                auxLeftHeight: 32,
                auxRightHeight: 32,
                menuBarHeight: 40,
                isMacOS27OrLater: true
            ),
            32
        )
    }

    func testNotchHeightUsesMaxWithMenuBarOnLegacyHosts() {
        // macOS ≤26: preserve the original max(aux, menu bar) formula so the
        // mask geometry stays byte-identical to the shipping pre-27 releases.
        // The same inputs as the macOS 27 test above resolve to 40 here, not 32.
        XCTAssertEqual(
            SystemHideNotchDisplayCatalog.notchHeight(
                auxLeftHeight: 32,
                auxRightHeight: 32,
                menuBarHeight: 40,
                isMacOS27OrLater: false
            ),
            40
        )
    }

    func testNotchHeightUsesTallerAuxSideWhenSidesDiffer() {
        XCTAssertEqual(
            SystemHideNotchDisplayCatalog.notchHeight(
                auxLeftHeight: 28,
                auxRightHeight: 32,
                menuBarHeight: 24,
                isMacOS27OrLater: true
            ),
            32
        )
    }

    func testNotchHeightFallsBackToMenuBarWhenAuxHeightsAreZero() {
        XCTAssertEqual(
            SystemHideNotchDisplayCatalog.notchHeight(
                auxLeftHeight: 0,
                auxRightHeight: 0,
                menuBarHeight: 24,
                isMacOS27OrLater: true
            ),
            24
        )
    }

    func testNotchHeightIsZeroWhenAllInputsAreZero() {
        XCTAssertEqual(
            SystemHideNotchDisplayCatalog.notchHeight(
                auxLeftHeight: 0,
                auxRightHeight: 0,
                menuBarHeight: 0,
                isMacOS27OrLater: true
            ),
            0
        )
    }

    func testNotchHeightRejectsNonFiniteInputs() {
        XCTAssertEqual(
            SystemHideNotchDisplayCatalog.notchHeight(
                auxLeftHeight: .nan,
                auxRightHeight: .infinity,
                menuBarHeight: -1,
                isMacOS27OrLater: true
            ),
            0
        )
    }

    func testNotchHeightKeepsValidSideWhenOtherSideIsNaN() {
        // max(.nan, 32) returns .nan in Swift, so a NaN left side must be
        // sanitized before max() or it would discard the valid right side
        // and wrongly fall back to the menu bar estimate.
        XCTAssertEqual(
            SystemHideNotchDisplayCatalog.notchHeight(
                auxLeftHeight: .nan,
                auxRightHeight: 32,
                menuBarHeight: 24,
                isMacOS27OrLater: true
            ),
            32
        )
    }

    func testResolverFiltersOutNonDesktopSpaces() {
        let spaces = HideNotchManagedDisplaySpaceResolver.spaces(from: [
            "Current Space": [
                "uuid": "",
                "type": 0
            ],
            "Spaces": [
                [
                    "uuid": "",
                    "type": 0
                ],
                [
                    "uuid": "E511762E-A085-4DFB-AF2E-B8F5E83A7952",
                    "type": 4,
                    "WallSpace": [
                        "uuid": "48CC1451-CDC2-4890-91F0-A03908F06252",
                        "type": 6
                    ]
                ],
                [
                    "uuid": "DESKTOP-2",
                    "type": 0
                ]
            ]
        ])

        XCTAssertEqual(
            spaces,
            [
                HideNotchDisplaySpace(
                    identifier: HideNotchDisplaySpace.currentPlaceholderIdentifier,
                    isCurrent: true
                ),
                HideNotchDisplaySpace(
                    identifier: "DESKTOP-2",
                    isCurrent: false
                )
            ]
        )
    }
}
