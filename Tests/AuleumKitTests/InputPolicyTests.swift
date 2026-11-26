import CoreGraphics
import Foundation
import Testing
@testable import AuleumKit

@Suite("Input policy")
struct InputPolicyTests {
    private func disposition(
        origin: InputOrigin,
        rawEventType: UInt32 = CGEventType.keyDown.rawValue,
        keyCode: Int64? = 0,
        isRepeat: Bool = false,
        enabled: Bool = true,
        remoteMode: Bool = false,
        authenticationMode: Bool = false,
        passwordAuthentication: Bool = false
    ) -> InputDisposition {
        InputPolicy.disposition(
            rawEventType: rawEventType,
            keyCode: keyCode,
            isRepeat: isRepeat,
            origin: origin,
            isEnabled: enabled,
            remoteMode: remoteMode,
            authenticationMode: authenticationMode,
            passwordAuthentication: passwordAuthentication
        )
    }

    @Test("Origin requires HID state and no software marker")
    func originClassification() {
        #expect(InputPolicy.origin(
            sourcePID: 0,
            sourceStateID: 1
        ) == .physical)
        #expect(InputPolicy.origin(
            sourcePID: 0,
            sourceStateID: 1,
            sourceUserData: 100
        ) == .synthetic)
        #expect(InputPolicy.origin(
            sourcePID: 0,
            sourceStateID: 0
        ) == .synthetic)
        #expect(InputPolicy.origin(
            sourcePID: 4242,
            sourceStateID: 1
        ) == .synthetic)
        #expect(InputPolicy.origin(
            sourcePID: 4242,
            sourceStateID: 1,
            isRemoteProcess: true
        ) == .remoteProcess)
        #expect(InputPolicy.origin(
            sourcePID: 4242,
            sourceStateID: 1,
            isRemoteProcess: true,
            isDeniedProcess: true
        ) == .deniedProcess)
        #expect(InputPolicy.origin(
            sourcePID: 0,
            sourceStateID: 1,
            isVirtualDevice: true
        ) == .virtualDevice)
        #expect(InputPolicy.origin(
            sourcePID: 0,
            sourceStateID: 1,
            isVirtualDevice: true,
            isDeniedVirtualDevice: true
        ) == .deniedVirtualDevice)
        #expect(InputPolicy.origin(
            sourcePID: 0,
            sourceStateID: 0,
            isVirtualDevice: true
        ) == .synthetic)
    }

    @Test("Physical keyboard and mouse are blocked")
    func physicalInputIsBlocked() {
        #expect(disposition(origin: .physical) == .block)
        #expect(disposition(
            origin: .physical,
            rawEventType: CGEventType.leftMouseDown.rawValue,
            keyCode: nil
        ) == .block)
    }

    @Test("Synthetic and remote process input passes through")
    func syntheticInputPasses() {
        #expect(disposition(origin: .synthetic) == .pass)
        #expect(disposition(origin: .remoteProcess) == .pass)
        #expect(disposition(
            origin: .synthetic,
            rawEventType: CGEventType.leftMouseDown.rawValue,
            keyCode: nil
        ) == .pass)
    }

    @Test("Denied processes stay blocked")
    func deniedProcessIsBlocked() {
        #expect(disposition(origin: .deniedProcess) == .block)
        #expect(disposition(
            origin: .deniedProcess,
            remoteMode: true
        ) == .block)
    }

    @Test("Virtual HID devices only pass in remote mode")
    func virtualDevicePolicy() {
        #expect(disposition(origin: .virtualDevice) == .block)
        #expect(disposition(
            origin: .virtualDevice,
            remoteMode: true
        ) == .pass)
        #expect(disposition(
            origin: .deniedVirtualDevice,
            remoteMode: true
        ) == .block)
    }

    @Test("Touch ID hold only starts from a physical Esc down")
    func escapeHoldIsPhysicalOnly() {
        #expect(disposition(
            origin: .physical,
            keyCode: 53
        ) == .beginHold)
        #expect(disposition(
            origin: .physical,
            keyCode: 53,
            isRepeat: true
        ) == .block)
        #expect(disposition(
            origin: .physical,
            rawEventType: CGEventType.keyUp.rawValue,
            keyCode: 53
        ) == .cancelHold)
        #expect(disposition(
            origin: .synthetic,
            keyCode: 53
        ) == .pass)
        #expect(disposition(
            origin: .virtualDevice,
            keyCode: 53,
            remoteMode: true
        ) == .pass)
    }

    @Test("System gesture stream is blocked in strict mode and passed remotely")
    func gesturesAreBlocked() {
        #expect(disposition(
            origin: .synthetic,
            rawEventType: 30,
            keyCode: nil
        ) == .block)
        #expect(disposition(
            origin: .synthetic,
            rawEventType: 30,
            keyCode: nil,
            remoteMode: true
        ) == .pass)
    }

    @Test("Authentication mode blocks physical input but leaves synthetic input alone")
    func authenticationModeBlocksPhysicalInput() {
        #expect(disposition(
            origin: .physical,
            authenticationMode: true
        ) == .block)
        #expect(disposition(
            origin: .physical,
            rawEventType: CGEventType.leftMouseDown.rawValue,
            keyCode: nil,
            authenticationMode: true
        ) == .block)
        #expect(disposition(
            origin: .physical,
            rawEventType: CGEventType.keyUp.rawValue,
            keyCode: 53,
            authenticationMode: true
        ) == .block)
        #expect(disposition(
            origin: .synthetic,
            authenticationMode: true
        ) == .pass)
        #expect(disposition(
            origin: .remoteProcess,
            authenticationMode: true
        ) == .pass)
        #expect(disposition(
            origin: .synthetic,
            rawEventType: 30,
            keyCode: nil,
            authenticationMode: true
        ) == .block)
        #expect(disposition(
            origin: .synthetic,
            rawEventType: 30,
            keyCode: nil,
            remoteMode: true,
            authenticationMode: true
        ) == .pass)
    }

    @Test("Password auth passes trusted input but blocks agent injection")
    func passwordAuthInputPolicy() {
        #expect(disposition(
            origin: .physical,
            authenticationMode: true,
            passwordAuthentication: true
        ) == .pass)
        #expect(disposition(
            origin: .physical,
            rawEventType: CGEventType.leftMouseDown.rawValue,
            keyCode: nil,
            authenticationMode: true,
            passwordAuthentication: true
        ) == .pass)
        #expect(disposition(
            origin: .synthetic,
            authenticationMode: true,
            passwordAuthentication: true
        ) == .block)
        #expect(disposition(
            origin: .remoteProcess,
            authenticationMode: true,
            passwordAuthentication: true
        ) == .block)
        #expect(disposition(
            origin: .remoteProcess,
            remoteMode: true,
            authenticationMode: true,
            passwordAuthentication: true
        ) == .pass)
        #expect(disposition(
            origin: .virtualDevice,
            remoteMode: true,
            authenticationMode: true,
            passwordAuthentication: true
        ) == .pass)
        #expect(disposition(
            origin: .virtualDevice,
            authenticationMode: true,
            passwordAuthentication: true
        ) == .block)
        #expect(disposition(
            origin: .deniedProcess,
            remoteMode: true,
            authenticationMode: true,
            passwordAuthentication: true
        ) == .block)
        #expect(disposition(
            origin: .synthetic,
            rawEventType: 30,
            keyCode: nil,
            authenticationMode: true,
            passwordAuthentication: true
        ) == .block)
    }

    @Test("Remote sources can start exit gestures only in remote mode")
    func exitGestureOrigins() {
        #expect(InputPolicy.canTriggerExitGesture(
            origin: .physical,
            remoteMode: false
        ))
        #expect(!InputPolicy.canTriggerExitGesture(
            origin: .remoteProcess,
            remoteMode: false
        ))
        #expect(InputPolicy.canTriggerExitGesture(
            origin: .remoteProcess,
            remoteMode: true
        ))
        #expect(!InputPolicy.canTriggerExitGesture(
            origin: .virtualDevice,
            remoteMode: false
        ))
        #expect(InputPolicy.canTriggerExitGesture(
            origin: .virtualDevice,
            remoteMode: true
        ))
        #expect(!InputPolicy.canTriggerExitGesture(
            origin: .synthetic,
            remoteMode: true
        ))
        #expect(!InputPolicy.canTriggerExitGesture(
            origin: .deniedProcess,
            remoteMode: true
        ))
        #expect(!InputPolicy.canTriggerExitGesture(
            origin: .deniedVirtualDevice,
            remoteMode: true
        ))
    }

    @Test("Disabled guard passes everything")
    func disabledGuardPasses() {
        #expect(disposition(
            origin: .physical,
            enabled: false
        ) == .pass)
        #expect(disposition(
            origin: .deniedVirtualDevice,
            rawEventType: 30,
            keyCode: nil,
            enabled: false
        ) == .pass)
    }
}

