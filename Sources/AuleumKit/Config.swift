import Foundation
import CoreGraphics

/// 运行配置。只保留用户真正会调的东西；截图目录、码率这些属于命令行参数，不在这里。
/// 新增字段全部带默认值，老配置文件可以直接升级（未知字段自动忽略）。
public struct AuleumConfig: Codable, Equatable {
    /// 长按 Esc 多少秒后弹出 Touch ID。
    public var holdToAuthSeconds: Double
    /// 双击 Esc 的判定窗口。两次物理 Esc 在这个时间内按下会直接请求 Touch ID。
    public var doubleEscapeSeconds: Double
    /// 开发兜底：入幕后多少秒发起一次 Touch ID，0 表示关闭（默认关闭）。
    public var safetyTimeoutSeconds: Double
    /// 幕帘期间是否隐藏鼠标指针。
    public var hideCursorDuringVeil: Bool
    /// Touch ID 不可用时是否允许系统密码验证。默认关闭。
    public var allowPasswordFallback: Bool
    /// 输出层幕帘纯色，格式 #RRGGBB。
    public var veilColor: String
    /// 起幕/撤幕快捷键。默认 ⌃⌥⌘C。
    public var hotkeyKeyCode: Int64
    public var hotkeyModifiers: UInt64
    /// 四个场景的独立全局快捷键；未写入的键使用场景默认值。
    public var sceneHotkeys: [String: SceneHotkey]
    /// 首次使用说明是否已经显示过。
    public var hasShownOnboarding: Bool
    /// 展示模式：用窗口显示背景图/时钟；关闭时改用 gamma 输出层幕帘。默认开启。
    /// 开启后只承诺常规 ScreenCaptureKit 采集看不到窗口。
    public var presentationModeEnabled: Bool
    /// 展示模式自定义背景图路径；空字符串时按默认渐变或幕帘底色显示。
    public var presentationImagePath: String
    /// 展示模式时钟样式：digital / analog / editorial。
    public var presentationClockStyle: String
    /// 展示模式版式：centered / corner / minimal / custom。
    public var presentationLayout: String
    /// 自由排版时三个组件的归一化位置。
    public var presentationCustomLayout: PresentationCustomLayout
    /// 组件底板：auto / glass / clear。
    public var presentationComponentBackground: String
    /// 没有自定义背景图时是否使用内置深色渐变。
    public var presentationDefaultBackdrop: Bool
    /// 展示时钟里的秒、农历和计时徽标。
    public var presentationShowSeconds: Bool
    public var presentationShowLunar: Bool
    public var presentationShowElapsed: Bool
    /// 展示模式主屏角色：black / presentation。
    public var mainDisplayRole: String
    /// 展示模式副屏角色：black / presentation。
    public var secondaryDisplayRole: String
    /// 背景图焦点，0...1，默认居中。
    public var presentationFocusX: Double
    public var presentationFocusY: Double
    /// 背景图放大倍数，1...2。
    public var presentationZoom: Double
    /// 额外暗化，0...0.8。
    public var presentationDim: Double
    /// 空闲多久后自动起幕。
    public var idleAutoVeilEnabled: Bool
    public var idleAutoVeilSeconds: Double
    /// 每天定时保护窗口。
    public var scheduleEnabled: Bool
    public var scheduleStartMinutes: Int
    public var scheduleEndMinutes: Int
    /// bit 0 = 周一 ... bit 6 = 周日；0 表示未选择，仅在定时保护关闭时保留。
    public var scheduleWeekdays: Int
    /// 定时窗口结束后发起 Touch ID，不自动撤幕。默认关闭。
    public var scheduleAutoExit: Bool
    /// 每次手动起幕的默认保护时长，0 表示不自动结束。
    public var defaultProtectionMinutes: Int
    /// 菜单栏场景的完整配置，键为 AuleumScene.rawValue。
    /// 未写入的键使用场景自带的默认配置。
    public var sceneProfiles: [String: AuleumSceneProfile]
    /// 幕帘期间允许合盖继续运行的系统电源断言。
    public var clamshellModeEnabled: Bool
    /// 启动后和每隔几小时检查 GitHub 最新 release。
    public var automaticUpdateChecksEnabled: Bool
    /// 发现新版本后自动下载、校验并在空闲时安装。
    public var automaticUpdateInstallsEnabled: Bool

