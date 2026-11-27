import AppKit
import AuleumKit
import Foundation

extension AppDelegate {
    // MARK: - 远程兼容模式

    /// 远程兼容只在配置开启时生效；手动开关优先于自动识别。
    var desiredRemoteMode: Bool {
        guard config.remoteCompatibilityEnabled else { return false }
        if let remoteModeOverride { return remoteModeOverride }
        guard config.remoteAutoDetectEnabled else { return false }
        return !remoteRegistry.snapshot().remotePIDs.isEmpty
    }

    /// disabled / manual-on / manual-off / auto / auto-idle / auto-off。
    var remoteModeSource: String {
        guard config.remoteCompatibilityEnabled else { return "disabled" }
        if let remoteModeOverride {
            return remoteModeOverride ? "manual-on" : "manual-off"
        }
        guard config.remoteAutoDetectEnabled else { return "auto-off" }
        return remoteRegistry.snapshot().remotePIDs.isEmpty
            ? "auto-idle"
            : "auto"
    }

    var remoteToolsSummary: String {
        let names = remoteRegistry.snapshot().toolNames
        return names.isEmpty ? "无" : names
    }

    func refreshRemoteMode() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.refreshRemoteMode()
            }
            return
        }
        let previous = effectiveRemoteMode
        effectiveRemoteMode = desiredRemoteMode
        inputGuard?.remoteMode = effectiveRemoteMode
        shield?.remoteMode = effectiveRemoteMode
        presentation?.remoteMode = effectiveRemoteMode
        shield?.applyCursorVisibility()
        presentation?.applyCursorVisibility()
        updateStatusItem()
        guard previous != effectiveRemoteMode else { return }
        audit?.write("remote_mode_changed", [
            "enabled": effectiveRemoteMode,
            "source": remoteModeSource,
            "tools": remoteToolsSummary,
        ])
        if effectiveRemoteMode {
            relinquishFocusForRemoteMode()
        }
    }

    /// 远控模式下把键盘焦点还给下层应用。幕帘窗口不接收键盘，如果 Auleum
    /// 仍是活动应用（例如刚从状态面板起幕），远控端的按键会全部落在 Auleum
    /// 上，看起来像键盘失灵。异步执行，等面板收起、窗口层级稳定后再让出。
    func relinquishFocusForRemoteMode() {
        // 认证期间不要抢走系统验证面板的焦点。
        guard effectiveRemoteMode, state == .active else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.effectiveRemoteMode,
                  self.state == .active else { return }
            NSApp.deactivate()
        }
    }

    func toggleRemoteModeOverride() {
        let next = !effectiveRemoteMode
        remoteModeOverride = next
        refreshRemoteMode()
        audit?.write("remote_mode_override", [
            "enabled": next,
            "source": remoteModeSource,
        ])
    }

    func remoteStatusData() -> [String: String] {
        let snapshot = remoteRegistry.snapshot()
        return [
            "remote_mode": effectiveRemoteMode ? "on" : "off",
            "remote_mode_source": remoteModeSource,
            "remote_compatibility": config.remoteCompatibilityEnabled
                ? "on"
                : "off",
            "remote_auto_detect": config.remoteAutoDetectEnabled ? "on" : "off",
            "remote_tools": snapshot.tools.map(\.rawValue).sorted()
                .joined(separator: ","),
            "remote_tool_names": snapshot.toolNames,
            "remote_processes": "\(snapshot.remotePIDs.count)",
            "remote_denied_processes": "\(snapshot.deniedPIDs.count)",
            "remote_hid_spi": HIDDeviceInspector.isSPIAvailable
                ? "available"
                : "unavailable",
        ]
    }
}
