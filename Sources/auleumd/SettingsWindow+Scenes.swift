import AppKit
import AuleumKit
import UniformTypeIdentifiers

extension SettingsWindowController {
    func makeScenesPage() -> NSView {
        configureSceneControls()

        let title = AuleumTheme.label("场景预设", size: 13, weight: .semibold)
        let subtitle = AuleumTheme.label(
            "每个场景独立保存时长、背景、时钟与提示。",
            size: 10.5,
            color: AuleumTheme.secondaryInk
        )
        let header = AuleumTheme.stack([title, subtitle], spacing: 3)
        header.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let headerRow = AuleumTheme.stack(
            [header, headerSpacer, sceneResetButton],
            orientation: .horizontal,
            spacing: 12,
            alignment: .top
        )

        sceneSelector.segmentCount = AuleumScene.allCases.count
        for (index, scene) in AuleumScene.allCases.enumerated() {
            sceneSelector.setLabel(scene.title, forSegment: index)
            sceneSelector.setWidth(0, forSegment: index)
        }
        sceneSelector.selectedSegment = 0
        sceneSelector.trackingMode = .selectOne
        sceneSelector.segmentStyle = .rounded
        sceneSelector.target = self
        sceneSelector.action = #selector(sceneSelectorChanged)
        sceneSelector.translatesAutoresizingMaskIntoConstraints = false
        sceneSelector.setContentHuggingPriority(.defaultLow, for: .horizontal)

        sceneDetailLabel.font = .systemFont(ofSize: 10.5)
        sceneDetailLabel.textColor = AuleumTheme.secondaryInk
        sceneDetailLabel.maximumNumberOfLines = 2
        sceneDetailLabel.lineBreakMode = .byWordWrapping

        let hotkeyRow = AuleumSettingRow(
            title: "场景快捷键",
            detail: "已起幕时不会切换场景。",
            control: sceneHotkeyButton
        )
        let selectorContent = AuleumTheme.stack(
            [headerRow, sceneSelector, sceneDetailLabel, hotkeyRow],
            spacing: 10
        )
        let selectorCard = AuleumCardView()
        selectorCard.contentView.addSubview(selectorContent)
        pin(selectorContent, to: selectorCard.contentView)
        headerRow.widthAnchor.constraint(equalTo: selectorContent.widthAnchor)
            .isActive = true
        sceneSelector.widthAnchor.constraint(equalTo: selectorContent.widthAnchor)
            .isActive = true
        hotkeyRow.widthAnchor.constraint(equalTo: selectorContent.widthAnchor)
            .isActive = true

        let previewCard = AuleumCardView(
            padding: NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        )
        previewCard.contentView.addSubview(scenePreview)
        pin(scenePreview, to: previewCard.contentView)
        scenePreviewHeight = scenePreview.heightAnchor.constraint(
            equalToConstant: selectedPresentationLayout == .custom ? 300 : 190
        )
        scenePreviewHeight?.isActive = true

        let presentationRow = AuleumSettingRow(
            title: "展示方式",
            detail: "纯黑幕帘，或背景与时钟。",
            control: scenePresentationPopup
        )
        let minutesRow = AuleumSettingRow(
            title: "保护时长",
            detail: "到时只发起验证；0 表示不限时。",
            control: sceneMinuteField
        )
        let messageRow = AuleumSettingRow(
            title: "提示文字",
            detail: "显示在时钟上方。",
            control: sceneMessageField
        )
        let returnRow = AuleumSettingRow(
            title: "显示预计返回时间",
            detail: "按保护时长推算，显示在时钟下方。",
            control: sceneReturnSwitch
        )

        let imageControls = NSStackView()
        imageControls.orientation = .horizontal
        imageControls.spacing = 8
        imageControls.addArrangedSubview(sceneImageLabel)
        imageControls.addArrangedSubview(sceneImageButton)
        imageControls.addArrangedSubview(sceneImageClearButton)
        sceneImageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sceneImageLabel.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        let imageRow = AuleumSettingRow(
            title: "背景图片",
            detail: "留空时跟随展示模式的全局背景。",
            control: imageControls
        )
        let clockRow = AuleumSettingRow(
            title: "时钟样式",
            detail: "跟随全局，或单独指定。",
            control: sceneClockPopup
        )

        let mainRoleRow = AuleumSettingRow(
            title: "主屏角色",
            detail: "覆盖全局主屏角色。",
            control: sceneMainRolePopup,
            verticalInset: 7
        )
        let secondaryRoleRow = AuleumSettingRow(
            title: "副屏角色",
            detail: "其余显示器使用这个角色。",
            control: sceneSecondaryRolePopup,
            verticalInset: 7
        )
        let roleRow = twoColumnRow(mainRoleRow, secondaryRoleRow)

        let basicRow = twoColumnRow(presentationRow, minutesRow)
        let timingRow = twoColumnRow(returnRow, clockRow)
        let detailCard = card(containing: [
            basicRow,
            messageRow,
            timingRow,
            imageRow,
            roleRow,
        ])

        loadSelectedScene()
        return page(
            views: [selectorCard, previewCard, detailCard],
            spacing: AuleumTheme.sectionSpacing
        )
    }

