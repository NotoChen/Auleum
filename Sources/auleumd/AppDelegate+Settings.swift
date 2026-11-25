import AppKit
import AuleumKit

extension AppDelegate {
    /// 设置窗口：保存后立即生效（不必重启 app）。
    func showSettings() {
        if settingsWindow == nil {
            let controller = SettingsWindowController(config: config)
            controller.onOpenPermissions = { [weak self] in
                guard let self else { return }
                self.settingsWindow?.hide()
                self.showPermissionGuide(openSettings: true)
            }
            controller.onAudit = { [weak self] event, details in
                self?.audit.write(event, details)
            }
            controller.onCheckForUpdates = { [weak self] in
                self?.checkForUpdates()
            }
            controller.onInstallUpdate = { [weak self] in
                self?.installAvailableUpdate()
            }
            controller.onOpenUpdateRelease = { [weak self] in
                self?.openUpdateReleasePage()
            }
            controller.onPreviewPresentation = { [weak self] preview in
                guard let self else { return }
                let screens = ScreenInventory.current()
                self.settingsWindow?.hide()
                if let error = self.presentationPreview.start(
                    screens: screens,
                    configuration: preview,
                    completion: { [weak self] result in
                        guard let self else { return }
                        self.settingsWindow?.show()
                        if case .failure(let error) = result {
                            self.presentError(
                                error.message,
                                title: "全屏试看已结束"
                            )
                        }
                    }
                ) {
                    self.settingsWindow?.show()
                    self.presentError(
                        error.message,
                        title: "无法开始全屏试看"
                    )
                    return
                }
                self.audit.write("presentation_preview", [
                    "screens": screens.count,
                    "seconds": preview.duration,
                    "clock": preview.clockStyle.rawValue,
                    "image": preview.imagePath ?? "none",
                ])
            }
            controller.onSave = { [weak self] updated in
                guard let self else { return }
                self.config = updated
                self.shield.hidesCursor = updated.hideCursorDuringVeil
                self.shield.applyCursorVisibility()
                self.presentation?.hidesCursor = updated.hideCursorDuringVeil
                self.presentation?.applyCursorVisibility()
                self.shield.setBackgroundColor(AuleumColor(hex: updated.veilColor) ?? .black)
                self.sentinel.preventsClamshellSleep = updated.clamshellModeEnabled
                self.resetAutomationState()
                if updated.presentationModeEnabled {
                    self.presentation?.setColor(AuleumColor(hex: updated.veilColor) ?? .black)
                    self.presentation?.setImagePath(updated.presentationImagePath.isEmpty ? nil : updated.presentationImagePath)
                    self.presentation?.setImagePresentation(
                        focus: CGPoint(
                            x: updated.presentationFocusX,
                            y: updated.presentationFocusY
                        ),
                        zoom: updated.presentationZoom,
                        dim: updated.presentationDim
                    )
                    self.presentation?.setClockStyle(
                        PresentationClockStyle.storedValue(
                            updated.presentationClockStyle
                        )
                    )
                    self.presentation?.setLayout(
                        PresentationLayout.storedValue(
                            updated.presentationLayout
                        )
                    )
                    self.presentation?.setCustomLayout(
                        updated.presentationCustomLayout
                    )
                    self.presentation?.setDefaultBackdropEnabled(
                        updated.presentationDefaultBackdrop
                    )
                    self.presentation?.setComponentBackground(
                        PresentationComponentBackground.storedValue(
                            updated.presentationComponentBackground
                        )
                    )
                    self.presentation?.setWidgets(
                        PresentationClockWidgets(
                            showsSeconds: updated.presentationShowSeconds,
                            showsLunar: updated.presentationShowLunar,
                            showsElapsed: updated.presentationShowElapsed
                        )
                    )
                }
                self.inputGuard.holdToAuthSeconds = updated.holdToAuthSeconds
                self.inputGuard.doubleEscapeSeconds = updated.doubleEscapeSeconds
                self.applyHotkeySettings(to: self.inputGuard)
                self.applyHotkey(updated)
                self.audit.write("config_saved", [
                    "hold": updated.holdToAuthSeconds,
                    "double_escape": updated.doubleEscapeSeconds,
                    "hide_cursor": updated.hideCursorDuringVeil,
                    "color": updated.veilColor,
                    "presentation_mode": updated.presentationModeEnabled,
                    "presentation_image": updated.presentationImagePath,
                    "presentation_clock": updated.presentationClockStyle,
                    "presentation_layout": updated.presentationLayout,
                    "presentation_default_backdrop":
                        updated.presentationDefaultBackdrop,
                    "presentation_component_background":
                        updated.presentationComponentBackground,
                    "presentation_widgets": [
                        updated.presentationShowSeconds ? "seconds" : "",
                        updated.presentationShowLunar ? "lunar" : "",
                        updated.presentationShowElapsed ? "elapsed" : "",
                    ].filter { !$0.isEmpty }.joined(separator: ","),
                    "presentation_main_role": updated.mainDisplayRole,
                    "presentation_secondary_role": updated.secondaryDisplayRole,
                    "presentation_focus": "\(updated.presentationFocusX),\(updated.presentationFocusY)",
                    "presentation_zoom": updated.presentationZoom,
                    "presentation_dim": updated.presentationDim,
                    "idle_auto": updated.idleAutoVeilEnabled,
                    "idle_auto_seconds": updated.idleAutoVeilSeconds,
                    "schedule": updated.scheduleEnabled,
                    "default_protection_minutes": updated.defaultProtectionMinutes,
                    "clamshell": updated.clamshellModeEnabled,
                    "hotkey": HotkeyPolicy.displayString(
                        keyCode: updated.hotkeyKeyCode,
                        modifiers: CGEventFlags(rawValue: updated.hotkeyModifiers)
                    ),
                ])
                self.updates.refreshSchedule()
            }
            settingsWindow = controller
        }
        settingsWindow?.show()
        settingsWindow?.applyUpdateState(updates.state)
    }

