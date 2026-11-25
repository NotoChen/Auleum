import Foundation
import Testing
@testable import AuleumKit

@Suite("Config")
struct ConfigTests {
    @Test("Decoded values are clamped")
    func decodedValuesAreClamped() throws {
        let data = Data(#"""
        {
          "holdToAuthSeconds": -3,
          "doubleEscapeSeconds": 9,
          "veilColor": "#12abEF",
          "safetyTimeoutSeconds": 9999999,
          "hideCursorDuringVeil": false
        }
        """#.utf8)

        let config = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(config.holdToAuthSeconds == 1.0)
        #expect(config.doubleEscapeSeconds == 1.5)
        #expect(config.veilColor == "#12ABEF")
        #expect(config.safetyTimeoutSeconds == 86_400)
        #expect(!config.hideCursorDuringVeil)
    }

    @Test("Missing and unknown fields use defaults")
    func unknownFieldsUseDefaults() throws {
        let data = Data(#"{"unknown":true,"holdToAuthSeconds":3.5}"#.utf8)
        let config = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(config.holdToAuthSeconds == 3.5)
        #expect(config.doubleEscapeSeconds == 0.7)
        #expect(config.veilColor == "#000000")
        #expect(config.safetyTimeoutSeconds == 0)
        #expect(config.hideCursorDuringVeil)
        #expect(!config.allowPasswordFallback)
    }

    @Test("Password fallback is off by default and round-trips")
    func passwordFallbackRoundTrips() throws {
        var config = try JSONDecoder().decode(
            AuleumConfig.self,
            from: Data("{}".utf8)
        )
        #expect(!config.allowPasswordFallback)

        config.allowPasswordFallback = true
        let decoded = try JSONDecoder().decode(
            AuleumConfig.self,
            from: JSONEncoder().encode(config)
        )
        #expect(decoded.allowPasswordFallback)
    }

    @Test("Invalid veil colors fall back to black")
    func invalidColorFallsBack() throws {
        let data = Data(#"{"veilColor":"not-a-color"}"#.utf8)
        let config = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(config.veilColor == "#000000")
    }

    @Test("Invalid hotkey falls back to the default binding")
    func invalidHotkeyFallsBack() throws {
        let data = Data(#"{"hotkeyKeyCode":8,"hotkeyModifiers":0}"#.utf8)
        let config = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(config.hotkeyKeyCode == HotkeyPolicy.keyCode)
        #expect(config.hotkeyModifiers == HotkeyPolicy.modifiers.rawValue)
    }

    @Test("Scene hotkeys have unique defaults and round-trip")
    func sceneHotkeysRoundTrip() throws {
        var config = try JSONDecoder().decode(
            AuleumConfig.self,
            from: Data("{}".utf8)
        )
        #expect(AuleumScene.allCases.map {
            config.sceneHotkey(for: $0).displayString
        } == ["⌃⌥⌘1", "⌃⌥⌘2", "⌃⌥⌘3", "⌃⌥⌘4"])
        let defaults = AuleumScene.allCases.map {
            config.sceneHotkey(for: $0)
        }
        #expect(Set(defaults.map {
            "\($0.keyCode):\($0.modifiers)"
        }).count == AuleumScene.allCases.count)

        config.sceneHotkeys["away"] = SceneHotkey(
            keyCode: 0,
            modifiers: [.maskControl, .maskAlternate]
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(decoded.sceneHotkey(for: .away).keyCode == 0)
        #expect(decoded.sceneHotkey(for: .meeting) ==
            AuleumScene.meeting.defaultHotkey)
    }

    @Test("Invalid stored scene hotkeys fall back to that scene default")
    func invalidSceneHotkeyFallsBack() throws {
        let data = Data(#"""
        {
          "sceneHotkeys": {
            "away": {
              "keyCode": 8,
              "modifiers": 0
            },
            "meeting": {
              "keyCode": 19,
              "modifiers": 1835008
            }
          }
        }
        """#.utf8)
        let config = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(config.sceneHotkey(for: .away) ==
            AuleumScene.away.defaultHotkey)
        #expect(config.sceneHotkey(for: .meeting).keyCode == 19)
    }

    @Test("Presentation mode defaults to on")
    func presentationDefaultsOn() throws {
        let config = try JSONDecoder().decode(AuleumConfig.self, from: Data("{}".utf8))
        #expect(config.presentationModeEnabled)
        #expect(AuleumConfig.default.presentationModeEnabled)
        #expect(config.presentationImagePath.isEmpty)
        #expect(config.presentationClockStyle == "digital")
        #expect(config.presentationLayout == "centered")
        #expect(config.presentationDefaultBackdrop)
        #expect(config.presentationShowSeconds)
        #expect(config.presentationShowLunar)
        #expect(config.presentationShowElapsed)
        #expect(!config.hasShownOnboarding)
    }

    @Test("Invalid presentation clock style falls back to digital")
    func invalidPresentationClockFallsBack() throws {
        let data = Data(#"{"presentationClockStyle":"sundial"}"#.utf8)
        let config = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(config.presentationClockStyle == PresentationClockStyle.digital.rawValue)
    }

    @Test("Presentation layout is sanitized and the backdrop can be disabled")
    func presentationLayoutIsSanitized() throws {
        let data = Data(#"""
        {
          "presentationLayout": "sidebar",
          "presentationDefaultBackdrop": false,
          "presentationShowSeconds": false,
          "presentationShowLunar": false,
          "presentationShowElapsed": false
        }
        """#.utf8)
        let config = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(config.presentationLayout == PresentationLayout.centered.rawValue)
        #expect(!config.presentationDefaultBackdrop)
        #expect(!config.presentationShowSeconds)
        #expect(!config.presentationShowLunar)
        #expect(!config.presentationShowElapsed)

        let corner = AuleumConfig(presentationLayout: "CORNER")
        #expect(corner.presentationLayout == PresentationLayout.corner.rawValue)
    }

    @Test("Automation and display settings use safe defaults")
    func automationDefaults() throws {
        let config = try JSONDecoder().decode(AuleumConfig.self, from: Data("{}".utf8))
        #expect(!config.idleAutoVeilEnabled)
        #expect(config.idleAutoVeilSeconds == 600)
        #expect(!config.scheduleEnabled)
        #expect(!config.scheduleAutoExit)
        #expect(config.defaultProtectionMinutes == 0)
        #expect(!config.clamshellModeEnabled)
        #expect(config.mainDisplayRole == AuleumDisplayRole.presentation.rawValue)
        #expect(config.secondaryDisplayRole == AuleumDisplayRole.presentation.rawValue)
        #expect(config.presentationFocusX == 0.5)
        #expect(config.presentationZoom == 1)
        #expect(config.presentationDim == 0)
    }

    @Test("Automation values are clamped and display roles are validated")
    func automationClamps() throws {
        let data = Data(#"""
        {
          "idleAutoVeilSeconds": 5,
          "scheduleWeekdays": 999,
          "scheduleStartMinutes": -4,
          "scheduleEndMinutes": 99999,
          "defaultProtectionMinutes": 99999,
          "presentationZoom": 9,
          "presentationDim": -1,
          "presentationFocusX": 2,
          "mainDisplayRole": "broken",
          "secondaryDisplayRole": "black"
        }
        """#.utf8)
        let config = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(config.idleAutoVeilSeconds == 60)
        #expect(config.scheduleWeekdays == 0b1111111)
        #expect(config.scheduleStartMinutes == 0)
        #expect(config.scheduleEndMinutes == 1439)
        #expect(config.defaultProtectionMinutes == 1440)
        #expect(config.presentationZoom == 2)
        #expect(config.presentationDim == 0)
        #expect(config.presentationFocusX == 1)
        #expect(config.mainDisplayRole == AuleumDisplayRole.presentation.rawValue)
        #expect(config.secondaryDisplayRole == AuleumDisplayRole.black.rawValue)
    }

    @Test("An empty weekday selection is preserved for a disabled schedule")
    func emptyWeekdaySelection() throws {
        let data = Data(#"{"scheduleEnabled":false,"scheduleWeekdays":0}"#.utf8)
        let config = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(config.scheduleWeekdays == 0)
        #expect(!config.scheduleEnabled)
    }

    @Test("Output-layer mode overrides display roles")
    func rolesRequirePresentationMode() {
        var config = AuleumConfig.default
        config.presentationModeEnabled = false
        config.mainDisplayRole = AuleumDisplayRole.presentation.rawValue
        #expect(config.displayRole(isMain: true) == .black)
        config.presentationModeEnabled = true
        #expect(config.displayRole(isMain: true) == .presentation)
        config.mainDisplayRole = AuleumDisplayRole.black.rawValue
        #expect(config.displayRole(isMain: true) == .black)
    }

    @Test("Scene profiles use defaults and sanitize overrides")
    func sceneProfiles() throws {
        let data = Data(#"""
        {
          "sceneProfiles": {
            "away": {
              "protectionMinutes": 15,
              "usesPresentation": true,
              "message": "离开中"
            },
            "meeting": {
              "protectionMinutes": 99999,
              "usesPresentation": false
            },
            "guest": {
              "protectionMinutes": -3,
              "usesPresentation": true
            },
            "unknown": {
              "protectionMinutes": 20
            }
          }
        }
        """#.utf8)
        let config = try JSONDecoder().decode(AuleumConfig.self, from: data)

        #expect(config.protectionMinutes(for: .away) == 15)
        #expect(config.protectionMinutes(for: .meeting) == 1440)
        #expect(config.protectionMinutes(for: .guest) == 0)
        #expect(config.protectionMinutes(for: .focus) ==
            AuleumScene.focus.defaultProtectionMinutes)
        #expect(config.sceneProfiles["unknown"] == nil)
        #expect(config.sceneProfile(for: .away).usesPresentation)
        #expect(!config.sceneProfile(for: .meeting).usesPresentation)
    }

    @Test("Scene profiles round-trip without changing defaults")
    func sceneProfileRoundTrip() throws {
        var config = AuleumConfig.default
        config.sceneProfiles = [
            "away": AuleumSceneProfile(
                protectionMinutes: 180,
                usesPresentation: true,
                message: "离开中"
            )
        ]
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AuleumConfig.self, from: data)

        #expect(decoded.protectionMinutes(for: .away) == 180)
        #expect(decoded.sceneProfile(for: .away).message == "离开中")
        #expect(decoded.protectionMinutes(for: .meeting) ==
            AuleumScene.meeting.defaultProtectionMinutes)
        #expect(AuleumScene.durationText(minutes: 120) == "2 小时")
        #expect(AuleumScene.durationText(minutes: 45) == "45 分钟")
        #expect(AuleumScene.durationText(minutes: 0) == "不限时")
    }

    @Test("Legacy scene minute overrides become full profiles")
    func legacySceneMinutesBecomeProfiles() throws {
        let data = Data(#"""
        {
          "sceneProtectionMinutes": {
            "away": 45,
            "meeting": 120
          }
        }
        """#.utf8)
        let config = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(config.protectionMinutes(for: .away) == 45)
        #expect(config.protectionMinutes(for: .meeting) == 120)
        #expect(config.sceneProfile(for: .meeting).usesPresentation == false)
    }

    @Test("Scene roles can override the global display roles")
    func sceneRoleOverrides() {
        var config = AuleumConfig.default
        config.presentationModeEnabled = true
        config.mainDisplayRole = AuleumDisplayRole.presentation.rawValue
        config.secondaryDisplayRole = AuleumDisplayRole.presentation.rawValue
        var profile = AuleumScene.away.defaultProfile
        profile.mainDisplayRole = AuleumDisplayRole.black.rawValue
        profile.secondaryDisplayRole = AuleumDisplayRole.presentation.rawValue
        config.sceneProfiles["away"] = profile

        #expect(config.displayRole(for: .away, isMain: true) == .black)
        #expect(config.displayRole(for: .away, isMain: false) == .presentation)
        #expect(config.displayRole(for: .guest, isMain: true) == .presentation)
    }

    @Test("Freeform layout is a real layout option")
    func freeformLayoutIsSelectable() {
        #expect(PresentationLayout.allCases.contains(.custom))
        #expect(PresentationLayout.storedValue("CUSTOM") == .custom)
        #expect(PresentationLayout.storedValue("freeform") == .centered)
        #expect(PresentationLayout.custom.displayName == "自由")
    }

    @Test("Freeform layout persists and round-trips")
    func freeformLayoutRoundTrip() throws {
        var config = AuleumConfig.default
        config.presentationLayout = PresentationLayout.custom.rawValue
        config.presentationCustomLayout = PresentationCustomLayout(
            clock: PresentationWidgetPlacement(x: 0.32, y: 0.64),
            message: PresentationWidgetPlacement(x: 0.18, y: 0.12),
            returnTime: PresentationWidgetPlacement(x: 0.86, y: 0.92)
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AuleumConfig.self, from: data)

        #expect(decoded.presentationLayout ==
            PresentationLayout.custom.rawValue)
        #expect(decoded.presentationCustomLayout == config.presentationCustomLayout)
    }

    @Test("Freeform positions are clamped and fall back when malformed")
    func freeformLayoutIsSanitized() throws {
        let data = Data(#"""
        {
          "presentationLayout": "custom",
          "presentationCustomLayout": {
            "clock": { "x": 2.5, "y": -1 },
            "message": { "x": 0.25 },
            "returnTime": "somewhere"
          }
        }
        """#.utf8)
        let config = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(config.presentationLayout == PresentationLayout.custom.rawValue)
        #expect(config.presentationCustomLayout.clock.x == 1)
        #expect(config.presentationCustomLayout.clock.y == 0)
        #expect(config.presentationCustomLayout.message.x == 0.25)
        #expect(config.presentationCustomLayout.message.y ==
            PresentationCustomLayout.default.message.y)
        #expect(config.presentationCustomLayout.returnTime ==
            PresentationCustomLayout.default.returnTime)

        let malformed = Data(#"""
        { "presentationCustomLayout": "not-an-object" }
        """#.utf8)
        let fallback = try JSONDecoder().decode(AuleumConfig.self, from: malformed)
        #expect(fallback.presentationCustomLayout == .default)

        let direct = PresentationWidgetPlacement(
            x: .infinity,
            y: .nan
        )
        #expect(direct.x == 0.5)
        #expect(direct.y == 0.5)
    }

    @Test("Freeform placement clamps inside the canvas margins")
    func freeformPlacementClamps() {
        let canvas = CGSize(width: 1000, height: 500)
        let item = CGSize(width: 200, height: 100)

        let outside = PresentationPlacementResolver.normalizedCenter(
            CGPoint(x: -50, y: 1000),
            itemSize: item,
            canvasSize: canvas,
            margin: 20
        )
        #expect(abs(outside.x - 0.12) < 0.0001)
        #expect(abs(outside.y - 0.86) < 0.0001)

        let centered = PresentationPlacementResolver.normalizedCenter(
            CGPoint(x: 500, y: 250),
            itemSize: item,
            canvasSize: canvas,
            margin: 20
        )
        #expect(centered.x == 0.5)
        #expect(centered.y == 0.5)

        let oversized = PresentationPlacementResolver.normalizedCenter(
            CGPoint(x: 0, y: 0),
            itemSize: CGSize(width: 1200, height: 700),
            canvasSize: canvas,
            margin: 20
        )
        #expect(oversized.x == 0.5)
        #expect(oversized.y == 0.5)

        let empty = PresentationPlacementResolver.normalizedCenter(
            CGPoint(x: 10, y: 10),
            itemSize: item,
            canvasSize: .zero,
            margin: 20
        )
        #expect(empty == PresentationWidgetPlacement(x: 0.5, y: 0.5))
    }

    @Test("Component background is selectable and falls back to auto")
    func componentBackgroundIsSanitized() throws {
        #expect(PresentationComponentBackground.allCases == [.auto, .glass, .clear])
        #expect(PresentationComponentBackground.storedValue("CLEAR") == .clear)
        #expect(PresentationComponentBackground.storedValue("wat") == .auto)
        #expect(PresentationComponentBackground.auto.displayName == "自动")
        #expect(PresentationComponentBackground.clear.displayName == "透明")

        var config = AuleumConfig.default
        config.presentationComponentBackground =
            PresentationComponentBackground.glass.rawValue
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(decoded.presentationComponentBackground == "glass")

        let malformed = try JSONDecoder().decode(
            AuleumConfig.self,
            from: Data(#"{"presentationComponentBackground":"wat"}"#.utf8)
        )
        #expect(malformed.presentationComponentBackground == "auto")
    }

    @Test("A wrong field type only resets that field")
    func wrongFieldTypeIsIsolated() throws {
        let data = Data(#"""
        {
          "holdToAuthSeconds": "soon",
          "doubleEscapeSeconds": 1.1,
          "allowPasswordFallback": true,
          "presentationModeEnabled": false,
          "sceneHotkeys": "nope",
          "sceneProfiles": "nope"
        }
        """#.utf8)
        let config = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(config.holdToAuthSeconds == 2.0)
        #expect(config.doubleEscapeSeconds == 1.1)
        #expect(config.allowPasswordFallback)
        #expect(!config.presentationModeEnabled)
        #expect(config.sceneHotkey(for: .away) ==
            AuleumScene.away.defaultHotkey)
        #expect(config.protectionMinutes(for: .away) ==
            AuleumScene.away.defaultProtectionMinutes)
    }

    @Test("A valid config file loads without an issue")
    func validConfigFileLoads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        let expected = AuleumConfig(allowPasswordFallback: true)
        try JSONEncoder().encode(expected).write(to: url)

        let result = AuleumConfig.loadResult(
            at: url,
            backupDirectory: directory
        )
        #expect(result.issue == nil)
        #expect(result.config.allowPasswordFallback)
    }

    @Test("A corrupt config file falls back to defaults and is backed up")
    func corruptConfigFileIsBackedUp() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        let broken = Data(#"{"holdToAuthSeconds": "#.utf8)
        try broken.write(to: url)

        let result = AuleumConfig.loadResult(
            at: url,
            backupDirectory: directory
        )
        #expect(result.issue != nil)
        #expect(result.config == .default)

        let backups = try FileManager.default.contentsOfDirectory(
            atPath: directory.path
        ).filter { $0.hasPrefix("config.corrupt-") }
        #expect(backups.count == 1)
        let backup = try Data(
            contentsOf: directory.appendingPathComponent(backups[0])
        )
        #expect(backup == broken)
    }

    @Test("A missing config file is not reported as an issue")
    func missingConfigFileUsesDefaults() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let result = AuleumConfig.loadResult(
            at: directory.appendingPathComponent("config.json"),
            backupDirectory: directory
        )
        #expect(result.issue == nil)
        #expect(result.config == .default)
    }
    @Test("Component chrome adapts to the veil color")
    func componentChromeAdaptsToColor() {
        let black = AuleumColor.black
        let white = AuleumColor(red: 1, green: 1, blue: 1)
        let midGray = AuleumColor(red: 0.5, green: 0.5, blue: 0.5)

        #expect(PresentationChromeResolver.relativeLuminance(black) == 0)
        #expect(abs(
            PresentationChromeResolver.relativeLuminance(white) - 1
        ) < 0.0001)
        #expect(PresentationChromeResolver.ink(for: black) == .light)
        #expect(PresentationChromeResolver.ink(for: white) == .dark)
        #expect(PresentationChromeResolver.ink(for: midGray) == .dark)

        #expect(PresentationChromeResolver.resolve(
            hasImage: false,
            usesDefaultBackdrop: false,
            color: black,
            componentBackground: .auto,
            layout: .centered
        ) == PresentationChrome(ink: .light, panelTone: nil))

        #expect(PresentationChromeResolver.resolve(
            hasImage: false,
            usesDefaultBackdrop: false,
            color: white,
            componentBackground: .auto,
            layout: .custom
        ) == PresentationChrome(ink: .dark, panelTone: nil))

        #expect(PresentationChromeResolver.resolve(
            hasImage: true,
            usesDefaultBackdrop: true,
            color: white,
            componentBackground: .auto,
            layout: .centered
        ) == PresentationChrome(ink: .light, panelTone: .dark))

        #expect(PresentationChromeResolver.resolve(
            hasImage: false,
            usesDefaultBackdrop: true,
            color: white,
            componentBackground: .auto,
            layout: .corner
        ) == PresentationChrome(ink: .light, panelTone: .dark))

        #expect(PresentationChromeResolver.resolve(
            hasImage: false,
            usesDefaultBackdrop: false,
            color: white,
            componentBackground: .glass,
            layout: .centered
        ) == PresentationChrome(ink: .dark, panelTone: .light))

        #expect(PresentationChromeResolver.resolve(
            hasImage: false,
            usesDefaultBackdrop: false,
            color: black,
            componentBackground: .glass,
            layout: .centered
        ) == PresentationChrome(ink: .light, panelTone: .dark))

        #expect(PresentationChromeResolver.resolve(
            hasImage: true,
            usesDefaultBackdrop: true,
            color: black,
            componentBackground: .clear,
            layout: .custom
        ) == PresentationChrome(ink: .light, panelTone: nil))

        #expect(PresentationChromeResolver.resolve(
            hasImage: false,
            usesDefaultBackdrop: false,
            color: black,
            componentBackground: .glass,
            layout: .minimal
        ) == PresentationChrome(ink: .light, panelTone: nil))
    }

    @Test("Update settings default on and decode independently")
    func updateSettings() throws {
        let defaults = AuleumConfig.default
        #expect(defaults.automaticUpdateChecksEnabled)
        #expect(defaults.automaticUpdateInstallsEnabled)

        let data = Data(#"""
        {
          "automaticUpdateChecksEnabled": false,
          "automaticUpdateInstallsEnabled": "not-a-bool"
        }
        """#.utf8)
        let config = try JSONDecoder().decode(AuleumConfig.self, from: data)
        #expect(config.automaticUpdateChecksEnabled == false)
        #expect(config.automaticUpdateInstallsEnabled)
    }
}
