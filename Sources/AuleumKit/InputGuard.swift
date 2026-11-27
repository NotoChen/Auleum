import AppKit
import CoreGraphics
import Foundation

/// 输入事件的纯策略层，便于单测。真正的 tap 只负责把系统事件翻译成这里的结论。
public enum InputDisposition: Equatable {
    case pass
    case block
    case beginHold
    case cancelHold
}

/// 输入来源。区分物理设备、远控进程、普通合成输入和虚拟 HID 设备。
/// 只有 `.physical` 会触发 Esc 手势/全局快捷键，也只有它始终被拦截。
public enum InputOrigin: Equatable {
    case physical
    /// 来自已知远控工具的进程（CGEventPost，来源 PID 非 0）。
    case remoteProcess
    /// 其他合成输入，或 PID 0 但 stateID 不是 HID system 的事件。
    case synthetic
    /// PID 0、stateID 1，但底层是虚拟 HID 设备。
    case virtualDevice
    case deniedProcess
    case deniedVirtualDevice
}

/// 只用于诊断的计数；帮助判断远控键鼠最终被归为哪一类。
public struct InputGuardCounters: Equatable, Sendable {
    public var physicalBlocked = 0
    public var remotePassed = 0
    public var virtualPassed = 0
    public var virtualBlocked = 0
    public var deniedBlocked = 0

    public init() {}
}

public enum InputPolicy {
    /// CoreGraphics 没有公开的 CGEventType case，但它们会出现在 session 事件流里：
    /// 旋转/缩放手势、Dock 的 Space/Mission Control 控制流、三指滑动等。
    /// 30 与 NSEvent.magnify 共用原始值，必须按 Dock control 处理。
    public static let gestureEventRawValues: Set<UInt32> = [18, 19, 20, 29, 30, 31, 32]

    public static func isGesture(rawValue: UInt32) -> Bool {
        gestureEventRawValues.contains(rawValue)
    }

    /// 物理事件必须同时满足 PID 0 和 HID system state；只满足其一的事件
    /// 是合成/远程注入。`eventSourceUserData` 非 0 是软件设置的标记，
    /// 也按合成输入处理（RustDesk 等会用它标记自己注入的输入）。
    public static func origin(sourcePID: Int32,
                              sourceStateID: Int64,
                              sourceUserData: Int64 = 0,
                              isRemoteProcess: Bool = false,
                              isDeniedProcess: Bool = false,
                              isVirtualDevice: Bool = false,
                              isDeniedVirtualDevice: Bool = false) -> InputOrigin {
        if sourcePID != 0 {
            if isDeniedProcess { return .deniedProcess }
            if isRemoteProcess { return .remoteProcess }
            return .synthetic
        }
        guard sourceStateID == Int64(CGEventSourceStateID.hidSystemState.rawValue) else {
            return .synthetic
        }
        guard sourceUserData == 0 else { return .synthetic }
        if isVirtualDevice {
            return isDeniedVirtualDevice ? .deniedVirtualDevice : .virtualDevice
        }
        return .physical
    }

    /// 物理输入一律拦；远程进程和普通合成输入放行。
    /// 虚拟 HID 设备只有在远程兼容模式下放行，避免本机 Karabiner 之类的
    /// 重映射设备绕过物理输入拦截。
    /// Esc 长按/双击和撤幕快捷键允许哪些来源触发。远程模式下已知远控进程
    /// 和虚拟 HID 也可以发起验证，最终仍要过 Touch ID 或密码。普通合成
    /// 输入不参与，避免本机 Agent 误触认证面板。
    public static func canTriggerExitGesture(origin: InputOrigin,
                                             remoteMode: Bool) -> Bool {
        switch origin {
        case .physical:
            return true
        case .remoteProcess, .virtualDevice:
            return remoteMode
        case .synthetic, .deniedProcess, .deniedVirtualDevice:
            return false
        }
    }

