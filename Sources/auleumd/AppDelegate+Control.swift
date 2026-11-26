import AppKit
import AuleumKit

extension AppDelegate {
    // MARK: - 控制协议

    func handle(_ request: ControlRequest, peer: ProcessPeer?) -> ControlResponse {
        switch request.cmd {
        case "on":
            return onMain {
                self.turnOn(
                    trigger: .cli,
                    protectionMinutes: request.minutes
                )
            }
        case "protect":
            return onMain {
                self.turnOn(
                    trigger: .cli,
                    protectionMinutes: request.minutes
                )
            }
        case "scene":
            return onMain {
                guard let raw = request.scene,
                      let scene = AuleumScene(rawValue: raw) else {
                    return .failure(
                        "未知场景；可选 away、meeting、guest、focus"
                    )
                }
                return self.turnOn(
                    trigger: .scene,
                    protectionMinutes: request.minutes
                        ?? self.config.protectionMinutes(for: scene),
                    scene: scene
                )
            }
        case "off":
            return onMain {
                guard self.veilOn else {
                    return ControlResponse(ok: true, message: "幕帘本来就没开")
                }
                self.requestExit(trigger: .control)
                return ControlResponse(ok: true, message: "已请求验证，验证通过后撤幕")
            }
        case "remote":
            return onMain {
                let action = (request.remote ?? "status").lowercased()
                if action == "status" {
                    let enabled = self.effectiveRemoteMode ? "开启" : "关闭"
                    return ControlResponse(
                        ok: true,
                        message: "远程兼容当前\(enabled)（\(self.remoteModeSource)）",
                        data: self.remoteStatusData()
                    )
                }
                guard action == "on" || action == "off" || action == "auto" else {
                    return .failure("remote 需要 on、off、auto 或 status")
                }
                if action == "on", !self.config.remoteCompatibilityEnabled {
                    return .failure("远程兼容已在设置中关闭；请先在设置中开启")
                }
                switch action {
                case "on":
                    self.remoteModeOverride = true
                case "off":
                    self.remoteModeOverride = false
                default:
                    self.remoteModeOverride = nil
                }
                self.refreshRemoteMode()
                self.audit.write("remote_mode_command", [
                    "action": action,
                    "effective": self.effectiveRemoteMode,
                    "source": self.remoteModeSource,
                    "tools": self.remoteToolsSummary,
                ])
                let state = self.effectiveRemoteMode ? "开启" : "关闭"
                return ControlResponse(
                    ok: true,
                    message: "远程兼容已\(state)（\(self.remoteModeSource)）",
                    data: self.remoteStatusData()
                )
            }
        case "message":
            return onMain {
                guard self.veilOn else {
                    return .failure("幕帘未开启，没有可更新的幕帘消息")
                }
                let message = VeilMessagePolicy.normalized(request.text ?? "")
                self.sessionMessageOverride = message
                self.presentation?.update(status: self.presentationStatus())
                let visible = self.presentation?.isActive == true
                self.audit.write("veil_message", [
                    "chars": message?.count ?? 0,
                    "visible": visible,
                ])
                if let message {
                    return ControlResponse(
                        ok: true,
                        message: visible
                            ? "幕帘消息已更新"
                            : "幕帘消息已记录；当前为输出层幕帘，不会显示文字",
                        data: [
                            "chars": "\(message.count)",
                            "visible": visible ? "yes" : "no",
                        ]
                    )
                }
                return ControlResponse(
                    ok: true,
                    message: visible ? "已清除动态消息" : "已清除动态消息；当前为输出层幕帘",
                    data: [
                        "chars": "0",
                        "visible": visible ? "yes" : "no",
                    ]
                )
            }
        case "panic":
            // 应急出口：只走本地 shell，猫不可能敲命令。用于指纹路径失效时自救。
            return onMain {
                guard self.veilOn else { return ControlResponse(ok: true, message: "幕帘本来就没开") }
                self.audit.write("panic_off", [:])
                self.turnOff(reason: "panic")
                return ControlResponse(ok: true, message: "已强制撤幕（panic）")
            }
        case "status":
            return onMain {
                self.status(
                    caller: self.requestCaller(request, peer: peer),
                    peer: peer
                )
            }
        case "doctor":
            return doctorReport()
        case "capture":
            return capture(request, peer: peer)
        case "record_start":
            return recordStart(request, peer: peer)
        case "record_stop":
            return recordStop()
        case "audit":
            let count = request.display ?? 20
            guard count > 0, count <= 10_000 else {
                return .failure("audit 条数必须在 1–10000 之间")
            }
            let lines = audit.tail(count)
            return ControlResponse(ok: true, message: lines.joined(separator: "\n"), data: ["count": "\(lines.count)"])
        default:
            return .failure("未知命令：\(request.cmd)")
        }
    }

