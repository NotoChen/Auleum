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
