import AppKit
import AuleumKit

final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    var onFinish: ((Bool) -> Void)?
    var onOpenSettings: (() -> Void)?

    private let hotkey: String
    private var currentStep = 0
    private var dontShowAgain = true
    private var didFinish = false

    private let progressStack = NSStackView()
    private let stepCountLabel = NSTextField(labelWithString: "")
    private let headlineLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let bodyHost = NSView()
    private let bodyCard = AuleumCardView(
        padding: NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
    )
    private let backButton = AuleumButton(
        title: "上一步",
        symbol: "chevron.left",
        style: .secondary,
        target: nil,
        action: nil
    )
    private let nextButton = AuleumButton(
        title: "继续",
        symbol: "chevron.right",
        style: .primary,
        target: nil,
        action: nil
    )
    private var progressBars: [NSView] = []
    private var stepViews: [NSView] = []

    private let steps: [(title: String, subtitle: String)] = [
        (
            "幕帘挡人眼，不挡 Agent",
            "同一块屏幕有两种现实：你看不到内容，通过 Auleum 访问的 Agent 仍能正常工作。"
        ),
        (
            "起幕和撤幕都很直接",
            "起幕不打断工作；撤幕默认只认 Touch ID，也可以在设置里开启密码兜底。"
        ),
        (
            "按你的方式开始使用",
            "常用操作都在菜单栏，展示模式和自动化可以稍后在设置里调整。"
        ),
    ]

    init(hotkey: String) {
        self.hotkey = hotkey
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 610),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        AuleumWindowChrome.apply(to: window, title: "欢迎使用 Auleum")
        AuleumWindowChrome.centerOnActiveScreen(window)
        super.init(window: window)
        window.delegate = self
        buildUI()
        renderStep()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        finish()
    }

#if DEBUG
    func previewStep(_ index: Int) {
        currentStep = min(steps.count - 1, max(0, index))
        renderStep()
    }