    func status(caller: String? = nil, peer: ProcessPeer? = nil) -> ControlResponse {
        let recording = recorder.snapshot()
        let inputStats = inputGuard.counters()
        let screens = ScreenInventory.current()
        let presentationIDs = screens.filter {
            effectiveDisplayRole(isMain: $0.isMain) == .presentation
        }.map(\.displayID)
        let blackIDs = screens.filter {
            effectiveDisplayRole(isMain: $0.isMain) == .black
        }.map(\.displayID)
        let hotkeyText = HotkeyPolicy.displayString(
            keyCode: config.hotkeyKeyCode,
            modifiers: CGEventFlags(rawValue: config.hotkeyModifiers)
        )
        let sceneHotkeyText = AuleumScene.allCases.map {
            "\($0.rawValue)=\(config.sceneHotkey(for: $0).displayString)"
        }.joined(separator: ",")
        let sceneHotkeyActiveCount = sceneHotkeys.values.filter(\.isActive).count
        let data: [String: String] = [
            "veil": veilOn ? "on" : "off",
            "displays": "\(NSScreen.screens.count)",
            "display_ids": screens.map { "\($0.displayID)" }.joined(separator: ","),
            "presentation_display_ids": presentationIDs.map(String.init).joined(separator: ","),
            "black_display_ids": blackIDs.map(String.init).joined(separator: ","),
            "auth_pending": authPending ? "yes" : "no",
            "auth_method": authPending ? authMethod.rawValue : "",
            "degraded": veilDegraded ? "yes" : "no",
            "degraded_reason": lastVeilFailureReason ?? "",
            "password_fallback": config.allowPasswordFallback ? "on" : "off",
            "password_auth": auth.canUseSystemAuthentication() ? "available" : "unavailable",
            "veil_message": sessionMessageOverride ?? "",
            "config_issue": AuleumConfig.lastLoadIssue ?? "",
            "recording": recording.isRecording ? "yes" : "no",
            "recording_frames": "\(recording.framesAppended)",
            "recording_error": recording.lastError ?? "",
            "hold_to_auth": "\(config.holdToAuthSeconds)s",
            "double_escape": "\(config.doubleEscapeSeconds)s",
            "veil_color": config.veilColor,
            "hotkey": hotkeyText,
            "global_hotkey": globalHotkey?.isActive == true ? "active" : "inactive",
            "scene_hotkeys": sceneHotkeyText,
            "scene_hotkeys_active": "\(sceneHotkeyActiveCount)/\(sceneHotkeys.count)",
            "accessibility": Permissions.hasAccessibility() ? "granted" : "missing",
            "screen_recording": Permissions.hasScreenRecording() ? "granted" : "missing",
            "input_gestures": veilOn
                ? (inputGuard.gesturesProtected ? "protected" : "unavailable")
                : "idle",
            "input_physical_blocked": "\(inputStats.physicalBlocked)",
            "input_remote_passed": "\(inputStats.remotePassed)",
            "input_virtual_passed": "\(inputStats.virtualPassed)",
            "input_virtual_blocked": "\(inputStats.virtualBlocked)",
            "input_denied_blocked": "\(inputStats.deniedBlocked)",
            "caller": caller ?? "unknown",
            "caller_process": peer?.direct.name ?? "",
            "caller_parent": peer?.principal.name ?? "",
            "caller_environment": peer?.environmentHint ?? "",
            "caller_chain": peer?.chainText ?? "",
            "trigger": self.sessionTrigger.rawValue,
            "scene": self.sessionScene?.rawValue ?? "",
            "protection_minutes": "\(self.sessionProtectionMinutes)",
            "protection_remaining": "\(self.protectionRemainingSeconds())",
            "idle_auto_veil": self.config.idleAutoVeilEnabled ? "on" : "off",
            "idle_seconds": "\(Int(InputIdleMonitor.secondsSinceLastInput(includeSynthetic: self.effectiveRemoteMode)))",
            "schedule": self.config.scheduleEnabled ? "on" : "off",
            "clamshell": self.config.clamshellModeEnabled ? "on" : "off",
            "remote_mode": self.effectiveRemoteMode ? "on" : "off",
            "remote_mode_source": self.remoteModeSource,
            "remote_compatibility": self.config.remoteCompatibilityEnabled
                ? "on"
                : "off",
            "remote_auto_detect": self.config.remoteAutoDetectEnabled
                ? "on"
                : "off",
            "remote_tools": self.remoteRegistry.snapshot().tools
                .map(\.rawValue)
                .sorted()
                .joined(separator: ","),
            "remote_tool_names": self.remoteToolsSummary,
            "remote_processes": "\(self.remoteRegistry.snapshot().remotePIDs.count)",
            "remote_hid_spi": HIDDeviceInspector.isSPIAvailable
                ? "available"
                : "unavailable",
            "screens_asleep": self.screensAsleepWithClamshell ? "yes" : "no",
            "update_phase": self.updatePhaseName(self.updates.state.phase),
            "update_current": self.updates.currentVersion,
            "update_latest": self.updates.state.latestVersion ?? "",
            "update_message": self.updates.state.message ?? "",
            "update_auto_check": self.config.automaticUpdateChecksEnabled ? "on" : "off",
            "update_auto_install": self.config.automaticUpdateInstallsEnabled ? "on" : "off",
        ]
        return ControlResponse(ok: true, message: veilOn ? "幕帘已开启" : "幕帘已关闭", data: data)
    }

    func updatePhaseName(_ phase: UpdatePhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .checking: return "checking"
        case .upToDate: return "up-to-date"
        case .available: return "available"
        case .downloading: return "downloading"
        case .ready: return "ready"
        case .installing: return "installing"
        case .failed: return "failed"
        }
    }
}
