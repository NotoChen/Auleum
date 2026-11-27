import AppKit
import Foundation
import QuartzCore

/// 没有图片或视频时可以使用的内置动态背景。
/// 只做缓慢、低亮度的光影，避免抢走时钟和提示文字。
public enum PresentationAmbientStyle: String, CaseIterable, Codable, Sendable {
    case off
    case aurora
    case ember

    public var displayName: String {
        switch self {
        case .off: return "关闭"
        case .aurora: return "极光"
        case .ember: return "暖焰"
        }
    }

    public static func storedValue(_ raw: String) -> PresentationAmbientStyle {
        PresentationAmbientStyle(rawValue: raw.lowercased()) ?? .off
    }
}

/// Core Animation 驱动的内置动态背景：深色底 + 两到三团缓慢漂移的柔光。
/// 层数很少，不依赖视频解码，适合长时间挂在幕帘后面。
final class PresentationAmbientBackdropView: NSView {
    var style: PresentationAmbientStyle = .off {
        didSet {
            guard oldValue != style else { return }
            needsRebuild = true
            needsLayout = true
        }
    }

    private let baseLayer = CAGradientLayer()
    private var glowLayers: [CAGradientLayer] = []
    private var builtStyle: PresentationAmbientStyle?
    private var builtSize = CGSize.zero
    private var needsRebuild = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        baseLayer.startPoint = CGPoint(x: 0.5, y: 1)
        baseLayer.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(baseLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { true }

    override func layout() {
        super.layout()
        if needsRebuild || builtStyle != style || builtSize != bounds.size {
            rebuild()
        }
    }

    private func rebuild() {
        needsRebuild = false
        builtStyle = style
        builtSize = bounds.size
        glowLayers.forEach { $0.removeFromSuperlayer() }
        glowLayers.removeAll()
        baseLayer.frame = bounds

        switch style {
        case .off:
            baseLayer.colors = [
                NSColor.black.cgColor,
                NSColor.black.cgColor,
            ]
        case .aurora:
            baseLayer.colors = [
                NSColor(srgbRed: 0.016, green: 0.027, blue: 0.055, alpha: 1).cgColor,
                NSColor(srgbRed: 0.024, green: 0.043, blue: 0.075, alpha: 1).cgColor,
                NSColor(srgbRed: 0.012, green: 0.024, blue: 0.038, alpha: 1).cgColor,
            ]
            baseLayer.locations = [0, 0.55, 1]
            addGlow(
                color: NSColor(srgbRed: 0.20, green: 0.62, blue: 0.58, alpha: 0.30),
                center: CGPoint(x: bounds.width * 0.28, y: bounds.height * 0.30),
                size: CGSize(width: bounds.width * 0.78, height: bounds.height * 0.78),
                drift: CGSize(width: bounds.width * 0.12, height: bounds.height * 0.10),
                duration: 46,
                phase: 0
            )
            addGlow(
                color: NSColor(srgbRed: 0.34, green: 0.36, blue: 0.82, alpha: 0.24),
                center: CGPoint(x: bounds.width * 0.76, y: bounds.height * 0.66),
                size: CGSize(width: bounds.width * 0.86, height: bounds.height * 0.86),
                drift: CGSize(width: bounds.width * 0.10, height: bounds.height * 0.14),
                duration: 58,
                phase: 12
            )
            addGlow(
                color: NSColor(srgbRed: 0.62, green: 0.30, blue: 0.64, alpha: 0.16),
                center: CGPoint(x: bounds.width * 0.52, y: bounds.height * 0.86),
                size: CGSize(width: bounds.width * 0.64, height: bounds.height * 0.64),
                drift: CGSize(width: bounds.width * 0.16, height: bounds.height * 0.08),
                duration: 64,
                phase: 26
            )
        case .ember:
            baseLayer.colors = [
                NSColor(srgbRed: 0.048, green: 0.030, blue: 0.024, alpha: 1).cgColor,
                NSColor(srgbRed: 0.066, green: 0.040, blue: 0.030, alpha: 1).cgColor,
                NSColor(srgbRed: 0.026, green: 0.020, blue: 0.018, alpha: 1).cgColor,
            ]
            baseLayer.locations = [0, 0.52, 1]
            addGlow(
                color: NSColor(srgbRed: 0.86, green: 0.48, blue: 0.18, alpha: 0.26),
                center: CGPoint(x: bounds.width * 0.24, y: bounds.height * 0.20),
                size: CGSize(width: bounds.width * 0.76, height: bounds.height * 0.76),
                drift: CGSize(width: bounds.width * 0.12, height: bounds.height * 0.09),
                duration: 50,
                phase: 4
            )
            addGlow(
                color: NSColor(srgbRed: 0.62, green: 0.24, blue: 0.14, alpha: 0.22),
                center: CGPoint(x: bounds.width * 0.78, y: bounds.height * 0.58),
                size: CGSize(width: bounds.width * 0.82, height: bounds.height * 0.82),
                drift: CGSize(width: bounds.width * 0.09, height: bounds.height * 0.13),
                duration: 60,
                phase: 18
            )
            addGlow(
                color: NSColor(srgbRed: 0.50, green: 0.12, blue: 0.16, alpha: 0.14),
                center: CGPoint(x: bounds.width * 0.56, y: bounds.height * 0.92),
                size: CGSize(width: bounds.width * 0.62, height: bounds.height * 0.62),
                drift: CGSize(width: bounds.width * 0.15, height: bounds.height * 0.07),
                duration: 68,
                phase: 32
            )
        }
    }

    private func addGlow(color: NSColor,
                         center: CGPoint,
                         size: CGSize,
                         drift: CGSize,
                         duration: CFTimeInterval,
                         phase: CFTimeInterval) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.colors = [
            color.cgColor,
            color.withAlphaComponent(color.alphaComponent * 0.45).cgColor,
            NSColor.clear.cgColor,
        ]
        glow.locations = [0, 0.48, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.frame = CGRect(origin: .zero, size: size)
        glow.position = center
        layer?.insertSublayer(glow, above: baseLayer)

        let path = CGPath(
            ellipseIn: CGRect(
                x: center.x - drift.width,
                y: center.y - drift.height,
                width: drift.width * 2,
                height: drift.height * 2
            ),
            transform: nil
        )
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.duration = duration
        move.repeatCount = .infinity
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        move.timeOffset = phase
        glow.add(move, forKey: "drift")

        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 0.94
        breathe.toValue = 1.10
        breathe.duration = duration * 0.72
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        breathe.timeOffset = phase * 0.5
        glow.add(breathe, forKey: "breathe")

        glowLayers.append(glow)
    }
}
