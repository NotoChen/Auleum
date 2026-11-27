import AppKit
import Foundation

/// 「展示模式」：用窗口显示背景图和日期、时间、星期、农历。
///
/// 这条路径和 gamma 幕帘的保证不同：它依赖窗口共享排除，只承诺常规
/// ScreenCaptureKit 截图/录屏看不到；硬件采集、私有采集 API 不在保证范围内。
/// 默认开启，可在设置里关闭并改用 gamma 幕帘。
public final class PresentationOverlay {
    private static let overlayLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

    private struct ScreenWindow {
        var screen: ScreenSnapshot
        let window: NSWindow
        let canvas: PresentationCanvasView
    }

    private var windows: [ScreenWindow] = []
    private var cursorHiddenDisplayIDs: [CGDirectDisplayID] = []
    private var cursorRevealedForAuth = false
    private var backgroundImage: CGImage?
    public var backgroundColor: AuleumColor = .black
    public var imagePath: String?
    public var videoPath: String?
    public var ambientStyle: PresentationAmbientStyle = .off
    public var clockStyle: PresentationClockStyle = .digital
    public var imageFocus = CGPoint(x: 0.5, y: 0.5)
    public var imageZoom: CGFloat = 1
    public var imageDim: CGFloat = 0
    public var layout: PresentationLayout = .centered
    public var customLayout = PresentationCustomLayout.default
    public var usesDefaultBackdrop = true
    public var componentBackground: PresentationComponentBackground = .auto
    public var clockWidgets = PresentationClockWidgets()
    public var hidesCursor = true
    /// 远程兼容模式：远控端需要看到指针，否则鼠标完全不可见。
    public var remoteMode = false {
        didSet {
            guard oldValue != remoteMode else { return }
            applyCursorVisibility()
            applyPointerEventPolicy()
        }
    }
    /// 是否让展示窗口自己接住指针事件。真实幕帘不接住：物理输入由 HID
    /// 事件 tap 拦截，远控和 Agent 的合成点击必须落到下层应用。全屏试看
    /// 会打开它，避免试看期间误点后面的应用。
    public var blocksPointerEvents = false {
        didSet {
            guard oldValue != blocksPointerEvents else { return }
            applyPointerEventPolicy()
        }
    }
#if DEBUG
    public var allowsScreenCapture = false
#endif
    private var lastStatus: PresentationStatus?

    public init() {}

    public var isActive: Bool { !windows.isEmpty }
    public var displayIDs: Set<CGDirectDisplayID> {
        Set(windows.map(\.screen.displayID))
    }

    @discardableResult
    public func show(screens: [ScreenSnapshot],
                     color: AuleumColor,
                     imagePath: String?,
                     clockStyle: PresentationClockStyle,
                     imageFocus: CGPoint = CGPoint(x: 0.5, y: 0.5),
                     imageZoom: CGFloat = 1,
                     imageDim: CGFloat = 0,
                     layout: PresentationLayout = .centered,
                     customLayout: PresentationCustomLayout = .default,
                     usesDefaultBackdrop: Bool = true,
                     componentBackground: PresentationComponentBackground = .auto,
                     widgets: PresentationClockWidgets = PresentationClockWidgets(),
                     videoPath: String? = nil,
                     ambientStyle: PresentationAmbientStyle = .off,
                     status: PresentationStatus?) -> Bool {
        close()
        backgroundColor = color
        self.imagePath = imagePath
        self.videoPath = (videoPath?.isEmpty == true) ? nil : videoPath
        self.ambientStyle = ambientStyle
        self.clockStyle = clockStyle
        self.imageFocus = imageFocus
        self.imageZoom = imageZoom
        self.imageDim = imageDim
        self.layout = layout
        self.customLayout = customLayout.sanitized()
        self.usesDefaultBackdrop = usesDefaultBackdrop
        self.componentBackground = componentBackground
        clockWidgets = widgets
        lastStatus = status
        guard !screens.isEmpty else { return false }

        let hasVideo = !(videoPath ?? "").isEmpty
        if let imagePath, !imagePath.isEmpty {
            let target = PresentationBackgroundLoader.recommendedPixelSize(
                for: screens
            )
            if let image = PresentationBackgroundLoader.load(
                path: imagePath,
                maxPixelSize: target
            ) {
                backgroundImage = image
            } else if hasVideo {
                // 视频优先；图片读不到不应阻止视频幕帘启动。
                backgroundImage = nil
            } else {
                return false
            }
        } else {
            backgroundImage = nil
        }

        for screen in screens {
            let window = makeWindow(for: screen)
            windows.append(window)
        }
        applyPointerEventPolicy()
        applyCursorVisibility()
        update(status: status)
        return true
    }

