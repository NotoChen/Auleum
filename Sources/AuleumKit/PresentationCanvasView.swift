import AppKit

/// 展示模式的实际画布。窗口、设置预览和 DEBUG 预览共用同一套布局，
/// 避免预览与实际幕帘各维护一份时钟样式。
public final class PresentationCanvasView: NSView {
    private let background = AspectFillImageView()
    private let ambientBackdrop = PresentationAmbientBackdropView()
    private let videoBackground = PresentationVideoBackgroundView()
    private let defaultBackdrop = PresentationDefaultBackdropView()
    private let shade = PresentationShadeView()
    private let card = NSView()
    private let cardStack = NSStackView()
    private let clockView: PresentationClockView
    private let sceneMessageLabel = NSTextField(labelWithString: "")
    private let returnLabel = NSTextField(labelWithString: "")
    private let returnHint = PresentationReturnHintView()
    private let compact: Bool
    private var layoutStyle: PresentationLayout
    private var customLayout: PresentationCustomLayout
    private var usesDefaultBackdrop: Bool
    private var ambientStyle: PresentationAmbientStyle
    private var componentBackground: PresentationComponentBackground
    private var hintWorkItem: DispatchWorkItem?
    private var hintAnimationToken = 0
    private var backgroundColor: AuleumColor
    private var cardPanelAlpha: CGFloat = 0.42
    private var cardBorderWidth: CGFloat = 0.8
    private var cardCornerRadius: CGFloat = 28
    private var cardShadowOpacity: CGFloat = 0.3
    private var cardShadowRadius: CGFloat = 30
    private var cardShadowOffset = CGSize(width: 0, height: -10)

    /// 只在设置预览里打开拖拽；真实幕帘和全屏试看保持不可编辑。
    public var isCustomLayoutEditingEnabled = false {
        didSet {
            guard oldValue != isCustomLayoutEditingEnabled else { return }
            window?.invalidateCursorRects(for: self)
        }
    }
    /// 拖拽结束时回调归一化后的位置，供设置页写入草稿。
    public var onCustomLayoutChange: ((PresentationCustomLayout) -> Void)?

    private var cardWidth: NSLayoutConstraint!
    private var cardStackLeading: NSLayoutConstraint!
    private var cardStackTrailing: NSLayoutConstraint!
    private var cardStackTop: NSLayoutConstraint!
    private var cardStackBottom: NSLayoutConstraint!
    private var centeredConstraints: [NSLayoutConstraint] = []
    private var cornerConstraints: [NSLayoutConstraint] = []
    private var customConstraints: [NSLayoutConstraint] = []
    private var customCardX: NSLayoutConstraint!
    private var customCardY: NSLayoutConstraint!
    private var customMessageX: NSLayoutConstraint!
    private var customMessageY: NSLayoutConstraint!
    private var customReturnX: NSLayoutConstraint!
    private var customReturnY: NSLayoutConstraint!
    private var customLabelConstraints: [NSLayoutConstraint] = []
    private var messageMaxWidth: NSLayoutConstraint!
    private var returnMaxWidth: NSLayoutConstraint!
    private var hintCenteredConstraint: NSLayoutConstraint!
    private var hintLeadingConstraint: NSLayoutConstraint!
    private var hintBottom: NSLayoutConstraint!

    private enum CustomDragBlock: Equatable {
        case clock
        case message
        case returnTime
    }

    private var dragBlock: CustomDragBlock?
    private var dragStartCenter = CGPoint.zero