@Suite("Auleum state")
struct AuleumStateTests {
    @Test("Only active and authenticating states are on")
    func onStates() {
        #expect(!AuleumState.idle.isOn)
        #expect(AuleumState.active.isOn)
        #expect(AuleumState.authenticating.isOn)
        #expect(!AuleumState.active.isAuthenticating)
        #expect(AuleumState.authenticating.isAuthenticating)
    }
}

@Suite("Escape exit gesture")
struct DoubleEscapeRecognizerTests {
    @Test("Two presses inside the window trigger once")
    func doublePressFires() {
        var recognizer = DoubleEscapeRecognizer()
        let start = Date()
        let first = recognizer.registerDown(at: start, window: 0.7)
        #expect(!first)
        let second = recognizer.registerDown(at: start.addingTimeInterval(0.5), window: 0.7)
        #expect(second)
        let third = recognizer.registerDown(at: start.addingTimeInterval(1.0), window: 0.7)
        #expect(!third)
    }

    @Test("A slow second press starts a new window")
    func slowPressDoesNotFire() {
        var recognizer = DoubleEscapeRecognizer()
        let start = Date()
        let first = recognizer.registerDown(at: start, window: 0.7)
        #expect(!first)
        let second = recognizer.registerDown(at: start.addingTimeInterval(0.8), window: 0.7)
        #expect(!second)
        let third = recognizer.registerDown(at: start.addingTimeInterval(1.2), window: 0.7)
        #expect(third)
    }

