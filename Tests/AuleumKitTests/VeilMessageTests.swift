import Foundation
import Testing
@testable import AuleumKit

@Suite("Veil message")
struct VeilMessageTests {
    @Test("Whitespace is collapsed and blank text clears the message")
    func normalizesWhitespace() {
        #expect(VeilMessagePolicy.normalized("  正在跑测试\n预计 12:30 完成  ")
            == "正在跑测试 预计 12:30 完成")
        #expect(VeilMessagePolicy.normalized(" \n\t ") == nil)
        #expect(VeilMessagePolicy.normalized("") == nil)
    }

    @Test("Control characters are removed")
    func removesControlCharacters() {
        #expect(VeilMessagePolicy.normalized("abc\u{0007}def") == "abcdef")
    }

    @Test("Long messages are truncated to the limit")
    func truncatesLongMessages() {
        let raw = String(repeating: "a", count: VeilMessagePolicy.maxLength + 20)
        #expect(VeilMessagePolicy.normalized(raw)?.count == VeilMessagePolicy.maxLength)
    }
}