    public init(holdToAuthSeconds: Double = 2.0,
                doubleEscapeSeconds: Double = 0.7,
                safetyTimeoutSeconds: Double = 0,
                hideCursorDuringVeil: Bool = true,
                allowPasswordFallback: Bool = false,
                veilColor: String = "#000000",
                hotkeyKeyCode: Int64 = HotkeyPolicy.keyCode,
                hotkeyModifiers: UInt64 = HotkeyPolicy.modifiers.rawValue,
                sceneHotkeys: [String: SceneHotkey] = [:],
                hasShownOnboarding: Bool = false,
                presentationModeEnabled: Bool = true,
                presentationImagePath: String = "",
                presentationClockStyle: String =
                    PresentationClockStyle.digital.rawValue,
                presentationLayout: String =
                    PresentationLayout.centered.rawValue,
                presentationCustomLayout: PresentationCustomLayout = .default,
                presentationComponentBackground: String =
                    PresentationComponentBackground.auto.rawValue,
                presentationDefaultBackdrop: Bool = true,
                presentationShowSeconds: Bool = true,
                presentationShowLunar: Bool = true,
                presentationShowElapsed: Bool = true,
                mainDisplayRole: String =
                    AuleumDisplayRole.presentation.rawValue,
                secondaryDisplayRole: String =
                    AuleumDisplayRole.presentation.rawValue,
                presentationFocusX: Double = 0.5,
                presentationFocusY: Double = 0.5,
                presentationZoom: Double = 1,
                presentationDim: Double = 0,
                idleAutoVeilEnabled: Bool = false,
                idleAutoVeilSeconds: Double = 600,
                scheduleEnabled: Bool = false,
                scheduleStartMinutes: Int = 9 * 60,
                scheduleEndMinutes: Int = 18 * 60,
                scheduleWeekdays: Int = 0b1111111,
                scheduleAutoExit: Bool = false,
                defaultProtectionMinutes: Int = 0,
                sceneProfiles: [String: AuleumSceneProfile] = [:],
                clamshellModeEnabled: Bool = false,
                automaticUpdateChecksEnabled: Bool = true,
                automaticUpdateInstallsEnabled: Bool = true) {
        self.holdToAuthSeconds = holdToAuthSeconds
        self.doubleEscapeSeconds = doubleEscapeSeconds
        self.safetyTimeoutSeconds = safetyTimeoutSeconds
        self.hideCursorDuringVeil = hideCursorDuringVeil
        self.allowPasswordFallback = allowPasswordFallback
        self.veilColor = AuleumColor(hex: veilColor)?.hex ?? AuleumColor.black.hex
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.sceneHotkeys = Self.sanitizeSceneHotkeys(sceneHotkeys)
        self.hasShownOnboarding = hasShownOnboarding
        self.presentationModeEnabled = presentationModeEnabled
        self.presentationImagePath = presentationImagePath
        self.presentationClockStyle = PresentationClockStyle
            .storedValue(presentationClockStyle)
            .rawValue
        self.presentationLayout = PresentationLayout
            .storedValue(presentationLayout)
            .rawValue
        self.presentationCustomLayout = presentationCustomLayout.sanitized()
        self.presentationComponentBackground = PresentationComponentBackground
            .storedValue(presentationComponentBackground)
            .rawValue
        self.presentationDefaultBackdrop = presentationDefaultBackdrop
        self.presentationShowSeconds = presentationShowSeconds
        self.presentationShowLunar = presentationShowLunar
        self.presentationShowElapsed = presentationShowElapsed
        self.mainDisplayRole = AuleumDisplayRole
            .storedValue(mainDisplayRole)
            .rawValue
        self.secondaryDisplayRole = AuleumDisplayRole
            .storedValue(secondaryDisplayRole)
            .rawValue
        self.presentationFocusX = Self.clamp(presentationFocusX, 0...1, fallback: 0.5)
        self.presentationFocusY = Self.clamp(presentationFocusY, 0...1, fallback: 0.5)
        self.presentationZoom = Self.clamp(presentationZoom, 1...2, fallback: 1)
        self.presentationDim = Self.clamp(presentationDim, 0...0.8, fallback: 0)
        self.idleAutoVeilEnabled = idleAutoVeilEnabled
        self.idleAutoVeilSeconds = Self.clamp(
            idleAutoVeilSeconds,
            60...86_400,
            fallback: 600
        )
        self.scheduleEnabled = scheduleEnabled
        self.scheduleStartMinutes = min(1439, max(0, scheduleStartMinutes))
        self.scheduleEndMinutes = min(1439, max(0, scheduleEndMinutes))
        self.scheduleWeekdays = min(0b1111111, max(0, scheduleWeekdays))
        self.scheduleAutoExit = scheduleAutoExit
        self.defaultProtectionMinutes = min(1440, max(0, defaultProtectionMinutes))
        self.sceneProfiles = Self.sanitizeSceneProfiles(sceneProfiles)
        self.clamshellModeEnabled = clamshellModeEnabled
        self.automaticUpdateChecksEnabled = automaticUpdateChecksEnabled
        self.automaticUpdateInstallsEnabled = automaticUpdateInstallsEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case holdToAuthSeconds, doubleEscapeSeconds, safetyTimeoutSeconds
        case hideCursorDuringVeil, allowPasswordFallback, veilColor
        case hotkeyKeyCode, hotkeyModifiers
        case sceneHotkeys
        case hasShownOnboarding
        case presentationModeEnabled, presentationImagePath, presentationClockStyle
        case presentationLayout, presentationCustomLayout
        case presentationComponentBackground
        case presentationDefaultBackdrop
        case presentationShowSeconds, presentationShowLunar
        case presentationShowElapsed
        case mainDisplayRole, secondaryDisplayRole
        case presentationFocusX, presentationFocusY, presentationZoom, presentationDim
        case idleAutoVeilEnabled, idleAutoVeilSeconds
        case scheduleEnabled, scheduleStartMinutes, scheduleEndMinutes
        case scheduleWeekdays, scheduleAutoExit
        case defaultProtectionMinutes, sceneProfiles, clamshellModeEnabled
        case automaticUpdateChecksEnabled, automaticUpdateInstallsEnabled
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case sceneProtectionMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 每个字段独立容错：一个字段类型写错只回退该字段，
        // 不会让整份配置被当成损坏文件而重置。
        let hold = (try? c.decodeIfPresent(
            Double.self,
            forKey: .holdToAuthSeconds
        )) ?? 2.0
        let doubleEscape = (try? c.decodeIfPresent(
            Double.self,
            forKey: .doubleEscapeSeconds
        )) ?? 0.7
        let safety = (try? c.decodeIfPresent(
            Double.self,
            forKey: .safetyTimeoutSeconds
        )) ?? 0
        holdToAuthSeconds = hold.isFinite ? min(5.0, max(1.0, hold)) : 2.0
        doubleEscapeSeconds = doubleEscape.isFinite ? min(1.5, max(0.3, doubleEscape)) : 0.7
        safetyTimeoutSeconds = safety.isFinite ? min(86_400, max(0, safety)) : 0
        hideCursorDuringVeil = (try? c.decodeIfPresent(
            Bool.self,
            forKey: .hideCursorDuringVeil
        )) ?? true
        allowPasswordFallback = (try? c.decodeIfPresent(
            Bool.self,
            forKey: .allowPasswordFallback
        )) ?? false
        let color = (try? c.decodeIfPresent(
            String.self,
            forKey: .veilColor
        )) ?? AuleumColor.black.hex
        veilColor = AuleumColor(hex: color)?.hex ?? AuleumColor.black.hex
        let keyCode = (try? c.decodeIfPresent(
            Int64.self,
            forKey: .hotkeyKeyCode
        )) ?? HotkeyPolicy.keyCode
        let rawModifiers = (try? c.decodeIfPresent(
            UInt64.self,
            forKey: .hotkeyModifiers
        )) ?? HotkeyPolicy.modifiers.rawValue
        let binding = HotkeyBinding(
            keyCode: keyCode,
            modifiers: CGEventFlags(rawValue: rawModifiers)
        )
        if binding.isValid {
            hotkeyKeyCode = binding.keyCode
            hotkeyModifiers = binding.modifiers.rawValue
        } else {
            hotkeyKeyCode = HotkeyPolicy.keyCode
            hotkeyModifiers = HotkeyPolicy.modifiers.rawValue
        }
        sceneHotkeys = Self.sanitizeSceneHotkeys(
            (try? c.decodeIfPresent(
                [String: SceneHotkey].self,
                forKey: .sceneHotkeys
            )) ?? [:]
        )
        hasShownOnboarding = (try? c.decodeIfPresent(
            Bool.self,
            forKey: .hasShownOnboarding
        )) ?? false
        presentationModeEnabled = (try? c.decodeIfPresent(
            Bool.self,
            forKey: .presentationModeEnabled
        )) ?? true
        let path = (try? c.decodeIfPresent(
            String.self,
            forKey: .presentationImagePath
        )) ?? ""
        presentationImagePath = path.count <= 4096 ? path : ""
        let style = (try? c.decodeIfPresent(
            String.self,
            forKey: .presentationClockStyle
        )) ?? PresentationClockStyle.digital.rawValue
        presentationClockStyle = PresentationClockStyle
            .storedValue(style)
            .rawValue
        presentationLayout = PresentationLayout.storedValue(
            (try? c.decodeIfPresent(
                String.self,
                forKey: .presentationLayout
            )) ?? ""
        ).rawValue
        presentationCustomLayout = (
            try? c.decode(
                PresentationCustomLayout.self,
                forKey: .presentationCustomLayout
            )
        )?.sanitized() ?? .default
        presentationComponentBackground = PresentationComponentBackground
            .storedValue(
                (try? c.decodeIfPresent(
                    String.self,
                    forKey: .presentationComponentBackground
                )) ?? ""
            )
            .rawValue
        presentationDefaultBackdrop = (try? c.decodeIfPresent(
            Bool.self,
            forKey: .presentationDefaultBackdrop
        )) ?? true
        presentationShowSeconds = (try? c.decodeIfPresent(
            Bool.self,
            forKey: .presentationShowSeconds
        )) ?? true
        presentationShowLunar = (try? c.decodeIfPresent(
            Bool.self,
            forKey: .presentationShowLunar
        )) ?? true
        presentationShowElapsed = (try? c.decodeIfPresent(
            Bool.self,
            forKey: .presentationShowElapsed
        )) ?? true
        mainDisplayRole = AuleumDisplayRole.storedValue(
            (try? c.decodeIfPresent(
                String.self,
                forKey: .mainDisplayRole
            )) ?? ""
        ).rawValue
        secondaryDisplayRole = AuleumDisplayRole.storedValue(
            (try? c.decodeIfPresent(
                String.self,
                forKey: .secondaryDisplayRole
            )) ?? ""
        ).rawValue
        presentationFocusX = Self.clamp(
            (try? c.decodeIfPresent(
                Double.self,
                forKey: .presentationFocusX
            )) ?? 0.5,
            0...1,
            fallback: 0.5
        )
        presentationFocusY = Self.clamp(
            (try? c.decodeIfPresent(
                Double.self,
                forKey: .presentationFocusY
            )) ?? 0.5,
            0...1,
            fallback: 0.5
        )
        presentationZoom = Self.clamp(
            (try? c.decodeIfPresent(
                Double.self,
                forKey: .presentationZoom
            )) ?? 1,
            1...2,
            fallback: 1
        )
        presentationDim = Self.clamp(
            (try? c.decodeIfPresent(
                Double.self,
                forKey: .presentationDim
            )) ?? 0,
            0...0.8,
            fallback: 0
        )
        idleAutoVeilEnabled = (try? c.decodeIfPresent(
            Bool.self,
            forKey: .idleAutoVeilEnabled
        )) ?? false
        idleAutoVeilSeconds = Self.clamp(
            (try? c.decodeIfPresent(
                Double.self,
                forKey: .idleAutoVeilSeconds
            )) ?? 600,
            60...86_400,
            fallback: 600
        )
        scheduleEnabled = (try? c.decodeIfPresent(
            Bool.self,
            forKey: .scheduleEnabled
        )) ?? false
        scheduleStartMinutes = min(1439, max(0, (try? c.decodeIfPresent(
            Int.self,
            forKey: .scheduleStartMinutes
        )) ?? 9 * 60))
        scheduleEndMinutes = min(1439, max(0, (try? c.decodeIfPresent(
            Int.self,
            forKey: .scheduleEndMinutes
        )) ?? 18 * 60))
        scheduleWeekdays = min(0b1111111, max(0, (try? c.decodeIfPresent(
            Int.self,
            forKey: .scheduleWeekdays
        )) ?? 0b1111111))
        scheduleAutoExit = (try? c.decodeIfPresent(
            Bool.self,
            forKey: .scheduleAutoExit
        )) ?? false
        defaultProtectionMinutes = min(1440, max(0, (try? c.decodeIfPresent(
            Int.self,
            forKey: .defaultProtectionMinutes
        )) ?? 0))
        if let decoded = try? c.decodeIfPresent(
            [String: AuleumSceneProfile].self,
            forKey: .sceneProfiles
        ) {
            sceneProfiles = Self.sanitizeSceneProfiles(decoded)
        } else {
            let legacyContainer = try decoder.container(
                keyedBy: LegacyCodingKeys.self
            )
            let legacy = (try? legacyContainer.decodeIfPresent(
                [String: Int].self,
                forKey: .sceneProtectionMinutes
            )) ?? [:]
            var migrated: [String: AuleumSceneProfile] = [:]
            for (key, minutes) in legacy {
                guard let scene = AuleumScene(rawValue: key) else { continue }
                var profile = scene.defaultProfile
                profile.protectionMinutes = min(1440, max(0, minutes))
                migrated[key] = profile
            }
            sceneProfiles = migrated
        }
        clamshellModeEnabled = (try? c.decodeIfPresent(
            Bool.self,
            forKey: .clamshellModeEnabled
        )) ?? false
        automaticUpdateChecksEnabled = (try? c.decodeIfPresent(
            Bool.self,
            forKey: .automaticUpdateChecksEnabled
        )) ?? true
        automaticUpdateInstallsEnabled = (try? c.decodeIfPresent(
            Bool.self,
            forKey: .automaticUpdateInstallsEnabled
        )) ?? true
    }

