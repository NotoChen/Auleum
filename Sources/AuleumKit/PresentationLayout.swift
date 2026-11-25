import Foundation

/// 展示画布的版式。时钟样式决定“画什么”，版式决定“放在哪、有没有底板”。
public enum PresentationLayout: String, CaseIterable, Codable {
    case centered
    case corner
    case minimal
    case custom

    public var displayName: String {
        switch self {
        case .centered: return "居中卡片"
        case .corner: return "右下角"
        case .minimal: return "极简"
        case .custom: return "自由"
        }
    }

    public static func storedValue(_ raw: String) -> PresentationLayout {
        PresentationLayout(rawValue: raw.lowercased()) ?? .centered
    }
}
