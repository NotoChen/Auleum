import AppKit
import AuleumKit
import LocalAuthentication

/// 正常撤幕的验证方式。Touch ID 是默认出口，密码兜底需要显式开启。
enum AuthMethod: String {
    case touchID = "touchid"
    case password = "password"
}

/// 正常撤幕请求的来源，只写审计，不参与授权判断。
enum ExitTrigger: String {
    case escape
    case hotkey
    case dashboard
    case control
    case url
    case schedule
    case protection
    case safety
}

extension AppDelegate {
    // MARK: - 幕帘

    func turnOn(
        trigger: AuleumTrigger = .manual,
        protectionMinutes: Int? = nil,
        scene: AuleumScene? = nil
    ) -> ControlResponse {
        if presentationPreview.isActive {
            presentationPreview.stop(notify: false)
        }
        if state == .active {
            if let protectionMinutes {
                configureProtection(
                    minutes: protectionMinutes,
                    auditReason: "updated_by_\(trigger.rawValue)"
                )
                return ControlResponse(
                    ok: true,
                    message: protectionMinutes > 0
                        ? "幕帘已开启，保护时长已更新"
                        : "幕帘已开启，已取消自动结束",
                    data: [
                        "trigger": sessionTrigger.rawValue,
                        "protection_minutes": "\(sessionProtectionMinutes)",
                        "protection_remaining": "\(protectionRemainingSeconds())",
                    ]
                )
            }
            return ControlResponse(ok: true, message: "幕帘已经开着")
        }
        guard state == .idle else {
            return .failure("正在等待验证，不能重复起幕")
        }
        // 没有可用验证方式时不要起幕：开着幕帘却无法正常退出，只能 panic。
        let touchIDAvailable = auth?.isAvailable() == true
        let passwordAvailable = config.allowPasswordFallback
            && auth?.canUseSystemAuthentication() == true
        guard touchIDAvailable || passwordAvailable else {
            audit.write("veil_start_refused", [
                "reason": "no_authentication_method",
                "touchid": touchIDAvailable ? "available" : "unavailable",
                "password_fallback": config.allowPasswordFallback ? "enabled" : "disabled",
            ])
            if config.allowPasswordFallback {
                return .failure("此 Mac 没有可用的 Touch ID，系统密码验证也不可用。幕帘开启后无法正常撤幕，因此未开启。")
            }
            return .failure("此 Mac 没有可用的 Touch ID。幕帘开启后无法正常撤幕，因此未开启；可在设置中开启密码验证，或先启用 Touch ID。")
        }
        guard !systemAsleep, !sessionInactive else {
            return .failure("系统睡眠或会话未激活，幕帘未开启")
        }
        guard controlServerReady else {
            return .failure("本地控制面不可用，无法安全开启幕帘")
        }
        guard Permissions.hasAccessibility(), Permissions.hasScreenRecording() else {
            return .failure("缺少系统权限，幕帘未开启。请先授权设备控制和数据访问、录屏与系统录音。")
        }
        let screens = ScreenInventory.current()
        guard !screens.isEmpty else {
            return .failure("没有可用的显示器，幕帘未开启")
        }
        let profile = scene.map { config.sceneProfile(for: $0) }
        let presentationEnabledForSession = config.presentationModeEnabled
            && profile?.usesPresentation != false
        let presentationScreens = screens.filter {
            displayRole(
                isMain: $0.isMain,
                presentationEnabled: presentationEnabledForSession,
                scene: scene
            ) == .presentation
        }
        let blackScreens = screens.filter {
            displayRole(
                isMain: $0.isMain,
                presentationEnabled: presentationEnabledForSession,
                scene: scene
            ) == .black
        }
        guard !presentationScreens.isEmpty || !blackScreens.isEmpty else {
            return .failure("没有显示器分配到幕帘或展示角色")
        }
        let effectiveMinutes = min(
            1440,
            max(
                0,
                protectionMinutes
                    ?? scene.map { config.protectionMinutes(for: $0) }
                    ?? config.defaultProtectionMinutes
            )
        )

        let startedAt = Date()
        // 起幕前刷新一次，确保刚启动/刚切换的远控工具在本次会话里生效。
        refreshRemoteMode()
        sessionStartedAt = startedAt
        veilDegraded = false
        lastVeilFailureReason = nil
        coverRecoveryAttempts = 0
        failureAuditTimes.removeAll()
        sessionAuthPrompts = 0
        sessionAuthFailures = 0
        activeRecordingStartedAt = nil
        activeRecordingClient = nil
        sessionTrigger = trigger
        sessionScene = scene
        sessionSceneProfile = profile
        sessionPresentationEnabled = presentationEnabledForSession
        sessionMessageOverride = nil
        didShowReturnHint = false
        sessionProtectionMinutes = effectiveMinutes
        protectionPrompted = false
        if globalHotkey?.isActive != true {
            startGlobalHotkeyIfPermitted()
        }

        func rollback(_ message: String) -> ControlResponse {
            presentation?.close()
            shield?.lower()
            inputGuard.setEnabled(false)
            inputGuard.stop()
            stopPresentationTimer()
            sessionStartedAt = nil
            sessionTrigger = .manual
            sessionScene = nil
            sessionSceneProfile = nil
            sessionPresentationEnabled = false
            sessionMessageOverride = nil
            didShowReturnHint = false
            sessionProtectionMinutes = 0
            protectionDeadline = nil
            protectionPrompted = false
            audit.write("veil_start_failed", [
                "trigger": trigger.rawValue,
                "reason": message,
            ])
            return .failure(message)
        }

        NSLog(
            "veil.turnOn begin displays=%d presentation=%d black=%d",
            screens.count,
            presentationScreens.count,
            blackScreens.count
        )
        guard inputGuard.start() else {
            NSLog("veil.turnOn tap FAILED")
            DispatchQueue.main.async { [weak self] in
                self?.showPermissionGuide(openSettings: true)
            }
            return .failure("事件拦截启动失败：请在「系统设置 → 隐私与安全性 → 辅助功能」里勾选 Auleum，然后重新开启幕帘")
        }
        // 先启用拦截，再铺遮挡层：铺层期间物理输入也不能漏过去。
        // 如果铺层失败，rollback 会立即停掉 tap。
        inputGuard.setEnabled(true)

        var presentationStarted = false
        var shieldStarted = false
        if !presentationScreens.isEmpty {
            let sceneImagePath = profile?.backgroundImagePath ?? ""
            let effectiveImagePath = sceneImagePath.isEmpty
                ? config.presentationImagePath
                : sceneImagePath
            let videoCandidate = sceneImagePath.isEmpty
                ? config.presentationVideoPath
                : ""
            let effectiveVideoPath: String?
            if videoCandidate.isEmpty {
                effectiveVideoPath = nil
            } else if PresentationVideoLoader.isLoadable(path: videoCandidate) {
                effectiveVideoPath = videoCandidate
            } else {
                // 视频被删除或格式不再可读时不要让起幕失败，退回图片或内置背景。
                effectiveVideoPath = nil
                audit.write("presentation_video_unavailable", [
                    "path": videoCandidate,
                ])
            }
            let sceneClockStyle = profile?.clockStyle ?? ""
            let effectiveClockStyle = sceneClockStyle.isEmpty
                ? config.presentationClockStyle
                : sceneClockStyle
            if effectiveVideoPath == nil,
               !effectiveImagePath.isEmpty,
               !PresentationBackgroundLoader.isLoadable(
                    path: effectiveImagePath
               ) {
                return rollback("展示模式背景图无法读取：\(effectiveImagePath)")
            }
            let ambientStyle = PresentationAmbientStyle.storedValue(
                config.presentationAmbientStyle
            )
            presentation.hidesCursor = config.hideCursorDuringVeil
            presentation.remoteMode = effectiveRemoteMode
            // 真实幕帘的展示窗口不接住指针事件：物理点击由 HID tap 拦截，
            // 远控和 Agent 的合成点击则必须真正落到下层应用。
            presentation.blocksPointerEvents = false
            guard presentation.show(
                screens: presentationScreens,
                color: AuleumColor(hex: config.veilColor) ?? .black,
                imagePath: effectiveImagePath.isEmpty ? nil : effectiveImagePath,
                clockStyle: PresentationClockStyle.storedValue(
                    effectiveClockStyle
                ),
                imageFocus: CGPoint(
                    x: config.presentationFocusX,
                    y: config.presentationFocusY
                ),
                imageZoom: config.presentationZoom,
                imageDim: config.presentationDim,
                layout: PresentationLayout.storedValue(
                    config.presentationLayout
                ),
                customLayout: config.presentationCustomLayout,
                usesDefaultBackdrop: config.presentationDefaultBackdrop,
                componentBackground: PresentationComponentBackground.storedValue(
                    config.presentationComponentBackground
                ),
                widgets: PresentationClockWidgets(
                    showsSeconds: config.presentationShowSeconds,
                    showsLunar: config.presentationShowLunar,
                    showsElapsed: config.presentationShowElapsed
                ),
                videoPath: effectiveVideoPath,
                ambientStyle: ambientStyle,
                status: presentationStatus()
            ) else {
                return rollback("展示模式窗口创建失败，幕帘未开启")
            }
            presentationStarted = true
            audit.write("presentation_mode", [
                "screens": presentationScreens.count,
                "display_ids": presentationScreens.map { "\($0.displayID)" }.joined(separator: ","),
                "image": effectiveImagePath.isEmpty ? "none" : effectiveImagePath,
                "video": effectiveVideoPath ?? "none",
                "ambient": ambientStyle.rawValue,
                "layout": config.presentationLayout,
                "default_backdrop": config.presentationDefaultBackdrop,
                "component_background": config.presentationComponentBackground,
                "scene": scene?.rawValue ?? "",
                "message": profile?.message ?? "",
            ])
            NSLog("veil.turnOn presentation overlay shown")
        }
        if !blackScreens.isEmpty {
            shield.hidesCursor = config.hideCursorDuringVeil
            shield.remoteMode = effectiveRemoteMode
            shield.backgroundColor = AuleumColor(hex: config.veilColor) ?? .black
            guard shield.raise(displayIDs: blackScreens.map(\.displayID)) else {
                let error = shield.lastError ?? "无法建立输出层黑幕，幕帘未开启"
                return rollback(
                    presentationStarted ? "\(error)；展示窗口已回滚" : error
                )
            }
            shieldStarted = true
            NSLog("veil.turnOn shield raised")
        }

        sentinel.preventsClamshellSleep = config.clamshellModeEnabled
        sentinel.enable()
        state = .active
        // 从状态面板起幕时 Auleum 仍是活动应用；远控模式下让出焦点，
        // 否则远控端的键盘输入没有可接收的下层应用。
        relinquishFocusForRemoteMode()
        healthWatchdog?.start()
        if presentationStarted {
            startPresentationTimer()
        } else {
            stopPresentationTimer()
        }
        configureProtection(
            minutes: effectiveMinutes,
            auditReason: "session_start_\(trigger.rawValue)"
        )
        updateStatusItem()
        audit.write("veil_on", [
            "displays": screens.count,
            "presentation_displays": presentationStarted ? presentationScreens.count : 0,
            "black_displays": shieldStarted ? blackScreens.count : 0,
            "trigger": trigger.rawValue,
            "scene": scene?.rawValue ?? "",
            "protection_minutes": effectiveMinutes,
            "scene_message": profile?.message ?? "",
            "remote_mode": effectiveRemoteMode,
            "remote_tools": remoteToolsSummary,
        ])
        NSLog("veil.turnOn complete")

        if config.safetyTimeoutSeconds > 0 {
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.veilOn else { return }
                // 开发兜底也只发起验证，不直接撤幕。
                self.audit.write("safety_timeout", ["action": "auth_requested"])
                self.requestExit(trigger: .safety)
            }
            safetyItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + config.safetyTimeoutSeconds, execute: item)
        }

        return ControlResponse(ok: true, message: "幕帘已开启", data: [
            "displays": "\(screens.count)",
            "presentation_displays": "\(presentationStarted ? presentationScreens.count : 0)",
            "black_displays": "\(shieldStarted ? blackScreens.count : 0)",
            "trigger": trigger.rawValue,
            "scene": scene?.rawValue ?? "",
            "protection_minutes": "\(effectiveMinutes)",
            "protection_remaining": "\(protectionRemainingSeconds())",
            "hold_to_auth": "\(config.holdToAuthSeconds)s",
            "remote_mode": effectiveRemoteMode ? "on" : "off",
            "remote_mode_source": remoteModeSource,
        ])
    }

    func turnOff(reason: String) {
        guard state.isOn else { return }
        let endedAt = Date()
        let duration = sessionStartedAt.map { endedAt.timeIntervalSince($0) } ?? 0
        state = .idle
        authGeneration &+= 1
        auth.cancel()
        authCard?.close()
        authCard = nil
        healthWatchdog?.stop()
        coverRecoveryItem?.cancel()
        coverRecoveryItem = nil
        coverRecoveryAttempts = 0
        veilDegraded = false
        lastVeilFailureReason = nil
        failureAuditTimes.removeAll()
        safetyItem?.cancel()
        safetyItem = nil
        protectionItem?.cancel()
        protectionItem = nil
        protectionDeadline = nil
        stopPresentationTimer()
        // 先恢复屏幕，再放行物理输入。反过来会留下几毫秒“看不见但能点”的窗口。
        presentation?.close()
        shield.lower()
        inputGuard.setEnabled(false)
        inputGuard.stop()
        sentinel.disable()
        if globalHotkey?.isActive != true {
            startGlobalHotkeyIfPermitted()
        }
        screensAsleepWithClamshell = false
        updateStatusItem()
        audit.write("veil_off", [
            "reason": reason,
            "trigger": sessionTrigger.rawValue,
        ])
        finishSession(
            reason: reason,
            endedAt: endedAt,
            duration: duration
        )
        sessionTrigger = .manual
        sessionScene = nil
        sessionSceneProfile = nil
        sessionPresentationEnabled = false
        sessionMessageOverride = nil
        didShowReturnHint = false
        sessionProtectionMinutes = 0
        protectionPrompted = false
        maybeInstallUpdateAfterIdle()
    }

    func finishSession(reason: String,
                       endedAt: Date,
                       duration: TimeInterval) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var details: [String: Any] = [
            "reason": reason,
            "duration_seconds": (duration * 10).rounded() / 10,
            "auth_prompts": sessionAuthPrompts,
            "auth_failures": sessionAuthFailures,
            "trigger": sessionTrigger.rawValue,
            "protection_minutes": sessionProtectionMinutes,
        ]
        if let started = sessionStartedAt { details["started_at"] = formatter.string(from: started) }
        details["ended_at"] = formatter.string(from: endedAt)
        if let sessionScene {
            details["scene"] = sessionScene.rawValue
        }
        audit.write("session_summary", details)
        audit.flush()
    }

    /// 没有可用验证方式时保持幕帘，并给出可操作的提示。
    private func keepVeilWithoutAuthentication(trigger: ExitTrigger,
                                               remoteRequest: Bool = false) {
        audit.write("biometrics_unavailable", [
            "action": "veil_kept",
            "trigger": trigger.rawValue,
            "password_fallback": config.allowPasswordFallback ? "enabled" : "disabled",
            "remote_input": remoteRequest,
        ])
        guard presentation?.isActive == true else { return }
        let hint: String
        if remoteRequest, !config.allowPasswordFallback {
            hint = "远控输入需要密码验证；请开启密码兜底、在本机用 Touch ID，或用 auleumctl panic 应急撤幕"
        } else if config.allowPasswordFallback {
            hint = "系统密码验证不可用；修复后重试，或使用 auleumctl panic 应急撤幕"
        } else {
            hint = "Touch ID 不可用；可在设置中开启密码验证，或使用 auleumctl panic 应急撤幕"
        }
        presentation.showReturnHint(hint)
    }

    /// 双击/长按 Esc、再次按起幕快捷键或 auleumctl off：
    /// 默认在幕帘内显示自定义 Touch ID 卡片；Touch ID 不可用时直接用
    /// 系统密码面板。开启密码兜底后，指纹失败或锁定也会转入密码面板。
    /// 撤幕方式按输入来源选择：本机物理输入优先 Touch ID；远控输入不能
    /// 完成 Touch ID，只有密码兜底开启时才走系统密码，否则保持幕帘。
    func requestExit(trigger: ExitTrigger,
                     inputOrigin: InputOrigin? = nil) {
        guard state == .active else { return }

        let remoteRequest = effectiveRemoteMode
            && (inputOrigin == .remoteProcess
                || inputOrigin == .virtualDevice)
        let biometricsContext = auth.makeContext()
        let systemContext = auth.makeSystemContext()
        let preferred = ExitAuthPolicy.preferredMethod(
            remoteRequest: remoteRequest,
            physicalRequest: inputOrigin == .physical,
            remoteMode: effectiveRemoteMode,
            passwordFallbackEnabled: config.allowPasswordFallback,
            biometricsAvailable: biometricsContext != nil,
            systemAuthAvailable: systemContext != nil
        )
        let method: AuthMethod
        let context: LAContext
        if let preferred {
            let selected: LAContext?
            switch preferred {
            case .password:
                selected = systemContext
            case .touchID:
                selected = biometricsContext
            }
            guard let selected else {
                // 策略选中的方式在生成上下文时不可用：保持幕帘。
                keepVeilWithoutAuthentication(
                    trigger: trigger,
                    remoteRequest: remoteRequest
                )
                return
            }
            method = preferred == .password ? .password : .touchID
            context = selected
        } else {
            // 普通出口没有可用验证方式时保持幕帘，应急路径仍可用 panic。
            keepVeilWithoutAuthentication(
                trigger: trigger,
                remoteRequest: remoteRequest
            )
            return
        }

        state = .authenticating
        authGeneration &+= 1
        let generation = authGeneration
        authMethod = method
        updateStatusItem()
        if presentation?.isActive == true {
            presentation.hideForAuth()
            let authHint: String
            if method == .touchID {
                authHint = remoteRequest && !config.allowPasswordFallback
                    ? "远控模式下 Touch ID 无法完成；开启密码验证后可在远控端撤幕"
                    : "等待 Touch ID 验证…"
            } else {
                authHint = "在系统面板中输入登录密码…"
            }
            presentation.showReturnHint(authHint, duration: 30)
        }
        if shield.isUp, !shield.demoteForAuth() {
            // 降层失败：回到未认证状态，不要在幕帘后面留下半个认证界面。
            state = .active
            inputGuard.setAuthenticationMode(false)
            if presentation?.isActive == true {
                presentation.hideReturnHint(animated: false)
                presentation.restoreAfterAuth()
            }
            updateStatusItem()
            refreshVeilHealth()
            audit.write("auth_aborted", [
                "trigger": trigger.rawValue,
                "method": method.rawValue,
                "reason": "cover_unavailable",
            ])
            return
        }
        switch method {
        case .touchID:
            inputGuard.setAuthenticationMode(true)
            let card = AuthCard(
                context: context,
                passwordFallbackEnabled: config.allowPasswordFallback
            )
            authCard = card
            card.show()
        case .password:
            // 系统密码面板需要物理键盘和鼠标；合成输入已经在 tap 里拦截。
            inputGuard.setPasswordAuthenticationMode(true)
            presentation?.revealCursorForAuth()
            shield.revealCursorForAuth()
        }
        sessionAuthPrompts += 1
        audit.write("auth_prompt", [
            "trigger": trigger.rawValue,
            "method": method.rawValue,
            "remote_mode": effectiveRemoteMode,
            "remote_input": remoteRequest,
            "physical_input": inputOrigin == .physical,
        ])

        let completion: (Bool, Error?) -> Void = { [weak self] ok, error in
            guard let self else { return }
            guard self.authGeneration == generation, self.state == .authenticating else { return }
            if ok {
                self.completeAuthentication(method: method, generation: generation)
                return
            }
            // 用户主动取消不回退到密码；指纹失败、锁定或硬件错误才进入密码兜底。
            if method == .touchID,
               self.config.allowPasswordFallback,
               self.shouldFallBackToPassword(after: error),
               let systemContext = self.auth.makeSystemContext() {
                self.startPasswordFallback(
                    trigger: trigger,
                    previousGeneration: generation,
                    context: systemContext
                )
                return
            }
            self.failAuthentication(method: method, trigger: trigger)
        }
        switch method {
        case .touchID:
            auth.authenticate(using: context, reason: "解除幕帘", completion: completion)
        case .password:
            auth.authenticateWithSystem(
                using: context,
                reason: "解除幕帘",
                completion: completion
            )
        }
    }

    /// 认证成功：Touch ID 卡片停留一小会儿展示成功勾选，然后撤幕。
    private func completeAuthentication(method: AuthMethod, generation: UInt64) {
        let delay: TimeInterval = method == .touchID ? 0.35 : 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard self.authGeneration == generation,
                  self.state == .authenticating else { return }
            self.turnOff(reason: method.rawValue)
        }
    }

    private func failAuthentication(method: AuthMethod, trigger: ExitTrigger) {
        authCard?.close()
        authCard = nil
        state = .active
        inputGuard.setAuthenticationMode(false)
        if presentation?.isActive == true {
            presentation.hideReturnHint(animated: false)
            presentation.restoreAfterAuth()
            presentation.showReturnHint(
                method == .password
                    ? "密码验证未通过 · 再按 Esc 重试"
                    : "Touch ID 未通过 · 再按 Esc 重试",
                duration: 8
            )
        }
        if shield.isUp {
            shield.restoreLevel()
        }
        // restoreLevel 失败只会降级，不会撤幕；随后刷新健康状态并重试补涂。
        guard state == .active else { return }
        sessionAuthFailures += 1
        audit.write("auth_failed", [
            "trigger": trigger.rawValue,
            "method": method.rawValue,
        ])
        updateStatusItem()
        refreshVeilHealth()
        // 认证面板关闭后把焦点还给前台应用，避免远控键盘继续落在 Auleum。
        relinquishFocusForRemoteMode()
    }

    /// 指纹失败、锁定、硬件错误和用户主动选择「使用密码」都回退；
    /// Esc、应用取消和系统取消保持幕帘。
    private func shouldFallBackToPassword(after error: Error?) -> Bool {
        guard let error = error as? LAError else { return false }
        switch error.code {
        case .userCancel, .appCancel, .systemCancel:
            return false
        default:
            return true
        }
    }

    /// 从 Touch ID 卡片切换到系统密码面板，不撤幕、不恢复覆盖层。
    private func startPasswordFallback(trigger: ExitTrigger,
                                       previousGeneration: UInt64,
                                       context: LAContext) {
        guard state == .authenticating,
              authGeneration == previousGeneration else { return }
        // 先让旧的 Touch ID 回调失效，再取消 context，避免取消触发的
        // 完成回调把刚起步的密码验证误判成失败。
        authGeneration &+= 1
        let generation = authGeneration
        auth.cancel()
        authCard?.close()
        authCard = nil
        authMethod = .password
        inputGuard.setPasswordAuthenticationMode(true)
        if presentation?.isActive == true {
            presentation.hideReturnHint(animated: false)
            presentation.showReturnHint(
                "在系统面板中输入登录密码…",
                duration: 30
            )
        }
        presentation?.revealCursorForAuth()
        shield.revealCursorForAuth()
        sessionAuthPrompts += 1
        audit.write("auth_prompt", [
            "trigger": trigger.rawValue,
            "method": AuthMethod.password.rawValue,
            "fallback": "touchid_failed",
            "remote_mode": effectiveRemoteMode,
        ])
        auth.authenticateWithSystem(
            using: context,
            reason: "解除幕帘"
        ) { [weak self] ok, _ in
            guard let self else { return }
            guard self.authGeneration == generation, self.state == .authenticating else { return }
            if ok {
                self.completeAuthentication(method: .password, generation: generation)
            } else {
                self.failAuthentication(method: .password, trigger: trigger)
            }
        }
    }

    /// 认证界面显示期间再按一次物理 Esc：取消认证，回到仍然锁住的幕帘。
    func cancelAuthentication() {
        guard state == .authenticating else { return }
        let method = authMethod
        authGeneration &+= 1
        auth.cancel()
        authCard?.close()
        authCard = nil
        state = .active
        inputGuard.setAuthenticationMode(false)
        if presentation?.isActive == true {
            presentation.hideReturnHint(animated: false)
            presentation.restoreAfterAuth()
            if !systemAsleep, !sessionInactive {
                presentation.showReturnHint("已取消验证 · 幕帘保持", duration: 5)
            }
        }
        if shield.isUp {
            shield.restoreLevel()
        }
        // restoreLevel 失败只会降级，不会撤幕。
        guard state == .active else { return }
        audit.write("auth_cancelled", ["method": method.rawValue])
        updateStatusItem()
        refreshVeilHealth()
        relinquishFocusForRemoteMode()
    }

    func configureProtection(minutes: Int, auditReason: String) {
        protectionItem?.cancel()
        protectionItem = nil
        protectionDeadline = nil
        protectionPrompted = false
        sessionProtectionMinutes = min(1440, max(0, minutes))
        guard sessionProtectionMinutes > 0, veilOn else {
            audit.write("protection_cleared", ["reason": auditReason])
            return
        }
        let seconds = TimeInterval(sessionProtectionMinutes * 60)
        let deadline = Date().addingTimeInterval(seconds)
        protectionDeadline = deadline
        audit.write("protection_scheduled", [
            "minutes": sessionProtectionMinutes,
            "deadline": ISO8601DateFormatter().string(from: deadline),
            "reason": auditReason,
        ])
        let item = DispatchWorkItem { [weak self] in
            self?.protectionExpired()
        }
        protectionItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func protectionExpired() {
        guard veilOn, state == .active, !protectionPrompted else { return }
        protectionPrompted = true
        audit.write("protection_elapsed", [
            "minutes": sessionProtectionMinutes,
            "trigger": sessionTrigger.rawValue,
        ])
        presentation?.update(status: presentationStatus())
        requestExit(trigger: .protection)
    }

    func protectionRemainingSeconds() -> Int {
        guard let protectionDeadline else { return 0 }
        return max(0, Int(protectionDeadline.timeIntervalSinceNow.rounded(.up)))
    }

    func presentationStatus() -> PresentationStatus {
        var status = PresentationClockFormatter.status(
            at: Date(),
            startedAt: sessionStartedAt,
            messageText: sessionMessageOverride ?? sessionSceneProfile?.message ?? ""
        )
        if let profile = sessionSceneProfile,
           profile.showsReturnTime,
           let protectionDeadline {
            let components = Calendar.current.dateComponents(
                [.hour, .minute],
                from: protectionDeadline
            )
            status.returnText = String(
                format: "预计 %02d:%02d 回来",
                components.hour ?? 0,
                components.minute ?? 0
            )
        }
        let elapsed = status.elapsedText
        if let protectionDeadline {
            let remaining = Int(protectionDeadline.timeIntervalSinceNow.rounded(.up))
            if remaining > 0 {
                status.elapsedText = "\(elapsed) · 剩余 \(elapsedText(TimeInterval(remaining)))"
            } else {
                status.elapsedText = protectionPrompted
                    ? "已到保护时长 · 等待 Touch ID"
                    : "已到保护时长"
            }
        }
        return status
    }

    func elapsedText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    func startPresentationTimer() {
        stopPresentationTimer()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.veilOn else { return }
            self.presentation?.update(status: self.presentationStatus())
        }
        RunLoop.main.add(timer, forMode: .common)
        presentationTimer = timer
    }

    func stopPresentationTimer() {
        presentationTimer?.invalidate()
        presentationTimer = nil
    }
}
