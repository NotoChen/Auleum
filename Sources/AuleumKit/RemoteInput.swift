import Darwin
import Foundation

/// 常见远程控制工具。识别只用于「远程兼容」模式，不作为安全边界：
/// 同一用户下的进程本来就可以伪造路径或直接投递合成事件。
public enum RemoteTool: String, CaseIterable, Codable, Sendable {
    case uu
    case sunlogin
    case anydesk
    case rustdesk
    case todesk
    case teamViewer
    case screenSharing
    case parsec
    case jumpDesktop
    case chromeRemoteDesktop
    case vnc
    case noMachine
    case splashtop
    case logMeIn

    public var displayName: String {
        switch self {
        case .uu: return "UU 远程"
        case .sunlogin: return "向日葵"
        case .anydesk: return "AnyDesk"
        case .rustdesk: return "RustDesk"
        case .todesk: return "ToDesk"
        case .teamViewer: return "TeamViewer"
        case .screenSharing: return "屏幕共享"
        case .parsec: return "Parsec"
        case .jumpDesktop: return "Jump Desktop"
        case .chromeRemoteDesktop: return "Chrome 远程桌面"
        case .vnc: return "VNC"
        case .noMachine: return "NoMachine"
        case .splashtop: return "Splashtop"
        case .logMeIn: return "LogMeIn"
        }
    }
}

public enum RemoteProcessPolicy {
    private struct Rule {
        let tool: RemoteTool
        /// 小写路径片段，前后都带斜杠，避免 `NotUURemote.app` 这类误匹配。
        let pathFragments: [String]
        let executableNames: [String]
    }

    private static let rules: [Rule] = [
        Rule(
            tool: .uu,
            pathFragments: ["/uuremote.app/"],
            executableNames: [
                "uuremote", "uuremoteserver", "uuremotedaemon",
                "uuremoteservice", "uuhelper", "uuremotehelper",
            ]
        ),
        Rule(
            tool: .sunlogin,
            pathFragments: ["/sunloginclient.app/", "/sunloginremote.app/"],
            executableNames: [
                "sunloginclient", "sunloginremote", "sunloginservice",
                "sunloginclient_mini", "sunloginclientd",
            ]
        ),
        Rule(
            tool: .anydesk,
            pathFragments: ["/anydesk.app/"],
            executableNames: ["anydesk"]
        ),
        Rule(
            tool: .rustdesk,
            pathFragments: ["/rustdesk.app/"],
            executableNames: ["rustdesk"]
        ),
        Rule(
            tool: .todesk,
            pathFragments: ["/todesk.app/"],
            executableNames: ["todesk", "todesk_service", "todesk_server", "todesk_session"]
        ),
        Rule(
            tool: .teamViewer,
            pathFragments: ["/teamviewer.app/", "/teamviewerhost.app/"],
            executableNames: [
                "teamviewer", "teamviewer_service", "teamviewer_desktop",
                "teamviewer_agent", "teamviewerhost",
            ]
        ),
        Rule(
            tool: .screenSharing,
            pathFragments: ["/screen sharing.app/"],
            executableNames: [
                "screensharingd", "screensharingagent", "screensharing",
                "ardagent", "ssmenuagent",
            ]
        ),
        Rule(
            tool: .parsec,
            pathFragments: ["/parsec.app/"],
            executableNames: ["parsec", "parsecd"]
        ),
        Rule(
            tool: .jumpDesktop,
            pathFragments: ["/jump desktop.app/", "/jumpdesktop.app/"],
            executableNames: [
                "jumpdesktop", "jumpdesktophelper", "jumpdesktopconnect",
            ]
        ),
        Rule(
            tool: .chromeRemoteDesktop,
            pathFragments: ["/chrome remote desktop host.app/"],
            executableNames: ["remoting_me2me_host", "chrome_remote_desktop"]
        ),
        Rule(
            tool: .vnc,
            pathFragments: ["/vine server.app/", "/vnc server.app/", "/vncserver.app/"],
            executableNames: [
                "vncserver", "vncserver-x11", "vncserver-x11-serviced",
                "vineserver", "vnchttpd",
            ]
        ),
        Rule(
            tool: .noMachine,
            pathFragments: ["/nomachine.app/"],
            executableNames: ["nxserver", "nxnode", "nxexec"]
        ),
        Rule(
            tool: .splashtop,
            pathFragments: ["/splashtop streamer.app/", "/splashtop.app/"],
            executableNames: ["splashtopstreamer", "srstreamer", "splashtop"]
        ),
        Rule(
            tool: .logMeIn,
            pathFragments: ["/logmein.app/", "/logmein client.app/"],
            executableNames: ["logmein", "lmiguardian", "gotomypc"]
        ),
    ]

    /// Karabiner 的虚拟 HID 键盘会把重映射后的按键伪装成真实硬件。
    /// 它不是远控工具，远程兼容模式下也必须继续拦截。
    private static let deniedPathFragments: [String] = [
        "/karabiner-elements.app/",
        "org.pqrs.karabiner",
        "karabiner-driverkit-virtualhiddevice",
    ]