    public func displayRole(isMain: Bool) -> AuleumDisplayRole {
        guard presentationModeEnabled else { return .black }
        return AuleumDisplayRole.storedValue(
            isMain ? mainDisplayRole : secondaryDisplayRole
        )
    }

    /// 场景可以覆盖主/副屏角色；未覆盖时沿用全局配置。
    public func displayRole(for scene: AuleumScene?,
                            isMain: Bool) -> AuleumDisplayRole {
        guard presentationModeEnabled else { return .black }
        if let scene {
            let profile = sceneProfile(for: scene)
            let raw = isMain
                ? profile.mainDisplayRole
                : profile.secondaryDisplayRole
            if let raw, let role = AuleumDisplayRole(rawValue: raw) {
                return role
            }
        }
        return displayRole(isMain: isMain)
    }

    public func sceneProfile(for scene: AuleumScene) -> AuleumSceneProfile {
        sceneProfiles[scene.rawValue] ?? scene.defaultProfile
    }

    public func sceneHotkey(for scene: AuleumScene) -> SceneHotkey {
        sceneHotkeys[scene.rawValue] ?? scene.defaultHotkey
    }

    public func protectionMinutes(for scene: AuleumScene) -> Int {
        sceneProfile(for: scene).protectionMinutes
    }

    private static func sanitizeSceneHotkeys(
        _ raw: [String: SceneHotkey]
    ) -> [String: SceneHotkey] {
        var result: [String: SceneHotkey] = [:]
        for (key, value) in raw {
            guard AuleumScene(rawValue: key) != nil, value.isValid else {
                continue
            }
            result[key] = value
        }
        return result
    }