    public static func disposition(rawEventType: UInt32,
                                   keyCode: Int64?,
                                   isRepeat: Bool,
                                   origin: InputOrigin,
                                   isEnabled: Bool,
                                   remoteMode: Bool = false,
                                   authenticationMode: Bool = false,
                                   passwordAuthentication: Bool = false) -> InputDisposition {
        guard isEnabled else { return .pass }
        if isGesture(rawValue: rawEventType) {
            // 系统手势没有可靠的来源，严格模式下全部拦；远程模式下远控
            // 用户需要双指滚动/切换 Space，放行由系统自行处理。
            return remoteMode ? .pass : .block
        }
        if authenticationMode {
            if passwordAuthentication {
                // 系统密码面板需要物理键盘和鼠标。远程模式下也允许已知远控
                // 来源输入密码；普通合成输入仍然拦截，避免同用户 Agent 代输。
                switch origin {
                case .physical:
                    return .pass
                case .remoteProcess, .virtualDevice:
                    return remoteMode ? .pass : .block
                case .synthetic, .deniedProcess, .deniedVirtualDevice:
                    return .block
                }
            }
            // Touch ID 使用独立硬件，认证面板不需要键盘或鼠标输入。
            // 远程模式下远控输入继续放行，但不会触发 Touch ID。
            switch origin {
            case .physical:
                return .block
            case .remoteProcess, .synthetic:
                return .pass
            case .virtualDevice:
                return remoteMode ? .pass : .block
            case .deniedProcess, .deniedVirtualDevice:
                return .block
            }
        }
        switch origin {
        case .deniedProcess, .deniedVirtualDevice:
            return .block
        case .remoteProcess, .synthetic:
            return .pass
        case .virtualDevice:
            return remoteMode ? .pass : .block
        case .physical:
            if rawEventType == CGEventType.keyDown.rawValue, keyCode == 53, !isRepeat {
                return .beginHold
            }
            if rawEventType == CGEventType.keyUp.rawValue, keyCode == 53 {
                return .cancelHold
            }
            return .block
        }
    }
}

struct DoubleEscapeRecognizer {
    private var lastDownAt: Date?

    /// 返回 true 表示这是窗口内的第二次按下，应触发退出。
    mutating func registerDown(at now: Date = Date(), window: TimeInterval) -> Bool {
        let boundedWindow = max(0.1, window)
        if let lastDownAt, now.timeIntervalSince(lastDownAt) <= boundedWindow {
            self.lastDownAt = nil
            return true
        }
        lastDownAt = now
        return false
    }

    mutating func reset() {
        lastDownAt = nil
    }
}

/// 系统可能因为回调超时或输入压力反复禁用事件 tap。无限重试会让界面看起来
/// 仍在保护，实际物理输入却可能漏过去；这里用一个短窗口熔断，交给上层撤幕。
struct ReenableCircuitBreaker {
    static let threshold = 5
    static let window: TimeInterval = 10
    static let stableResetInterval: TimeInterval = 30

    private var attempts = 0
    private var windowStart: Date?
    private var lastAttempt: Date?
    private(set) var isTripped = false

    mutating func recordAttempt(at now: Date = Date()) -> Bool {
        if let windowStart, now.timeIntervalSince(windowStart) <= Self.window {
            attempts += 1
        } else {
            self.windowStart = now
            attempts = 1
        }
        lastAttempt = now
        if attempts >= Self.threshold {
            isTripped = true
        }
        return isTripped
    }

    mutating func resetIfStable(at now: Date = Date()) -> Bool {
        guard let lastAttempt,
              now.timeIntervalSince(lastAttempt) >= Self.stableResetInterval else {
            return false
        }
        attempts = 0
        windowStart = nil
        self.lastAttempt = nil
        isTripped = false
        return true
    }
}