    private static let deniedExecutableNames: Set<String> = [
        "karabiner-core-service",
        "karabiner-virtualhiddevice-daemon",
        "karabiner_grabber",
        "karabiner_observer",
        "karabiner_console_user_server",
    ]

    public static func tool(forExecutablePath path: String) -> RemoteTool? {
        let normalized = normalize(path)
        guard !normalized.isEmpty else { return nil }
        let executable = executableName(path)
        for rule in rules {
            if rule.pathFragments.contains(where: { normalized.contains($0) }) {
                return rule.tool
            }
            if rule.executableNames.contains(executable) {
                return rule.tool
            }
        }
        return nil
    }

    public static func isDenied(_ executablePath: String) -> Bool {
        let normalized = normalize(executablePath)
        guard !normalized.isEmpty else { return false }
        if deniedPathFragments.contains(where: { normalized.contains($0) }) {
            return true
        }
        return deniedExecutableNames.contains(executableName(executablePath))
    }

    private static func normalize(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        return (path as NSString).standardizingPath.lowercased()
    }

    private static func executableName(_ path: String) -> String {
        (path as NSString).lastPathComponent.lowercased()
    }
}

public struct RemoteProcessSnapshot: Equatable, Sendable {
    public var remotePIDs: Set<Int32>
    public var deniedPIDs: Set<Int32>
    public var tools: Set<RemoteTool>
    public var refreshedAt: Date

    public init(remotePIDs: Set<Int32> = [],
                deniedPIDs: Set<Int32> = [],
                tools: Set<RemoteTool> = [],
                refreshedAt: Date = Date()) {
        self.remotePIDs = remotePIDs
        self.deniedPIDs = deniedPIDs
        self.tools = tools
        self.refreshedAt = refreshedAt
    }

    public static let empty = RemoteProcessSnapshot()

    public var hasRemoteTool: Bool { !tools.isEmpty }

    public var toolNames: String {
        tools.map(\.displayName).sorted().joined(separator: "、")
    }

    public func isRemote(_ pid: Int32) -> Bool {
        remotePIDs.contains(pid)
    }

    public func isDenied(_ pid: Int32) -> Bool {
        deniedPIDs.contains(pid)
    }

    /// 时间戳不参与比较：进程集合没变时不应该触发 UI/模式刷新。
    public static func == (lhs: RemoteProcessSnapshot,
                           rhs: RemoteProcessSnapshot) -> Bool {
        lhs.remotePIDs == rhs.remotePIDs
            && lhs.deniedPIDs == rhs.deniedPIDs
            && lhs.tools == rhs.tools
    }
}

/// 低频扫描进程表，给事件 tap 提供 O(1) 的来源判断。
/// 3 秒一次足够覆盖远控工具的启动/退出，又不会明显占用 CPU。
public final class RemoteProcessRegistry: @unchecked Sendable {
    public var onChange: ((RemoteProcessSnapshot) -> Void)?

    private let queue = DispatchQueue(
        label: "io.github.notochen.auleum.remote-processes",
        qos: .utility
    )
    private let lock = NSLock()
    private var snapshotValue = RemoteProcessSnapshot.empty
    private var timer: DispatchSourceTimer?

    public init() {}

    public func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now(),
            repeating: 3,
            leeway: .milliseconds(500)
        )
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        self.timer = timer
        timer.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public func snapshot() -> RemoteProcessSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshotValue
    }

    public func refreshNow() {
        queue.async { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        let next = Self.scan()
        lock.lock()
        let changed = next != snapshotValue
        snapshotValue = next
        lock.unlock()
        guard changed else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(next)
        }
    }

    public static func scan() -> RemoteProcessSnapshot {
        let estimate = Int(proc_listallpids(nil, 0))
        guard estimate > 0 else { return .empty }
        var pids = [pid_t](
            repeating: 0,
            count: max(estimate + 32, 128)
        )
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(
                buffer.baseAddress,
                Int32(buffer.count)
            )
        }
        guard count > 0 else { return .empty }

        let selfPID = Int32(getpid())
        var remotePIDs = Set<Int32>()
        var deniedPIDs = Set<Int32>()
        var tools = Set<RemoteTool>()
        var pathBuffer = [UInt8](repeating: 0, count: 4096)

        for index in 0..<min(pids.count, Int(count)) {
            let pid = pids[index]
            guard pid > 0, pid != selfPID else { continue }
            let length = pathBuffer.withUnsafeMutableBytes { buffer in
                proc_pidpath(
                    pid,
                    buffer.baseAddress,
                    UInt32(buffer.count)
                )
            }
            guard length > 0 else { continue }
            let path = String(
                decoding: pathBuffer.prefix(while: { $0 != 0 }),
                as: UTF8.self
            )
            if RemoteProcessPolicy.isDenied(path) {
                deniedPIDs.insert(pid)
                continue
            }
            if let tool = RemoteProcessPolicy.tool(forExecutablePath: path) {
                remotePIDs.insert(pid)
                tools.insert(tool)
            }
        }
        return RemoteProcessSnapshot(
            remotePIDs: remotePIDs,
            deniedPIDs: deniedPIDs,
            tools: tools
        )
    }
}
