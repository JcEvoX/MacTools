import CoreFoundation
import CoreGraphics
import Foundation
import MultitouchSupport
import OSLog

/// 管理触控板多点触控设备回调，检测到指定手指数后通过 CGEvent tap 把系统左键事件原地改为中键。
///
/// 工作原理（行为思路参考 MiddleClick 的 tap-to-click 模式）：
/// - 多点触控回调维护 `threeDown` 标志（三指正在触碰 → true）。
/// - CGEvent tap 在主线程拦截 `leftMouseDown/Up`，三指期间将其原地改为 `otherMouseDown/Up`。
/// - 系统"轻点点按"产生的左键事件被转换，永不传递给应用，不额外合成事件，不会双击。
final class MiddleClickSession: @unchecked Sendable {

    // MARK: - CGEvent Tap State（CGEvent tap 与 C 回调线程均可读写）

    /// 当前是否有所需手指数正在触碰（供 CGEvent tap 使用）
    nonisolated(unsafe) var threeDown = false
    /// CGEvent tap 已把一次 leftMouseDown 转换为 otherMouseDown，等待配对的 Up
    nonisolated(unsafe) var wasThreeDown = false

    // MARK: - Config（由主线程设置，回调线程读取）

    nonisolated(unsafe) var requiredFingerCount: Int = 3

    // MARK: - Infrastructure

    private var devices: [MTDevice] = []
    private var eventTap: CFMachPort?
    private var runLoopSrc: CFRunLoopSource?
    private let logger = AppLog.middleClickSession

    // MARK: - 单例引用（供 C 回调访问）

    nonisolated(unsafe) static weak var activeSession: MiddleClickSession?

    // MARK: - MTDeviceCreateList（私有符号，通过 @_silgen_name 链接）

    @_silgen_name("MTDeviceCreateList")
    private static func _mtDeviceCreateList() -> Unmanaged<CFMutableArray>?

    private static func createDeviceList() -> [MTDevice] {
        _mtDeviceCreateList()?.takeUnretainedValue() as? [MTDevice] ?? []
    }

    // MARK: - 多点触控回调
    //
    // 只维护 threeDown 标志，不做手势识别。

    private let touchCallback: MTFrameCallbackFunction = { _, data, nFingers, _, _ in
        guard let session = MiddleClickSession.activeSession else { return }
        session.threeDown = (nFingers == Int32(session.requiredFingerCount))
    }

    // MARK: - CGEvent Tap

    private func startEventTap() {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)

        // @convention(c) 闭包不能捕获上下文，self 通过 userInfo 指针传入
        let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let ptr = userInfo else { return Unmanaged.passUnretained(event) }
            let session = Unmanaged<MiddleClickSession>.fromOpaque(ptr).takeUnretainedValue()
            let kCenter = Int64(CGMouseButton.center.rawValue)
            let passthrough = Unmanaged.passUnretained(event)

            if session.threeDown && (type == .leftMouseDown || type == .rightMouseDown) {
                session.wasThreeDown = true
                session.threeDown = false
                event.type = .otherMouseDown
                event.setIntegerValueField(.mouseEventButtonNumber, value: kCenter)
            } else if session.wasThreeDown && (type == .leftMouseUp || type == .rightMouseUp) {
                session.wasThreeDown = false
                event.type = .otherMouseUp
                event.setIntegerValueField(.mouseEventButtonNumber, value: kCenter)
            }

            return passthrough
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("无法创建 CGEvent tap，请检查辅助功能授权")
            return
        }

        guard let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSrc = src
        logger.info("CGEvent tap 已启动")
    }

    private func stopEventTap() {
        guard let tap = eventTap, CFMachPortIsValid(tap) else {
            eventTap = nil
            runLoopSrc = nil
            return
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let src = runLoopSrc {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSrc = nil
        }
        CFMachPortInvalidate(tap)
        eventTap = nil
        logger.info("CGEvent tap 已停止")
    }

    // MARK: - Start / Stop

    func start() {
        guard devices.isEmpty else { return }
        devices = Self.createDeviceList()
        if devices.isEmpty {
            logger.warning("未检测到多点触控设备，中键模拟无法启动")
        }
        devices.forEach { $0.register(contactFrameCallback: touchCallback); $0.start(runMode: 0) }
        startEventTap()
        logger.info("已启动多点触控监听，设备数：\(self.devices.count)")
    }

    func stop() {
        stopEventTap()
        devices.forEach { $0.unregister(contactFrameCallback: touchCallback); $0.stop(); $0.release() }
        devices.removeAll()
        threeDown = false
        wasThreeDown = false
        logger.info("已停止多点触控监听")
    }

    func activate() {
        MiddleClickSession.activeSession?.stop()
        MiddleClickSession.activeSession = self
        start()
    }

    func deactivate() {
        if MiddleClickSession.activeSession === self {
            MiddleClickSession.activeSession = nil
        }
        stop()
    }
}