    @Test("Reset discards the pending first press")
    func resetDiscards() {
        var recognizer = DoubleEscapeRecognizer()
        let start = Date()
        let first = recognizer.registerDown(at: start, window: 0.7)
        #expect(!first)
        recognizer.reset()
        let afterReset = recognizer.registerDown(at: start.addingTimeInterval(0.2), window: 0.7)
        #expect(!afterReset)
    }
}

@Suite("Global hotkey")
struct GlobalHotkeyTests {
    @Test("Only physical ctrl-option-command-C matches")
    func hotkeyMatching() {
        let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        #expect(HotkeyPolicy.matches(
            eventKeyCode: HotkeyPolicy.keyCode,
            flags: modifiers,
            sourcePID: 0
        ))
        #expect(!HotkeyPolicy.matches(
            eventKeyCode: HotkeyPolicy.keyCode,
            flags: modifiers,
            sourcePID: 4242
        ))
        #expect(!HotkeyPolicy.matches(
            eventKeyCode: HotkeyPolicy.keyCode,
            flags: modifiers,
            sourcePID: 0,
            sourceStateID: 0
        ))
        #expect(!HotkeyPolicy.matches(
            eventKeyCode: HotkeyPolicy.keyCode,
            flags: [.maskControl, .maskCommand],
            sourcePID: 0
        ))
        #expect(!HotkeyPolicy.matches(
            eventKeyCode: HotkeyPolicy.keyCode,
            flags: modifiers.union(.maskShift),
            sourcePID: 0
        ))
    }

    @Test("Remote sources match the exit hotkey without HID source fields")
    func injectedHotkeyMatching() {
        let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        #expect(HotkeyPolicy.matchesIgnoringSource(
            eventKeyCode: HotkeyPolicy.keyCode,
            flags: modifiers
        ))
        #expect(!HotkeyPolicy.matchesIgnoringSource(
            eventKeyCode: HotkeyPolicy.keyCode,
            flags: [.maskControl, .maskCommand]
        ))
        #expect(!HotkeyPolicy.matchesIgnoringSource(
            eventKeyCode: 1,
            flags: modifiers
        ))
    }

    @Test("Custom binding matches only its own key and modifiers")
    func customBindingMatching() {
        let custom: CGEventFlags = [.maskControl, .maskShift]
        #expect(HotkeyPolicy.matches(
            eventKeyCode: 1,
            flags: custom,
            sourcePID: 0,
            expectedKeyCode: 1,
            expectedModifiers: custom
        ))
        #expect(!HotkeyPolicy.matches(
            eventKeyCode: 1,
            flags: [.maskControl, .maskShift, .maskAlternate],
            sourcePID: 0,
            expectedKeyCode: 1,
            expectedModifiers: custom
        ))
        #expect(!HotkeyPolicy.matches(
            eventKeyCode: HotkeyPolicy.keyCode,
            flags: HotkeyPolicy.modifiers,
            sourcePID: 0,
            expectedKeyCode: 1,
            expectedModifiers: custom
        ))
    }

    @Test("Binding validation requires a normal key and a non-shift modifier")
    func bindingValidation() {
        #expect(HotkeyBinding(keyCode: 8, modifiers: [.maskCommand]).isValid)
        #expect(!HotkeyBinding(keyCode: 8, modifiers: [.maskShift]).isValid)
        #expect(!HotkeyBinding(keyCode: 8, modifiers: []).isValid)
        #expect(!HotkeyBinding(keyCode: 999, modifiers: [.maskCommand]).isValid)
    }

    @Test("Display string is stable")
    func displayString() {
        #expect(HotkeyPolicy.displayString(
            keyCode: HotkeyPolicy.keyCode,
            modifiers: HotkeyPolicy.modifiers
        ) == "⌃⌥⌘C")
    }
}