    func configureSceneControls() {
        sceneMinuteField.onChange = { [weak self] in
            self?.sceneControlChanged()
        }
        scenePresentationPopup.removeAllItems()
        scenePresentationPopup.addItems(withTitles: ["纯黑幕帘", "背景与时钟"])
        scenePresentationPopup.controlSize = .small
        scenePresentationPopup.translatesAutoresizingMaskIntoConstraints = false
        scenePresentationPopup.widthAnchor.constraint(equalToConstant: 148)
            .isActive = true
        scenePresentationPopup.target = self
        scenePresentationPopup.action = #selector(sceneControlChanged)

        sceneClockPopup.removeAllItems()
        sceneClockPopup.addItems(withTitles: [
            "跟随展示设置",
            PresentationClockStyle.digital.displayName,
            PresentationClockStyle.analog.displayName,
            PresentationClockStyle.editorial.displayName,
        ])
        sceneClockPopup.controlSize = .small
        sceneClockPopup.translatesAutoresizingMaskIntoConstraints = false
        sceneClockPopup.widthAnchor.constraint(equalToConstant: 148)
            .isActive = true
        sceneClockPopup.target = self
        sceneClockPopup.action = #selector(sceneControlChanged)

        sceneMessageField.isBezeled = true
        sceneMessageField.bezelStyle = .roundedBezel
        sceneMessageField.drawsBackground = true
        sceneMessageField.backgroundColor = AuleumTheme.field
        sceneMessageField.font = .systemFont(ofSize: 11)
        sceneMessageField.textColor = AuleumTheme.ink
        sceneMessageField.placeholderString = "例如：会议中，预计 18:30 回来"
        sceneMessageField.delegate = self
        sceneMessageField.translatesAutoresizingMaskIntoConstraints = false
        sceneMessageField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280)
            .isActive = true

        sceneReturnSwitch.controlSize = .small
        sceneReturnSwitch.target = self
        sceneReturnSwitch.action = #selector(sceneControlChanged)

        sceneImageLabel.font = .systemFont(ofSize: 11, weight: .medium)
        sceneImageLabel.textColor = AuleumTheme.secondaryInk
        sceneImageLabel.lineBreakMode = .byTruncatingMiddle
        sceneImageButton.target = self
        sceneImageButton.action = #selector(chooseSceneImage)
        sceneImageClearButton.target = self
        sceneImageClearButton.action = #selector(clearSceneImage)
        sceneResetButton.target = self
        sceneResetButton.action = #selector(resetSceneProfile)

        sceneHotkeyButton.translatesAutoresizingMaskIntoConstraints = false
        sceneHotkeyButton.widthAnchor.constraint(equalToConstant: 124)
            .isActive = true
        sceneHotkeyButton.heightAnchor.constraint(equalToConstant: 32)
            .isActive = true
        sceneHotkeyButton.onCapture = { [weak self] binding in
            guard let self else { return }
            self.sceneHotkeys[self.selectedScene] = SceneHotkey(
                binding: binding
            )
            self.updateSceneDetailLabel()
            self.updateSceneControls()
            self.updateDirtyState()
        }

