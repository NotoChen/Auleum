import AppKit
import Testing
@testable import AuleumKit

@Suite("Auth window level")
struct AuthWindowLevelTests {
    @Test("Auth cover stays above Dock/menu bar and below the Touch ID panel")
    func authCoverLevel() {
        // 菜单栏 24 高于 Dock 20；系统 Touch ID 面板实测为 1000。
        #expect(AuthWindowLevel.value.rawValue > NSWindow.Level.mainMenu.rawValue)
        #expect(AuthWindowLevel.value.rawValue < NSWindow.Level.screenSaver.rawValue)
        // 卡片压在覆盖层之上，但仍然低于系统面板层级。
        #expect(AuthWindowLevel.card.rawValue > AuthWindowLevel.value.rawValue)
        #expect(AuthWindowLevel.card.rawValue < NSWindow.Level.screenSaver.rawValue)
    }
}