/// HID 级事件拦截。
/// 规则：真实物理输入（PID 0 + HID state + 无软件标记）吞掉；合成事件放行；
/// 已知远控进程放行；虚拟 HID 设备只在远程兼容模式下放行；系统手势流单独拦。
/// 同时负责「长按 Esc」手势，触发 Touch ID。
public final class InputGuard {
    public var holdToAuthSeconds: Double = 2.0
    /// 两次物理 Esc 在这个窗口内按下时直接触发退出，不需要长按。
    public var doubleEscapeSeconds: Double = 0.7
    /// 幕帘期间的撤幕快捷键，必须和 GlobalHotkey 使用同一个绑定。
    public var exitHotkeyKeyCode: Int64 = HotkeyPolicy.keyCode
    public var exitHotkeyModifiers: CGEventFlags = HotkeyPolicy.modifiers
    public var onHoldEscape: ((InputOrigin) -> Void)?
    /// 幕帘期间再次按起幕快捷键时调用。
    public var onExitHotkey: ((InputOrigin) -> Void)?
    /// Touch ID 面板显示期间再次按物理 Esc 时取消认证。
    public var onCancelAuthentication: (() -> Void)?
    /// tap 被系统禁用且无法恢复时调用。调用方应尽快撤幕。
    public var onTapUnavailable: (() -> Void)?
    /// 幕帘期间检测到真实 HID 输入时调用。只用于低频界面提示，不参与授权。
    public var onPhysicalInteraction: (() -> Void)?
    /// 已知远控进程查询。由 AppDelegate 接到 RemoteProcessRegistry。
    public var remoteProcessLookup: ((Int32) -> Bool)?
    /// 已知需要拦截的虚拟 HID/重映射进程查询。
    public var deniedProcessLookup: ((Int32) -> Bool)?
    /// 虚拟 HID 设备识别（私有 SPI，失败时返回 nil）。
    public var deviceInspector: HIDDeviceInspector?

    /// 认证期间物理输入的放行方式。Touch ID 卡片不需要键鼠，
    /// 系统密码面板则必须收到物理键盘和鼠标。
    private enum AuthenticationInputMode {
        case none
        case biometrics
        case password
    }

    private let lock = NSLock()
    private let interactionLock = NSLock()
    private var _isEnabled = false
    private var _remoteMode = false
    private var inputCounters = InputGuardCounters()
    private var authenticationInputMode = AuthenticationInputMode.none
    private var tap: CFMachPort?
    private var gestureTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gestureRunLoopSource: CFRunLoopSource?
    private var holdWorkItem: DispatchWorkItem?
    private var escDown = false
    private var escapeTap = DoubleEscapeRecognizer()
    private var failureReported = false
    private var reenableBreaker = ReenableCircuitBreaker()
    private var lastPhysicalInteractionAt: TimeInterval = -.greatestFiniteMagnitude

    public init() {}

