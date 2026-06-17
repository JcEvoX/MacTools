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
            // 重新初始化（App 重启、插件热重载/重建）一律按 survivor 是否还在线来决定：
            // 外接屏还在就保持禁用，外接屏已断开才恢复内建屏；不因“非本会话禁用”而无条件恢复。
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
            survivorIdentities: survivors.map(survivorIdentity(for:)),
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

        do {
            try await Task.sleep(for: verificationSettleDelay)
        } catch {
            return
        }

        guard !Task.isCancelled else {
            return
        }

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

        guard !Task.isCancelled else {
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
            restoreCurrentBuiltInDisplay()
            return
        }

        let displays = service.listDisplays()
        let restoreCandidates = restoreTargetIDs(
            storedID: recoverySnapshot.builtInDisplayID,
            displays: displays
        )

        for displayID in restoreCandidates {
            do {
                try service.setDisplay(displayID, enabled: true)
                store.snapshot = nil
                updateAvailableSnapshot(displays: service.listDisplays())
                return
            } catch {
                continue
            }
        }

        snapshot = DisplayDisableSnapshot(
            status: .failed,
            isDisableAllowed: false,
            isRestoreAllowed: true,
            externalDisplayCount: externalSurvivors(in: displays).count,
            message: "恢复内建显示屏失败"
        )
    }

    private func restoreCurrentBuiltInDisplay() {
        let displays = service.listDisplays()
        guard let builtIn = displays.first(where: \.isBuiltin) else {
            updateAvailableSnapshot(displays: displays)
            return
        }

        do {
            try service.setDisplay(builtIn.id, enabled: true)
            store.snapshot = nil
            updateAvailableSnapshot(displays: service.listDisplays())
        } catch {
            snapshot = DisplayDisableSnapshot(
                status: .failed,
                isDisableAllowed: false,
                isRestoreAllowed: false,
                externalDisplayCount: externalSurvivors(in: displays).count,
                message: "恢复内建显示屏失败"
            )
        }
    }

    func reconcileTopology() async {
        let displays = service.listDisplays()
        guard store.snapshot != nil else {
            updateAvailableSnapshot(displays: displays)
            return
        }

        // 只要原外接 survivor 还在线就保持禁用；全部消失（真正断开外接屏）才安全恢复内建屏。
        // 不再用时间窗去无条件恢复，避免外接屏息屏/唤醒、改分辨率等良性拓扑事件误触发恢复。
        reconcileStoredSnapshot(displays: displays)
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

        if !storedSurvivorRemains(snapshot: recoverySnapshot, displays: displays) {
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

    private func storedSurvivorRemains(
        snapshot: DisplayDisableRecoverySnapshot,
        displays: [DisplayDisableDisplay]
    ) -> Bool {
        let onlineSurvivors = externalSurvivors(in: displays)

        if let identities = snapshot.survivorIdentities, !identities.isEmpty {
            return identities.contains { identity in
                onlineSurvivors.contains { matchesSurvivor(identity: identity, display: $0) }
            }
        }

        // 旧快照没有身份信息时退回按 displayID 匹配。
        let survivorIDs = Set(snapshot.survivorDisplayIDs)
        return onlineSurvivors.contains { survivorIDs.contains($0.id) }
    }

    // 优先按 EDID 身份（vendor/model/serial）匹配，避免外接屏睡眠/唤醒后 CGDirectDisplayID
    // 变号被误判为“已断开”。EDID 信息缺失时退回比对 displayID。
    private func matchesSurvivor(
        identity: DisplaySurvivorIdentity,
        display: DisplayDisableDisplay
    ) -> Bool {
        if identity.vendorNumber != nil || identity.modelNumber != nil || identity.serialNumber != nil {
            return identity.vendorNumber == display.vendorNumber
                && identity.modelNumber == display.modelNumber
                && identity.serialNumber == display.serialNumber
        }
        return identity.id == display.id
    }

    private func survivorIdentity(for display: DisplayDisableDisplay) -> DisplaySurvivorIdentity {
        DisplaySurvivorIdentity(
            id: display.id,
            vendorNumber: display.vendorNumber,
            modelNumber: display.modelNumber,
            serialNumber: display.serialNumber
        )
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

    private func restoreTargetIDs(
        storedID: CGDirectDisplayID,
        displays: [DisplayDisableDisplay]
    ) -> [CGDirectDisplayID] {
        var ids = [storedID]
        if let visibleBuiltInID = displays.first(where: \.isBuiltin)?.id,
           visibleBuiltInID != storedID {
            ids.append(visibleBuiltInID)
        }
        return ids
    }
}
