import AppKit
import AuleumKit
import UniformTypeIdentifiers

extension SettingsWindowController {
    func makePresentationPage() -> NSView {
        configureRolePopup(mainRolePopup)
        configureRolePopup(secondaryRolePopup)
        for slider in [focusXField, focusYField, zoomField, dimField] {
            slider.onChange = { [weak self] in
                self?.presentationAdjustmentsChanged()
            }
        }
        presentationSwitch.target = self
        presentationSwitch.action = #selector(presentationChanged)
        presentationImageLabel.font = .systemFont(ofSize: 11, weight: .medium)
        presentationImageLabel.textColor = AuleumTheme.secondaryInk
        presentationImageLabel.lineBreakMode = .byTruncatingMiddle
        presentationImageButton.target = self
        presentationImageButton.action = #selector(choosePresentationImage)
        presentationClearButton.target = self
        presentationClearButton.action = #selector(clearPresentationImage)
        presentationVideoLabel.font = .systemFont(ofSize: 11, weight: .medium)
        presentationVideoLabel.textColor = AuleumTheme.secondaryInk
        presentationVideoLabel.lineBreakMode = .byTruncatingMiddle
        presentationVideoButton.target = self
        presentationVideoButton.action = #selector(choosePresentationVideo)
        presentationVideoClearButton.target = self
        presentationVideoClearButton.action = #selector(clearPresentationVideo)
        presentationAmbientControl.segmentCount =
            PresentationAmbientStyle.allCases.count
        for (index, style) in PresentationAmbientStyle.allCases.enumerated() {
            presentationAmbientControl.setLabel(style.displayName, forSegment: index)
            presentationAmbientControl.setWidth(58, forSegment: index)
        }
        presentationAmbientControl.trackingMode = .selectOne
        presentationAmbientControl.segmentStyle = .rounded
        presentationAmbientControl.controlSize = .small
        presentationAmbientControl.target = self
        presentationAmbientControl.action = #selector(presentationAmbientChanged)
        presentationAmbientControl.translatesAutoresizingMaskIntoConstraints = false
        clockStylePicker.onSelect = { [weak self] style in
            self?.clockStyleChanged(style)
        }
        presentationLayoutControl.segmentCount = PresentationLayout.allCases.count
        for (index, layout) in PresentationLayout.allCases.enumerated() {
            presentationLayoutControl.setLabel(layout.displayName, forSegment: index)
            presentationLayoutControl.setWidth(72, forSegment: index)
        }
        presentationLayoutControl.trackingMode = .selectOne
        presentationLayoutControl.segmentStyle = .rounded
        presentationLayoutControl.controlSize = .small
        presentationLayoutControl.target = self
        presentationLayoutControl.action = #selector(presentationLayoutChanged)
        presentationLayoutControl.translatesAutoresizingMaskIntoConstraints = false
        presentationComponentControl.segmentCount =
            PresentationComponentBackground.allCases.count
        for (index, style) in PresentationComponentBackground.allCases.enumerated() {
            presentationComponentControl.setLabel(
                style.displayName,
                forSegment: index
            )
            presentationComponentControl.setWidth(58, forSegment: index)
        }
        presentationComponentControl.trackingMode = .selectOne
        presentationComponentControl.segmentStyle = .rounded
        presentationComponentControl.controlSize = .small
        presentationComponentControl.target = self
        presentationComponentControl.action =
            #selector(presentationComponentChanged)
        presentationComponentControl.translatesAutoresizingMaskIntoConstraints = false
        customLayoutResetButton.target = self
        customLayoutResetButton.action = #selector(resetCustomLayout)
        customLayoutResetButton.isHidden = true
        customLayoutResetButton.translatesAutoresizingMaskIntoConstraints = false
        defaultBackdropSwitch.controlSize = .small
        defaultBackdropSwitch.target = self
        defaultBackdropSwitch.action = #selector(presentationLayoutChanged)
        defaultBackdropSwitch.translatesAutoresizingMaskIntoConstraints = false
        for toggle in [
            presentationSecondsSwitch,
            presentationLunarSwitch,
            presentationElapsedSwitch,
        ] {
            toggle.controlSize = .small
            toggle.target = self
            toggle.action = #selector(presentationLayoutChanged)
            toggle.translatesAutoresizingMaskIntoConstraints = false
        }
        previewPresentationButton.target = self
        previewPresentationButton.action = #selector(previewPresentation)

        let imageControls = NSStackView()
        imageControls.orientation = .horizontal
        imageControls.spacing = 8
        imageControls.addArrangedSubview(presentationImageLabel)
        imageControls.addArrangedSubview(presentationImageButton)
        imageControls.addArrangedSubview(presentationClearButton)
        presentationImageLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let videoControls = NSStackView()
        videoControls.orientation = .horizontal
        videoControls.spacing = 8
        videoControls.addArrangedSubview(presentationVideoLabel)
        videoControls.addArrangedSubview(presentationVideoButton)
        videoControls.addArrangedSubview(presentationVideoClearButton)
        presentationVideoLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let switchRow = AuleumSettingRow(
            title: "启用窗口展示模式",
            detail: "默认开启；关闭时改用输出层幕帘。",
            control: presentationSwitch
        )
        let layoutControls = AuleumTheme.stack(
            [presentationLayoutControl, customLayoutResetButton],
            orientation: .horizontal,
            spacing: 8,
            alignment: .centerY
        )
        let layoutRow = AuleumSettingRow(
            title: "版式",
            detail: "卡片位置与留白；自由版式可拖动预览。",
            control: layoutControls
        )
        let componentRow = AuleumSettingRow(
            title: "组件底板",
            detail: "自动：纯色幕布透明，图片和渐变保留底板。",
            control: presentationComponentControl
        )
        let backdropRow = AuleumSettingRow(
            title: "默认背景",
            detail: "没有图片时显示内置深色渐变；关闭后使用幕帘颜色。",
            control: defaultBackdropSwitch
        )
        let imageRow = AuleumSettingRow(
            title: "背景图片",
            detail: "选择后等比铺满，取代默认背景。",
            control: imageControls
        )
        let videoRow = AuleumSettingRow(
            title: "背景视频",
            detail: "循环播放并静音；设置后优先于背景图片。",
            control: videoControls
        )
        let ambientRow = AuleumSettingRow(
            title: "动态背景",
            detail: "没有图片或视频时使用内置缓慢光影。",
            control: presentationAmbientControl
        )
        let mainRoleRow = AuleumSettingRow(
            title: "主屏角色",
            detail: "显示时钟，或保持纯黑幕帘。",
            control: mainRolePopup,
            verticalInset: 7
        )
        let secondaryRoleRow = AuleumSettingRow(
            title: "副屏角色",
            detail: "其余显示器统一使用这个角色。",
            control: secondaryRolePopup,
            verticalInset: 7
        )
        let focusXRow = AuleumSettingRow(
            title: "横向焦点",
            detail: "放大时保留画面的左右区域。",
            control: focusXField,
            verticalInset: 7
        )
        let focusYRow = AuleumSettingRow(
            title: "纵向焦点",
            detail: "放大时保留画面的上下区域。",
            control: focusYField,
            verticalInset: 7
        )
        let zoomRow = AuleumSettingRow(
            title: "背景缩放",
            detail: "放大背景，时钟位置不变。",
            control: zoomField,
            verticalInset: 7
        )
        let dimRow = AuleumSettingRow(
            title: "额外暗化",
            detail: "明亮背景上提高文字对比度。",
            control: dimField,
            verticalInset: 7
        )
        func widgetToggle(_ title: String, _ toggle: NSSwitch) -> NSStackView {
            AuleumTheme.stack(
                [
                    toggle,
                    AuleumTheme.label(
                        title,
                        size: 10.5,
                        color: AuleumTheme.secondaryInk
                    ),
                ],
                orientation: .horizontal,
                spacing: 5,
                alignment: .centerY
            )
        }
        let widgetControls = AuleumTheme.stack(
            [
                widgetToggle("秒", presentationSecondsSwitch),
                widgetToggle("农历", presentationLunarSwitch),
                widgetToggle("计时", presentationElapsedSwitch),
            ],
            orientation: .horizontal,
            spacing: 14,
            alignment: .centerY
        )
        let widgetsRow = AuleumSettingRow(
            title: "显示组件",
            detail: "秒、农历和计时徽标。",
            control: widgetControls,
            verticalInset: 7
        )
        let clockTitle = AuleumTheme.label(
            "时钟样式",
            size: 12.5,
            weight: .medium
        )
        let clockDetail = AuleumTheme.label(
            "只改变外观，日期和农历始终保留。",
            size: 10.5,
            color: AuleumTheme.secondaryInk
        )
        let clockStack = AuleumTheme.stack(
            [clockTitle, clockDetail, clockStylePicker],
            spacing: 6
        )
        let clockContainer = NSView()
        clockContainer.addSubview(clockStack)
        clockStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            clockStack.leadingAnchor.constraint(equalTo: clockContainer.leadingAnchor),
            clockStack.trailingAnchor.constraint(equalTo: clockContainer.trailingAnchor),
            clockStack.topAnchor.constraint(equalTo: clockContainer.topAnchor, constant: 8),
            clockStack.bottomAnchor.constraint(equalTo: clockContainer.bottomAnchor, constant: -6),
        ])
        let basicCard = card(containing: [
            switchRow,
            layoutRow,
            componentRow,
            backdropRow,
            imageRow,
            videoRow,
            ambientRow,
        ])
        let advancedCard = card(containing: [
            clockContainer,
            widgetsRow,
            twoColumnRow(mainRoleRow, secondaryRoleRow),
            twoColumnRow(focusXRow, focusYRow),
            twoColumnRow(zoomRow, dimRow),
        ])
        clockStylePicker.widthAnchor.constraint(equalTo: clockStack.widthAnchor).isActive = true

        let previewCard = AuleumCardView(
            padding: NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        )
        let previewLabel = AuleumTheme.label(
            "预览",
            size: 10.5,
            weight: .semibold,
            color: AuleumTheme.tertiaryInk
        )
        previewCard.contentView.addSubview(previewLabel)
        previewCard.contentView.addSubview(previewPresentationButton)
        previewCard.contentView.addSubview(presentationPreview)
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewPresentationButton.translatesAutoresizingMaskIntoConstraints = false
        presentationPreview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewLabel.leadingAnchor.constraint(
                equalTo: previewCard.contentView.leadingAnchor,
                constant: 14
            ),
            previewLabel.centerYAnchor.constraint(
                equalTo: previewPresentationButton.centerYAnchor
            ),
            previewPresentationButton.topAnchor.constraint(
                equalTo: previewCard.contentView.topAnchor,
                constant: 10
            ),
            previewPresentationButton.trailingAnchor.constraint(
                equalTo: previewCard.contentView.trailingAnchor,
                constant: -10
            ),
            presentationPreview.leadingAnchor.constraint(
                equalTo: previewCard.contentView.leadingAnchor,
                constant: 12
            ),
            presentationPreview.trailingAnchor.constraint(
                equalTo: previewCard.contentView.trailingAnchor,
                constant: -12
            ),
            presentationPreview.topAnchor.constraint(
                equalTo: previewPresentationButton.bottomAnchor,
                constant: 10
            ),
            presentationPreview.bottomAnchor.constraint(
                equalTo: previewCard.contentView.bottomAnchor,
                constant: -12
            ),
        ])
        presentationPreviewHeight = presentationPreview.heightAnchor.constraint(
            equalToConstant: selectedPresentationLayout == .custom ? 300 : 190
        )
        presentationPreviewHeight?.isActive = true
        presentationPreview.onCustomLayoutChange = { [weak self] layout in
            guard let self else { return }
            self.draftCustomLayout = layout
            self.refreshScenePreview()
            self.updateDirtyState()
        }

        updatePresentationControls()
        return page(
            views: [basicCard, previewCard, advancedCard],
            spacing: AuleumTheme.sectionSpacing
        )
    }

    func updatePresentationControls() {
        let presentationEnabled = presentationSwitch.state == .on
        presentationImageButton.title = presentationImagePath.isEmpty
            ? "选择图片…"
            : "更换图片…"
        presentationImageButton.isEnabled = presentationEnabled
        presentationClearButton.isEnabled = presentationEnabled
            && !presentationImagePath.isEmpty
        presentationVideoButton.title = presentationVideoPath.isEmpty
            ? "选择视频…"
            : "更换视频…"
        presentationVideoButton.isEnabled = presentationEnabled
        presentationVideoClearButton.isEnabled = presentationEnabled
            && !presentationVideoPath.isEmpty
        let ambientIndex = PresentationAmbientStyle.allCases.firstIndex(
            of: presentationAmbientStyle
        ) ?? 0
        if presentationAmbientControl.segmentCount > ambientIndex {
            presentationAmbientControl.selectedSegment = ambientIndex
        }
        presentationAmbientControl.isEnabled = presentationEnabled
        presentationAmbientControl.alphaValue = presentationEnabled ? 1 : 0.5
        mainRolePopup.isEnabled = presentationEnabled
        secondaryRolePopup.isEnabled = presentationEnabled
        focusXField.isEnabled = presentationEnabled
        focusYField.isEnabled = presentationEnabled
        zoomField.isEnabled = presentationEnabled
        dimField.isEnabled = presentationEnabled
        presentationLayoutControl.isEnabled = presentationEnabled
        presentationComponentControl.isEnabled = presentationEnabled
            && selectedPresentationLayout != .minimal
        defaultBackdropSwitch.isEnabled = presentationEnabled
        for toggle in [
            presentationSecondsSwitch,
            presentationLunarSwitch,
            presentationElapsedSwitch,
        ] {
            toggle.isEnabled = presentationEnabled
        }
        clockStylePicker.alphaValue = presentationEnabled ? 1 : 0.5
        presentationPreview.alphaValue = 1
        customLayoutResetButton.isHidden = selectedPresentationLayout != .custom
        customLayoutResetButton.isEnabled = presentationEnabled
        updatePreviewHeights()
    }

    /// 自由排版需要更高的预览才能把时钟和上下文字分开；
    /// 其它版式保持原来的紧凑高度。
    func updatePreviewHeights() {
        let height: CGFloat = selectedPresentationLayout == .custom ? 300 : 190
        presentationPreviewHeight?.constant = height
        scenePreviewHeight?.constant = height
    }

    var selectedPresentationLayout: PresentationLayout {
        let layouts = PresentationLayout.allCases
        let index = presentationLayoutControl.selectedSegment
        guard layouts.indices.contains(index) else { return .centered }
        return layouts[index]
    }

    var selectedComponentBackground: PresentationComponentBackground {
        let styles = PresentationComponentBackground.allCases
        let index = presentationComponentControl.selectedSegment
        guard styles.indices.contains(index) else { return .auto }
        return styles[index]
    }

    var selectedClockWidgets: PresentationClockWidgets {
        PresentationClockWidgets(
            showsSeconds: presentationSecondsSwitch.state == .on,
            showsLunar: presentationLunarSwitch.state == .on,
            showsElapsed: presentationElapsedSwitch.state == .on
        )
    }

    func configureRolePopup(_ popup: NSPopUpButton) {
        popup.removeAllItems()
        popup.addItems(withTitles: AuleumDisplayRole.allCases.map(\.displayName))
        popup.controlSize = .small
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: 132).isActive = true
    }

    func selectedRole(_ popup: NSPopUpButton) -> AuleumDisplayRole {
        let roles = AuleumDisplayRole.allCases
        guard roles.indices.contains(popup.indexOfSelectedItem) else {
            return .presentation
        }
        return roles[popup.indexOfSelectedItem]
    }

    func refreshPresentationPreview(startedAt: Date? = nil) {
        let freeform = selectedPresentationLayout == .custom
        presentationPreview.update(
            color: colorWell.color,
            imagePath: presentationImagePath,
            videoPath: presentationVideoPath.isEmpty
                ? nil
                : presentationVideoPath,
            ambientStyle: presentationAmbientStyle,
            clockStyle: selectedClockStyle,
            imageFocus: CGPoint(
                x: focusXField.value,
                y: focusYField.value
            ),
            imageZoom: zoomField.value,
            imageDim: dimField.value,
            layout: selectedPresentationLayout,
            customLayout: draftCustomLayout,
            componentBackground: selectedComponentBackground,
            isCustomLayoutEditing: presentationSwitch.state == .on && freeform,
            usesDefaultBackdrop: defaultBackdropSwitch.state == .on,
            widgets: selectedClockWidgets,
            startedAt: startedAt,
            // 自由排版时给空提示一个可拖动的示例位置；
            // 真实幕帘仍然只显示当前场景实际提供的内容。
            messageText: freeform ? "场景提示" : "",
            returnText: freeform ? "预计返回时间" : ""
        )
    }

    @objc func presentationAdjustmentsChanged() {
        refreshPresentationPreview()
        refreshScenePreview()
    }

    @objc func presentationLayoutChanged() {
        updatePreviewHeights()
        customLayoutResetButton.isHidden = selectedPresentationLayout != .custom
        presentationComponentControl.isEnabled =
            presentationSwitch.state == .on
            && selectedPresentationLayout != .minimal
        refreshPresentationPreview()
        refreshScenePreview()
        updateDirtyState()
    }

    @objc func presentationComponentChanged() {
        refreshPresentationPreview()
        refreshScenePreview()
        updateDirtyState()
    }

    @objc func resetCustomLayout() {
        draftCustomLayout = .default
        refreshPresentationPreview()
        refreshScenePreview()
        updateDirtyState()
    }

    @objc func presentationChanged() {
        diagnosticsModeValue.stringValue = presentationSwitch.state == .on
            ? "展示模式 · \(selectedClockStyle.displayName)"
            : "输出层 gamma"
        updatePresentationControls()
        refreshPresentationPreview()
        refreshScenePreview()
    }

    func clockStyleChanged(_ style: PresentationClockStyle) {
        diagnosticsModeValue.stringValue = presentationSwitch.state == .on
            ? "展示模式 · \(style.displayName)"
            : "输出层 gamma"
        refreshPresentationPreview()
        refreshScenePreview()
    }

    @objc func previewPresentation() {
        let imagePath = presentationImagePath
        if !imagePath.isEmpty,
           !PresentationBackgroundLoader.isLoadable(path: imagePath) {
            presentAlert(
                title: "背景图无法读取",
                message: "请选择有效的图片文件，或清除路径改用纯色背景。"
            )
            return
        }
        let videoPath = presentationVideoPath
        if !videoPath.isEmpty,
           !PresentationVideoLoader.isLoadable(path: videoPath) {
            presentAlert(
                title: "背景视频无法读取",
                message: "请选择有效的视频文件，或清除路径改用图片或默认背景。"
            )
            return
        }
        guard let onPreviewPresentation else {
            presentAlert(
                title: "全屏试看不可用",
                message: "请从 Auleum 的设置窗口打开此页面。"
            )
            return
        }
        let color = colorWell.color.usingColorSpace(.sRGB) ?? .black
        onPreviewPresentation(
            PresentationPreviewConfiguration(
                color: AuleumColor(
                    red: Double(color.redComponent),
                    green: Double(color.greenComponent),
                    blue: Double(color.blueComponent)
                ),
                imagePath: imagePath.isEmpty ? nil : imagePath,
                videoPath: videoPath.isEmpty ? nil : videoPath,
                ambientStyle: presentationAmbientStyle,
                clockStyle: selectedClockStyle,
                imageFocus: CGPoint(
                    x: focusXField.value,
                    y: focusYField.value
                ),
                imageZoom: zoomField.value,
                imageDim: dimField.value,
                layout: selectedPresentationLayout,
                customLayout: draftCustomLayout,
                usesDefaultBackdrop: defaultBackdropSwitch.state == .on,
                componentBackground: selectedComponentBackground,
                widgets: selectedClockWidgets,
                duration: 8
            )
        )
    }

    @objc func choosePresentationImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "使用这张图片"
        if panel.runModal() == .OK, let url = panel.url {
            presentationImagePath = url.path
            presentationImageLabel.stringValue = url.lastPathComponent
            // 图片和视频只保留一个主背景，避免两个入口互相覆盖。
            presentationVideoPath = ""
            presentationVideoLabel.stringValue = "未选择"
            refreshPresentationPreview()
            refreshScenePreview()
            updatePresentationControls()
        }
    }

    @objc func clearPresentationImage() {
        presentationImagePath = ""
        presentationImageLabel.stringValue = "纯色背景"
        refreshPresentationPreview()
        refreshScenePreview()
        updatePresentationControls()
    }

    @objc func choosePresentationVideo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = PresentationVideoLoader.allowedContentTypes
        panel.prompt = "使用这个视频"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard PresentationVideoLoader.isLoadable(path: url.path) else {
            presentAlert(
                title: "视频格式不受支持",
                message: "请选择 MOV、MP4 或 M4V 等 AVFoundation 可播放的视频文件。"
            )
            return
        }
        presentationVideoButton.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            let playable = await PresentationVideoLoader.isPlayable(
                path: url.path
            )
            self.presentationVideoButton.isEnabled =
                self.presentationSwitch.state == .on
            guard playable else {
                self.presentAlert(
                    title: "视频无法播放",
                    message: "文件没有可解码的视频轨，或格式不被系统支持。"
                )
                return
            }
            self.presentationVideoPath = url.path
            self.presentationVideoLabel.stringValue = url.lastPathComponent
            self.presentationImagePath = ""
            self.presentationImageLabel.stringValue = "纯色背景"
            self.refreshPresentationPreview()
            self.refreshScenePreview()
            self.updatePresentationControls()
        }
    }

    @objc func clearPresentationVideo() {
        presentationVideoPath = ""
        presentationVideoLabel.stringValue = "未选择"
        refreshPresentationPreview()
        refreshScenePreview()
        updatePresentationControls()
    }

    @objc func presentationAmbientChanged() {
        let styles = PresentationAmbientStyle.allCases
        let index = presentationAmbientControl.selectedSegment
        guard styles.indices.contains(index) else { return }
        presentationAmbientStyle = styles[index]
        refreshPresentationPreview()
        refreshScenePreview()
        updateDirtyState()
    }

    @objc func resetColor() {
        colorWell.color = .black
        refreshPresentationPreview()
        refreshScenePreview()
    }

    @objc func colorChanged() {
        refreshPresentationPreview()
        refreshScenePreview()
    }

    var selectedClockStyle: PresentationClockStyle {
        clockStylePicker.selectedStyle
    }
}