    /// 展示窗口何时应该忽略指针事件。真实幕帘传 `blocksPointerEvents =
    /// false`，远控和合成点击直接落到下层应用；全屏试看传 `true`，窗口
    /// 接住点击。远程兼容模式下无论调用方怎么设置都放行，否则远控端
    /// 能看到桌面和指针，点击却全部落在幕帘窗口上。物理输入始终在 HID
    /// 层被拦截，不依赖窗口这一层。
    static func windowIgnoresMouseEvents(blocksPointerEvents: Bool,
                                         remoteMode: Bool) -> Bool {
        remoteMode || !blocksPointerEvents
    }

    private func applyPointerEventPolicy() {
        let ignores = Self.windowIgnoresMouseEvents(
            blocksPointerEvents: blocksPointerEvents,
            remoteMode: remoteMode
        )
        for item in windows {
            item.window.ignoresMouseEvents = ignores
        }
    }

    /// 系统密码面板需要可见指针，认证结束后再按设置重新隐藏。
    public func revealCursorForAuth() {
        guard isActive else { return }
        cursorRevealedForAuth = true
        restoreCursor()
    }

    public func applyCursorVisibility() {
        guard isActive, !cursorRevealedForAuth else { return }
        if hidesCursor, !remoteMode {
            let hidden = Set(cursorHiddenDisplayIDs)
            for screen in ScreenInventory.current()
                where !hidden.contains(screen.displayID) {
                CGDisplayHideCursor(screen.displayID)
                cursorHiddenDisplayIDs.append(screen.displayID)
            }
        } else {
            restoreCursor()
        }
    }

    public func update(status: PresentationStatus?) {
        lastStatus = status
        guard let status else { return }
        for item in windows {
            item.canvas.update(status: status)
        }
    }

    public func setColor(_ color: AuleumColor) {
        backgroundColor = color
        for item in windows {
            item.window.backgroundColor = presentationNSColor(color)
            item.canvas.setColor(color)
        }
    }

    public func setImagePath(_ path: String?) {
        imagePath = path
        let screens = windows.map(\.screen)
        if let path, !path.isEmpty {
            backgroundImage = PresentationBackgroundLoader.load(
                path: path,
                maxPixelSize: PresentationBackgroundLoader.recommendedPixelSize(
                    for: screens
                )
            )
        } else {
            backgroundImage = nil
        }
        for item in windows {
            item.canvas.setBackgroundImage(
                backgroundImage,
                focus: imageFocus,
                zoom: imageZoom,
                dim: imageDim
            )
        }
    }

    /// 视频优先于图片；传 nil 清除播放器并回落到图片或默认背景。
    /// 路径未变化时不重建播放器，避免保存无关设置时视频从头开始。
    public func setVideoPath(_ path: String?) {
        let next = (path?.isEmpty == true) ? nil : path
        guard videoPath != next else { return }
        videoPath = next
        for item in windows {
            item.canvas.setVideoPath(next)
        }
    }

    public func setAmbientStyle(_ style: PresentationAmbientStyle) {
        ambientStyle = style
        for item in windows {
            item.canvas.setAmbientStyle(style)
        }
    }

    public func setImagePresentation(focus: CGPoint,
                                     zoom: CGFloat,
                                     dim: CGFloat) {
        imageFocus = focus
        imageZoom = zoom
        imageDim = dim
        for item in windows {
            item.canvas.setBackgroundImage(
                backgroundImage,
                focus: focus,
                zoom: zoom,
                dim: dim
            )
        }
    }

    public func setClockStyle(_ style: PresentationClockStyle) {
        clockStyle = style
        for item in windows {
            item.canvas.setClockStyle(style)
        }
    }

    public func setLayout(_ layout: PresentationLayout) {
        self.layout = layout
        for item in windows {
            item.canvas.setLayout(layout)
        }
    }

    public func setCustomLayout(_ layout: PresentationCustomLayout) {
        customLayout = layout.sanitized()
        for item in windows {
            item.canvas.setCustomLayout(customLayout)
        }
    }

    public func setDefaultBackdropEnabled(_ enabled: Bool) {
        usesDefaultBackdrop = enabled
        for item in windows {
            item.canvas.setDefaultBackdropEnabled(enabled)
        }
    }

    public func setComponentBackground(
        _ style: PresentationComponentBackground
    ) {
        componentBackground = style
        for item in windows {
            item.canvas.setComponentBackground(style)
        }
    }

    public func setWidgets(_ widgets: PresentationClockWidgets) {
        clockWidgets = widgets
        for item in windows {
            item.canvas.setWidgets(widgets)
        }
    }

    public func showReturnHint(_ text: String, duration: TimeInterval = 7) {
        for item in windows {
            item.canvas.showReturnHint(text, duration: duration)
        }
    }

    public func hideReturnHint(animated: Bool = true) {
        for item in windows {
            item.canvas.hideReturnHint(animated: animated)
        }
    }

    /// 显示器热插拔/重排后重建窗口，沿用当前颜色、背景图、样式和状态。
    @discardableResult
    public func rebuild(screens: [ScreenSnapshot]) -> Bool {
        reconcile(screens: screens)
    }

