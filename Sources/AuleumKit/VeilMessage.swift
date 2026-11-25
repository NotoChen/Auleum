import Foundation

/// 幕帘上的动态消息，供 Agent 报告当前进度。
/// 展示层只有一行，所以折叠空白、去掉控制字符并限制长度。
public enum VeilMessagePolicy {
    public static let maxLength = 200

    /// 空文本返回 nil，表示清除动态消息并回落到场景自带提示。
    public static func normalized(_ raw: String) -> String? {
        let words = raw.split(whereSeparator: \.isWhitespace)
        let cleaned = words.map {
            String($0).components(separatedBy: .controlCharacters).joined()
        }.filter { !$0.isEmpty }
        let text = cleaned.joined(separator: " ")
        guard !text.isEmpty else { return nil }
        return String(text.prefix(maxLength))
    }
}
