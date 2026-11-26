import Foundation
import Testing
@testable import AuleumKit

@Suite("Remote input policy")
struct RemoteInputTests {
    @Test("Known remote tools are recognized by bundle or executable")
    func remoteToolRecognition() {
        #expect(RemoteProcessPolicy.tool(
            forExecutablePath: "/Applications/UURemote.app/Contents/Helpers/UURemoteServer"
        ) == .uu)
        #expect(RemoteProcessPolicy.tool(
            forExecutablePath: "/Applications/SunloginClient.app/Contents/MacOS/SunloginClient"
        ) == .sunlogin)
        #expect(RemoteProcessPolicy.tool(
            forExecutablePath: "/Applications/AnyDesk.app/Contents/MacOS/AnyDesk"
        ) == .anydesk)
        #expect(RemoteProcessPolicy.tool(
            forExecutablePath: "/Applications/RustDesk.app/Contents/MacOS/RustDesk"
        ) == .rustdesk)
        #expect(RemoteProcessPolicy.tool(
            forExecutablePath: "/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/MacOS/ARDAgent"
        ) == .screenSharing)
        #expect(RemoteProcessPolicy.tool(
            forExecutablePath: "/usr/local/bin/remoting_me2me_host"
        ) == .chromeRemoteDesktop)
    }

    @Test("Lookalike paths do not match")
    func lookalikePathsDoNotMatch() {
        #expect(RemoteProcessPolicy.tool(
            forExecutablePath: "/Applications/NotUURemote.app/Contents/MacOS/NotUURemote"
        ) == nil)
        #expect(RemoteProcessPolicy.tool(
            forExecutablePath: "/Applications/Foo.app/Contents/MacOS/Foo"
        ) == nil)
        #expect(RemoteProcessPolicy.tool(forExecutablePath: "") == nil)
    }

    @Test("Karabiner virtual devices are denied")
    func karabinerIsDenied() {
        #expect(RemoteProcessPolicy.isDenied(
            "/Applications/Karabiner-Elements.app/Contents/MacOS/Karabiner-Core-Service"
        ))
        #expect(RemoteProcessPolicy.isDenied(
            "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/daemon"
        ))
        #expect(RemoteProcessPolicy.isDenied(
            "/usr/local/bin/Karabiner-VirtualHIDDevice-Daemon"
        ))
        #expect(!RemoteProcessPolicy.isDenied(
            "/Applications/UURemote.app/Contents/Helpers/UURemoteServer"
        ))
    }

    @Test("Snapshot lookup is cheap and ignores refresh time for equality")
    func snapshotLookup() {
        let snapshot = RemoteProcessSnapshot(
            remotePIDs: [42, 43],
            deniedPIDs: [7],
            tools: [.uu, .sunlogin]
        )
        #expect(snapshot.isRemote(42))
        #expect(!snapshot.isRemote(7))
        #expect(snapshot.isDenied(7))
        #expect(snapshot.hasRemoteTool)
        #expect(snapshot.toolNames == "UU 远程、向日葵")

        let later = RemoteProcessSnapshot(
            remotePIDs: [42, 43],
            deniedPIDs: [7],
            tools: [.uu, .sunlogin],
            refreshedAt: Date().addingTimeInterval(10)
        )
        #expect(snapshot == later)
    }

    @Test("Virtual HID classification separates remote tools from Karabiner")
    func virtualHIDClassification() {
        let uu = HIDDeviceIdentity.classify(
            senderID: 1,
            transport: "Virtual",
            product: "UU Remote Virtual Keyboard",
            manufacturer: "NetEase"
        )
        #expect(uu.isVirtual)
        #expect(!uu.isDeniedVirtualDevice)

        let karabiner = HIDDeviceIdentity.classify(
            senderID: 2,
            transport: "Virtual",
            product: "Karabiner DriverKit VirtualHIDKeyboard",
            manufacturer: "pqrs.org"
        )
        #expect(karabiner.isVirtual)
        #expect(karabiner.isDeniedVirtualDevice)

        let physical = HIDDeviceIdentity.classify(
            senderID: 3,
            transport: "USB",
            product: "Apple Internal Keyboard / Trackpad",
            manufacturer: "Apple Inc."
        )
        #expect(!physical.isVirtual)
        #expect(!physical.isDeniedVirtualDevice)

        let bluetooth = HIDDeviceIdentity.classify(
            senderID: 4,
            transport: "Bluetooth",
            product: "Magic Keyboard",
            manufacturer: "Apple Inc."
        )
        #expect(!bluetooth.isVirtual)
    }
}
