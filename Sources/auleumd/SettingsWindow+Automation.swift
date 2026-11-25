import AppKit
import AuleumKit

extension SettingsWindowController {
    func makeAutomationPage() -> NSView {
        for control in [
            idleSwitch,
            scheduleSwitch,
            scheduleAutoExitSwitch,
        ] {
            control.controlSize = .small
            control.translatesAutoresizingMaskIntoConstraints = false
        }
        idleSwitch.target = self
        idleSwitch.action = #selector(automationToggled)
        scheduleSwitch.target = self
        scheduleSwitch.action = #selector(automationToggled)
        scheduleAutoExitSwitch.target = self
        scheduleAutoExitSwitch.action = #selector(automationToggled)

        for picker in [scheduleStartPicker, scheduleEndPicker] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = .hourMinute
            picker.controlSize = .small
            picker.translatesAutoresizingMaskIntoConstraints = false
            picker.widthAnchor.constraint(equalToConstant: 108).isActive = true
        }
        let timeControls = AuleumTheme.stack(
            [
                AuleumTheme.label("从", size: 10.5, color: AuleumTheme.secondaryInk),
                scheduleStartPicker,
                AuleumTheme.label("到", size: 10.5, color: AuleumTheme.secondaryInk),
                scheduleEndPicker,
            ],
            orientation: .horizontal,
            spacing: 8,
            alignment: .centerY
        )

        weekdayButtons = ["一", "二", "三", "四", "五", "六", "日"].enumerated().map {
            index, title in
            let button = NSButton(title: title, target: nil, action: nil)
            button.tag = index
            button.setButtonType(.toggle)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: 10.5, weight: .medium)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 30).isActive = true
            return button
        }
        let weekdayControls = AuleumTheme.stack(
            weekdayButtons,
            orientation: .horizontal,
            spacing: 5,
            alignment: .centerY
        )

        let rows: [NSView] = [
            AuleumSettingRow(
                title: "空闲自动起幕",
                detail: "物理输入空闲达到阈值后自动起幕。",
                control: idleSwitch
            ),
            AuleumSettingRow(
                title: "空闲阈值",
                detail: "触发一次，真实输入后重新计时。",
                control: idleMinutesField
            ),
            AuleumSettingRow(
                title: "每日定时保护",
                detail: "到点自动起幕。",
                control: scheduleSwitch
            ),
            AuleumSettingRow(
                title: "保护时段",
                detail: "开始晚于结束表示跨午夜；相同表示全天。",
                control: timeControls
            ),
            AuleumSettingRow(
                title: "生效星期",
                detail: "启用定时时至少选一天。",
                control: weekdayControls
            ),
            AuleumSettingRow(
                title: "时段结束后验证退出",
                detail: "只发起验证，不自动露出桌面。",
                control: scheduleAutoExitSwitch
            ),
            AuleumSettingRow(
                title: "默认保护时长",
                detail: "到时只验证；0 表示不限时。",
                control: protectionMinutesField
            ),
        ]
        let settingsCard = card(containing: rows)

        let noteIcon = AuleumIconTile(
            symbol: "lock.shield",
            color: AuleumTheme.accent,
            size: 32
        )
        let noteTitle = AuleumTheme.label(
            "任何自动路径都不会绕过 Touch ID",
            size: 12,
            weight: .semibold
        )
        let noteText = AuleumTheme.label(
            "空闲、定时和倒计时只负责起幕或发起验证。默认出口仍是 Touch ID，密码兜底默认关闭；系统睡眠、权限失效和覆盖失败都会保持幕帘并重试，锁屏时让出登录界面、解锁后重建。",
            size: 10.5,
            color: AuleumTheme.secondaryInk
        )
        let noteStack = AuleumTheme.stack([noteTitle, noteText], spacing: 3)
        let noteRow = AuleumTheme.stack(
            [noteIcon, noteStack],
            orientation: .horizontal,
            spacing: 14,
            alignment: .top
        )
        let noteCard = AuleumCardView(
            padding: NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        )
        noteCard.contentView.addSubview(noteRow)
        pin(noteRow, to: noteCard.contentView)
        updateAutomationControls()

        return page(
            views: [settingsCard, noteCard],
            spacing: AuleumTheme.sectionSpacing
        )
    }

    func updateAutomationControls() {
        let idleEnabled = idleSwitch.state == .on
        idleMinutesField.isEnabled = idleEnabled
        let scheduleEnabled = scheduleSwitch.state == .on
        scheduleStartPicker.isEnabled = scheduleEnabled
        scheduleEndPicker.isEnabled = scheduleEnabled
        scheduleAutoExitSwitch.isEnabled = scheduleEnabled
        weekdayButtons.forEach { $0.isEnabled = scheduleEnabled }
    }

    @objc func automationToggled() {
        updateAutomationControls()
    }

    func date(fromMinutes minutes: Int) -> Date {
        let calendar = Calendar.current
        return calendar.date(
            byAdding: .minute,
            value: min(1439, max(0, minutes)),
            to: calendar.startOfDay(for: Date())
        ) ?? Date()
    }

    func minutes(from picker: NSDatePicker) -> Int {
        let components = Calendar.current.dateComponents(
            [.hour, .minute],
            from: picker.dateValue
        )
        return min(
            1439,
            max(0, (components.hour ?? 0) * 60 + (components.minute ?? 0))
        )
    }
}
