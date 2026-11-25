import AppKit

/// 认证期间覆盖层使用的窗口层级。
///
/// 实测系统 Touch ID 面板由 coreautha 以 1000（kCGScreenSaverWindowLevel）
/// 显示；Dock 是 20，菜单栏是 24。认证时把覆盖层从幕帘层级降到 101：
/// 仍然盖住 Dock、菜单栏和应用浮动面板，同时让 Touch ID 面板保持可见。
enum AuthWindowLevel {
    static let value = NSWindow.Level.popUpMenu
    /// 认证卡片压在覆盖层之上，但仍远低于系统面板层级。
    static let card = NSWindow.Level(rawValue: value.rawValue + 1)
}
