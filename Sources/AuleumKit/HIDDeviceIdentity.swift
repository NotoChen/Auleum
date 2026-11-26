import CoreGraphics
import Darwin
import Foundation
import IOKit

/// 一个输入 HID 设备的身份。`senderID` 来自 IOHIDEvent 的 sender，
/// 用于把 event tap 里的事件对应回 IORegistry 中的设备。
public struct HIDDeviceIdentity: Equatable, Sendable {
    public var senderID: UInt64
    public var transport: String
    public var product: String
    public var manufacturer: String
    public var isVirtual: Bool
    public var isDeniedVirtualDevice: Bool

    public init(senderID: UInt64,
                transport: String,
                product: String,
                manufacturer: String,
                isVirtual: Bool,
                isDeniedVirtualDevice: Bool) {
        self.senderID = senderID
        self.transport = transport
        self.product = product
        self.manufacturer = manufacturer
        self.isVirtual = isVirtual
        self.isDeniedVirtualDevice = isDeniedVirtualDevice
    }

    public static func classify(senderID: UInt64,
                                transport: String,
                                product: String,
                                manufacturer: String) -> HIDDeviceIdentity {
        let transportText = transport.lowercased()
        let productText = product.lowercased()
        let manufacturerText = manufacturer.lowercased()
        let isVirtual = transportText.contains("virtual")
            || productText.contains("virtual")
            || manufacturerText.contains("virtual")
            || productText.hasPrefix("v-")
        let isDenied = productText.contains("karabiner")
            || manufacturerText.contains("karabiner")
            || manufacturerText.contains("pqrs")
            || productText.contains("driverkit virtualhid")
        return HIDDeviceIdentity(
            senderID: senderID,
            transport: transport,
            product: product,
            manufacturer: manufacturer,
            isVirtual: isVirtual,
            isDeniedVirtualDevice: isDenied
        )
    }
}

/// 通过私有 SPI 读取事件背后的 IOHIDEvent sender，再查 IORegistry 判断
/// 它是不是虚拟 HID 设备。SPI 不可用时返回 nil，调用方仍按物理输入处理。
///
/// 这是「远程兼容模式」下放行 UU/向日葵等虚拟键盘的最后一块拼图：
/// 这类设备的 CGEvent 可能带着 PID 0 和 HID stateID 1，单看事件来源
/// 与真实键盘无法区分。
public final class HIDDeviceInspector: @unchecked Sendable {
    private typealias CopyIOHIDEvent = @convention(c) (CGEvent) -> Unmanaged<CFTypeRef>?
    private typealias GetSenderID = @convention(c) (CFTypeRef) -> UInt64

    private struct Symbols {
        let copyIOHIDEvent: CopyIOHIDEvent
        let getSenderID: GetSenderID
    }

    private static let symbols: Symbols? = {
        guard let copySymbol = loadSymbol("CGEventCopyIOHIDEvent"),
              let senderSymbol = loadSymbol("IOHIDEventGetSenderID") else {
            return nil
        }
        return Symbols(
            copyIOHIDEvent: unsafeBitCast(copySymbol, to: CopyIOHIDEvent.self),
            getSenderID: unsafeBitCast(senderSymbol, to: GetSenderID.self)
        )
    }()

    public static var isSPIAvailable: Bool {
        symbols != nil
    }

    private let lock = NSLock()
    private var cache: [UInt64: HIDDeviceIdentity] = [:]
    private var lastCacheReset = Date()

    public init() {}

    public var isAvailable: Bool {
        Self.symbols != nil
    }

    /// 返回 nil 表示无法判断，调用方应按物理输入处理（严格侧）。
    public func identify(event: CGEvent) -> HIDDeviceIdentity? {
        guard let symbols = Self.symbols,
              let eventRef = symbols.copyIOHIDEvent(event)?.takeRetainedValue() else {
            return nil
        }
        let senderID = symbols.getSenderID(eventRef)
        guard senderID != 0 else { return nil }

        lock.lock()
        if let cached = cache[senderID] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let properties = registryProperties(senderID: senderID) else {
            return nil
        }
        let identity = HIDDeviceIdentity.classify(
            senderID: senderID,
            transport: properties.transport,
            product: properties.product,
            manufacturer: properties.manufacturer
        )

        lock.lock()
        if Date().timeIntervalSince(lastCacheReset) > 60 {
            cache.removeAll(keepingCapacity: true)
            lastCacheReset = Date()
        }
        if cache.count >= 128 {
            cache.removeAll(keepingCapacity: true)
        }
        cache[senderID] = identity
        lock.unlock()
        return identity
    }

    private func registryProperties(
        senderID: UInt64
    ) -> (transport: String, product: String, manufacturer: String)? {
        let matching = IORegistryEntryIDMatching(senderID)
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            matching
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        func stringProperty(_ key: String) -> String {
            guard let value = IORegistryEntryCreateCFProperty(
                service,
                key as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() else {
                return ""
            }
            return value as? String ?? ""
        }

        let transport = stringProperty("Transport")
        let product = stringProperty("Product")
        let manufacturer = stringProperty("Manufacturer")
        guard !transport.isEmpty
                || !product.isEmpty
                || !manufacturer.isEmpty else {
            return nil
        }
        return (transport, product, manufacturer)
    }

    private static func loadSymbol(_ name: String) -> UnsafeMutableRawPointer? {
        if let symbol = dlsym(
            UnsafeMutableRawPointer(bitPattern: -2),
            name
        ) {
            return symbol
        }
        let paths = [
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            "/System/Library/Frameworks/IOKit.framework/IOKit",
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        ]
        for path in paths {
            guard let handle = dlopen(path, RTLD_LAZY) else { continue }
            if let symbol = dlsym(handle, name) {
                return symbol
            }
        }
        return nil
    }
}