    /// 只增减目标屏幕，不关闭仍然命中的窗口。混合多屏角色变化时，
    /// 调用方可以先给即将变成黑色的屏幕涂上 gamma，再移除对应展示窗口。
    @discardableResult
    public func reconcile(screens: [ScreenSnapshot]) -> Bool {
        guard !screens.isEmpty else {
            close()
            return false
        }
        if let path = imagePath, !path.isEmpty {
            backgroundImage = PresentationBackgroundLoader.load(
                path: path,
                maxPixelSize: PresentationBackgroundLoader.recommendedPixelSize(
                    for: screens
                )
            )
            if backgroundImage == nil, (videoPath ?? "").isEmpty {
                return false
            }
        }

        let targets = Set(screens.map(\.displayID))
        for displayID in Array(windows.map(\.screen.displayID))
            where !targets.contains(displayID) {
            guard let index = windows.firstIndex(
                where: { $0.screen.displayID == displayID }
            ) else { continue }
            let item = windows.remove(at: index)
            item.canvas.stopVideo()
            item.window.orderOut(nil)
            item.window.close()
        }

        for screen in screens {
            if let index = windows.firstIndex(
                where: { $0.screen.displayID == screen.displayID }
            ) {
                let item = windows[index]
                if item.screen.frame != screen.frame {
                    item.window.setFrame(screen.frame, display: true)
                    item.canvas.frame = NSRect(origin: .zero, size: screen.frame.size)
                    windows[index].screen = screen
                }
                item.canvas.setBackgroundImage(
                    backgroundImage,
                    focus: imageFocus,
                    zoom: imageZoom,
                    dim: imageDim
                )
                item.window.orderFrontRegardless()
            } else {
                windows.append(makeWindow(for: screen))
            }
        }
        applyPointerEventPolicy()
        applyCursorVisibility()
        update(status: lastStatus)
        return true
    }

    /// 认证期间降低窗口层级，让系统 Touch ID 面板显形，但保留全屏遮挡，
    /// 且仍盖住 Dock、菜单栏和浮动面板。与 gamma 幕帘的认证窗口策略一致。
    public func hideForAuth() {
        hideReturnHint(animated: false)
        for item in windows {
            item.canvas.setVideoPlayback(active: false)
            item.window.level = AuthWindowLevel.value
            item.window.orderFrontRegardless()
        }
    }

    public func restoreAfterAuth() {
        cursorRevealedForAuth = false
        for item in windows {
            item.window.level = Self.overlayLevel
            item.window.orderFrontRegardless()
            item.canvas.setVideoPlayback(active: true)
        }
        applyCursorVisibility()
        update(status: lastStatus)
    }

    public func close() {
        hideReturnHint(animated: false)
        cursorRevealedForAuth = false
        restoreCursor()
        for item in windows {
            item.canvas.stopVideo()
            item.window.orderOut(nil)
            item.window.close()
        }
        windows.removeAll()
        backgroundImage = nil
        // 保留 videoPath / ambientStyle：锁屏或切换用户后 overlay 会先 close，
        // 解锁时 screensChanged 通过 reconcile 重建窗口，需要沿用当前背景；
        // 下一次 show 会重新写入这两个值。
        lastStatus = nil
    }

    private func restoreCursor() {
        for displayID in cursorHiddenDisplayIDs {
            CGDisplayShowCursor(displayID)
        }
        cursorHiddenDisplayIDs.removeAll()
    }

    private func makeWindow(for screen: ScreenSnapshot) -> ScreenWindow {
        let window = PresentationOverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        // 和默认幕帘一样盖住菜单栏、Dock 和通知；认证时只降到
        // AuthWindowLevel，仍在 Dock/菜单栏之上。
        window.level = Self.overlayLevel
        window.backgroundColor = presentationNSColor(backgroundColor)
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = Self.windowIgnoresMouseEvents(
            blocksPointerEvents: blocksPointerEvents,
            remoteMode: remoteMode
        )
#if DEBUG
        window.sharingType = allowsScreenCapture ? .readOnly : .none
#else
        window.sharingType = .none
#endif
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let canvas = PresentationCanvasView(
            color: backgroundColor,
            image: backgroundImage,
            focus: imageFocus,
            zoom: imageZoom,
            dim: imageDim,
            clockStyle: clockStyle,
            status: lastStatus,
            layout: layout,
            customLayout: customLayout,
            usesDefaultBackdrop: usesDefaultBackdrop,
            componentBackground: componentBackground,
            widgets: clockWidgets,
            videoPath: videoPath,
            ambientStyle: ambientStyle
        )
        canvas.frame = NSRect(origin: .zero, size: screen.frame.size)
        canvas.autoresizingMask = [.width, .height]
        window.contentView = canvas
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()

        return ScreenWindow(screen: screen, window: window, canvas: canvas)
    }
}

/// 展示窗口永远不需要键盘焦点。禁止成为 key/main，避免远控或合成点击
/// 把焦点抢到 Auleum 上，导致后续键盘输入无处可去。
private final class PresentationOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
