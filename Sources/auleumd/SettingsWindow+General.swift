import AppKit
import AuleumKit

extension SettingsWindowController {
    func makeGeneralPage() -> NSView {
        let colorControls = NSStackView()
        colorControls.orientation = .horizontal
        colorControls.spacing = 8
        colorWell.color = nsColor(from: config.veilColor)
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            colorWell.widthAnchor.constraint(equalToConstant: 54),
            colorWell.heightAnchor.constraint(equalToConstant: 28),
        ])
        let resetColor = AuleumButton(
            title: "恢复黑色",
            style: .secondary,
            target: self,
            action: #selector(resetColor)
        )
        colorControls.addArrangedSubview(colorWell)
        colorControls.addArrangedSubview(resetColor)

        hotkeyButton.onCapture = { [weak self] binding in
            self?.diagnosticsHotkeyValue.stringValue = HotkeyPolicy.displayString(
                keyCode: binding.keyCode,
                modifiers: binding.modifiers
            )
        }
        hotkeyButton.translatesAutoresizingMaskIntoConstraints = false
        hotkeyButton.widthAnchor.constraint(equalToConstant: 124).isActive = true
        hotkeyButton.heightAnchor.constraint(equalToConstant: 32).isActive = true

        for control in [
            hideCursorSwitch,
            passwordFallbackSwitch,
            remoteCompatibilitySwitch,
            remoteAutoSwitch,
            launchAtLoginSwitch,
            clamshellSwitch,
            presentationSwitch,
        ] {
            control.controlSize = .small
            control.translatesAutoresizingMaskIntoConstraints = false
        }
        remoteCompatibilitySwitch.target = self
        remoteCompatibilitySwitch.action = #selector(remoteCompatibilityChanged)

        let rows: [NSView] = [
            AuleumSettingRow(
                title: "双击 Esc 解除",
                detail: "窗口内双击物理 Esc，直接验证。",
                control: doubleField
            ),
            AuleumSettingRow(
                title: "长按 Esc 兜底",
                detail: "按住达到时长后验证。",
                control: holdField
            ),
            AuleumSettingRow(
                title: "起幕 / 撤幕快捷键",
                detail: "必须包含 Control、Option 或 Command 中的至少一个。",
                control: hotkeyButton
            ),
            AuleumSettingRow(
                title: "幕帘颜色",
                detail: "输出层幕帘和纯色展示底色；图片和默认渐变优先。",
                control: colorControls
            ),
            AuleumSettingRow(
                title: "隐藏鼠标指针",
                detail: "幕帘期间隐藏指针；远程兼容时强制显示。",
                control: hideCursorSwitch
            ),
            AuleumSettingRow(
                title: "密码验证兜底",
                detail: "Touch ID 不可用或验证失败时改用系统密码面板；默认关闭。",
                control: passwordFallbackSwitch
            ),
            AuleumSettingRow(
                title: "远程控制兼容",
                detail: "幕帘期间放行远控键鼠并显示指针；物理键鼠仍拦截。",
                control: remoteCompatibilitySwitch
            ),
            AuleumSettingRow(
                title: "自动识别远控",
                detail: "检测到 UU、向日葵、AnyDesk、RustDesk、屏幕共享等进程时自动开启。",
                control: remoteAutoSwitch
            ),
            AuleumSettingRow(
                title: "开机自启",
                detail: "登录后自动启动；异常退出时由 launchd 拉起，不会绕过验证。",
                control: launchAtLoginSwitch
            ),
            AuleumSettingRow(
                title: "合盖继续运行",
                detail: "申请防休眠；是否继续由 macOS 电源策略决定。",
                control: clamshellSwitch
            ),
        ]
        let mainCard = card(containing: rows)

        let touchIcon = AuleumIconTile(
            symbol: "touchid",
            color: AuleumTheme.accent,
            size: 32
        )
        let noteTitle = AuleumTheme.label(
            "Touch ID 是默认出口",
            size: 12,
            weight: .semibold
        )
        let noteText = AuleumTheme.label(
            "验证界面显示在幕帘中央，指纹比对仍由系统完成。密码兜底默认关闭；开启后 Touch ID 不可用或验证失败时改用系统密码面板，期间物理键鼠放行给系统面板，合成输入仍被拦截。远程兼容开启时，已知远控进程和虚拟 HID 设备可以操作被幕帘挡住的桌面，鼠标指针会保持可见；本机物理键鼠仍然拦截。没有可用验证方式时不会允许起幕；应急撤幕使用 panic 或结束进程。",
            size: 10.5,
            color: AuleumTheme.secondaryInk
        )
        let noteStack = AuleumTheme.stack([noteTitle, noteText], spacing: 3)
        let noteRow = AuleumTheme.stack(
            [touchIcon, noteStack],
            orientation: .horizontal,
            spacing: 14,
            alignment: .top
        )
        let noteCard = AuleumCardView(padding: NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18))
        noteCard.contentView.addSubview(noteRow)
        pin(noteRow, to: noteCard.contentView)

        return page(views: [mainCard, noteCard], spacing: AuleumTheme.sectionSpacing)
    }
}
