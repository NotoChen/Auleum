import AppKit
import AuleumKit

struct DashboardSnapshot {
    var veilState: AuleumState
    var authMethod: AuthMethod?
    var degradedReason: String?
    var recording: Bool
    var hotkey: String
    var elapsed: String
    var scene: AuleumScene?
    var sceneMinutes: [AuleumScene: Int]
    var scenePresentationLabels: [AuleumScene: String]
    var sceneHotkeys: [AuleumScene: String]
    var protectionRemaining: String?
    var presentationLabel: String
    var hasAccessibility: Bool
    var hasScreenRecording: Bool
    var version: String
    var update = UpdateState()
    var remoteMode = false
    var remoteModeSource = "disabled"
    var remoteTools: [String] = []
    var remoteCompatibilityEnabled = false

    var permissionsReady: Bool {
        hasAccessibility && hasScreenRecording
    }
}

struct DashboardActions {
    let toggle: () -> Void
    let activateScene: (AuleumScene) -> Void
    let quickProtect: (Int) -> Void
    let stopRecording: () -> Void
    let permissions: () -> Void
    let settings: () -> Void
    let quit: () -> Void
    var checkForUpdates: () -> Void = {}
    var installUpdate: () -> Void = {}
    var toggleRemoteMode: () -> Void = {}
}

final class StatusPopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let actions: DashboardActions
    private var dashboard: DashboardViewController!
    private var lastContentSize: NSSize?

    init(provider: @escaping () -> DashboardSnapshot,
         actions: DashboardActions) {
        self.actions = actions
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 420, height: 360)
        popover.delegate = self
        let wrapped = DashboardActions(
            toggle: { [weak self] in
                guard let self else { return }
                self.perform(self.actions.toggle)
            },
            activateScene: { [weak self] scene in
                guard let self else { return }
                self.perform { self.actions.activateScene(scene) }
            },
            quickProtect: { [weak self] minutes in
                guard let self else { return }
                self.perform { self.actions.quickProtect(minutes) }
            },
            stopRecording: { [weak self] in
                guard let self else { return }
                self.perform(self.actions.stopRecording)
            },
            permissions: { [weak self] in
                guard let self else { return }
                self.perform(self.actions.permissions)
            },
            settings: { [weak self] in
                guard let self else { return }
                self.perform(self.actions.settings)
            },
            quit: { [weak self] in
                guard let self else { return }
                self.perform(self.actions.quit)
            },
            checkForUpdates: { [weak self] in
                guard let self else { return }
                self.perform(self.actions.checkForUpdates)
            },
            installUpdate: { [weak self] in
                guard let self else { return }
                self.perform(self.actions.installUpdate)
            },
            toggleRemoteMode: { [weak self] in
                guard let self else { return }
                self.perform(self.actions.toggleRemoteMode)
            }
        )
        dashboard = DashboardViewController(provider: provider, actions: wrapped)
        dashboard.onPreferredSizeChange = { [weak self] in
            guard let self, self.popover.isShown else { return }
            self.applyPreferredSizeIfNeeded()
        }
        popover.contentViewController = dashboard
    }

    var isShown: Bool {
        popover.isShown
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            close()
            return
        }
        dashboard.start()
        applyPreferredSizeIfNeeded()
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        dashboard.stop()
    }

    private func applyPreferredSizeIfNeeded() {
        let size = dashboard.preferredPopoverSize
        guard size != lastContentSize else { return }
        lastContentSize = size
        popover.contentSize = size
    }

    private func perform(_ action: @escaping () -> Void) {
        close()
        DispatchQueue.main.async {
            action()
        }
    }
}

final class DashboardViewController: NSViewController {
    private let provider: () -> DashboardSnapshot
    private let actions: DashboardActions
    private var timer: Timer?
    private var snapshot: DashboardSnapshot?
    var onPreferredSizeChange: (() -> Void)?