#endif

    private func buildUI() {
        guard let window else { return }
        let root = NSView()
        root.addSubview(AuleumBackdropView())
        root.subviews[0].translatesAutoresizingMaskIntoConstraints = false

        let brandIcon = AuleumBrandIconView(size: 40)
        let brandTitle = AuleumTheme.label(
            "AULEUM",
            size: 13,
            weight: .bold
        )
        brandTitle.attributedStringValue = NSAttributedString(
            string: "AULEUM",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .kern: 1.5,
                .foregroundColor: AuleumTheme.ink,
            ]
        )
        let brandSubtitle = AuleumTheme.label(
            "第一次使用",
            size: 10,
            color: AuleumTheme.secondaryInk
        )
        let brandText = AuleumTheme.stack([brandTitle, brandSubtitle], spacing: 1)
        let brand = AuleumTheme.stack(
            [brandIcon, brandText],
            orientation: .horizontal,
            spacing: 12,
            alignment: .centerY
        )

        stepCountLabel.font = .monospacedDigitSystemFont(
            ofSize: 10.5,
            weight: .medium
        )
        stepCountLabel.textColor = AuleumTheme.secondaryInk
        stepCountLabel.alignment = .right
        let brandSpacer = NSView()
        brandSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let topRow = AuleumTheme.stack(
            [brand, brandSpacer, stepCountLabel],
            orientation: .horizontal,
            spacing: 12,
            alignment: .centerY
        )

        progressStack.orientation = .horizontal
        progressStack.spacing = 7
        progressStack.alignment = .centerY
        progressStack.distribution = .fillEqually
        progressBars = (0..<steps.count).map { _ in
            let bar = NSView()
            bar.wantsLayer = true
            bar.layer?.cornerRadius = 2
            bar.heightAnchor.constraint(equalToConstant: 4).isActive = true
            progressStack.addArrangedSubview(bar)
            return bar
        }

        headlineLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        headlineLabel.textColor = AuleumTheme.ink
        headlineLabel.maximumNumberOfLines = 2
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.textColor = AuleumTheme.secondaryInk
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byWordWrapping
        let intro = AuleumTheme.stack([headlineLabel, detailLabel], spacing: 7)

        bodyHost.translatesAutoresizingMaskIntoConstraints = false
        bodyCard.contentView.addSubview(bodyHost)
        NSLayoutConstraint.activate([
            bodyHost.leadingAnchor.constraint(equalTo: bodyCard.contentView.leadingAnchor),
            bodyHost.trailingAnchor.constraint(equalTo: bodyCard.contentView.trailingAnchor),
            bodyHost.topAnchor.constraint(equalTo: bodyCard.contentView.topAnchor),
            bodyHost.bottomAnchor.constraint(equalTo: bodyCard.contentView.bottomAnchor),
            bodyCard.heightAnchor.constraint(equalToConstant: 300),
        ])
        stepViews = [
            makePrincipleStep(),
            makeOperationStep(),
            makeReadyStep(),
        ]
        for page in stepViews {
            bodyHost.addSubview(page)
            page.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: bodyHost.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: bodyHost.trailingAnchor),
                page.centerYAnchor.constraint(equalTo: bodyHost.centerYAnchor),
                page.topAnchor.constraint(greaterThanOrEqualTo: bodyHost.topAnchor),
                page.bottomAnchor.constraint(lessThanOrEqualTo: bodyHost.bottomAnchor),
            ])
        }

        let checkbox = NSButton(
            checkboxWithTitle: "以后不再显示这个说明",
            target: self,
            action: #selector(toggleDontShow)
        )
        checkbox.state = .on
        checkbox.font = .systemFont(ofSize: 10.5)

        let settingsButton = AuleumButton(
            title: "打开设置",
            symbol: "slider.horizontal.3",
            style: .secondary,
            target: self,
            action: #selector(openSettings)
        )
        backButton.target = self
        backButton.action = #selector(backClicked)
        nextButton.target = self
        nextButton.action = #selector(nextClicked)

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = AuleumTheme.stack(
            [checkbox, footerSpacer, settingsButton, backButton, nextButton],
            orientation: .horizontal,
            spacing: 9,
            alignment: .centerY
        )

        let flexibleSpace = NSView()
        flexibleSpace.setContentHuggingPriority(.defaultLow, for: .vertical)
        flexibleSpace.setContentCompressionResistancePriority(
            .defaultLow,
            for: .vertical
        )
        let content = AuleumTheme.stack(
            [topRow, progressStack, intro, bodyCard, flexibleSpace, footer],
            spacing: 14
        )
        content.distribution = .fill
        content.setCustomSpacing(10, after: topRow)
        content.setCustomSpacing(20, after: progressStack)
        content.setCustomSpacing(20, after: bodyCard)
        for child in [topRow, progressStack, intro, bodyCard, flexibleSpace, footer] {
            child.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }

        root.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.subviews[0].leadingAnchor.constraint(equalTo: root.leadingAnchor),
            root.subviews[0].trailingAnchor.constraint(equalTo: root.trailingAnchor),
            root.subviews[0].topAnchor.constraint(equalTo: root.topAnchor),
            root.subviews[0].bottomAnchor.constraint(equalTo: root.bottomAnchor),

            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -34),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 34),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
        ])
        window.contentView = root
    }

    private func renderStep() {
        guard steps.indices.contains(currentStep) else { return }
        let step = steps[currentStep]
        stepCountLabel.stringValue = String(
            format: "%02d / %02d",
            currentStep + 1,
            steps.count
        )
        headlineLabel.stringValue = step.title
        detailLabel.stringValue = step.subtitle
        for (index, bar) in progressBars.enumerated() {
            bar.layer?.backgroundColor = (
                index <= currentStep ? AuleumTheme.accent : NSColor.separatorColor
            ).cgColor
        }
        backButton.isHidden = currentStep == 0
        let isLast = currentStep == steps.count - 1
        nextButton.setTitle(isLast ? "开始使用" : "继续")
        nextButton.image = NSImage(
            systemSymbolName: isLast ? "checkmark" : "chevron.right",
            accessibilityDescription: nil
        )
        for (index, page) in stepViews.enumerated() {
            page.isHidden = index != currentStep
        }
    }

    private func makePrincipleStep() -> NSView {
        let human = realityPanel(
            symbol: "eye.slash.fill",
            eyebrow: "你看到的",
            title: "展示幕帘",
            detail: "屏幕上没有工作内容，物理输入也被拦截。",
            accent: AuleumTheme.accent
        )
        let agent = realityPanel(
            symbol: "terminal.fill",
            eyebrow: "Agent 看到的",
            title: "真实桌面",
            detail: "通过 auleumctl 截图或录屏时，拿到未遮挡的画面。",
            accent: AuleumTheme.success
        )
        let comparison = AuleumTheme.stack(
            [human, agent],
            orientation: .horizontal,
            spacing: 12,
            alignment: .top
        )
        comparison.distribution = .fillEqually

        let note = AuleumTheme.stack(
            [
                AuleumTheme.label(
                    "默认使用展示模式：屏幕上只有背景和时钟，不露出工作内容。",
                    size: 10.5,
                    color: AuleumTheme.secondaryInk
                ),
                AuleumTheme.label(
                    "可在设置里关闭展示模式，改用输出层 gamma 纯色幕帘。",
                    size: 10.5,
                    color: AuleumTheme.secondaryInk
                ),
            ],
            spacing: 4
        )
        let content = AuleumTheme.stack([comparison, note], spacing: 16)
        comparison.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        note.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        return content
    }

    private func makeOperationStep() -> NSView {
        let rows = [
            instructionRow(
                "01",
                "起幕",
                "按 \(hotkey)，或在菜单栏选择场景。"
            ),
            instructionRow(
                "02",
                "保持保护",
                "物理键盘、鼠标和系统手势被拦住；Agent 的截图和录制仍可工作。"
            ),
            instructionRow(
                "03",
                "撤幕",
                "双击或长按 Esc，也可以再按 \(hotkey)，然后验证 Touch ID（或已开启的密码兜底）。"
            ),
        ]
        let rowsStack = AuleumTheme.stack(rows, spacing: 12)
        for row in rows {
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }
        let note = AuleumTheme.stack(
            [
                AuleumTheme.label(
                    "Touch ID 是默认出口",
                    size: 11,
                    weight: .semibold
                ),
                AuleumTheme.label(
                    "密码兜底默认关闭，开启后 Touch ID 不可用或验证失败时改用系统密码面板。没有可用验证方式时不会允许起幕。应急时可在终端执行 auleumctl panic。",
                    size: 10.5,
                    color: AuleumTheme.secondaryInk
                ),
            ],
            spacing: 4
        )
        let content = AuleumTheme.stack([rowsStack, note], spacing: 18)
        rowsStack.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        note.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        return content
    }

    private func makeReadyStep() -> NSView {
        let options = [
            optionRow(
                symbol: "menubar.rectangle",
                title: "菜单栏快捷控制",
                detail: "离开、会议、访客、专注四种场景，以及 30 / 60 / 120 分钟快捷保护。"
            ),
            optionRow(
                symbol: "clock",
                title: "展示模式",
                detail: "自定义背景、完整日期时间、星期、农历和数字 / 表盘 / 日历三种时钟。"
            ),
            optionRow(
                symbol: "terminal",
                title: "Agent 命令",
                detail: "Agent 通过 auleumctl capture / record 工作，不需要接入 hooks、MCP 或 HTTP。"
            ),
        ]
        let optionsStack = AuleumTheme.stack(options, spacing: 9)
        for row in options {
            row.widthAnchor.constraint(equalTo: optionsStack.widthAnchor).isActive = true
        }
        let note = AuleumTheme.label(
            "这些都可以稍后在设置里修改；现在先熟悉最短路径。",
            size: 10.5,
            color: AuleumTheme.secondaryInk
        )
        let content = AuleumTheme.stack([optionsStack, note], spacing: 14)
        optionsStack.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        note.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        return content
    }

    private func realityPanel(symbol: String,
                              eyebrow: String,
                              title: String,
                              detail: String,
                              accent: NSColor) -> NSView {
        let icon = AuleumIconTile(symbol: symbol, color: accent, size: 30)
        let eyebrowLabel = AuleumTheme.label(
            eyebrow,
            size: 9.5,
            weight: .medium,
            color: AuleumTheme.secondaryInk
        )
        let titleLabel = AuleumTheme.label(title, size: 14, weight: .semibold)
        let detailLabel = AuleumTheme.label(
            detail,
            size: 10.5,
            color: AuleumTheme.secondaryInk
        )
        detailLabel.maximumNumberOfLines = 2
        let copy = AuleumTheme.stack([eyebrowLabel, titleLabel, detailLabel], spacing: 4)
        let content = AuleumTheme.stack(
            [icon, copy],
            orientation: .horizontal,
            spacing: 12,
            alignment: .top
        )
        let panel = AuleumCardView(
            padding: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        )
        panel.contentView.addSubview(content)
        pin(content, to: panel.contentView)
        return panel
    }

    private func instructionRow(_ number: String,
                                _ title: String,
                                _ detail: String) -> NSView {
        let badge = NSTextField(labelWithString: number)
        badge.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .bold)
        badge.alignment = .center
        badge.textColor = AuleumTheme.buttonText
        badge.wantsLayer = true
        badge.layer?.backgroundColor = AuleumTheme.accent.cgColor
        badge.layer?.cornerRadius = 9
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 22),
            badge.heightAnchor.constraint(equalToConstant: 22),
        ])
        let titleLabel = AuleumTheme.label(title, size: 11.5, weight: .semibold)
        let detailLabel = AuleumTheme.label(
            detail,
            size: 10.5,
            color: AuleumTheme.secondaryInk
        )
        detailLabel.maximumNumberOfLines = 2
        let copy = AuleumTheme.stack([titleLabel, detailLabel], spacing: 2)
        copy.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = AuleumTheme.stack(
            [badge, copy],
            orientation: .horizontal,
            spacing: 11,
            alignment: .top
        )
        copy.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        return row
    }

    private func optionRow(symbol: String, title: String, detail: String) -> NSView {
        let icon = AuleumIconTile(symbol: symbol, color: AuleumTheme.accent, size: 28)
        let titleLabel = AuleumTheme.label(title, size: 11.5, weight: .semibold)
        let detailLabel = AuleumTheme.label(
            detail,
            size: 10.5,
            color: AuleumTheme.secondaryInk
        )
        let copy = AuleumTheme.stack([titleLabel, detailLabel], spacing: 2)
        copy.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return AuleumTheme.stack(
            [icon, copy],
            orientation: .horizontal,
            spacing: 11,
            alignment: .top
        )
    }

    private func pin(_ child: NSView, to parent: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }

    @objc private func toggleDontShow(_ sender: NSButton) {
        dontShowAgain = sender.state == .on
    }

    @objc private func openSettings() {
        finish()
        onOpenSettings?()
    }

    @objc private func backClicked() {
        guard currentStep > 0 else { return }
        currentStep -= 1
        renderStep()
    }

    @objc private func nextClicked() {
        guard currentStep < steps.count - 1 else {
            finish()
            return
        }
        currentStep += 1
        renderStep()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        window?.delegate = nil
        window?.orderOut(nil)
        onFinish?(dontShowAgain)
    }

}
