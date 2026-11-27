import AppKit
import ApplicationServices
import AuleumKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - 运行状态

    var shield: Shield!
    var presentation: PresentationOverlay!
    let presentationPreview = PresentationPreviewSession()
    var inputGuard: InputGuard!
    var auth: AuthGate!
    var authCard: AuthCard?
    var broker: CaptureBroker!
    var recorder: Recorder!
    var sentinel: Sentinel!
    var audit: AuditLog!
    var server: ControlServer!
    var updates: UpdateController!
    var statusItem: NSStatusItem?
    var statusPopover: StatusPopoverController?
    var signalSource: DispatchSourceSignal?
    var intSignalSource: DispatchSourceSignal?

    var config = AuleumConfig.load()
    var state: AuleumState = .idle
    var authGeneration: UInt64 = 0
    var authMethod: AuthMethod = .touchID
    var safetyItem: DispatchWorkItem?
    var protectionItem: DispatchWorkItem?
    var protectionDeadline: Date?
    var sessionProtectionMinutes = 0
    var protectionPrompted = false
    var sessionTrigger: AuleumTrigger = .manual
    var sessionScene: AuleumScene?
    var sessionSceneProfile: AuleumSceneProfile?
    var sessionPresentationEnabled = false
    var sessionMessageOverride: String?
    var didShowReturnHint = false
    var automationTimer: Timer?
    var idleTriggerArmed = true
    var scheduleWasInside = false
    var automationRetryAfter = Date.distantPast
    var screensAsleepWithClamshell = false
    var systemAsleep = false
    var sessionInactive = false
    var healthWatchdog: HealthWatchdog?
    var veilDegraded = false
    var lastVeilFailureReason: String?
    var coverRecoveryItem: DispatchWorkItem?
    var coverRecoveryAttempts = 0
    var failureAuditTimes: [String: Date] = [:]
    var globalHotkey: GlobalHotkey?
    var sceneHotkeys: [AuleumScene: GlobalHotkey] = [:]
    let remoteRegistry = RemoteProcessRegistry()
    var remoteModeOverride: Bool?
    var effectiveRemoteMode = false
    var permissionGuide: PermissionGuideController?
    var settingsWindow: SettingsWindowController?
    var onboardingWindow: OnboardingWindowController?
    var presentationTimer: Timer?
    var singleInstance: SingleInstance?
    var controlServerReady = false
    var didTeardown = false
    var sessionStartedAt: Date?
    var sessionAuthPrompts = 0
    var sessionAuthFailures = 0
    var activeRecordingStartedAt: Date?
    var activeRecordingClient: String?

    var veilOn: Bool { state.isOn }
    var authPending: Bool { state.isAuthenticating }

    // MARK: - 启动与退出

    func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensureSupportDir()

        // 单实例：第二个实例直接退出，避免两个进程抢同一个 socket 和同一块屏。
        let instance = SingleInstance()
        guard instance.acquire() else {
            // 锁被占用时先问一下在跑的那个：能应答就是健康实例，安静退出（
            // launchd 的 RunAtLoad 也会走到这里，不该弹窗打扰用户）。
            if (try? ControlClient.send(ControlRequest(cmd: "status"))) != nil {
                NSApp.terminate(nil)
                return
            }
            NSSound.beep()
            let alert = NSAlert()
            alert.messageText = "Auleum 已经在运行"
            alert.informativeText = "菜单栏里已经有它的图标，但当前实例没有响应。可以先退出旧实例再打开。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        singleInstance = instance
        if !FileManager.default.fileExists(atPath: Paths.configURL.path) {
            _ = config.save()
        } else {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: Paths.configURL.path
            )
        }

        shield = Shield()
        presentation = PresentationOverlay()
        shield.hidesCursor = config.hideCursorDuringVeil
        presentation.hidesCursor = config.hideCursorDuringVeil
        shield.backgroundColor = AuleumColor(hex: config.veilColor) ?? .black
        shield.onUnavailable = { [weak self] message in
            self?.handleShieldFailure(message)
        }
        inputGuard = InputGuard()
        inputGuard.holdToAuthSeconds = config.holdToAuthSeconds
        inputGuard.doubleEscapeSeconds = config.doubleEscapeSeconds
        applyHotkeySettings(to: inputGuard)
        inputGuard.onHoldEscape = { [weak self] origin in
            self?.requestExit(trigger: .escape, inputOrigin: origin)
        }
        inputGuard.onExitHotkey = { [weak self] origin in
            self?.requestExit(trigger: .hotkey, inputOrigin: origin)
        }
        inputGuard.onCancelAuthentication = { [weak self] in self?.cancelAuthentication() }
        inputGuard.onTapUnavailable = { [weak self] in
            self?.handleHealthFailure("输入拦截 tap 已失效")
        }
        inputGuard.onPhysicalInteraction = { [weak self] in
            self?.handleReturnHint()
        }
        inputGuard.remoteProcessLookup = { [weak self] pid in
            self?.remoteRegistry.snapshot().isRemote(pid) ?? false
        }
        inputGuard.deniedProcessLookup = { [weak self] pid in
            self?.remoteRegistry.snapshot().isDenied(pid) ?? false
        }
        inputGuard.deviceInspector = HIDDeviceInspector()
        auth = AuthGate()
        broker = CaptureBroker()
        recorder = Recorder()
        recorder.onUnexpectedStop = { [weak self] message in
            guard let self else { return }
            self.audit.write("record_stream_stopped", ["error": message])
            self.activeRecordingStartedAt = nil
            self.activeRecordingClient = nil
            self.updateStatusItem()
        }
        sentinel = Sentinel()
        sentinel.preventsClamshellSleep = config.clamshellModeEnabled
        audit = AuditLog()
        if let issue = AuleumConfig.lastLoadIssue {
            audit.write("config_load_failed", ["issue": issue])
        }
        remoteRegistry.onChange = { [weak self] _ in
            self?.refreshRemoteMode()
        }
        remoteRegistry.start()

        let version = Bundle.main.infoDictionary?[
            "CFBundleShortVersionString"
        ] as? String ?? "0.0.0"
        let build = Bundle.main.infoDictionary?[
            "CFBundleVersion"
        ] as? String ?? "0"
        updates = UpdateController(currentVersion: version, currentBuild: build)
        updates.isBusy = { [weak self] in
            guard let self else { return true }
            return self.state.isOn
                || self.state.isAuthenticating
                || self.recorder.isRecording
                || self.presentationPreview.isActive
        }
        updates.isAutoCheckEnabled = { [weak self] in
            self?.config.automaticUpdateChecksEnabled ?? true
        }
        updates.isAutoInstallEnabled = { [weak self] in
            self?.config.automaticUpdateInstallsEnabled ?? true
        }
        updates.onStateChange = { [weak self] state in
            self?.updateStateChanged(state)
        }
        updates.onInstallScheduled = { [weak self] in
            guard let self else { return }
            self.teardown()
            NSApp.terminate(nil)
        }
        updates.onAudit = { [weak self] event, details in
            self?.audit.write(event, details)
        }

        setupStatusItem()
        refreshRemoteMode()
        setupSignalHandling()
        setupHealthWatchdog()
        globalHotkey = GlobalHotkey(
            keyCode: config.hotkeyKeyCode,
            modifiers: CGEventFlags(rawValue: config.hotkeyModifiers)
        )
        globalHotkey?.onPressed = { [weak self] in self?.handleHotkey() }
        globalHotkey?.onUnavailable = { [weak self] in
            guard let self else { return }
            self.audit.write("hotkey_unavailable", [:])
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state == .idle, self.globalHotkey?.isActive != true else { return }
                self.startGlobalHotkeyIfPermitted()
            }
        }
        configureSceneHotkeys()
        startGlobalHotkeyIfPermitted()

        server = ControlServer()
        do {
            try server.start { [weak self] request, peer in
                guard let self else { return ControlResponse.failure("auleumd 已退出") }
                return self.handle(request, peer: peer)
            }
            controlServerReady = true
        } catch {
            NSLog("Auleum control server failed: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.presentError(
                    "本地控制面启动失败，无法保证 auleumctl 的应急出口可用。\n\n\(error)",
                    title: "Auleum 启动失败"
                )
                NSApp.terminate(nil)
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        setupSystemObservers()
        startAutomationScheduler()
        updates.start()

        audit.write("daemon_start", ["displays": NSScreen.screens.count])
        preflightAccessibility()

        // 缺权限就直接把引导面板摆出来，而不是等用户点「开启幕帘」才发现。
        if !Permissions.hasAccessibility() || !Permissions.hasScreenRecording() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showPermissionGuide()
            }
        } else if !config.hasShownOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.showOnboarding()
            }
        }
    }

    /// 权限入口只打开系统设置和拖拽浮窗，不再叠一个重复的大授权窗口。
    func showPermissionGuide(openSettings: Bool = false) {
        if permissionGuide == nil {
            let controller = PermissionGuideController()
            controller.onAllGranted = { [weak self] in
                guard let self else { return }
                self.audit.write("permissions_granted", [:])
                self.startGlobalHotkeyIfPermitted()
                self.recoverVeilLayers()
                if !self.config.hasShownOnboarding {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                        self?.showOnboarding()
                    }
                }
            }
            permissionGuide = controller
        }
        permissionGuide?.present(openSettings: openSettings)
    }

    /// 启动时只做状态检查，不弹系统框：真正申请放到用户点「打开设置」时，
    /// 那时系统会把 Auleum.app 加进对应列表，少一次莫名其妙的弹窗。
    private func preflightAccessibility() {
        let trusted = Permissions.hasAccessibility()
        let screen = Permissions.hasScreenRecording()
        audit.write("accessibility_check", ["trusted": trusted, "screen": screen])
        if !trusted {
            NSLog("Auleum: 设备控制和数据访问 未授权")
        }
        if !screen {
            NSLog("Auleum: 录屏与系统录音 未授权")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        teardown()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = AuleumURLCommand(url: url) else {
                audit.write("url_ignored", ["url": url.absoluteString])
                continue
            }
            switch command.action {
            case .on, .protect:
                startVeil(
                    trigger: .url,
                    protectionMinutes: command.minutes
                )
            case .off:
                if state == .active {
                    requestExit(trigger: .url)
                }
            case .status:
                statusItemClicked()
            case .settings:
                showSettings()
            }
        }
    }

    func teardown() {
        guard !didTeardown else { return }
        didTeardown = true
        healthWatchdog?.stop()
        safetyItem?.cancel()
        safetyItem = nil
        protectionItem?.cancel()
        protectionItem = nil
        coverRecoveryItem?.cancel()
        coverRecoveryItem = nil
        automationTimer?.invalidate()
        automationTimer = nil
        remoteRegistry.stop()
        remoteRegistry.onChange = nil
        updates?.stop()
        auth?.cancel()
        authCard?.close()
        authCard = nil
        stopPresentationTimer()
        presentationPreview.stop(notify: false)
        presentation?.close()
        permissionGuide?.stop()
        if state.isOn {
            turnOff(reason: "daemon_exit")
        }
        // 状态机之外再兜底清理一次，避免任何异常路径留下 gamma 黑幕或事件 tap。
        shield?.lower()
        inputGuard?.stop()
        sentinel?.disable()
        globalHotkey?.stop()
        globalHotkey = nil
        sceneHotkeys.values.forEach { $0.stop() }
        sceneHotkeys.removeAll()
        server?.stop()
        singleInstance?.release()
        singleInstance = nil
        if let audit {
            audit.write("daemon_stop", [:])
            audit.flush()
        }
    }
}