    private let statusPill = AuleumStatusPillView(text: "待命", color: AuleumTheme.secondaryInk)
    private let hero = DashboardHeroView()
    private let degradedCard = DashboardDegradedCard()
    private let updateCard = DashboardUpdateCard()
    private let remoteCard = DashboardRemoteCard()
    private let quickPanel = DashboardQuickPanel()
    private let permissionCard = DashboardPermissionCard()
    private let versionLabel = NSTextField(labelWithString: "")
    private let updateButton = AuleumIconButton(
        symbol: "arrow.triangle.2.circlepath",
        accessibilityLabel: "检查更新",
        target: nil,
        action: nil
    )

    init(provider: @escaping () -> DashboardSnapshot,
         actions: DashboardActions) {
        self.provider = provider
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 640))
        root.addSubview(AuleumBackdropView())
        root.subviews[0].translatesAutoresizingMaskIntoConstraints = false

        let icon = AuleumBrandIconView(size: 31)
        let name = NSTextField(labelWithString: "AULEUM")
        name.attributedStringValue = NSAttributedString(
            string: "AULEUM",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .kern: 1.5,
                .foregroundColor: AuleumTheme.ink,
            ]
        )
        let subtitle = NSTextField(labelWithString: "可见性开关")
        subtitle.font = .systemFont(ofSize: 9)
        subtitle.textColor = AuleumTheme.tertiaryInk
        let brandText = AuleumTheme.stack([name, subtitle], spacing: 1)
        let quitButton = AuleumIconButton(
            symbol: "power",
            accessibilityLabel: "退出 Auleum",
            target: self,
            action: #selector(quitClicked)
        )
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = AuleumTheme.stack(
            [icon, brandText, headerSpacer, statusPill, quitButton],
            orientation: .horizontal,
            spacing: 11,
            alignment: .centerY
        )

        hero.onToggle = { [weak self] in
            self?.actions.toggle()
        }
        hero.onStopRecording = { [weak self] in
            self?.actions.stopRecording()
        }
        quickPanel.onScene = { [weak self] scene in
            self?.actions.activateScene(scene)
        }
        quickPanel.onMinutes = { [weak self] minutes in
            self?.actions.quickProtect(minutes)
        }

        permissionCard.onOpen = { [weak self] in
            self?.actions.permissions()
        }
        updateCard.onCheck = { [weak self] in
            self?.actions.checkForUpdates()
        }
        updateCard.onInstall = { [weak self] in
            self?.actions.installUpdate()
        }
        remoteCard.onToggle = { [weak self] in
            self?.actions.toggleRemoteMode()
        }
        updateButton.target = self
        updateButton.action = #selector(checkUpdatesClicked)

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.spacing = 14
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        degradedCard.isHidden = true
        updateCard.isHidden = true
        let contentViews: [NSView] = [
            hero,
            degradedCard,
            updateCard,
            remoteCard,
            quickPanel,
            permissionCard,
        ]
        for view in contentViews {
            contentStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        let document = DashboardFlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(contentStack)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let footerDivider = AuleumDividerView()
        let settingsButton = AuleumButton(
            title: "设置",
            symbol: "slider.horizontal.3",
            style: .secondary,
            target: self,
            action: #selector(settingsClicked)
        )
        versionLabel.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        versionLabel.textColor = AuleumTheme.tertiaryInk
        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = AuleumTheme.stack(
            [settingsButton, updateButton, footerSpacer, versionLabel],
            orientation: .horizontal,
            spacing: 8,
            alignment: .centerY
        )

        root.addSubview(header)
        root.addSubview(scroll)
        root.addSubview(footerDivider)
        root.addSubview(footer)
        header.translatesAutoresizingMaskIntoConstraints = false
        footerDivider.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            root.subviews[0].leadingAnchor.constraint(equalTo: root.leadingAnchor),
            root.subviews[0].trailingAnchor.constraint(equalTo: root.trailingAnchor),
            root.subviews[0].topAnchor.constraint(equalTo: root.topAnchor),
            root.subviews[0].bottomAnchor.constraint(equalTo: root.bottomAnchor),

            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),

            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            scroll.bottomAnchor.constraint(equalTo: footerDivider.topAnchor, constant: -12),

            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            contentStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: document.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: document.bottomAnchor),

            footerDivider.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            footerDivider.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footerDivider.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
        ])
        view = root
    }

    func start() {
        update()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.update()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var preferredPopoverSize: NSSize {
        guard let snapshot else {
            return NSSize(width: 420, height: 560)
        }
        let base: CGFloat = snapshot.veilState.isOn ? 450 : 540
        let missingPermissions: CGFloat = snapshot.permissionsReady ? 0 : 84
        let degraded: CGFloat = snapshot.degradedReason == nil ? 0 : 68
        let update: CGFloat = updateCard.isHidden ? 0 : 84
        let remote: CGFloat = remoteCard.isHidden ? 0 : 62
        return NSSize(
            width: 420,
            height: base + missingPermissions + degraded + update + remote
        )
    }

    private func update() {
        let snapshot = provider()
        self.snapshot = snapshot
        statusPill.update(text: stateLabel(snapshot), color: stateColor(snapshot))
        hero.update(snapshot: snapshot)
        degradedCard.update(reason: snapshot.degradedReason)
        degradedCard.isHidden = snapshot.degradedReason == nil
        updateCard.update(state: snapshot.update)
        updateCard.isHidden = updateCard.isHiddenState
        remoteCard.update(snapshot: snapshot)
        remoteCard.isHidden = !snapshot.remoteCompatibilityEnabled
        updateButton.isEnabled = snapshot.update.phase != .checking
            && snapshot.update.phase != .downloading
            && snapshot.update.phase != .installing
        updateButton.toolTip = snapshot.update.phase == .failed
            ? "更新检查失败，点击重试"
            : "检查更新"
        quickPanel.update(snapshot: snapshot)
        permissionCard.isHidden = snapshot.permissionsReady
        versionLabel.stringValue = "v\(snapshot.version)"
        onPreferredSizeChange?()
    }

    private func stateLabel(_ snapshot: DashboardSnapshot) -> String {
        switch snapshot.veilState {
        case .idle: return snapshot.recording ? "录制中" : "待命"
        case .active: return "已遮挡"
        case .authenticating: return "验证中"
        }
    }

    private func stateColor(_ snapshot: DashboardSnapshot) -> NSColor {
        switch snapshot.veilState {
        case .idle: return snapshot.recording ? AuleumTheme.danger : AuleumTheme.secondaryInk
        case .active: return snapshot.degradedReason == nil
            ? AuleumTheme.accent
            : AuleumTheme.warning
        case .authenticating: return AuleumTheme.warning
        }
    }

    @objc private func quitClicked() {
        actions.quit()
    }

    @objc private func settingsClicked() {
        actions.settings()
    }

    @objc private func checkUpdatesClicked() {
        actions.checkForUpdates()
    }

}

