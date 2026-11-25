import AppKit
import Foundation

/// 时钟组件的底板策略。
///
/// `auto` 在纯色幕布上不画底板，让文字直接落在幕布颜色上；图片和内置渐变
/// 仍然保留半透明底板，避免文字被照片细节吃掉。`glass` 始终保留底板，
/// `clear` 始终不画底板，供用户自己选择。
public enum PresentationComponentBackground: String, CaseIterable, Codable {
    case auto
    case glass
    case clear

    public var displayName: String {
        switch self {
        case .auto: return "自动"
        case .glass: return "玻璃"
        case .clear: return "透明"
        }
    }

    public static func storedValue(
        _ raw: String
    ) -> PresentationComponentBackground {
        PresentationComponentBackground(rawValue: raw.lowercased()) ?? .auto
    }
}

/// 组件底板落在背景上的明暗。纯色幕布会按亮度选择，图片和渐变按深色处理。
public enum PresentationPanelTone: String, Equatable {
    case dark
    case light
}

/// 展示画布的文字与底板配色，保证换幕布颜色后仍然能读。
public enum PresentationInk: String, Equatable {
    /// 深色背景上的浅色文字。
    case light
    /// 浅色背景上的深色文字。
    case dark

    public var primary: NSColor {
        switch self {
        case .light: return .white
        case .dark: return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.9)
        }
    }

    public var secondary: NSColor {
        switch self {
        case .light: return NSColor.white.withAlphaComponent(0.88)
        case .dark: return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.8)
        }
    }

    public var tertiary: NSColor {
        switch self {
        case .light: return NSColor.white.withAlphaComponent(0.56)
        case .dark: return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.6)
        }
    }

    public var faint: NSColor {
        switch self {
        case .light: return NSColor.white.withAlphaComponent(0.42)
        case .dark: return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.46)
        }
    }

    public var message: NSColor {
        switch self {
        case .light: return NSColor.white.withAlphaComponent(0.9)
        case .dark: return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.9)
        }
    }

    public var returnTime: NSColor {
        switch self {
        case .light: return NSColor.white.withAlphaComponent(0.56)
        case .dark: return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.6)
        }
    }

    public var accent: NSColor {
        switch self {
        case .light: return NSColor(srgbRed: 0.86, green: 0.65, blue: 0.29, alpha: 1)
        case .dark: return NSColor(srgbRed: 0.55, green: 0.35, blue: 0.10, alpha: 1)
        }
    }

    public var badgeFill: NSColor {
        switch self {
        case .light: return NSColor.white.withAlphaComponent(0.08)
        case .dark: return NSColor.black.withAlphaComponent(0.06)
        }
    }

    public var badgeBorder: NSColor {
        switch self {
        case .light: return NSColor.white.withAlphaComponent(0.11)
        case .dark: return NSColor.black.withAlphaComponent(0.12)
        }
    }

    public var badgeText: NSColor {
        switch self {
        case .light: return NSColor.white.withAlphaComponent(0.76)
        case .dark: return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.68)
        }
    }

    public var rule: NSColor {
        switch self {
        case .light: return NSColor.white.withAlphaComponent(0.14)
        case .dark: return NSColor.black.withAlphaComponent(0.14)
        }
    }

    public var ring: NSColor {
        switch self {
        case .light: return NSColor.white.withAlphaComponent(0.2)
        case .dark: return NSColor.black.withAlphaComponent(0.22)
        }
    }

    public var tick: NSColor {
        switch self {
        case .light: return NSColor.white.withAlphaComponent(0.42)
        case .dark: return NSColor.black.withAlphaComponent(0.46)
        }
    }

    public var hand: NSColor {
        switch self {
        case .light: return NSColor.white.withAlphaComponent(0.9)
        case .dark: return NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.86)
        }
    }
}

public struct PresentationChrome: Equatable {
    public var ink: PresentationInk
    /// `nil` 表示组件直接落在幕布上，不画底板。
    public var panelTone: PresentationPanelTone?

    public var showsPanel: Bool { panelTone != nil }

    public init(ink: PresentationInk, panelTone: PresentationPanelTone?) {
        self.ink = ink
        self.panelTone = panelTone
    }
}

public enum PresentationChromeResolver {
    /// sRGB 相对亮度。黑色 0，白色 1。
    public static func relativeLuminance(_ color: AuleumColor) -> Double {
        func linear(_ channel: Double) -> Double {
            let value = min(1, max(0, channel))
            return value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }

    /// 相对亮度约 0.179 时，黑字和白字的对比度相同；更高的底色用深色文字。
    public static func ink(for color: AuleumColor) -> PresentationInk {
        relativeLuminance(color) > 0.179 ? .dark : .light
    }

    public static func resolve(hasImage: Bool,
                               usesDefaultBackdrop: Bool,
                               color: AuleumColor,
                               componentBackground: PresentationComponentBackground,
                               layout: PresentationLayout) -> PresentationChrome {
        let visualBackground = hasImage || usesDefaultBackdrop
        let backgroundInk: PresentationInk = visualBackground
            ? .light
            : ink(for: color)

        guard layout != .minimal else {
            return PresentationChrome(ink: backgroundInk, panelTone: nil)
        }

        switch componentBackground {
        case .clear:
            return PresentationChrome(ink: backgroundInk, panelTone: nil)
        case .auto:
            guard visualBackground else {
                return PresentationChrome(ink: backgroundInk, panelTone: nil)
            }
            return PresentationChrome(ink: .light, panelTone: .dark)
        case .glass:
            guard !visualBackground else {
                return PresentationChrome(ink: .light, panelTone: .dark)
            }
            // 纯色浅幕布上用浅色玻璃，否则半透明黑底会把浅色压成中间调，
            // 黑字白字都不够清楚。
            if backgroundInk == .dark {
                return PresentationChrome(ink: .dark, panelTone: .light)
            }
            return PresentationChrome(ink: .light, panelTone: .dark)
        }
    }
}
