import Foundation
import LocalAuthentication

/// 默认出口：Touch ID。策略用 biometrics-only，不给密码回退。
/// 密码兜底默认关闭；开启后 Touch ID 不可用或验证失败时改用系统密码面板。
public final class AuthGate {
    private var activeContext: LAContext?

    public init() {}

    /// 生物识别硬件是否可用。不可用时普通出口必须保持幕帘，不能绕过 Touch ID；
    /// 应急撤幕由 `panic` 或结束进程负责。
    public func isAvailable() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// 为内嵌认证视图准备一个可用上下文；不可用时返回 nil。
    public func makeContext() -> LAContext? {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            return nil
        }
        return ctx
    }

    /// 使用已经绑定到 `LAAuthenticationView` 的上下文发起验证。
    public func authenticate(
        using context: LAContext,
        reason: String,
        completion: @escaping (Bool) -> Void
    ) {
        authenticate(using: context, reason: reason) { ok, _ in
            completion(ok)
        }
    }

    /// 带错误信息的 Touch ID 验证；错误用于区分「用户取消」和
    /// 「指纹失败/锁定」，后者可以进入密码兜底。
    public func authenticate(
        using context: LAContext,
        reason: String,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        activeContext = context
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] ok, error in
            DispatchQueue.main.async {
                if self?.activeContext === context {
                    self?.activeContext = nil
                }
                completion(ok, error)
            }
        }
    }

    /// 系统验证（Touch ID 或登录密码）是否可用。密码兜底开启后，
    /// 它决定没有 Touch ID 的 Mac 是否还能正常撤幕。
    public func canUseSystemAuthentication() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// 为系统认证面板准备上下文。使用 `.deviceOwnerAuthentication` 时
    /// 密码由系统的 `coreautha` 面板处理，Auleum 不接触明文密码。
    public func makeSystemContext() -> LAContext? {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            return nil
        }
        return ctx
    }

    /// 使用系统认证面板验证；Touch ID 不可用时这会显示密码输入。
    /// 面板显示期间必须拦截合成输入，只放行物理键鼠。
    public func authenticateWithSystem(
        using context: LAContext,
        reason: String,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        activeContext = context
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] ok, error in
            DispatchQueue.main.async {
                if self?.activeContext === context {
                    self?.activeContext = nil
                }
                completion(ok, error)
            }
        }
    }

    /// 取消尚未完成的认证；其 completion 仍可能回调，调用方需用 generation 丢弃旧结果。
    public func cancel() {
        activeContext?.invalidate()
        activeContext = nil
    }
}