    public var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isEnabled
    }

    public var remoteMode: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _remoteMode
        }
        set {
            setRemoteMode(newValue)
        }
    }

    public func setRemoteMode(_ on: Bool) {
        lock.lock()
        let changed = _remoteMode != on
        _remoteMode = on
        lock.unlock()
        if changed, on {
            // 切换模式时丢弃正在进行的 Esc 手势，避免旧状态跨模式触发验证。
            escDown = false
            escapeTap.reset()
            cancelHold()
        }
    }

    public func counters() -> InputGuardCounters {
        lock.lock()
        defer { lock.unlock() }
        return inputCounters
    }

    public func resetCounters() {
        lock.lock()
        inputCounters = InputGuardCounters()
        lock.unlock()
    }

    public var gesturesProtected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return gestureTap != nil
    }

    @discardableResult
    public func start() -> Bool {
        lock.lock()
        let existingPrimary = tap
        let existingGesture = gestureTap
        lock.unlock()
        let existingReady: Bool
        if let existingPrimary, let existingGesture {
            existingReady = CGEvent.tapIsEnabled(tap: existingPrimary)
                && CGEvent.tapIsEnabled(tap: existingGesture)
        } else {
            existingReady = false
        }
        if existingReady { return true }

        stop()

        guard let primaryTap = makePrimaryTap() else { return false }
        guard let gestureTap = makeGestureTap() else {
            CFMachPortInvalidate(primaryTap)
            return false
        }
        guard let primarySource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, primaryTap, 0),
              let gestureSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gestureTap, 0) else {
            CFMachPortInvalidate(primaryTap)
            CFMachPortInvalidate(gestureTap)
            return false
        }

        lock.lock()
        self.tap = primaryTap
        self.gestureTap = gestureTap
        self.runLoopSource = primarySource
        self.gestureRunLoopSource = gestureSource
        failureReported = false
        reenableBreaker = ReenableCircuitBreaker()
        lock.unlock()

        CFRunLoopAddSource(CFRunLoopGetMain(), primarySource, .commonModes)
        CFRunLoopAddSource(CFRunLoopGetMain(), gestureSource, .commonModes)
        CGEvent.tapEnable(tap: primaryTap, enable: true)
        CGEvent.tapEnable(tap: gestureTap, enable: true)

        guard CGEvent.tapIsEnabled(tap: primaryTap), CGEvent.tapIsEnabled(tap: gestureTap) else {
            stop()
            return false
        }
        return true
    }

    public func setEnabled(_ on: Bool) {
        lock.lock()
        _isEnabled = on
        if !on { authenticationInputMode = .none }
        lock.unlock()
        if !on {
            escDown = false
            escapeTap.reset()
            cancelHold()
        }
    }

    /// Touch ID 面板显示期间，物理键盘/鼠标仍被吞掉；Touch ID 使用独立硬件。
    /// 合成输入继续放行，避免误伤正在执行任务的 Agent。
    /// 传入 `false` 会同时退出密码认证模式。
    public func setAuthenticationMode(_ on: Bool) {
        setAuthenticationInputMode(on ? .biometrics : .none)
    }

    /// 系统密码面板显示期间，物理输入必须送达面板；合成输入一律拦截，
    /// 防止同用户下的 Agent 代替用户输入密码。
    public func setPasswordAuthenticationMode(_ on: Bool) {
        setAuthenticationInputMode(on ? .password : .none)
    }

    private func setAuthenticationInputMode(_ mode: AuthenticationInputMode) {
        lock.lock()
        authenticationInputMode = mode
        lock.unlock()
        if mode != .none {
            escDown = false
            escapeTap.reset()
            cancelHold()
        }
    }

    private var currentAuthenticationInputMode: AuthenticationInputMode {
        lock.lock()
        defer { lock.unlock() }
        return authenticationInputMode
    }

    /// 由后台 watchdog 定期调用。返回 false 表示至少一个 tap 已经无法恢复。
    public func healthCheck() -> Bool {
        lock.lock()
        let enabled = _isEnabled
        let primary = tap
        let gesture = gestureTap
        lock.unlock()

        guard enabled else { return true }
        guard let primary, let gesture else {
            reportUnavailable()
            return false
        }

        for tap in [primary, gesture] where !CGEvent.tapIsEnabled(tap: tap) {
            guard reenable(tap) else {
                reportUnavailable()
                return false
            }
        }
        let ok = CGEvent.tapIsEnabled(tap: primary) && CGEvent.tapIsEnabled(tap: gesture)
        if ok {
            resetFailure()
            lock.lock()
            _ = reenableBreaker.resetIfStable()
            lock.unlock()
        } else {
            reportUnavailable()
        }
        return ok
    }

    public func stop() {
        lock.lock()
        let primary = tap
        let gesture = gestureTap
        let primarySource = runLoopSource
        let gestureSource = gestureRunLoopSource
        tap = nil
        gestureTap = nil
        runLoopSource = nil
        gestureRunLoopSource = nil
        _isEnabled = false
        authenticationInputMode = .none
        failureReported = false
        reenableBreaker = ReenableCircuitBreaker()
        lock.unlock()

        escDown = false
        escapeTap.reset()
        cancelHold()
        if let primary { CGEvent.tapEnable(tap: primary, enable: false) }
        if let gesture { CGEvent.tapEnable(tap: gesture, enable: false) }
        if let primarySource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), primarySource, .commonModes)
        }
        if let gestureSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), gestureSource, .commonModes)
        }
        if let primary { CFMachPortInvalidate(primary) }
        if let gesture { CFMachPortInvalidate(gesture) }
    }

    private func makePrimaryTap() -> CFMachPort? {
        var mask: CGEventMask = 0
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .mouseMoved,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel,
            .tabletPointer, .tabletProximity,
        ]
        for type in types { mask |= (CGEventMask(1) << type.rawValue) }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        return CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let guarder = Unmanaged<InputGuard>.fromOpaque(refcon).takeUnretainedValue()
                return guarder.handlePrimary(type: type, event: event)
            },
            userInfo: userInfo
        )
    }

    private func makeGestureTap() -> CFMachPort? {
        var mask: CGEventMask = 0
        for rawValue in InputPolicy.gestureEventRawValues {
            mask |= (CGEventMask(1) << rawValue)
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        return CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let guarder = Unmanaged<InputGuard>.fromOpaque(refcon).takeUnretainedValue()
                return guarder.handleGesture(type: type, event: event)
            },
            userInfo: userInfo
        )
    }

    private func handlePrimary(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if !reenable(tap) {
                reportUnavailable()
            }
            return nil
        }

        let enabled = isEnabled
        let remoteMode = self.remoteMode
        let sourcePID = Int32(event.getIntegerValueField(.eventSourceUnixProcessID))
        let sourceStateID = event.getIntegerValueField(.eventSourceStateID)
        let sourceUserData = event.getIntegerValueField(.eventSourceUserData)
        let origin = inputOrigin(
            pid: sourcePID,
            stateID: sourceStateID,
            userData: sourceUserData,
            event: event
        )
        let keyCode: Int64? = (type == .keyDown || type == .keyUp)
            ? event.getIntegerValueField(.keyboardEventKeycode)
            : nil
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let authInputMode = currentAuthenticationInputMode
        let authenticationMode = authInputMode != .none
        let passwordAuthentication = authInputMode == .password
        let flags = event.flags

        if enabled, origin == .physical, !authenticationMode, keyCode != 53 {
            notifyPhysicalInteraction()
        }

        let canTriggerExit = enabled && InputPolicy.canTriggerExitGesture(
            origin: origin,
            remoteMode: remoteMode
        )
        if canTriggerExit, let keyCode,
           type == .keyDown || type == .keyUp {
            if authenticationMode, keyCode == 53 {
                if type == .keyDown, !isRepeat {
                    DispatchQueue.main.async { [weak self] in
                        self?.onCancelAuthentication?()
                    }
                }
                return nil
            }

            if !authenticationMode {
                let hotkeyMatches: Bool
                if origin == .physical {
                    hotkeyMatches = HotkeyPolicy.matches(
                        eventKeyCode: keyCode,
                        flags: flags,
                        sourcePID: sourcePID,
                        sourceStateID: sourceStateID,
                        expectedKeyCode: exitHotkeyKeyCode,
                        expectedModifiers: exitHotkeyModifiers
                    )
                } else {
                    // 远控进程和虚拟 HID 的 PID/stateID 不是本机 HID 来源，
                    // 但远程模式下应能用同一个快捷键发起验证。
                    hotkeyMatches = HotkeyPolicy.matchesIgnoringSource(
                        eventKeyCode: keyCode,
                        flags: flags,
                        expectedKeyCode: exitHotkeyKeyCode,
                        expectedModifiers: exitHotkeyModifiers
                    )
                }
                if hotkeyMatches {
                    if type == .keyDown, !isRepeat {
                        DispatchQueue.main.async { [weak self] in
                            self?.onExitHotkey?(origin)
                        }
                    }
                    return nil
                }
            }

            if !authenticationMode, keyCode == 53, type == .keyDown, !isRepeat {
                if escapeTap.registerDown(window: doubleEscapeSeconds) {
                    escDown = false
                    cancelHold()
                    DispatchQueue.main.async { [weak self] in
                        self?.onHoldEscape?(origin)
                    }
                    return nil
                }
            }
        }

        let disposition = InputPolicy.disposition(
            rawEventType: type.rawValue,
            keyCode: keyCode,
            isRepeat: isRepeat,
            origin: origin,
            isEnabled: enabled,
            remoteMode: remoteMode,
            authenticationMode: authenticationMode,
            passwordAuthentication: passwordAuthentication
        )
        record(origin: origin, disposition: disposition)

        switch disposition {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .block:
            return nil
        case .beginHold:
            if !escDown {
                escDown = true
                scheduleHold()
            }
            return nil
        case .cancelHold:
            escDown = false
            cancelHold()
            return nil
        }
    }

    private func record(origin: InputOrigin,
                        disposition: InputDisposition) {
        lock.lock()
        switch disposition {
        case .block:
            switch origin {
            case .physical:
                inputCounters.physicalBlocked += 1
            case .virtualDevice:
                inputCounters.virtualBlocked += 1
            case .deniedProcess, .deniedVirtualDevice:
                inputCounters.deniedBlocked += 1
            case .remoteProcess, .synthetic:
                break
            }
        case .pass:
            switch origin {
            case .remoteProcess:
                inputCounters.remotePassed += 1
            case .virtualDevice:
                inputCounters.virtualPassed += 1
            default:
                break
            }
        case .beginHold, .cancelHold:
            break
        }
        lock.unlock()
    }

    private func inputOrigin(pid: Int32,
                             stateID: Int64,
                             userData: Int64,
                             event: CGEvent) -> InputOrigin {
        let isRemoteProcess = pid != 0
            && (remoteProcessLookup?(pid) ?? false)
        let isDeniedProcess = pid != 0
            && (deniedProcessLookup?(pid) ?? false)
        var isVirtualDevice = false
        var isDeniedVirtualDevice = false
        // 只在远程模式、事件看起来像物理输入时才查设备，避免每个事件都走
        // IORegistry；严格模式下虚拟设备也按物理输入拦，不需要细分。
        if pid == 0,
           stateID == Int64(CGEventSourceStateID.hidSystemState.rawValue),
           userData == 0,
           remoteMode,
           let deviceInspector,
           let identity = deviceInspector.identify(event: event) {
            isVirtualDevice = identity.isVirtual
            isDeniedVirtualDevice = identity.isDeniedVirtualDevice
        }
        return InputPolicy.origin(
            sourcePID: pid,
            sourceStateID: stateID,
            sourceUserData: userData,
            isRemoteProcess: isRemoteProcess,
            isDeniedProcess: isDeniedProcess,
            isVirtualDevice: isVirtualDevice,
            isDeniedVirtualDevice: isDeniedVirtualDevice
        )
    }

    private func handleGesture(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if !reenable(gestureTap) {
                reportUnavailable()
            }
            return nil
        }
        guard isEnabled else { return Unmanaged.passUnretained(event) }
        // 远控用户需要双指滚动/切换 Space；严格模式下仍然吞掉全部手势。
        return remoteMode ? Unmanaged.passUnretained(event) : nil
    }

    private func reenable(_ target: CFMachPort?) -> Bool {
        guard let target else { return false }
        if !CGEvent.tapIsEnabled(tap: target) {
            lock.lock()
            if reenableBreaker.isTripped {
                lock.unlock()
                return false
            }
            let tripped = reenableBreaker.recordAttempt()
            lock.unlock()
            guard !tripped else { return false }
            CGEvent.tapEnable(tap: target, enable: true)
        }
        return CGEvent.tapIsEnabled(tap: target)
    }

    private func scheduleHold() {
        cancelHold()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isEnabled, self.escDown else { return }
            self.onHoldEscape?(.physical)
        }
        holdWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + holdToAuthSeconds, execute: item)
    }

    private func cancelHold() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
    }

    private func reportUnavailable() {
        lock.lock()
        let shouldReport = !failureReported
        failureReported = true
        lock.unlock()
        guard shouldReport else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onTapUnavailable?()
        }
    }

    private func notifyPhysicalInteraction() {
        let now = ProcessInfo.processInfo.systemUptime
        interactionLock.lock()
        guard now - lastPhysicalInteractionAt >= 1 else {
            interactionLock.unlock()
            return
        }
        lastPhysicalInteractionAt = now
        interactionLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.onPhysicalInteraction?()
        }
    }

    private func resetFailure() {
        lock.lock()
        failureReported = false
        lock.unlock()
    }

}