private final class DashboardHeroView: NSView {
    var onToggle: (() -> Void)?
    var onStopRecording: (() -> Void)?

    private let gradient = CAGradientLayer()
    private let glow = CAGradientLayer()
    private let eyebrow = NSTextField(labelWithString: "")
    private let recordLabel = NSTextField(labelWithString: "●  录制中")
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let primaryMetric = DashboardHeroMetric(label: "快捷键")
    private let toggleButton = AuleumButton(
        title: "开启幕帘",
        symbol: "rectangle.fill",
        style: .primary,
        target: nil,
        action: nil
    )
    private let stopButton = AuleumButton(
        title: "结束录制",
        symbol: "stop.fill",
        style: .danger,
        target: nil,
        action: nil
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        layer?.borderWidth = 0.7
        layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor
        gradient.colors = [
            NSColor(srgbRed: 0.105, green: 0.126, blue: 0.155, alpha: 1).cgColor,
            NSColor(srgbRed: 0.031, green: 0.039, blue: 0.052, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradient)
        glow.type = .radial
        glow.colors = [
            AuleumTheme.accent.withAlphaComponent(0.22).cgColor,
            AuleumTheme.accent.withAlphaComponent(0).cgColor,
        ]
        glow.startPoint = CGPoint(x: 0.78, y: 0.9)
        glow.endPoint = CGPoint(x: 1.4, y: 0)
        layer?.addSublayer(glow)

        eyebrow.font = .systemFont(ofSize: 9, weight: .bold)
        eyebrow.textColor = AuleumTheme.accent
        recordLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        recordLabel.textColor = AuleumTheme.danger
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        title.textColor = .white
        detail.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        detail.textColor = NSColor.white.withAlphaComponent(0.56)
        detail.lineBreakMode = .byTruncatingTail
        detail.maximumNumberOfLines = 1

        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let topRow = AuleumTheme.stack(
            [eyebrow, topSpacer, recordLabel],
            orientation: .horizontal,
            spacing: 8,
            alignment: .centerY
        )
        stopButton.target = self
        stopButton.action = #selector(stopClicked)
        stopButton.isHidden = true
        toggleButton.target = self
        toggleButton.action = #selector(toggleClicked)
        let buttonRow = AuleumTheme.stack(
            [toggleButton, stopButton],
            orientation: .horizontal,
            spacing: 8,
            alignment: .centerY
        )
        toggleButton.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let content = AuleumTheme.stack(
            [topRow, title, detail, primaryMetric, buttonRow],
            spacing: 6
        )
        content.setCustomSpacing(12, after: detail)
        content.setCustomSpacing(14, after: primaryMetric)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            topRow.widthAnchor.constraint(equalTo: content.widthAnchor),
            primaryMetric.widthAnchor.constraint(equalTo: content.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: content.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        gradient.frame = bounds
        glow.frame = bounds
    }

    func update(snapshot: DashboardSnapshot) {
        switch snapshot.veilState {
        case .idle:
            eyebrow.stringValue = "READY"
            title.stringValue = "幕帘待命"
            detail.stringValue = "按 \(snapshot.hotkey) 开启"
            toggleButton.setTitle("开启幕帘")
            toggleButton.image = NSImage(
                systemSymbolName: "rectangle.fill",
                accessibilityDescription: nil
            )
            toggleButton.isEnabled = true
        case .active:
            eyebrow.stringValue = snapshot.scene.map {
                "VISIBILITY OFF · \($0.title)"
            } ?? "VISIBILITY OFF"
            title.stringValue = "幕帘已遮挡"
            let scenePrefix = snapshot.scene.map { "\($0.title) · " } ?? ""
            detail.stringValue = "\(scenePrefix)双击 Esc 或按 \(snapshot.hotkey) 解除"
            toggleButton.setTitle("解除幕帘")
            toggleButton.image = NSImage(
                systemSymbolName: "touchid",
                accessibilityDescription: nil
            )
            toggleButton.isEnabled = true
        case .authenticating:
            let usesPassword = snapshot.authMethod == .password
            eyebrow.stringValue = snapshot.scene.map {
                "\(usesPassword ? "PASSWORD" : "TOUCH ID") · \($0.title)"
            } ?? (usesPassword ? "PASSWORD" : "TOUCH ID")
            title.stringValue = usesPassword ? "等待密码验证" : "等待 Touch ID"
            let scenePrefix = snapshot.scene.map { "\($0.title) · " } ?? ""
            detail.stringValue = usesPassword
                ? "\(scenePrefix)在系统面板中输入登录密码；再按一次 Esc 取消"
                : "\(scenePrefix)再按一次 Esc 取消验证"
            toggleButton.setTitle(usesPassword ? "等待密码验证" : "等待 Touch ID")
            toggleButton.image = NSImage(
                systemSymbolName: usesPassword ? "lock.fill" : "hourglass",
                accessibilityDescription: nil
            )
            toggleButton.isEnabled = false
        }
        recordLabel.isHidden = !snapshot.recording
        stopButton.isHidden = !snapshot.recording
        primaryMetric.update(
            value: snapshot.veilState.isOn ? snapshot.elapsed : snapshot.hotkey,
            label: snapshot.veilState.isOn ? "已保护" : "快捷键"
        )
    }

    @objc private func toggleClicked() {
        onToggle?()
    }

    @objc private func stopClicked() {
        onStopRecording?()
    }
}

private final class DashboardHeroMetric: NSView {
    private let valueLabel = NSTextField(labelWithString: "—")
    private let nameLabel = NSTextField(labelWithString: "")

    init(label: String) {
        super.init(frame: .zero)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        valueLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        valueLabel.lineBreakMode = .byTruncatingTail
        valueLabel.maximumNumberOfLines = 1
        nameLabel.stringValue = label
        nameLabel.font = .systemFont(ofSize: 8.5)
        nameLabel.textColor = NSColor.white.withAlphaComponent(0.42)
        let stack = AuleumTheme.stack([valueLabel, nameLabel], spacing: 2)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(value: String, label: String) {
        valueLabel.stringValue = value
        nameLabel.stringValue = label
    }
}

private final class DashboardDegradedCard: NSView {
    private let detail = AuleumTheme.label(
        "",
        size: 9.5,
        color: AuleumTheme.secondaryInk
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 13
        let icon = AuleumIconTile(
            symbol: "exclamationmark.triangle.fill",
            color: AuleumTheme.warning,
            size: 30
        )
        let title = AuleumTheme.label(
            "保护降级",
            size: 11,
            weight: .semibold
        )
        detail.lineBreakMode = .byTruncatingTail
        let textStack = AuleumTheme.stack([title, detail], spacing: 2)
        let row = AuleumTheme.stack(
            [icon, textStack],
            orientation: .horizontal,
            spacing: 12,
            alignment: .centerY
        )
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(reason: String?) {
        detail.stringValue = reason ?? ""
        detail.toolTip = reason
        setAccessibilityLabel(
            reason.map { "保护降级：\($0)" } ?? "保护降级"
        )
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = AuleumTheme.warning
                .withAlphaComponent(0.09).cgColor
            layer?.borderWidth = 0.7
            layer?.borderColor = AuleumTheme.warning
                .withAlphaComponent(0.18).cgColor
        }
    }
}

private final class DashboardUpdateCard: NSView {
    var onCheck: (() -> Void)?
    var onInstall: (() -> Void)?
    private let icon = AuleumIconTile(
        symbol: "arrow.triangle.2.circlepath",
        color: AuleumTheme.accent,
        size: 30
    )
    private let title = AuleumTheme.label(
        "",
        size: 11,
        weight: .semibold
    )
    private let detail = AuleumTheme.label(
        "",
        size: 9.5,
        color: AuleumTheme.secondaryInk
    )
    private let actionButton = AuleumButton(
        title: "检查更新",
        style: .secondary,
        target: nil,
        action: nil
    )
    private var phase: UpdatePhase = .idle
    private(set) var isHiddenState = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 13
        detail.lineBreakMode = .byTruncatingTail
        let textStack = AuleumTheme.stack([title, detail], spacing: 2)
        let row = AuleumTheme.stack(
            [icon, textStack, actionButton],
            orientation: .horizontal,
            spacing: 12,
            alignment: .centerY
        )
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.target = self
        actionButton.action = #selector(actionClicked)
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(state: UpdateState) {
        phase = state.phase
        let version = state.latestVersion.map { "v\($0)" } ?? ""
        switch state.phase {
        case .checking:
            isHiddenState = false
            title.stringValue = "正在检查更新"
            detail.stringValue = "连接 GitHub Releases…"
            actionButton.isHidden = true
        case .available:
            isHiddenState = false
            title.stringValue = "发现新版本 \(version)"
            detail.stringValue = "下载并通过校验后即可安装"
            actionButton.isHidden = false
            actionButton.setTitle("下载并安装")
            actionButton.isEnabled = true
        case .downloading:
            isHiddenState = false
            title.stringValue = "正在下载 \(version)"
            detail.stringValue = "下载后会校验 SHA-256 和签名"
            actionButton.isHidden = false
            actionButton.setTitle("正在下载…")
            actionButton.isEnabled = false
        case .ready:
            isHiddenState = false
            title.stringValue = "更新已就绪 \(version)"
            detail.stringValue = "安装后 Auleum 会自动重启"
            actionButton.isHidden = false
            actionButton.setTitle("安装并重启")
            actionButton.isEnabled = true
        case .installing:
            isHiddenState = false
            title.stringValue = "正在安装更新"
            detail.stringValue = "Auleum 即将重启…"
            actionButton.isHidden = true
        case .failed where state.isManual:
            isHiddenState = false
            title.stringValue = "更新检查失败"
            detail.stringValue = state.message ?? "请稍后重试"
            actionButton.isHidden = false
            actionButton.setTitle(state.canInstall ? "安装并重启" : "重试")
            actionButton.isEnabled = true
        default:
            isHiddenState = true
        }
        icon.setColor(
            state.phase == .failed ? AuleumTheme.danger : AuleumTheme.accent
        )
        setAccessibilityLabel(
            "\(title.stringValue)：\(detail.stringValue)"
        )
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = AuleumTheme.accent
                .withAlphaComponent(0.08).cgColor
            layer?.borderWidth = 0.7
            layer?.borderColor = AuleumTheme.accent
                .withAlphaComponent(0.18).cgColor
        }
    }

    @objc private func actionClicked() {
        if phase == .available || phase == .ready
            || (phase == .failed && actionButton.title == "安装并重启") {
            onInstall?()
        } else {
            onCheck?()
        }
    }
}

private final class DashboardRemoteCard: NSView {
    var onToggle: (() -> Void)?

    private let icon = AuleumIconTile(
        symbol: "display.2",
        color: AuleumTheme.secondaryInk,
        size: 30
    )
    private let title = AuleumTheme.label(
        "远程兼容",
        size: 11,
        weight: .semibold
    )
    private let detail = AuleumTheme.label(
        "",
        size: 9.5,
        color: AuleumTheme.secondaryInk
    )
    private let actionButton = AuleumButton(
        title: "开启",
        style: .secondary,
        target: nil,
        action: nil
    )
    private var active = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 13
        detail.lineBreakMode = .byTruncatingTail
        let textStack = AuleumTheme.stack([title, detail], spacing: 2)
        let row = AuleumTheme.stack(
            [icon, textStack, actionButton],
            orientation: .horizontal,
            spacing: 12,
            alignment: .centerY
        )
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.target = self
        actionButton.action = #selector(toggleClicked)
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(snapshot: DashboardSnapshot) {
        active = snapshot.remoteMode
        title.stringValue = active ? "远程兼容已开启" : "远程兼容已关闭"
        let tools = snapshot.remoteTools.isEmpty
            ? ""
            : " · \(snapshot.remoteTools.joined(separator: "、"))"
        switch snapshot.remoteModeSource {
        case "manual-on":
            detail.stringValue = "手动开启\(tools) · 物理键鼠仍拦截"
        case "manual-off":
            detail.stringValue = "手动关闭 · 物理键鼠仍拦截"
        case "auto":
            detail.stringValue = "自动识别\(tools) · 物理键鼠仍拦截"
        case "auto-idle":
            detail.stringValue = "未检测到远控工具 · 物理键鼠仍拦截"
        case "auto-off":
            detail.stringValue = "自动识别已关闭 · 可手动开启"
        default:
            detail.stringValue = "远程兼容已关闭"
        }
        actionButton.setTitle(active ? "关闭" : "开启")
        icon.setColor(active ? AuleumTheme.success : AuleumTheme.secondaryInk)
        setAccessibilityLabel("\(title.stringValue)：\(detail.stringValue)")
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let tint = active ? AuleumTheme.success : AuleumTheme.tertiaryInk
            layer?.backgroundColor = tint.withAlphaComponent(0.07).cgColor
            layer?.borderWidth = 0.7
            layer?.borderColor = tint.withAlphaComponent(0.16).cgColor
        }
    }

    @objc private func toggleClicked() {
        onToggle?()
    }
}

private final class DashboardPermissionCard: NSView {
    var onOpen: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 13
        let icon = AuleumIconTile(
            symbol: "exclamationmark.shield.fill",
            color: AuleumTheme.warning,
            size: 30
        )
        let title = AuleumTheme.label(
            "系统权限还不完整",
            size: 11,
            weight: .semibold
        )
        let detail = AuleumTheme.label(
            "打开系统设置，把 Auleum 拖进对应列表。",
            size: 9.5,
            color: AuleumTheme.secondaryInk
        )
        let textStack = AuleumTheme.stack([title, detail], spacing: 2)
        let button = AuleumButton(
            title: "打开设置",
            style: .secondary,
            target: self,
            action: #selector(openClicked)
        )
        let row = AuleumTheme.stack(
            [icon, textStack, button],
            orientation: .horizontal,
            spacing: 12,
            alignment: .centerY
        )
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = AuleumTheme.warning.withAlphaComponent(0.09).cgColor
            layer?.borderWidth = 0.7
            layer?.borderColor = AuleumTheme.warning.withAlphaComponent(0.18).cgColor
        }
    }

    @objc private func openClicked() {
        onOpen?()
    }
}

