import CoreGraphics
import Foundation

struct DisplayDisableDisplay: Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let isActive: Bool
    let isInMirrorSet: Bool
    let isVisibleToAppKit: Bool
    let vendorNumber: UInt32?
    let modelNumber: UInt32?
    let serialNumber: UInt32?

    init(
        id: CGDirectDisplayID,
        name: String,
        isBuiltin: Bool,
        isActive: Bool,
        isInMirrorSet: Bool,
        isVisibleToAppKit: Bool,
        vendorNumber: UInt32? = nil,
        modelNumber: UInt32? = nil,
        serialNumber: UInt32? = nil
    ) {
        self.id = id
        self.name = name
        self.isBuiltin = isBuiltin
        self.isActive = isActive
        self.isInMirrorSet = isInMirrorSet
        self.isVisibleToAppKit = isVisibleToAppKit
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
    }
}

extension DisplayDisableDisplay {
    func withActive(_ value: Bool) -> DisplayDisableDisplay {
        DisplayDisableDisplay(
            id: id,
            name: name,
            isBuiltin: isBuiltin,
            isActive: value,
            isInMirrorSet: isInMirrorSet,
            isVisibleToAppKit: isVisibleToAppKit,
            vendorNumber: vendorNumber,
            modelNumber: modelNumber,
            serialNumber: serialNumber
        )
    }

    func withVisibleToAppKit(_ value: Bool) -> DisplayDisableDisplay {
        DisplayDisableDisplay(
            id: id,
            name: name,
            isBuiltin: isBuiltin,
            isActive: isActive,
            isInMirrorSet: isInMirrorSet,
            isVisibleToAppKit: value,
            vendorNumber: vendorNumber,
            modelNumber: modelNumber,
            serialNumber: serialNumber
        )
    }
}

enum DisplayDisableStatus: Equatable {
    case available
    case disabled
    case unavailable
    case unsupported
    case busy
    case failed
}

struct DisplayDisableSnapshot: Equatable {
    let status: DisplayDisableStatus
    let isDisableAllowed: Bool
    let isRestoreAllowed: Bool
    let externalDisplayCount: Int
    let message: String?

    static let unsupported = DisplayDisableSnapshot(
        status: .unsupported,
        isDisableAllowed: false,
        isRestoreAllowed: false,
        externalDisplayCount: 0,
        message: "当前系统不支持关闭内建显示屏"
    )
}

struct DisplayDisableRecoverySnapshot: Codable, Equatable {
    let createdAt: Date
    let builtInDisplayID: CGDirectDisplayID
    let vendorNumber: UInt32?
    let modelNumber: UInt32?
    let serialNumber: UInt32?
    let survivorDisplayIDs: [CGDirectDisplayID]
    let originalMainDisplayID: CGDirectDisplayID?
}
