import Foundation

/// 撤幕验证方式。Touch ID 需要本地手指，系统密码面板可以由远控端完成。
public enum ExitAuthMethod: Equatable, Sendable {
    case touchID
    case password
}

/// 选择撤幕验证方式。把来源和配置分开，方便单测覆盖远控/本机两套路径。
public enum ExitAuthPolicy {
    /// - Parameters:
    ///   - remoteRequest: 这次撤幕是否由已知远控来源或虚拟 HID 输入发起。
    ///   - physicalRequest: 这次撤幕是否由本机物理输入发起。
    ///   - remoteMode: 当前是否处于远程兼容模式。
    ///   - passwordFallbackEnabled: 设置里的密码兜底开关。
    ///   - biometricsAvailable: Touch ID 是否可用。
    ///   - systemAuthAvailable: 系统密码验证是否可用。
    public static func preferredMethod(
        remoteRequest: Bool,
        physicalRequest: Bool,
        remoteMode: Bool,
        passwordFallbackEnabled: Bool,
        biometricsAvailable: Bool,
        systemAuthAvailable: Bool
    ) -> ExitAuthMethod? {
        // 远控来源不可能完成 Touch ID；只有用户显式开启密码兜底时才允许
        // 密码出口，不能因为远程模式开着就绕过这个安全设置。
        if remoteRequest {
            if passwordFallbackEnabled, systemAuthAvailable {
                return .password
            }
            return nil
        }
        // 本机物理输入优先 Touch ID，即使远控模式开启且密码兜底已启用，
        // 也不要让坐在机器前的人被迫输入密码。
        if physicalRequest, biometricsAvailable {
            return .touchID
        }
        // 非输入来源（面板按钮、定时、CLI）沿用旧行为：远控模式 + 密码
        // 兜底时优先密码，避免远端无法完成本机指纹。
        if remoteMode, passwordFallbackEnabled, systemAuthAvailable {
            return .password
        }
        if biometricsAvailable {
            return .touchID
        }
        if passwordFallbackEnabled, systemAuthAvailable {
            return .password
        }
        return nil
    }
}