    public init(color: AuleumColor,
                image: CGImage? = nil,
                focus: CGPoint = CGPoint(x: 0.5, y: 0.5),
                zoom: CGFloat = 1,
                dim: CGFloat = 0,
                clockStyle: PresentationClockStyle,
                status: PresentationStatus?,
                compact: Bool = false,
                layout: PresentationLayout = .centered,
                customLayout: PresentationCustomLayout = .default,
                usesDefaultBackdrop: Bool = true,
                componentBackground: PresentationComponentBackground = .auto,
                widgets: PresentationClockWidgets = PresentationClockWidgets(),
                videoPath: String? = nil,
                ambientStyle: PresentationAmbientStyle = .off) {
        self.backgroundColor = color
        self.compact = compact
        self.layoutStyle = layout
        self.customLayout = customLayout.sanitized()
        self.usesDefaultBackdrop = usesDefaultBackdrop
        self.ambientStyle = ambientStyle
        self.componentBackground = componentBackground
        self.clockView = PresentationClockView(
            style: clockStyle,
            compact: compact,
            widgets: widgets
        )
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = presentationNSColor(color).cgColor

        background.autoresizingMask = [.width, .height]
        background.apply(image: image, focus: focus, zoom: zoom)
        addSubview(background)

        ambientBackdrop.style = ambientStyle
        ambientBackdrop.autoresizingMask = [.width, .height]
        ambientBackdrop.isHidden = true
        addSubview(ambientBackdrop)

        videoBackground.autoresizingMask = [.width, .height]
        videoBackground.onUnavailable = { [weak self] in
            self?.handleVideoUnavailable()
        }
        addSubview(videoBackground)
        if let videoPath {
            videoBackground.setVideo(path: videoPath)
        }

        defaultBackdrop.autoresizingMask = [.width, .height]
        addSubview(defaultBackdrop)

        shade.autoresizingMask = [.width, .height]
        addSubview(shade)

        card.wantsLayer = true
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        sceneMessageLabel.alignment = .center
        sceneMessageLabel.maximumNumberOfLines = 2
        sceneMessageLabel.lineBreakMode = .byTruncatingTail

        returnLabel.textColor = NSColor.white.withAlphaComponent(0.56)
        returnLabel.alignment = .center
        returnLabel.maximumNumberOfLines = 1
        returnLabel.lineBreakMode = .byTruncatingTail

        clockView.translatesAutoresizingMaskIntoConstraints = false
        cardStack.orientation = .vertical
        cardStack.alignment = .centerX
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        cardStack.addArrangedSubview(sceneMessageLabel)
        cardStack.addArrangedSubview(clockView)
        cardStack.addArrangedSubview(returnLabel)
        card.addSubview(cardStack)

        cardWidth = card.widthAnchor.constraint(equalToConstant: 580)
        cardWidth.priority = .defaultHigh
        cardStackLeading = cardStack.leadingAnchor.constraint(
            equalTo: card.leadingAnchor,
            constant: 30
        )
        cardStackTrailing = cardStack.trailingAnchor.constraint(
            equalTo: card.trailingAnchor,
            constant: -30
        )
        cardStackTop = cardStack.topAnchor.constraint(
            equalTo: card.topAnchor,
            constant: 28
        )
        cardStackBottom = cardStack.bottomAnchor.constraint(
            equalTo: card.bottomAnchor,
            constant: -28
        )
        centeredConstraints = [
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        cornerConstraints = [
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -44),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -44),
        ]
        NSLayoutConstraint.activate([
            cardWidth,
            card.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: 20
            ),
            card.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -20
            ),
            cardStackLeading,
            cardStackTrailing,
            cardStackTop,
            cardStackBottom,
        ])

        customCardX = card.centerXAnchor.constraint(equalTo: centerXAnchor)
        customCardY = card.centerYAnchor.constraint(equalTo: centerYAnchor)
        customMessageX = sceneMessageLabel.centerXAnchor.constraint(
            equalTo: centerXAnchor
        )
        customMessageY = sceneMessageLabel.centerYAnchor.constraint(
            equalTo: centerYAnchor
        )
        customReturnX = returnLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
        customReturnY = returnLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        customConstraints = [
            customCardX,
            customCardY,
            customMessageX,
            customMessageY,
            customReturnX,
            customReturnY,
        ]
        customLabelConstraints = [
            sceneMessageLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: 24
            ),
            sceneMessageLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -24
            ),
            returnLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: 24
            ),
            returnLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -24
            ),
        ]
        messageMaxWidth = sceneMessageLabel.widthAnchor.constraint(
            lessThanOrEqualToConstant: 300
        )
        returnMaxWidth = returnLabel.widthAnchor.constraint(
            lessThanOrEqualToConstant: 300
        )
        NSLayoutConstraint.activate([messageMaxWidth, returnMaxWidth])

        for view in [card, sceneMessageLabel, returnLabel] {
            view.addGestureRecognizer(
                NSPanGestureRecognizer(
                    target: self,
                    action: #selector(handleCustomPan(_:))
                )
            )
        }

        returnHint.isHidden = true
        returnHint.alphaValue = 0
        returnHint.wantsLayer = true
        returnHint.layer?.zPosition = 10
        returnHint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(returnHint)
        hintCenteredConstraint = returnHint.centerXAnchor.constraint(
            equalTo: centerXAnchor
        )
        hintLeadingConstraint = returnHint.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: 28
        )
        hintBottom = returnHint.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -56
        )
        NSLayoutConstraint.activate([
            hintBottom,
            returnHint.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -24
            ),
        ])

        applyBackdropVisibility()
        applyLayout()

        if let status {
            update(status: status)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func layout() {
        super.layout()
        background.frame = bounds
        ambientBackdrop.frame = bounds
        videoBackground.frame = bounds
        defaultBackdrop.frame = bounds
        shade.frame = bounds
    }

    /// 画布尺寸由窗口决定；位置常量必须在布局流程之外写入，
    /// 否则同一次布局会继续使用旧的常量。
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyCustomPositions()
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        guard layoutStyle == .custom, isCustomLayoutEditingEnabled else {
            return
        }
        addCursorRect(card.frame, cursor: .openHand)
        if !sceneMessageLabel.isHidden {
            addCursorRect(sceneMessageLabel.frame, cursor: .openHand)
        }
        if !returnLabel.isHidden {
            addCursorRect(returnLabel.frame, cursor: .openHand)
        }
    }

    public func update(status: PresentationStatus) {
        clockView.update(status: status)
        sceneMessageLabel.stringValue = status.messageText
        sceneMessageLabel.isHidden = status.messageText.isEmpty
        returnLabel.stringValue = status.returnText
        returnLabel.isHidden = status.returnText.isEmpty
        applyCustomPositions()
        window?.invalidateCursorRects(for: self)
    }

    public func setColor(_ color: AuleumColor) {
        backgroundColor = color
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = presentationNSColor(color).cgColor
        }
        applyChrome()
    }

    public func setBackgroundImage(_ image: CGImage?,
                                  focus: CGPoint,
                                  zoom: CGFloat,
                                  dim: CGFloat) {
        background.apply(image: image, focus: focus, zoom: zoom)
        shade.dimOpacity = dim
        shade.needsDisplay = true
        applyBackdropVisibility()
        applyChrome()
    }

    /// 视频优先于图片；路径为空时清除播放器并回落到图片或默认背景。
    public func setVideoPath(_ path: String?) {
        videoBackground.setVideo(path: path)
        applyBackdropVisibility()
        applyChrome()
    }

    public func setAmbientStyle(_ style: PresentationAmbientStyle) {
        guard ambientStyle != style else { return }
        ambientStyle = style
        ambientBackdrop.style = style
        applyBackdropVisibility()
        applyChrome()
    }

    public func setVideoPlayback(active: Bool) {
        videoBackground.setPlayback(active: active)
    }

    public func stopVideo() {
        videoBackground.clear()
    }

    private func handleVideoUnavailable() {
        videoBackground.clear()
        applyBackdropVisibility()
        applyChrome()
    }

    public func setClockStyle(_ style: PresentationClockStyle) {
        clockView.setStyle(style)
        applyCustomPositions()
    }

    public func setWidgets(_ widgets: PresentationClockWidgets) {
        clockView.setWidgets(widgets)
        applyCustomPositions()
    }

    /// 版式决定卡片的位置、尺寸和底板；切换后即时重排，不重建窗口。
    public func setLayout(_ layout: PresentationLayout) {
        guard layoutStyle != layout else { return }
        layoutStyle = layout
        applyLayout()
    }

    /// 自由排版的归一化位置；只在 `.custom` 版式下生效。
    public func setCustomLayout(_ layout: PresentationCustomLayout) {
        let sanitized = layout.sanitized()
        guard customLayout != sanitized else { return }
        customLayout = sanitized
        applyCustomPositions()
        window?.invalidateCursorRects(for: self)
    }

    /// 没有自定义背景图时，是否绘制内置深色渐变。
    public func setDefaultBackdropEnabled(_ enabled: Bool) {
        guard usesDefaultBackdrop != enabled else { return }
        usesDefaultBackdrop = enabled
        applyBackdropVisibility()
        applyChrome()
    }

    /// 组件底板策略：自动、始终玻璃或始终透明。
    public func setComponentBackground(
        _ style: PresentationComponentBackground
    ) {
        guard componentBackground != style else { return }
        componentBackground = style
        applyChrome()
    }

    /// 回座提示只短暂出现，不承载统计或长期状态。
    public func showReturnHint(_ text: String, duration: TimeInterval = 7) {
        guard !compact else { return }
        returnHint.setText(text)
        hintWorkItem?.cancel()
        hintAnimationToken += 1
        let token = hintAnimationToken
        returnHint.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            returnHint.animator().alphaValue = 1
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.hintAnimationToken == token else { return }
            self.hideReturnHint()
        }
        hintWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    public func hideReturnHint(animated: Bool = true) {
        hintWorkItem?.cancel()
        hintWorkItem = nil
        hintAnimationToken += 1
        let token = hintAnimationToken
        guard !returnHint.isHidden else { return }
        guard animated else {
            returnHint.alphaValue = 0
            returnHint.isHidden = true
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.45
            returnHint.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.hintAnimationToken == token else { return }
            self.returnHint.isHidden = true
        }
    }

    private var hasVideo: Bool {
        videoBackground.videoPath != nil
    }

    private var hasAmbientBackdrop: Bool {
        ambientStyle != .off && background.image == nil && !hasVideo
    }

    private func applyBackdropVisibility() {
        let hasImage = background.image != nil
        let hasVideo = self.hasVideo
        let hasAmbient = hasAmbientBackdrop
        background.isHidden = !hasImage || hasVideo
        videoBackground.isHidden = !hasVideo
        ambientBackdrop.isHidden = !hasAmbient
        defaultBackdrop.isHidden = hasImage || hasVideo || hasAmbient
            || !usesDefaultBackdrop
        defaultBackdrop.needsDisplay = true
        // 纯色幕布不需要为图片准备的上暗下亮渐变，否则幕布颜色会被改写。
        shade.isHidden = !(hasImage || hasVideo || hasAmbient
            || usesDefaultBackdrop)
    }

    private func applyLayout() {
        NSLayoutConstraint.deactivate(centeredConstraints + cornerConstraints)
        NSLayoutConstraint.deactivate([hintCenteredConstraint, hintLeadingConstraint])
        NSLayoutConstraint.deactivate(customConstraints + customLabelConstraints)

        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let messageSize: CGFloat
        let returnSize: CGFloat

        if layoutStyle == .custom {
            cardWidth.isActive = false
            attachFloatingLabels()
            NSLayoutConstraint.activate(customConstraints + customLabelConstraints)
        } else {
            cardWidth.isActive = true
            attachStackedLabels()
        }

        switch layoutStyle {
        case .centered:
            NSLayoutConstraint.activate(centeredConstraints)
            NSLayoutConstraint.activate([hintCenteredConstraint])
            cardWidth.constant = compact ? 360 : 580
            horizontalPadding = compact ? 20 : 30
            verticalPadding = compact ? 18 : 28
            messageSize = compact ? 10 : 18
            returnSize = compact ? 8 : 12
            cardStack.spacing = compact ? 6 : 10
            hintBottom.constant = compact ? -18 : -56
            setCardPanel(alpha: 0.42,
                         borderWidth: 0.8,
                         cornerRadius: compact ? 20 : 28,
                         shadowOpacity: 0.3,
                         shadowRadius: compact ? 18 : 30,
                         shadowOffset: CGSize(
                            width: 0,
                            height: compact ? -6 : -10
                         ))
        case .corner:
            NSLayoutConstraint.activate(cornerConstraints)
            NSLayoutConstraint.activate([hintLeadingConstraint])
            let margin: CGFloat = compact ? 12 : 44
            cornerConstraints[0].constant = -margin
            cornerConstraints[1].constant = -margin
            cardWidth.constant = compact ? 250 : 340
            horizontalPadding = compact ? 14 : 22
            verticalPadding = compact ? 12 : 18
            messageSize = compact ? 9 : 13
            returnSize = compact ? 7 : 10
            cardStack.spacing = compact ? 4 : 7
            hintBottom.constant = compact ? -16 : -28
            setCardPanel(alpha: 0.5,
                         borderWidth: 0.7,
                         cornerRadius: compact ? 16 : 20,
                         shadowOpacity: 0.26,
                         shadowRadius: compact ? 16 : 22,
                         shadowOffset: CGSize(
                            width: 0,
                            height: compact ? -4 : -8
                         ))
        case .minimal:
            NSLayoutConstraint.activate(centeredConstraints)
            NSLayoutConstraint.activate([hintCenteredConstraint])
            cardWidth.constant = compact ? 360 : 580
            horizontalPadding = compact ? 8 : 12
            verticalPadding = compact ? 4 : 8
            messageSize = compact ? 10 : 19
            returnSize = compact ? 8 : 12
            cardStack.spacing = compact ? 6 : 12
            hintBottom.constant = compact ? -18 : -56
            setCardPanel(alpha: 0,
                         borderWidth: 0,
                         cornerRadius: 0,
                         shadowOpacity: 0,
                         shadowRadius: 0,
                         shadowOffset: .zero)
        case .custom:
            NSLayoutConstraint.activate([hintCenteredConstraint])
            horizontalPadding = compact ? 14 : 22
            verticalPadding = compact ? 12 : 20
            messageSize = compact ? 10 : 18
            returnSize = compact ? 8 : 12
            cardStack.spacing = 0
            hintBottom.constant = compact ? -18 : -44
            setCardPanel(alpha: 0.42,
                         borderWidth: 0.8,
                         cornerRadius: compact ? 20 : 26,
                         shadowOpacity: 0.3,
                         shadowRadius: compact ? 18 : 30,
                         shadowOffset: CGSize(
                            width: 0,
                            height: compact ? -6 : -10
                         ))
        }

        messageMaxWidth.constant = compact ? 300 : 560
        returnMaxWidth.constant = compact ? 300 : 560
        cardStackLeading.constant = horizontalPadding
        cardStackTrailing.constant = -horizontalPadding
        cardStackTop.constant = verticalPadding
        cardStackBottom.constant = -verticalPadding
        sceneMessageLabel.font = .systemFont(ofSize: messageSize, weight: .semibold)
        returnLabel.font = .systemFont(ofSize: returnSize, weight: .regular)
        clockView.setCompact(compact || layoutStyle == .corner)
        applyChrome()
        if layoutStyle == .custom {
            applyCustomPositions()
        }
        window?.invalidateCursorRects(for: self)
    }

    private func setCardPanel(alpha: CGFloat,
                              borderWidth: CGFloat,
                              cornerRadius: CGFloat,
                              shadowOpacity: CGFloat,
                              shadowRadius: CGFloat,
                              shadowOffset: CGSize) {
        cardPanelAlpha = alpha
        cardBorderWidth = borderWidth
        cardCornerRadius = cornerRadius
        cardShadowOpacity = shadowOpacity
        cardShadowRadius = shadowRadius
        cardShadowOffset = shadowOffset
    }

    /// 底板和文字颜色由背景决定：纯色幕布上按亮度选黑字或白字，
    /// 图片和内置渐变上保持浅色文字，必要时保留玻璃底板。
    private func applyChrome() {
        let chrome = PresentationChromeResolver.resolve(
            hasImage: background.image != nil || hasVideo || hasAmbientBackdrop,
            usesDefaultBackdrop: usesDefaultBackdrop,
            color: backgroundColor,
            componentBackground: componentBackground,
            layout: layoutStyle
        )
        let layer = card.layer
        switch chrome.panelTone {
        case .dark:
            layer?.backgroundColor = NSColor.black
                .withAlphaComponent(cardPanelAlpha).cgColor
            layer?.borderWidth = cardBorderWidth
            layer?.borderColor = NSColor.white
                .withAlphaComponent(0.1).cgColor
            layer?.shadowOpacity = Float(cardShadowOpacity)
        case .light:
            layer?.backgroundColor = NSColor.white
                .withAlphaComponent(0.72).cgColor
            layer?.borderWidth = cardBorderWidth
            layer?.borderColor = NSColor.black
                .withAlphaComponent(0.06).cgColor
            layer?.shadowOpacity = Float(cardShadowOpacity * 0.65)
        case nil:
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
            layer?.shadowOpacity = 0
        }
        layer?.cornerRadius = cardCornerRadius
        layer?.shadowRadius = cardShadowRadius
        layer?.shadowOffset = cardShadowOffset
        sceneMessageLabel.textColor = chrome.ink.message
        returnLabel.textColor = chrome.ink.returnTime
        clockView.setInk(chrome.ink)
    }

    /// 自由排版时提示和返回时间脱离卡片，才能各自拖动。
    private func attachFloatingLabels() {
        guard sceneMessageLabel.superview !== self else { return }
        cardStack.removeArrangedSubview(sceneMessageLabel)
        cardStack.removeArrangedSubview(returnLabel)
        sceneMessageLabel.removeFromSuperview()
        returnLabel.removeFromSuperview()
        sceneMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        returnLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sceneMessageLabel)
        addSubview(returnLabel)
    }

    private func attachStackedLabels() {
        guard sceneMessageLabel.superview !== cardStack else { return }
        sceneMessageLabel.removeFromSuperview()
        returnLabel.removeFromSuperview()
        sceneMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        returnLabel.translatesAutoresizingMaskIntoConstraints = false
        cardStack.insertArrangedSubview(sceneMessageLabel, at: 0)
        cardStack.addArrangedSubview(returnLabel)
    }

    private func applyCustomPositions() {
        guard layoutStyle == .custom, bounds.width > 1, bounds.height > 1 else {
            return
        }
        let margin: CGFloat = compact ? 10 : 28
        position(
            placement: customLayout.clock,
            size: customSize(for: .clock),
            xConstraint: customCardX,
            yConstraint: customCardY,
            margin: margin
        )
        position(
            placement: customLayout.message,
            size: customSize(for: .message),
            xConstraint: customMessageX,
            yConstraint: customMessageY,
            margin: margin
        )
        position(
            placement: customLayout.returnTime,
            size: customSize(for: .returnTime),
            xConstraint: customReturnX,
            yConstraint: customReturnY,
            margin: margin
        )
    }

    /// 用固有尺寸计算，而不是读取当前 frame：窗口第一次布局前 frame 还是零，
    /// 而从 layout() 里改常量又赶不上同一次布局。
    private func customSize(for block: CustomDragBlock) -> CGSize {
        let horizontalPadding: CGFloat = compact ? 14 : 22
        let verticalPadding: CGFloat = compact ? 12 : 20
        switch block {
        case .clock:
            let clock = clockView.intrinsicContentSize
            return CGSize(
                width: clock.width + horizontalPadding * 2,
                height: clock.height + verticalPadding * 2
            )
        case .message:
            return labelSize(sceneMessageLabel)
        case .returnTime:
            return labelSize(returnLabel)
        }
    }

    private func labelSize(_ label: NSTextField) -> CGSize {
        guard !label.isHidden else { return .zero }
        let intrinsic = label.intrinsicContentSize
        let maxWidth = compact ? 300.0 : 560.0
        return CGSize(
            width: min(intrinsic.width, maxWidth),
            height: intrinsic.height
        )
    }

    private func position(placement: PresentationWidgetPlacement,
                          size: CGSize,
                          xConstraint: NSLayoutConstraint,
                          yConstraint: NSLayoutConstraint,
                          margin: CGFloat) {
        // Auto Layout 的纵向常量以顶部为原点：正数向下。
        let resolved = PresentationPlacementResolver.normalizedCenter(
            CGPoint(
                x: CGFloat(placement.x) * bounds.width,
                y: CGFloat(placement.y) * bounds.height
            ),
            itemSize: size,
            canvasSize: bounds.size,
            margin: margin
        )
        let centerX = CGFloat(resolved.x) * bounds.width
        let centerY = CGFloat(resolved.y) * bounds.height
        let dx = centerX - bounds.midX
        let dy = centerY - bounds.midY
        if abs(xConstraint.constant - dx) > 0.5 {
            xConstraint.constant = dx
        }
        if abs(yConstraint.constant - dy) > 0.5 {
            yConstraint.constant = dy
        }
    }

    @objc private func handleCustomPan(_ gesture: NSPanGestureRecognizer) {
        guard layoutStyle == .custom,
              isCustomLayoutEditingEnabled,
              let view = gesture.view,
              let block = dragBlock(for: view) else {
            return
        }
        switch gesture.state {
        case .began:
            dragBlock = block
            dragStartCenter = CGPoint(x: view.frame.midX, y: view.frame.midY)
            NSCursor.closedHand.set()
        case .changed:
            guard dragBlock == block else { return }
            let translation = gesture.translation(in: self)
            setCustomPlacement(
                block,
                center: CGPoint(
                    x: dragStartCenter.x + translation.x,
                    y: dragStartCenter.y + translation.y
                )
            )
        case .ended:
            dragBlock = nil
            window?.invalidateCursorRects(for: self)
            onCustomLayoutChange?(customLayout)
        case .cancelled, .failed:
            dragBlock = nil
            window?.invalidateCursorRects(for: self)
            onCustomLayoutChange?(customLayout)
        default:
            break
        }
    }

    private func dragBlock(for view: NSView) -> CustomDragBlock? {
        if view === card { return .clock }
        if view === sceneMessageLabel { return .message }
        if view === returnLabel { return .returnTime }
        return nil
    }

    private func setCustomPlacement(_ block: CustomDragBlock,
                                    center: CGPoint) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let margin: CGFloat = compact ? 10 : 28
        let size = customSize(for: block)
        // center 来自 AppKit 视图坐标（原点在下），位置约束以顶部为原点。
        let placement = PresentationPlacementResolver.normalizedCenter(
            CGPoint(x: center.x, y: bounds.height - center.y),
            itemSize: size,
            canvasSize: bounds.size,
            margin: margin
        )
        switch block {
        case .clock:
            customLayout.clock = placement
        case .message:
            customLayout.message = placement
        case .returnTime:
            customLayout.returnTime = placement
        }
        applyCustomPositions()
    }
}

