import CoreGraphics
import Foundation

@MainActor
protocol DisplayDisableCoordinating: AnyObject {
    var snapshot: DisplayDisableSnapshot { get }

    func refreshSnapshot()
    func disableBuiltInDisplay() async
    func restoreBuiltInDisplay()
    func reconcileTopology() async
}

@MainActor
final class DisplayDisableCoordinator: DisplayDisableCoordinating {
    private let service: any DisplayDisableServicing
    private let store: any DisplayDisableStateStoring
    private let verificationSettleDelay: Duration

    private(set) var snapshot: DisplayDisableSnapshot = .unsupported

    init(
        service: any DisplayDisableServicing,
        store: any DisplayDisableStateStoring,
        verificationSettleDelay: Duration = .milliseconds(800)
    ) {
        self.service = service
        self.store = store
        self.verificationSettleDelay = verificationSettleDelay
        refreshSnapshot()
    }

    func refreshSnapshot() {
        guard service.isSupported else {
            snapshot = .unsupported
            return
        }

        let displays = service.listDisplays()
        if store.snapshot != nil {
            reconcileStoredSnapshot(displays: displays)
            return
        }

        updateAvailableSnapshot(displays: displays)
    }

    private func updateAvailableSnapshot(displays: [DisplayDisableDisplay]) {
        guard displays.contains(where: \.isBuiltin) else {
            snapshot = DisplayDisableSnapshot(
                status: .unavailable,
                isDisableAllowed: false,
                isRestoreAllowed: store.snapshot != nil,
                externalDisplayCount: externalSurvivors(in: displays).count,
                message: "未检测到内建显示屏"
            )
            return
        }

        let externalCount = externalSurvivors(in: displays).count
        snapshot = DisplayDisableSnapshot(
            status: .available,
            isDisableAllowed: externalCount > 0,
            isRestoreAllowed: store.snapshot != nil,
            externalDisplayCount: externalCount,
            message: externalCount > 0 ? nil : "连接外接显示器后可关闭内建显示屏"
        )
    }

    func disableBuiltInDisplay() async {
        guard service.isSupported else {
            snapshot = .unsupported
            return
        }

        let displays = service.listDisplays()
        guard let builtIn = displays.first(where: \.isBuiltin) else {
            snapshot = DisplayDisableSnapshot(
                status: .unavailable,
                isDisableAllowed: false,
                isRestoreAllowed: store.snapshot != nil,
                externalDisplayCount: externalSurvivors(in: displays).count,
                message: "未检测到内建显示屏"
            )
            return
        }

        let survivors = externalSurvivors(in: displays)
        guard !survivors.isEmpty else {
            snapshot = DisplayDisableSnapshot(
                status: .available,
                isDisableAllowed: false,
                isRestoreAllowed: store.snapshot != nil,
                externalDisplayCount: 0,
                message: "连接外接显示器后可关闭内建显示屏"
            )
            return
        }

        guard !builtIn.isInMirrorSet else {
            snapshot = DisplayDisableSnapshot(
                status: .available,
                isDisableAllowed: false,
                isRestoreAllowed: store.snapshot != nil,
                externalDisplayCount: survivors.count,
                message: "镜像显示时暂不支持关闭内建显示屏"
            )
            return
        }

        let recoverySnapshot = DisplayDisableRecoverySnapshot(
            createdAt: Date(),
            builtInDisplayID: builtIn.id,
            vendorNumber: builtIn.vendorNumber,
            modelNumber: builtIn.modelNumber,
            serialNumber: builtIn.serialNumber,
            survivorDisplayIDs: survivors.map(\.id),
            originalMainDisplayID: nil
        )
        store.snapshot = recoverySnapshot

        do {
            try service.setDisplay(builtIn.id, enabled: false)
        } catch {
            store.snapshot = nil
            snapshot = DisplayDisableSnapshot(
                status: .failed,
                isDisableAllowed: true,
                isRestoreAllowed: false,
                externalDisplayCount: survivors.count,
                message: "关闭内建显示屏失败"
            )
            return
        }

        try? await Task.sleep(for: verificationSettleDelay)
        let verifiedDisplays = service.listDisplays()
        if disableSucceeded(targetID: builtIn.id, survivorIDs: Set(survivors.map(\.id)), displays: verifiedDisplays) {
            snapshot = DisplayDisableSnapshot(
                status: .disabled,
                isDisableAllowed: false,
                isRestoreAllowed: true,
                externalDisplayCount: survivors.count,
                message: nil
            )
            return
        }

        try? service.setDisplay(builtIn.id, enabled: true)
        snapshot = DisplayDisableSnapshot(
            status: .failed,
            isDisableAllowed: true,
            isRestoreAllowed: true,
            externalDisplayCount: externalSurvivors(in: verifiedDisplays).count,
            message: "关闭内建显示屏失败，已尝试恢复"
        )
    }

