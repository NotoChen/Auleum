import AppKit
import LocalAuthentication
import LocalAuthenticationEmbeddedUI

/// 幕帘内的 Touch ID 卡片。
///
/// `LAAuthenticationView` 把系统验证画在卡片里，不再弹 `coreautha` 的
/// 标准认证面板；指纹比对仍由系统完成，Auleum 只拿到成功/失败。
public final class AuthCard {
    private static let cardSize = NSSize(width: 460, height: 360)
    /// `LAAuthenticationView` 会自己撑到 128×128，不能用更小的 frame 硬压。
    private static let authViewSize: CGFloat = 128

    private final class CardWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private let window: CardWindow

    public init(context: LAContext, passwordFallbackEnabled: Bool = false) {
        let size = Self.cardSize
        window = CardWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = AuthWindowLevel.card
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.sharingType = .none
        window.animationBehavior = .none
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]

        let card = NSView(frame: NSRect(origin: .zero, size: size))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.97).cgColor
        card.layer?.cornerRadius = 26
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.08).cgColor
        window.contentView = card

        let overline = Self.label(
            "Auleum · 幕帘已开启",
            font: .systemFont(ofSize: 11, weight: .medium),
            color: NSColor(calibratedRed: 0.78, green: 0.55, blue: 0.38, alpha: 0.95)
        )
        overline.frame = NSRect(x: 20, y: 318, width: size.width - 40, height: 16)
        card.addSubview(overline)

        let title = Self.label(
            "解除幕帘",
            font: .systemFont(ofSize: 24, weight: .semibold),
            color: .white
        )
        title.frame = NSRect(x: 20, y: 280, width: size.width - 40, height: 32)
        card.addSubview(title)

        let subtitle = Self.label(
            "将手指放在触控 ID 上",
            font: .systemFont(ofSize: 14, weight: .regular),
            color: NSColor(calibratedWhite: 1, alpha: 0.62)
        )
        subtitle.frame = NSRect(x: 20, y: 250, width: size.width - 40, height: 20)
        card.addSubview(subtitle)

        let iconContainer = NSView(frame: NSRect(
            x: (size.width - Self.authViewSize) / 2,
            y: 100,
            width: Self.authViewSize,
            height: Self.authViewSize
        ))
        iconContainer.wantsLayer = true
        iconContainer.layer?.masksToBounds = true
        card.addSubview(iconContainer)

        let authView = LAAuthenticationView(context: context, controlSize: .large)
        authView.frame = iconContainer.bounds
        iconContainer.addSubview(authView)

        let hint = Self.label(
            "按 Esc 取消",
            font: .systemFont(ofSize: 12, weight: .regular),
            color: NSColor(calibratedWhite: 1, alpha: 0.38)
        )
        hint.frame = NSRect(x: 20, y: 64, width: size.width - 40, height: 18)
        card.addSubview(hint)

        let note = Self.label(
            passwordFallbackEnabled
                ? "Touch ID 由系统验证 · 失败后自动改用密码"
                : "Touch ID 由系统验证",
            font: .systemFont(ofSize: 11, weight: .regular),
            color: NSColor(calibratedWhite: 1, alpha: 0.30)
        )
        note.frame = NSRect(x: 20, y: 32, width: size.width - 40, height: 16)
        card.addSubview(note)

        window.title = "解除幕帘"
        window.setAccessibilityLabel(
            passwordFallbackEnabled
                ? "解除幕帘，将手指放在触控 ID 上；验证失败后会自动改用密码"
                : "解除幕帘，将手指放在触控 ID 上"
        )
    }

    public func show() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        window.setFrameOrigin(NSPoint(
            x: frame.midX - window.frame.width / 2,
            y: frame.midY - window.frame.height / 2
        ))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        window.orderOut(nil)
        window.close()
    }

    private static func label(
        _ text: String,
        font: NSFont,
        color: NSColor
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.alignment = .center
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}