    func showOnboarding(force: Bool = false) {
        guard onboardingWindow == nil || force else {
            onboardingWindow?.show()
            return
        }
        let controller = OnboardingWindowController(hotkey: hotkeyDisplay)
        controller.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        controller.onFinish = { [weak self] dontShowAgain in
            guard let self else { return }
            if dontShowAgain, !self.config.hasShownOnboarding {
                self.config.hasShownOnboarding = true
                _ = self.config.save()
            }
            self.onboardingWindow = nil
        }
        onboardingWindow = controller
        controller.show()
    }

    var hotkeyDisplay: String {
        HotkeyPolicy.displayString(
            keyCode: config.hotkeyKeyCode,
            modifiers: CGEventFlags(rawValue: config.hotkeyModifiers)
        )
    }

    func applyHotkeySettings(to guarder: InputGuard) {
        guarder.exitHotkeyKeyCode = config.hotkeyKeyCode
        guarder.exitHotkeyModifiers = CGEventFlags(rawValue: config.hotkeyModifiers)
    }

    func applyHotkey(_ config: AuleumConfig) {
        globalHotkey?.stop()
        let hotkey = GlobalHotkey(
            keyCode: config.hotkeyKeyCode,
            modifiers: CGEventFlags(rawValue: config.hotkeyModifiers)
        )
        hotkey.onPressed = { [weak self] in self?.handleHotkey() }
        hotkey.onUnavailable = { [weak self] in
            guard let self else { return }
            self.audit.write("hotkey_unavailable", [:])
            DispatchQueue.main.async { [weak self] in
                guard let self, self.state == .idle, self.globalHotkey?.isActive != true else { return }
                _ = self.globalHotkey?.start()
            }
        }
        globalHotkey = hotkey
        configureSceneHotkeys()
        startGlobalHotkeyIfPermitted()
    }

    func configureSceneHotkeys() {
        sceneHotkeys.values.forEach { $0.stop() }
        sceneHotkeys.removeAll()
        for scene in AuleumScene.allCases {
            let binding = config.sceneHotkey(for: scene)
            guard binding.isValid else { continue }
            let hotkey = GlobalHotkey(
                keyCode: binding.keyCode,
                modifiers: binding.binding.modifiers
            )
            hotkey.onPressed = { [weak self] in
                self?.handleSceneHotkey(scene)
            }
            hotkey.onUnavailable = { [weak self] in
                guard let self else { return }
                self.audit.write(
                    "scene_hotkey_unavailable",
                    ["scene": scene.rawValue]
                )
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.state == .idle else { return }
                    self.startGlobalHotkeyIfPermitted()
                }
            }
            sceneHotkeys[scene] = hotkey
        }
    }
}