    private static func sanitizeSceneProfiles(
        _ raw: [String: AuleumSceneProfile]
    ) -> [String: AuleumSceneProfile] {
        var result: [String: AuleumSceneProfile] = [:]
        for (key, value) in raw {
            guard AuleumScene(rawValue: key) != nil else { continue }
            result[key] = value.sanitized()
        }
        return result
    }

    private static func clamp(_ value: Double,
                              _ range: ClosedRange<Double>,
                              fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    public static let `default` = AuleumConfig()

    /// 最近一次 `load()` 发现的问题。配置损坏时不静默丢弃用户设置，
    /// 而是备份原文件并在状态/自检里报告。
    public private(set) static var lastLoadIssue: String?

    public struct LoadResult {
        public let config: AuleumConfig
        public let issue: String?
    }

    public static func load() -> AuleumConfig {
        let result = loadResult()
        lastLoadIssue = result.issue
        return result.config
    }

    public static func loadResult() -> LoadResult {
        loadResult(at: Paths.configURL, backupDirectory: Paths.supportDir)
    }

    static func loadResult(at url: URL, backupDirectory: URL) -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LoadResult(config: .default, issue: nil)
        }
        do {
            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(AuleumConfig.self, from: data)
            return LoadResult(config: config, issue: nil)
        } catch {
            let backup = quarantine(url, in: backupDirectory)
            let message = "配置无法读取或解析：\(error.localizedDescription)"
                + (backup.map { "；已备份为 \($0.lastPathComponent)" }
                    ?? "；备份失败")
            return LoadResult(config: .default, issue: message)
        }
    }

    /// 复制而不是移动：原文件保留，用户可以对比或手工修复。
    private static func quarantine(_ url: URL, in directory: URL) -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        var destination = directory.appendingPathComponent(
            "config.corrupt-\(stamp).json"
        )
        var suffix = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent(
                "config.corrupt-\(stamp)-\(suffix).json"
            )
            suffix += 1
        }
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
            return destination
        } catch {
            return nil
        }
    }

    @discardableResult
    public func save() -> String? {
        guard Paths.ensureSupportDir() else {
            return "无法创建 \(Paths.supportDir.path)"
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try enc.encode(self)
            try data.write(to: Paths.configURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: Paths.configURL.path
            )
            return nil
        } catch {
            return "写入 \(Paths.configURL.path) 失败：\(error)"
        }
    }
}
