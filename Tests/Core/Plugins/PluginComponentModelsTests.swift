import AppKit
import SwiftUI
import XCTest
@testable import MacTools

final class PluginComponentModelsTests: XCTestCase {
    func testComponentSpanAcceptsSupportedSizes() {
        XCTAssertEqual(PluginComponentSpan(width: 1, height: 1), .oneByOne)
        XCTAssertEqual(PluginComponentSpan(width: 1, height: 2), .oneByTwo)
        XCTAssertEqual(PluginComponentSpan(width: 2, height: 1), .twoByOne)
        XCTAssertEqual(PluginComponentSpan(width: 2, height: 2), .twoByTwo)
        XCTAssertEqual(PluginComponentSpan(width: 4, height: 2), .fourByTwo)
        XCTAssertEqual(PluginComponentSpan(width: 2, height: 4)?.height, 4)
    }

    func testComponentSpanRejectsUnsupportedSizes() {
        XCTAssertNil(PluginComponentSpan(width: 0, height: 1))
        XCTAssertNil(PluginComponentSpan(width: 5, height: 1))
        XCTAssertNil(PluginComponentSpan(width: 1, height: 0))
    }

    func testPluginMetadataCarriesStableIdentityAndDisplayFields() {
        let metadata = PluginMetadata(
            id: "mock-feature",
            title: "Mock Feature",
            iconName: "sparkles",
            iconTint: Color(nsColor: .systemPurple),
            order: 42,
            defaultDescription: "Feature description"
        )

        XCTAssertEqual(metadata.id, "mock-feature")
        XCTAssertEqual(metadata.title, "Mock Feature")
        XCTAssertEqual(metadata.iconName, "sparkles")
        XCTAssertEqual(metadata.order, 42)
        XCTAssertEqual(metadata.defaultDescription, "Feature description")
    }

    func testPrimaryPanelDescriptorCarriesPanelSpecificFields() {
        let descriptor = PluginPrimaryPanelDescriptor(
            controlStyle: .button,
            menuActionBehavior: .dismissBeforeHandling,
            buttonTitle: "Run"
        )

        XCTAssertEqual(descriptor.controlStyle, .button)
        XCTAssertEqual(descriptor.menuActionBehavior, .dismissBeforeHandling)
        XCTAssertEqual(descriptor.buttonTitle, "Run")
    }
}
