import Testing
@testable import AuleumKit

@Suite("Exit auth policy")
struct ExitAuthPolicyTests {
    @Test("Remote input uses the system password when fallback is enabled")
    func remoteInputUsesPassword() {
        #expect(
            ExitAuthPolicy.preferredMethod(
                remoteRequest: true,
                physicalRequest: false,
                remoteMode: true,
                passwordFallbackEnabled: true,
                biometricsAvailable: true,
                systemAuthAvailable: true
            ) == .password
        )
    }

    @Test("Remote input respects the disabled password fallback")
    func remoteInputRespectsFallbackSetting() {
        // 密码兜底是显式安全设置；不能因为远程模式开着就绕过它。
        #expect(
            ExitAuthPolicy.preferredMethod(
                remoteRequest: true,
                physicalRequest: false,
                remoteMode: true,
                passwordFallbackEnabled: false,
                biometricsAvailable: true,
                systemAuthAvailable: true
            ) == nil
        )
    }

    @Test("Physical input prefers Touch ID in remote mode")
    func physicalInputPrefersTouchID() {
        // 远控模式自动开启、密码兜底也开了，本地用户仍应能用指纹撤幕。
        #expect(
            ExitAuthPolicy.preferredMethod(
                remoteRequest: false,
                physicalRequest: true,
                remoteMode: true,
                passwordFallbackEnabled: true,
                biometricsAvailable: true,
                systemAuthAvailable: true
            ) == .touchID
        )
    }

    @Test("Non-input exits keep the remote password habit")
    func nonInputUsesRemoteFallback() {
        #expect(
            ExitAuthPolicy.preferredMethod(
                remoteRequest: false,
                physicalRequest: false,
                remoteMode: true,
                passwordFallbackEnabled: true,
                biometricsAvailable: true,
                systemAuthAvailable: true
            ) == .password
        )
    }

    @Test("Local non-input exits prefer Touch ID")
    func localNonInputPrefersTouchID() {
        #expect(
            ExitAuthPolicy.preferredMethod(
                remoteRequest: false,
                physicalRequest: false,
                remoteMode: false,
                passwordFallbackEnabled: true,
                biometricsAvailable: true,
                systemAuthAvailable: true
            ) == .touchID
        )
    }

    @Test("Password fallback stays opt-in for local exits")
    func localPasswordRequiresFallback() {
        #expect(
            ExitAuthPolicy.preferredMethod(
                remoteRequest: false,
                physicalRequest: false,
                remoteMode: false,
                passwordFallbackEnabled: false,
                biometricsAvailable: false,
                systemAuthAvailable: true
            ) == nil
        )
    }

    @Test("Remote input without system auth keeps the veil")
    func remoteInputWithoutSystemAuth() {
        #expect(
            ExitAuthPolicy.preferredMethod(
                remoteRequest: true,
                physicalRequest: false,
                remoteMode: true,
                passwordFallbackEnabled: true,
                biometricsAvailable: true,
                systemAuthAvailable: false
            ) == nil
        )
    }

    @Test("Nothing available keeps the veil")
    func nothingAvailable() {
        #expect(
            ExitAuthPolicy.preferredMethod(
                remoteRequest: true,
                physicalRequest: true,
                remoteMode: true,
                passwordFallbackEnabled: false,
                biometricsAvailable: false,
                systemAuthAvailable: false
            ) == nil
        )
    }
}