@Suite("Event tap recovery")
struct ReenableCircuitBreakerTests {
    @Test("Five rapid re-enables trip the breaker")
    func tripsAfterRepeatedFailures() {
        var breaker = ReenableCircuitBreaker()
        let start = Date()
        for index in 0..<4 {
            let tripped = breaker.recordAttempt(at: start.addingTimeInterval(Double(index) * 0.5))
            #expect(!tripped)
        }
        let tripped = breaker.recordAttempt(at: start.addingTimeInterval(2))
        #expect(tripped)
        #expect(breaker.isTripped)
    }

    @Test("A slow re-enable outside the window starts a fresh count")
    func oldFailuresDoNotAccumulate() {
        var breaker = ReenableCircuitBreaker()
        let start = Date()
        var tripped = breaker.recordAttempt(at: start)
        #expect(!tripped)
        tripped = breaker.recordAttempt(at: start.addingTimeInterval(11))
        #expect(!tripped)
        tripped = breaker.recordAttempt(at: start.addingTimeInterval(22))
        #expect(!tripped)
        #expect(!breaker.isTripped)
    }

    @Test("A long stable period resets a tripped breaker")
    func stablePeriodResetsBreaker() {
        var breaker = ReenableCircuitBreaker()
        let start = Date()
        for _ in 0..<5 {
            _ = breaker.recordAttempt(at: start)
        }
        #expect(breaker.isTripped)
        var reset = breaker.resetIfStable(at: start.addingTimeInterval(29))
        #expect(!reset)
        reset = breaker.resetIfStable(at: start.addingTimeInterval(31))
        #expect(reset)
        #expect(!breaker.isTripped)
    }
}
