import AuleumKit
import Foundation

func usage() -> Never {
    print("""
    auleumctl — 控制 Auleum 幕帘

      auleumctl on [--minutes N]              升起幕帘（纯色 + 拦截物理输入）
      auleumctl protect [--minutes N]         同 on；并设置本次保护时长
      auleumctl scene <away|meeting|guest|focus> [--minutes N]
                                               使用场景预设起幕
      auleumctl off                           请求解除（双击 Esc / 快捷键 → 验证）
      auleumctl message <text>                更新幕帘上的动态进度消息（最多 200 字）
      auleumctl message --clear               清除动态消息，回落到场景提示
      auleumctl panic                         应急强制撤幕（不验指纹，需本地 shell）
      auleumctl status                        查看状态（JSON，含真实调用方）
      auleumctl doctor                        自检：权限 / 屏 / gamma 纯色 / tap / 审计链 / 自启

      auleumctl capture [--out PATH] [--display N | --display-id ID] [--all] [--cursor] [--region x,y,w,h] [--client NAME]
                                               截取桌面（画面中不含幕帘）；--all 每屏一张
      auleumctl record start [--out PATH] [--display N | --display-id ID] [--fps 30] [--bitrate 8000000] [--client NAME]
      auleumctl record stop

      auleumctl audit [N]                     最近 N 条审计（默认 20）
      auleumctl audit --verify                校验审计哈希链

      auleumctl install-agent                 安装开机自启（LaunchAgent）
      auleumctl uninstall-agent               移除开机自启
      auleumctl agent-status                  查看自启状态

    远端命令返回 JSON；失败时退出码 1。doctor 输出为纯文本。
    """)
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
args.removeFirst()
if command == "help" || args.contains("--help") || args.contains("-h") {
    usage()
}

func value(for flag: String) -> String? {
    guard let index = args.firstIndex(of: flag), args.index(after: index) < args.endIndex else { return nil }
    return args[args.index(after: index)]
}

func clientName() -> String? {
    let environment = ProcessInfo.processInfo.environment
    return value(for: "--client") ?? environment["AULEUM_CLIENT"]
}

func hasFlag(_ flag: String) -> Bool { args.contains(flag) }

func minutesValue() -> Int? {
    guard hasFlag("--minutes") else { return nil }
    guard let raw = value(for: "--minutes") else {
        FileHandle.standardError.write(Data("--minutes 需要一个整数\n".utf8))
        exit(1)
    }
    guard let minutes = Int(raw), (0...1440).contains(minutes) else {
        FileHandle.standardError.write(
            Data("--minutes 必须是 0–1440 的整数\n".utf8)
        )
        exit(1)
    }
    return minutes
}

func daemonPath() -> String {
    let installed = "/Applications/Auleum.app/Contents/MacOS/auleumd"
    if FileManager.default.isExecutableFile(atPath: installed) { return installed }
    let sibling = URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent().appendingPathComponent("auleumd").path
    if FileManager.default.isExecutableFile(atPath: sibling) { return sibling }
    return installed
}

/// 本地命令（不需要 auleumd 在跑）
switch command {
case "install-agent":
    if let error = LaunchAgent.install(executable: daemonPath()) {
        FileHandle.standardError.write(Data("安装失败：\(error)\n".utf8))
        exit(1)
    }
    print("已安装开机自启：\(LaunchAgent.plistURL.path)")
    print("程序：\(daemonPath())")
    exit(0)
case "uninstall-agent":
    if let error = LaunchAgent.uninstall() {
        FileHandle.standardError.write(Data("移除失败：\(error)\n".utf8))
        exit(1)
    }
    print("已移除开机自启")
    exit(0)
case "agent-status":
    let status = LaunchAgent.status()
    print("plist：\(status.installed ? "已安装" : "未安装")  \(LaunchAgent.plistURL.path)")
    print("launchd：\(status.loaded ? "已加载" : "未加载")")
    if let exe = status.executablePath { print("程序：\(exe)") }
    exit(0)
case "audit" where hasFlag("--verify"):
    let result = AuditLog.verify()
    if result.ok {
        print("审计链完整：\(result.count) 条")
        exit(0)
    }
    print("审计链断裂：第 \(result.brokenAtLine ?? -1) 行，\(result.reason ?? "")")
    exit(1)
default:
    break
}

let request: ControlRequest
switch command {
case "on":
    request = ControlRequest(
        cmd: "on",
        minutes: minutesValue()
    )
case "protect":
    request = ControlRequest(
        cmd: "protect",
        minutes: minutesValue()
    )
case "scene":
    guard let raw = args.first,
          let scene = AuleumScene(rawValue: raw) else {
        FileHandle.standardError.write(
            Data("场景必须是 away、meeting、guest 或 focus\n".utf8)
        )
        exit(1)
    }
    request = ControlRequest(
        cmd: "scene",
        minutes: minutesValue(),
        scene: scene.rawValue
    )
case "off":
    request = ControlRequest(cmd: "off")
case "message":
    let clear = hasFlag("--clear")
    let text = args.filter { $0 != "--clear" }.joined(separator: " ")
    if !clear, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        FileHandle.standardError.write(
            Data("message 需要文本或 --clear\n".utf8)
        )
        exit(1)
    }
    request = ControlRequest(cmd: "message", text: clear ? "" : text)
case "status":
    request = ControlRequest(cmd: "status")
case "doctor":
    request = ControlRequest(cmd: "doctor")
case "panic":
    request = ControlRequest(cmd: "panic")
case "capture":
    let displayArg = value(for: "--display")
    let all = hasFlag("--all") || displayArg == "all"
    let client = value(for: "--client") ?? ProcessInfo.processInfo.environment["AULEUM_CLIENT"]
    request = ControlRequest(
        cmd: "capture",
        out: value(for: "--out"),
        display: displayArg.flatMap(Int.init),
        displayID: value(for: "--display-id").flatMap(UInt32.init),
        cursor: hasFlag("--cursor"),
        region: value(for: "--region"),
        allDisplays: all,
        client: client
    )
case "record":
    guard let action = args.first else { usage() }
    if action == "start" {
        let client = clientName()
        request = ControlRequest(
            cmd: "record_start",
            out: value(for: "--out"),
            display: value(for: "--display").flatMap(Int.init),
            displayID: value(for: "--display-id").flatMap(UInt32.init),
            fps: value(for: "--fps").flatMap(Int.init),
            bitrate: value(for: "--bitrate").flatMap(Int.init),
            client: client
        )
    } else if action == "stop" {
        request = ControlRequest(cmd: "record_stop")
    } else {
        usage()
    }
case "audit":
    let count: Int
    if let raw = args.first {
        guard let parsed = Int(raw), parsed > 0, parsed <= 10_000 else {
            FileHandle.standardError.write(Data("审计条数必须在 1–10000 之间\n".utf8))
            exit(1)
        }
        count = parsed
    } else {
        count = 20
    }
    request = ControlRequest(cmd: "audit", display: count)
case "-h", "--help", "help":
    usage()
default:
    usage()
}

do {
    let response = try ControlClient.send(request)
    if command == "doctor" {
        print(response.message)
        exit(response.ok ? 0 : 1)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(response), let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    exit(response.ok ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data("auleumctl: \(error)\n".utf8))
    exit(1)
}