        configureSceneRolePopup(sceneMainRolePopup)
        configureSceneRolePopup(sceneSecondaryRolePopup)
    }

    func configureSceneRolePopup(_ popup: NSPopUpButton) {
        popup.removeAllItems()
        popup.addItems(withTitles: ["跟随全局", "纯黑", "展示"])
        popup.controlSize = .small
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: 120).isActive = true
        popup.target = self
        popup.action = #selector(sceneControlChanged)
    }

    func loadSceneProfiles() {
        sceneHotkeys = Dictionary(
            uniqueKeysWithValues: AuleumScene.allCases.map {
                ($0, config.sceneHotkey(for: $0))
            }
        )
        sceneProfiles = Dictionary(
            uniqueKeysWithValues: AuleumScene.allCases.map {
                ($0, config.sceneProfile(for: $0))
            }
        )
        sceneSelector.selectedSegment = AuleumScene.allCases.firstIndex(
            of: selectedScene
        ) ?? 0
        loadSelectedScene()
    }

    func loadSelectedScene() {
        guard let profile = sceneProfiles[selectedScene] else { return }
        sceneSelector.selectedSegment = AuleumScene.allCases.firstIndex(
            of: selectedScene
        ) ?? 0
        sceneHotkeyButton.binding = (
            sceneHotkeys[selectedScene] ?? selectedScene.defaultHotkey
        ).binding
        updateSceneDetailLabel()
        sceneMinuteField.value = Double(profile.protectionMinutes)
        scenePresentationPopup.selectItem(at: profile.usesPresentation ? 1 : 0)
        sceneMessageField.stringValue = profile.message
        sceneReturnSwitch.state = profile.showsReturnTime ? .on : .off
        if profile.clockStyle.isEmpty {
            sceneClockPopup.selectItem(at: 0)
        } else {
            sceneClockPopup.selectItem(at: 1 + (
                PresentationClockStyle.allCases.firstIndex(
                    of: PresentationClockStyle.storedValue(profile.clockStyle)
                ) ?? 0
            ))
        }
        selectSceneRole(profile.mainDisplayRole, in: sceneMainRolePopup)
        selectSceneRole(profile.secondaryDisplayRole, in: sceneSecondaryRolePopup)
        updateSceneImageLabel(profile.backgroundImagePath)
        updateSceneControls()
        refreshScenePreview()
    }

    func commitSceneProfile() {
        guard let previous = sceneProfiles[selectedScene] else { return }
        let clockStyle: String
        switch sceneClockPopup.indexOfSelectedItem {
        case 1: clockStyle = PresentationClockStyle.digital.rawValue
        case 2: clockStyle = PresentationClockStyle.analog.rawValue
        case 3: clockStyle = PresentationClockStyle.editorial.rawValue
        default: clockStyle = ""
        }
        let profile = AuleumSceneProfile(
            protectionMinutes: Int(sceneMinuteField.value.rounded()),
            usesPresentation: scenePresentationPopup.indexOfSelectedItem == 1,
            backgroundImagePath: previous.backgroundImagePath,
            clockStyle: clockStyle,
            message: sceneMessageField.stringValue,
            showsReturnTime: sceneReturnSwitch.state == .on,
            mainDisplayRole: selectedSceneRole(sceneMainRolePopup),
            secondaryDisplayRole: selectedSceneRole(sceneSecondaryRolePopup)
        )
        sceneProfiles[selectedScene] = profile
    }

    func updateSceneControls() {
        let presentation = scenePresentationPopup.indexOfSelectedItem == 1
        let profile = sceneProfiles[selectedScene] ?? selectedScene.defaultProfile
        let hotkey = sceneHotkeys[selectedScene] ?? selectedScene.defaultHotkey
        sceneResetButton.isEnabled = profile != selectedScene.defaultProfile
            || hotkey != selectedScene.defaultHotkey
        sceneMinuteField.isEnabled = true
        sceneReturnSwitch.isEnabled = presentation
        sceneMessageField.isEnabled = presentation
        sceneImageButton.isEnabled = presentation
        sceneImageClearButton.isEnabled = presentation
            && !(sceneProfiles[selectedScene]?.backgroundImagePath.isEmpty ?? true)
        sceneClockPopup.isEnabled = presentation
        sceneMainRolePopup.isEnabled = presentation
        sceneSecondaryRolePopup.isEnabled = presentation
        sceneImageLabel.textColor = presentation
            ? AuleumTheme.secondaryInk
            : AuleumTheme.tertiaryInk
    }

    func refreshScenePreview() {
        guard let profile = sceneProfiles[selectedScene] else { return }
        let displayEnabled = presentationSwitch.state == .on
            && profile.usesPresentation
        let clockStyle: PresentationClockStyle
        if profile.clockStyle.isEmpty {
            clockStyle = selectedClockStyle
        } else {
            clockStyle = PresentationClockStyle.storedValue(profile.clockStyle)
        }
        let imagePath = displayEnabled
            ? (profile.backgroundImagePath.isEmpty
                ? (presentationImagePath.isEmpty
                    ? nil
                    : presentationImagePath)
                : profile.backgroundImagePath)
            : nil
        let returnText = displayEnabled
            && profile.showsReturnTime
            && profile.protectionMinutes > 0
            ? estimatedReturnText(minutes: profile.protectionMinutes)
            : ""
        scenePreview.update(
            color: colorWell.color,
            imagePath: imagePath,
            clockStyle: clockStyle,
            imageFocus: CGPoint(
                x: focusXField.value,
                y: focusYField.value
            ),
            imageZoom: zoomField.value,
            imageDim: dimField.value,
            layout: selectedPresentationLayout,
            customLayout: draftCustomLayout,
            componentBackground: selectedComponentBackground,
            usesDefaultBackdrop: defaultBackdropSwitch.state == .on,
            widgets: selectedClockWidgets,
            startedAt: Date().addingTimeInterval(-42 * 60),
            messageText: displayEnabled ? profile.message : "",
            returnText: returnText,
            displayEnabled: displayEnabled
        )
    }

    func estimatedReturnText(minutes: Int) -> String {
        let date = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let components = Calendar.current.dateComponents(
            [.hour, .minute],
            from: date
        )
        return String(
            format: "预计 %02d:%02d 回来",
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    func updateSceneImageLabel(_ path: String) {
        if path.isEmpty {
            let global = presentationImagePath
            sceneImageLabel.stringValue = global.isEmpty
                ? "跟随全局背景"
                : "跟随全局 · \(URL(fileURLWithPath: global).lastPathComponent)"
        } else {
            sceneImageLabel.stringValue = URL(fileURLWithPath: path).lastPathComponent
        }
        sceneImageClearButton.isEnabled = !path.isEmpty
            && scenePresentationPopup.indexOfSelectedItem == 1
    }

    func selectedSceneRole(_ popup: NSPopUpButton) -> String? {
        switch popup.indexOfSelectedItem {
        case 1: return AuleumDisplayRole.black.rawValue
        case 2: return AuleumDisplayRole.presentation.rawValue
        default: return nil
        }
    }

    func selectSceneRole(_ role: String?, in popup: NSPopUpButton) {
        guard let role, let parsed = AuleumDisplayRole(rawValue: role) else {
            popup.selectItem(at: 0)
            return
        }
        popup.selectItem(at: parsed == .black ? 1 : 2)
    }

    @objc func sceneSelectorChanged() {
        commitSceneProfile()
        let index = sceneSelector.selectedSegment
        guard AuleumScene.allCases.indices.contains(index) else { return }
        selectedScene = AuleumScene.allCases[index]
        loadSelectedScene()
        updateDirtyState()
    }

    @objc func resetSceneProfile() {
        sceneProfiles[selectedScene] = selectedScene.defaultProfile
        sceneHotkeys[selectedScene] = selectedScene.defaultHotkey
        loadSelectedScene()
        updateDirtyState()
    }

    @objc func sceneControlChanged() {
        commitSceneProfile()
        updateSceneDetailLabel()
        updateSceneImageLabel(sceneProfiles[selectedScene]?.backgroundImagePath ?? "")
        updateSceneControls()
        refreshScenePreview()
        updateDirtyState()
    }

    func updateSceneDetailLabel() {
        let profile = sceneProfiles[selectedScene] ?? selectedScene.defaultProfile
        let hotkey = sceneHotkeys[selectedScene] ?? selectedScene.defaultHotkey
        let suffix = profile == selectedScene.defaultProfile
            && hotkey == selectedScene.defaultHotkey
            ? ""
            : " · 已自定义"
        sceneDetailLabel.stringValue = selectedScene.detail + suffix
    }

    @objc func chooseSceneImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "使用这张图片"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        commitSceneProfile()
        guard var profile = sceneProfiles[selectedScene] else { return }
        profile.backgroundImagePath = url.path
        sceneProfiles[selectedScene] = profile
        updateSceneImageLabel(profile.backgroundImagePath)
        refreshScenePreview()
        updateDirtyState()
    }

    @objc func clearSceneImage() {
        commitSceneProfile()
        guard var profile = sceneProfiles[selectedScene] else { return }
        profile.backgroundImagePath = ""
        sceneProfiles[selectedScene] = profile
        updateSceneImageLabel("")
        refreshScenePreview()
        updateDirtyState()
    }
}

extension SettingsWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === sceneMessageField else {
            return
        }
        commitSceneProfile()
        refreshScenePreview()
        updateDirtyState()
    }
}
