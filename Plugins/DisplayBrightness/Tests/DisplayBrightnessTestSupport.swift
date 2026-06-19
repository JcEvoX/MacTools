import CoreGraphics
import MacToolsPluginKit
@testable import MacTools
@testable import DisplayBrightnessPlugin

func makeTestDisplay(
    id: CGDirectDisplayID,
    name: String,
    isBuiltin: Bool = false,
    isMain: Bool = false,
    vendorNumber: UInt32? = nil,
    modelNumber: UInt32? = nil,
    serialNumber: UInt32? = nil
) -> DisplayInfo {
    DisplayInfo(
        id: id,
        name: name,
        isBuiltin: isBuiltin,
        isMain: isMain,
        vendorNumber: vendorNumber,
        modelNumber: modelNumber,
        serialNumber: serialNumber
    )
}

func makeBrightnessDisplay(
    id: CGDirectDisplayID,
    name: String,
    brightness: Double,
    vendorNumber: UInt32? = nil,
    modelNumber: UInt32? = nil,
    serialNumber: UInt32? = nil
) -> DisplayBrightnessDisplay {
    DisplayBrightnessDisplay(
        display: makeTestDisplay(
            id: id,
            name: name,
            vendorNumber: vendorNumber,
            modelNumber: modelNumber,
            serialNumber: serialNumber
        ),
        brightness: brightness,
        isPendingWrite: false
    )
}

@MainActor
final class MockDisplayBrightnessController: DisplayBrightnessControlling {
    var onStateChange: (() -> Void)?
    var snapshotValue = DisplayBrightnessSnapshot(displays: [], errorMessage: nil)

    func refresh() {}

    func snapshot() -> DisplayBrightnessSnapshot {
        snapshotValue
    }

    func setBrightness(
        _ value: Double,
        for displayID: CGDirectDisplayID,
        phase: PluginPanelAction.SliderPhase
    ) {
        snapshotValue = DisplayBrightnessSnapshot(
            displays: snapshotValue.displays.map { display in
                guard display.id == displayID else { return display }
                return DisplayBrightnessDisplay(
                    display: display.display,
                    brightness: min(max(value, 0), 1),
                    isPendingWrite: phase != .ended
                )
            },
            errorMessage: snapshotValue.errorMessage
        )
    }
}
