import AppKit
import AuleumKit

extension AppDelegate {
    // MARK: - 系统事件

    func setupSystemObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionResigned),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionActivated),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    @objc func systemWillSleep() {
        systemAsleep = true
        // 睡眠期间主线程会停摆；先停看门狗，唤醒后重新计时，避免误判卡死。
        healthWatchdog?.stop()
        if state == .authenticating {
            cancelAuthentication()
        }
        coverRecoveryItem?.cancel()
        coverRecoveryItem = nil
        guard veilOn else { return }
        audit.write("system_sleep", ["action": "veil_kept"])
    }

    @objc func systemDidWake() {
        systemAsleep = false
        screensAsleepWithClamshell = false
        if veilOn {
            recoverVeilLayers()
        }
        if globalHotkey?.isActive != true {
            startGlobalHotkeyIfPermitted()
        }
    }

    /// 未授权时不要创建事件 tap：CGEventTap 会触发 macOS 自己的 TCC 同意框。
    /// 用户从授权浮窗完成授权后，onAllGranted 会再次调用这里。
    func startGlobalHotkeyIfPermitted() {
        guard Permissions.hasAccessibility() else { return }
        if globalHotkey?.start() == false {
            NSLog("Auleum: global hotkey monitor could not be started")
        }
        for (scene, hotkey) in sceneHotkeys where hotkey.start() == false {
            NSLog(
                "Auleum: scene hotkey monitor could not be started: \(scene.rawValue)"
            )
        }
    }

    @objc func sessionResigned() {
        // 锁屏、快速切换用户或注销时保留幕帘状态，但先移除覆盖层，
        // 让系统登录界面可见；解锁后由 sessionActivated 重新补涂。
        sessionInactive = true
        healthWatchdog?.stop()
        if state == .authenticating {
            cancelAuthentication()
        }
        coverRecoveryItem?.cancel()
        coverRecoveryItem = nil
        guard veilOn else { return }
        // 登录界面必须能接收密码；解锁后由 recoverInputGuard 重新挂 tap。
        inputGuard.setEnabled(false)
        inputGuard.stop()
        presentation?.close()
        shield?.lower()
        audit.write("session_resigned", ["action": "veil_suspended_for_lock"])
    }

    @objc func sessionActivated() {
        sessionInactive = false
        systemAsleep = false
        guard veilOn else {
            if globalHotkey?.isActive != true {
                startGlobalHotkeyIfPermitted()
            }
            return
        }
        audit.write("session_activated", ["action": "veil_reapply"])
        recoverVeilLayers()
        if globalHotkey?.isActive != true {
            startGlobalHotkeyIfPermitted()
        }
    }

    @objc func screensDidSleep() {
        guard veilOn else { return }
        audit.write("screens_sleep", ["action": "veil_kept"])
        if config.clamshellModeEnabled {
            screensAsleepWithClamshell = true
            audit.write("screens_sleep_kept_for_clamshell", [:])
        }
    }

    @objc func screensDidWake() {
        systemAsleep = false
        if veilOn {
            recoverVeilLayers()
        }
        screensAsleepWithClamshell = false
    }

    // MARK: - 生命周期保障

    func setupSignalHandling() {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        signal(SIGPIPE, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.teardown()
            exit(1)
        }
        source.resume()
        signalSource = source

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSource.setEventHandler { [weak self] in
            self?.teardown()
            exit(1)
        }
        intSource.resume()
        intSignalSource = intSource
    }

    func setupHealthWatchdog() {
        let watchdog = HealthWatchdog()
        watchdog.repeatInterval = 5
        watchdog.check = { [weak self] in
            guard let self else { return "auleumd 已退出" }
            if !Permissions.hasAccessibility() {
                return "「设备控制和数据访问」权限已撤销"
            }
            if !Permissions.hasScreenRecording() {
                return "「录屏与系统录音」权限已撤销"
            }
            if !self.inputGuard.healthCheck() {
                return "输入拦截 tap 已失效且无法恢复"
            }
            return nil
        }
        watchdog.onFailure = { [weak self] reason in
            self?.handleHealthFailure(reason)
        }
        watchdog.onHealthy = { [weak self] in
            self?.refreshVeilHealth()
        }
        watchdog.onMainThreadStalled = {
            NSLog("Auleum: main thread stalled; terminating to restore input and screen")
            exit(70)
        }
        healthWatchdog = watchdog
    }

    /// 失败路径不再撤幕：保持遮挡，记录降级并持续重试。
    /// 只有 Touch ID、panic 或进程退出会真正移除幕帘。
    func handleHealthFailure(_ reason: String) {
        guard state.isOn, !systemAsleep, !sessionInactive else { return }

        // 权限齐全时优先原地重挂输入 tap；缺权限时不要创建 tap，
        // 否则会触发 macOS 自己的 TCC 同意框。
        if recoverInputGuard() {
            if shouldAuditFailure("health_recovered") {
                audit.write("health_failure", [
                    "reason": reason,
                    "action": "input_recovered",
                ])
            }
            refreshVeilHealth()
            return
        }

        if shouldAuditFailure("health") {
            audit.write("health_failure", [
                "reason": reason,
                "action": "veil_kept",
            ])
            markVeilDegraded(reason: reason)
            showFailureHint(
                "输入拦截失效；幕帘保持遮挡。请修复权限，或使用 auleumctl panic 应急撤幕"
            )
        }
    }

    func handleShieldFailure(_ reason: String) {
        guard state.isOn, !systemAsleep, !sessionInactive else { return }
        if shouldAuditFailure("shield") {
            audit.write("shield_failure", [
                "reason": reason,
                "action": "veil_kept",
            ])
            showFailureHint(
                "输出层幕帘失效；幕帘状态保持并重试。请修复权限，或使用 auleumctl panic 应急撤幕"
            )
        }
        markVeilDegraded(reason: reason)
        scheduleCoverRecovery()
    }

    func handlePresentationFailure(_ reason: String) {
        guard state.isOn, !systemAsleep, !sessionInactive else { return }
        if shouldAuditFailure("presentation") {
            audit.write("presentation_failure", [
                "reason": reason,
                "action": "veil_kept",
            ])
            showFailureHint(
                "展示窗口失效；幕帘状态保持并重试。请修复权限，或使用 auleumctl panic 应急撤幕"
            )
        }
        markVeilDegraded(reason: reason)
        scheduleCoverRecovery()
    }

    // MARK: - 降级与恢复

    @discardableResult
    func recoverInputGuard() -> Bool {
        guard !systemAsleep, !sessionInactive else { return false }
        guard Permissions.hasAccessibility(), Permissions.hasScreenRecording() else {
            return false
        }
        guard inputGuard.start() else { return false }
        inputGuard.setEnabled(true)
        if state == .authenticating {
            if authMethod == .password {
                inputGuard.setPasswordAuthenticationMode(true)
            } else {
                inputGuard.setAuthenticationMode(true)
            }
        }
        return true
    }

    /// 唤醒、解锁、权限恢复后重新补涂所有遮挡层；失败时只降级，不撤幕。
    func recoverVeilLayers() {
        // 睡眠中或锁屏界面还在时不要重新盖住，避免把登录界面涂黑。
        guard state.isOn, !systemAsleep, !sessionInactive else { return }
        coverRecoveryAttempts = 0
        // 先把画面盖回去，再恢复物理输入拦截。
        screensChanged()
        _ = recoverInputGuard()
        if veilOn {
            healthWatchdog?.start()
        }
        refreshVeilHealth()
    }

    /// 输入与覆盖都健康后才清除降级标记。
    func refreshVeilHealth() {
        guard state.isOn, !systemAsleep, !sessionInactive else { return }
        let permissionsOK = Permissions.hasAccessibility()
            && Permissions.hasScreenRecording()
        let inputOK = inputGuard.isEnabled && inputGuard.healthCheck()
        if permissionsOK && inputOK && currentCoverComplete() {
            clearVeilDegraded()
        }
    }

    func currentCoverComplete() -> Bool {
        let screens = ScreenInventory.current()
        guard !screens.isEmpty else { return false }
        var presentationIDs = Set<CGDirectDisplayID>()
        var blackIDs = Set<CGDirectDisplayID>()
        for screen in screens {
            switch effectiveDisplayRole(isMain: screen.isMain) {
            case .presentation:
                presentationIDs.insert(screen.displayID)
            case .black:
                blackIDs.insert(screen.displayID)
            }
        }
        if !presentationIDs.isEmpty,
           !presentationIDs.isSubset(of: presentation.displayIDs) {
            return false
        }
        if !blackIDs.isEmpty,
           (!shield.isUp || !blackIDs.isSubset(of: shield.displayIDs)) {
            return false
        }
        return true
    }

    /// 覆盖失败后最多补涂三轮（0.25s / 1s / 3s），之后等待显示器事件或下次唤醒。
    func scheduleCoverRecovery() {
        coverRecoveryItem?.cancel()
        guard state.isOn, !systemAsleep, !sessionInactive,
              coverRecoveryAttempts < 3 else { return }
        let attempt = coverRecoveryAttempts
        coverRecoveryAttempts += 1
        let delays: [TimeInterval] = [0.25, 1, 3]
        let delay = delays[min(attempt, delays.count - 1)]
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state.isOn else { return }
            self.screensChanged()
        }
        coverRecoveryItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func markVeilDegraded(reason: String) {
        lastVeilFailureReason = reason
        if !veilDegraded {
            veilDegraded = true
            audit.write("veil_degraded", ["reason": reason])
        }
        updateStatusItem()
    }

    func clearVeilDegraded() {
        coverRecoveryAttempts = 0
        failureAuditTimes.removeAll()
        lastVeilFailureReason = nil
        guard veilDegraded else { return }
        veilDegraded = false
        audit.write("veil_recovered", [:])
        updateStatusItem()
    }

    func shouldAuditFailure(_ key: String, cooldown: TimeInterval = 60) -> Bool {
        let now = Date()
        if let last = failureAuditTimes[key],
           now.timeIntervalSince(last) < cooldown {
            return false
        }
        failureAuditTimes[key] = now
        return true
    }

    func showFailureHint(_ text: String) {
        guard presentation?.isActive == true else { return }
        presentation.showReturnHint(text, duration: 60)
    }

    func veilStateString() -> String {
        onMain { self.veilOn ? "on" : "off" }
    }

    func onMain<T>(_ body: () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
    }
}