private final class DashboardQuickPanel: NSView {
    var onScene: ((AuleumScene) -> Void)?
    var onMinutes: ((Int) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let sceneRow = NSStackView()
    private let minuteRow = NSStackView()
    private var sceneTiles: [AuleumScene: DashboardSceneTile] = [:]
    private var minuteButtons: [AuleumButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let card = AuleumCardView(
            padding: NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        )
        addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = AuleumTheme.ink
        detailLabel.font = .systemFont(ofSize: 9.5)
        detailLabel.textColor = AuleumTheme.tertiaryInk
        detailLabel.alignment = .right
        detailLabel.lineBreakMode = .byTruncatingTail
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let titleRow = AuleumTheme.stack(
            [titleLabel, spacer, detailLabel],
            orientation: .horizontal,
            spacing: 10,
            alignment: .centerY
        )

        sceneRow.orientation = .horizontal
        sceneRow.distribution = .fillEqually
        sceneRow.spacing = 8
        sceneRow.alignment = .centerY
        for scene in AuleumScene.allCases {
            let tile = DashboardSceneTile(scene: scene)
            tile.onClick = { [weak self] in
                self?.onScene?(scene)
            }
            sceneTiles[scene] = tile
            sceneRow.addArrangedSubview(tile)
            tile.heightAnchor.constraint(equalToConstant: 74).isActive = true
        }

        minuteRow.orientation = .horizontal
        minuteRow.distribution = .fillEqually
        minuteRow.spacing = 7
        minuteRow.alignment = .centerY
        for minutes in [30, 60, 120, 0] {
            let button = AuleumButton(
                title: minutes == 0 ? "不限时" : "\(minutes) 分钟",
                style: .secondary,
                target: self,
                action: #selector(minuteClicked(_:))
            )
            button.tag = minutes
            minuteButtons.append(button)
            minuteRow.addArrangedSubview(button)
        }

        let stack = AuleumTheme.stack(
            [titleRow, sceneRow, minuteRow],
            spacing: 10
        )
        card.contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
            titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sceneRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            minuteRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(snapshot: DashboardSnapshot) {
        let active = snapshot.veilState.isOn
        if active {
            titleLabel.stringValue = "延长保护"
            detailLabel.stringValue = snapshot.protectionRemaining.map {
                "剩余 \($0)"
            } ?? "当前不限时"
            sceneRow.isHidden = true
            for (index, title) in ["+30 分", "+60 分", "+120 分", "不限时"].enumerated() {
                minuteButtons[index].setTitle(title)
            }
        } else {
            titleLabel.stringValue = "一键保护"
            detailLabel.stringValue = "选择场景，或直接按时长起幕"
            sceneRow.isHidden = false
            for scene in AuleumScene.allCases {
                sceneTiles[scene]?.update(
                    minutes: snapshot.sceneMinutes[scene]
                        ?? scene.defaultProtectionMinutes,
                    presentationLabel: snapshot.scenePresentationLabels[scene]
                        ?? snapshot.presentationLabel,
                    hotkey: snapshot.sceneHotkeys[scene] ?? ""
                )
            }
            for (index, minutes) in [30, 60, 120, 0].enumerated() {
                minuteButtons[index].setTitle(
                    minutes == 0 ? "不限时" : "\(minutes) 分钟"
                )
            }
        }
        let canAct = snapshot.veilState != .authenticating
        minuteButtons.forEach { $0.isEnabled = canAct }
    }

    @objc private func minuteClicked(_ sender: NSButton) {
        onMinutes?(sender.tag)
    }
}

private final class DashboardSceneTile: NSButton {
    var onClick: (() -> Void)?

    private let scene: AuleumScene
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private var hovered = false

    init(scene: AuleumScene) {
        self.scene = scene
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        title = ""
        imagePosition = .noImage
        target = self
        action = #selector(clicked)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.borderWidth = 0.7

        iconView.image = NSImage(
            systemSymbolName: scene.symbol,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        )
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = tint
        titleLabel.stringValue = scene.title
        titleLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        titleLabel.textColor = AuleumTheme.ink
        durationLabel.font = .systemFont(ofSize: 8.5)
        durationLabel.textColor = AuleumTheme.tertiaryInk
        durationLabel.lineBreakMode = .byTruncatingTail
        shortcutLabel.font = .monospacedSystemFont(
            ofSize: 7.5,
            weight: .medium
        )
        shortcutLabel.textColor = AuleumTheme.tertiaryInk
        shortcutLabel.alignment = .right

        let titleSpacer = NSView()
        titleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let titleRow = AuleumTheme.stack(
            [titleLabel, titleSpacer, shortcutLabel],
            orientation: .horizontal,
            spacing: 3,
            alignment: .centerY
        )

        let stack = AuleumTheme.stack(
            [iconView, titleRow, durationLabel],
            spacing: 3
        )
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 17),
            iconView.heightAnchor.constraint(equalToConstant: 17),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -9),
            titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.45 }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(minutes: Int, presentationLabel: String, hotkey: String) {
        durationLabel.stringValue = "\(AuleumScene.durationText(minutes: minutes))"
            + " · \(presentationLabel)"
        shortcutLabel.stringValue = hotkey
        shortcutLabel.isHidden = hotkey.isEmpty
    }

    private var tint: NSColor {
        switch scene {
        case .away: return AuleumTheme.accent
        case .meeting: return AuleumTheme.warning
        case .guest: return AuleumTheme.success
        case .focus: return AuleumTheme.focus
        }
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (hovered
                ? tint.withAlphaComponent(0.13)
                : AuleumTheme.field
            ).cgColor
            layer?.borderColor = (hovered
                ? tint.withAlphaComponent(0.34)
                : AuleumTheme.border
            ).cgColor
        }
    }

    @objc private func clicked() {
        onClick?()
    }
}

private final class DashboardFlippedView: NSView {
    override var isFlipped: Bool { true }
}
