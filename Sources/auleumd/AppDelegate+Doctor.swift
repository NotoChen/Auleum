import AppKit
import AuleumKit
import Security

extension AppDelegate {
    // MARK: - 自检

    func doctorReport() -> ControlResponse {
        let mainState = onMain {
            () -> (
                veil: Bool,
                shieldUp: Bool,
                presentationActive: Bool,
                recording: Bool,
                displays: Int,
                controlServer: Bool,
                degraded: Bool,
                degradedReason: String?
            ) in
            (
                self.veilOn,
                self.shield.isUp,
                self.presentation.isActive,
                self.recorder.snapshot().isRecording,
                NSScreen.screens.count,
                self.controlServerReady,
                self.veilDegraded,
                self.lastVeilFailureReason
            )
        }
        // doctor 在控制面队列上执行，耗时检查（审计、SCK）不能占住主线程，
        // 但配置、快捷键和电源状态都由主线程维护，先在这里做一次快照。
        let settings = onMain {
            (
                config: self.config,
                hotkeyActive: self.globalHotkey?.isActive == true,
                sceneHotkeys: self.sceneHotkeys.mapValues(\.isActive),
                clamshellStatus: self.sentinel.clamshellStatus,
                hasExternalDisplay: self.sentinel.hasExternalDisplay
            )
        }
        let config = settings.config
        var lines: [String] = []
        let ax = Permissions.hasAccessibility()
        let screen = Permissions.hasScreenRecording()
        lines.append("权限 设备控制和数据访问：\(ax ? "已授权" : "缺失")")
        lines.append("权限 录屏与系统录音：\(screen ? "已授权" : "缺失")")

        let displayCount = mainState.displays
        if screen {
            let sckCount = broker.displayCount()
            lines.append("显示器：\(displayCount) 块（SCK 可见 \(sckCount) 块）")
        } else {
            lines.append("显示器：\(displayCount) 块（录屏未授权，跳过 SCK 探测）")
        }
        let displayIDs = onMain { ScreenInventory.current().map(\.displayID) }
        let blackoutSupported: Bool
        let blackoutState: String
        if mainState.veil {
            blackoutSupported = true
            blackoutState = "幕帘开启中，跳过写探测"
        } else {
            let unsupported = displayIDs.filter { !Shield.supportsOutputBlackout($0) }
            blackoutSupported = !displayIDs.isEmpty && unsupported.isEmpty
            if displayIDs.isEmpty {
                blackoutState = "没有可用显示器"
            } else if unsupported.isEmpty {
                blackoutState = "\(displayIDs.count) 块显示器支持"
            } else {
                blackoutState = "不支持：\(unsupported.map(String.init).joined(separator: ","))"
            }
        }
        lines.append("输出层黑幕 API：\(blackoutState)")
        let tapOK = canCreateTap()
        let gestureTapOK = canCreateGestureTap()
        let hotkeyOK = settings.hotkeyActive
        let expectedSceneHotkeys = AuleumScene.allCases.filter {
            config.sceneHotkey(for: $0).isValid
        }.count
        let activeSceneHotkeys = settings.sceneHotkeys.values.filter { $0 }.count
        let sceneHotkeysOK = activeSceneHotkeys == expectedSceneHotkeys
        let touchIDOK = auth.isAvailable()
        let passwordAuthOK = auth.canUseSystemAuthentication()
        let exitMethodOK = touchIDOK
            || (config.allowPasswordFallback && passwordAuthOK)
        lines.append("事件 tap：\(tapOK ? "可创建" : "创建失败")")
        lines.append("手势 tap：\(gestureTapOK ? "可创建" : "创建失败")")
        lines.append("全局快捷键：\(hotkeyOK ? "已生效" : "未生效")")
        let sceneHotkeySummary = AuleumScene.allCases.map {
            "\($0.title) \(config.sceneHotkey(for: $0).displayString)"
        }.joined(separator: " / ")
        lines.append(
            "场景快捷键：\(sceneHotkeysOK ? "已生效" : "未完全生效")"
                + "（\(activeSceneHotkeys)/\(expectedSceneHotkeys)）"
                + " · \(sceneHotkeySummary)"
        )
        lines.append("Touch ID：\(touchIDOK ? "可用" : "不可用")")
        lines.append(
            "密码兜底：\(config.allowPasswordFallback ? "已开启" : "关闭")"
                + " · 系统验证\(passwordAuthOK ? "可用" : "不可用")"
        )
        let hotkeyText = HotkeyPolicy.displayString(
            keyCode: config.hotkeyKeyCode,
            modifiers: CGEventFlags(rawValue: config.hotkeyModifiers)
        )
        lines.append("快捷键：\(hotkeyText)（全局监听）")
        lines.append("合盖模式：\(settings.clamshellStatus)")

        let agent = LaunchAgent.status()
        lines.append("开机自启：\(agent.installed ? "已安装" : "未安装")\(agent.installed ? (agent.loaded ? "、已加载" : "、未加载") : "")")

        let verify = AuditLog.verify()
        let auditLine = verify.ok
            ? "审计：\(verify.count) 条已校验" + (verify.legacy > 0 ? "（另有 \(verify.legacy) 条旧格式）" : "") + "，哈希链完整"
            : "审计：第 \(verify.brokenAtLine ?? -1) 行断裂（\(verify.reason ?? "")）"
        lines.append(auditLine)
        let auditStatus = audit.status()
        if auditStatus.writeFailures > 0 {
            lines.append("审计写入失败：\(auditStatus.writeFailures) 次（\(auditStatus.lastWriteError ?? "unknown")）")
        }
        if let issue = AuleumConfig.lastLoadIssue {
            lines.append("配置：\(issue)")
        }
        let updateState = onMain { self.updates.state }
        lines.append(
            "更新：\(updatePhaseName(updateState.phase))"
                + (updateState.latestVersion.map { " · 最新 v\($0)" } ?? "")
                + (updateState.message.map { " · \($0)" } ?? "")
        )

        lines.append("签名：\(signingIdentity())")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        lines.append("版本：\(version)")
        lines.append("可执行文件：\(Bundle.main.bundlePath)")
        lines.append("状态：幕帘\(mainState.veil ? "开启" : "关闭")、录屏\(mainState.recording ? "进行中" : "空闲")")
        if mainState.degraded {
            lines.append("降级：\(mainState.degradedReason ?? "未知原因")")
        }
        lines.append("控制面：\(mainState.controlServer ? "可用" : "不可用")")

        let data: [String: String] = [
            "accessibility": ax ? "granted" : "missing",
            "screen_recording": screen ? "granted" : "missing",
            "displays": "\(displayCount)",
            "output_blackout": mainState.veil
                ? "active"
                : (blackoutSupported ? "ok" : "failed"),
            "tap": tapOK ? "ok" : "failed",
            "gesture_tap": gestureTapOK ? "ok" : "failed",
            "global_hotkey": hotkeyOK ? "ok" : "failed",
            "scene_hotkeys": sceneHotkeysOK ? "ok" : "failed",
            "scene_hotkeys_active": "\(activeSceneHotkeys)/\(expectedSceneHotkeys)",
            "clamshell_status": config.clamshellModeEnabled
                ? (settings.hasExternalDisplay
                    ? "external-display"
                    : "idle-assertion-only")
                : "off",
            "touchid": touchIDOK ? "ok" : "unavailable",
            "password_fallback": config.allowPasswordFallback ? "on" : "off",
            "password_auth": passwordAuthOK ? "ok" : "unavailable",
            "audit_ok": verify.ok ? "yes" : "no",
            "audit_write_failures": "\(auditStatus.writeFailures)",
            "launch_agent": agent.installed ? "installed" : "absent",
            "control_server": mainState.controlServer ? "ok" : "failed",
            "degraded": mainState.degraded ? "yes" : "no",
            "degraded_reason": mainState.degradedReason ?? "",
            "config": AuleumConfig.lastLoadIssue == nil ? "ok" : "defaults",
            "config_issue": AuleumConfig.lastLoadIssue ?? "",
            "update_phase": updatePhaseName(updateState.phase),
            "update_latest": updateState.latestVersion ?? "",
            "update_auto_check": config.automaticUpdateChecksEnabled ? "on" : "off",
            "update_auto_install": config.automaticUpdateInstallsEnabled ? "on" : "off",
            "shield_up": mainState.shieldUp ? "yes" : "no",
            "presentation_active": mainState.presentationActive ? "yes" : "no",
            "clamshell": config.clamshellModeEnabled ? "on" : "off",
            "overall": "pending",
        ]
        let checksOK = ax
            && screen
            && blackoutSupported
            && tapOK
            && gestureTapOK
            && hotkeyOK
            && sceneHotkeysOK
            && exitMethodOK
            && verify.ok
            && auditStatus.writeFailures == 0
            && AuleumConfig.lastLoadIssue == nil
            && !mainState.degraded
            && mainState.controlServer
            && (!mainState.veil
                || mainState.shieldUp
                || mainState.presentationActive)
        var finalData = data
        finalData["overall"] = checksOK ? "ok" : "failed"
        lines.append("结论：\(checksOK ? "全部关键项可用" : "存在缺失项，不能宣称可用")")
        return ControlResponse(
            ok: checksOK,
            message: lines.joined(separator: "\n"),
            data: finalData
        )
    }

    /// 只创建并立刻销毁一个 listen-only tap，用来判断事件拦截权限是否到位。
    func canCreateTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else { return false }
        CFMachPortInvalidate(tap)
        return true
    }

    func canCreateGestureTap() -> Bool {
        var mask: CGEventMask = 0
        for rawValue in InputPolicy.gestureEventRawValues {
            mask |= (CGEventMask(1) << rawValue)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else { return false }
        CFMachPortInvalidate(tap)
        return true
    }

    func signingIdentity() -> String {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: getpid()] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code, let staticCode = try? staticCode(of: code) else {
            return "未知"
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return "未知" }
        let identifier = dict[kSecCodeInfoIdentifier as String] as? String ?? "?"
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        let certs = dict[kSecCodeInfoCertificates as String] as? [Any]
        let kind = certs == nil ? "ad-hoc" : (team.map { "Team \($0)" } ?? "自签名")
        return "\(identifier)（\(kind)）"
    }

    func staticCode(of code: SecCode) throws -> SecStaticCode {
        var staticCode: SecStaticCode?
        let status = SecCodeCopyStaticCode(code, [], &staticCode)
        guard status == errSecSuccess, let staticCode else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return staticCode
    }
}