/// 没有自定义背景图时的内置背景：深色渐变、低饱和暖光和暗角，
/// 只负责托住时钟，不抢走文字。
private final class PresentationDefaultBackdropView: NSView {
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0,
              bounds.height > 0,
              let context = NSGraphicsContext.current?.cgContext else {
            return
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        let bounds = self.bounds

        // 基底：上方近黑蓝，下方略带暖意的石墨色。
        let base = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                NSColor(srgbRed: 0.043, green: 0.051, blue: 0.071, alpha: 1).cgColor,
                NSColor(srgbRed: 0.071, green: 0.067, blue: 0.082, alpha: 1).cgColor,
                NSColor(srgbRed: 0.102, green: 0.082, blue: 0.078, alpha: 1).cgColor,
            ] as CFArray,
            locations: [0, 0.58, 1]
        )
        if let base {
            context.drawLinearGradient(
                base,
                start: CGPoint(x: bounds.midX, y: bounds.maxY),
                end: CGPoint(x: bounds.midX, y: bounds.minY),
                options: []
            )
        }

        // 左下暖光，呼应铜色品牌；右上冷光做平衡。
        drawGlow(
            in: context,
            colorSpace: colorSpace,
            center: CGPoint(x: bounds.width * 0.2, y: bounds.height * 0.08),
            radius: max(bounds.width, bounds.height) * 0.62,
            color: NSColor(srgbRed: 0.84, green: 0.58, blue: 0.34, alpha: 0.17)
        )
        drawGlow(
            in: context,
            colorSpace: colorSpace,
            center: CGPoint(x: bounds.width * 0.84, y: bounds.height * 0.92),
            radius: max(bounds.width, bounds.height) * 0.55,
            color: NSColor(srgbRed: 0.42, green: 0.55, blue: 0.74, alpha: 0.09)
        )

        // 暗角，把视线收回到画面中心。
        let diagonal = hypot(bounds.width, bounds.height)
        let vignette = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                NSColor.black.withAlphaComponent(0).cgColor,
                NSColor.black.withAlphaComponent(0.16).cgColor,
                NSColor.black.withAlphaComponent(0.5).cgColor,
            ] as CFArray,
            locations: [0, 0.55, 1]
        )
        if let vignette {
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            context.drawRadialGradient(
                vignette,
                startCenter: center,
                startRadius: diagonal * 0.24,
                endCenter: center,
                endRadius: diagonal * 0.56,
                options: []
            )
        }
    }

    private func drawGlow(in context: CGContext,
                          colorSpace: CGColorSpace,
                          center: CGPoint,
                          radius: CGFloat,
                          color: NSColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.usingColorSpace(.sRGB)?.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        )
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha).cgColor,
                NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha * 0.32).cgColor,
                NSColor(srgbRed: red, green: green, blue: blue, alpha: 0).cgColor,
            ] as CFArray,
            locations: [0, 0.45, 1]
        )
        guard let gradient else { return }
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: []
        )
    }
}