    func restoreBuiltInDisplay() {
        guard let recoverySnapshot = store.snapshot else {
            refreshSnapshot()
            return
        }

        let displays = service.listDisplays()
        guard let restoreTarget = restoreTarget(
            storedID: recoverySnapshot.builtInDisplayID,
            displays: displays
        ) else {
            snapshot = DisplayDisableSnapshot(
                status: .failed,
                isDisableAllowed: false,
                isRestoreAllowed: true,
                externalDisplayCount: externalSurvivors(in: displays).count,
                message: "无法找到内建显示屏"
            )
            return
        }

        do {
            try service.setDisplay(restoreTarget.id, enabled: true)
            store.snapshot = nil
            updateAvailableSnapshot(displays: service.listDisplays())
        } catch {
            snapshot = DisplayDisableSnapshot(
                status: .failed,
                isDisableAllowed: false,
                isRestoreAllowed: true,
                externalDisplayCount: externalSurvivors(in: displays).count,
                message: "恢复内建显示屏失败"
            )
        }
    }

    func reconcileTopology() async {
        reconcileStoredSnapshot(displays: service.listDisplays())
    }

    private func reconcileStoredSnapshot(displays: [DisplayDisableDisplay]) {
        guard let recoverySnapshot = store.snapshot else {
            updateAvailableSnapshot(displays: displays)
            return
        }

        if let builtIn = restoreTarget(storedID: recoverySnapshot.builtInDisplayID, displays: displays),
           builtIn.isActive || builtIn.isVisibleToAppKit {
            store.snapshot = nil
            updateAvailableSnapshot(displays: displays)
            return
        }

        let survivorIDs = Set(recoverySnapshot.survivorDisplayIDs)
        let survivorRemains = displays.contains { display in
            survivorIDs.contains(display.id) && (display.isActive || display.isVisibleToAppKit)
        }
        if !survivorRemains {
            restoreBuiltInDisplay()
            return
        }

        snapshot = DisplayDisableSnapshot(
            status: .disabled,
            isDisableAllowed: false,
            isRestoreAllowed: true,
            externalDisplayCount: externalSurvivors(in: displays).count,
            message: nil
        )
    }

    private func externalSurvivors(in displays: [DisplayDisableDisplay]) -> [DisplayDisableDisplay] {
        displays.filter { display in
            !display.isBuiltin && (display.isActive || display.isVisibleToAppKit)
        }
    }

    private func disableSucceeded(
        targetID: CGDirectDisplayID,
        survivorIDs: Set<CGDirectDisplayID>,
        displays: [DisplayDisableDisplay]
    ) -> Bool {
        let targetIsGone = displays.first(where: { $0.id == targetID }).map {
            !$0.isActive && !$0.isVisibleToAppKit
        } ?? true
        let survivorRemains = displays.contains { display in
            survivorIDs.contains(display.id) && (display.isActive || display.isVisibleToAppKit)
        }
        return targetIsGone && survivorRemains
    }

    private func restoreTarget(
        storedID: CGDirectDisplayID,
        displays: [DisplayDisableDisplay]
    ) -> DisplayDisableDisplay? {
        if let storedDisplay = displays.first(where: { $0.id == storedID && $0.isBuiltin }) {
            return storedDisplay
        }

        return displays.first(where: \.isBuiltin)
    }
}