private final class PresentationReturnHintView: NSView {
    private let textLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 19
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        layer?.borderWidth = 0.7
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -5)
        layer?.shadowOpacity = 0.28

        let keycap = PresentationKeycapView()
        textLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        textLabel.textColor = NSColor.white.withAlphaComponent(0.88)
        textLabel.maximumNumberOfLines = 1
        textLabel.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [keycap, textLabel])
        row.orientation = .horizontal
        row.spacing = 9
        row.alignment = .centerY
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setText(_ text: String) {
        textLabel.stringValue = text
    }
}

private final class PresentationKeycapView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.13).cgColor
        layer?.borderWidth = 0.6
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        let label = NSTextField(labelWithString: "esc")
        label.font = .monospacedSystemFont(ofSize: 9.5, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.76)
        label.alignment = .center
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 20),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

private final class PresentationShadeView: NSView {
    var dimOpacity: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if dimOpacity > 0 {
            NSColor.black.withAlphaComponent(dimOpacity).setFill()
            bounds.fill()
        }
        let gradient = NSGradient(
            starting: NSColor.black.withAlphaComponent(0.08),
            ending: NSColor.black.withAlphaComponent(0.46)
        )
        gradient?.draw(in: bounds, angle: -90)
    }
}

func presentationNSColor(_ color: AuleumColor) -> NSColor {
    NSColor(
        srgbRed: CGFloat(color.red),
        green: CGFloat(color.green),
        blue: CGFloat(color.blue),
        alpha: 1
    )
}
