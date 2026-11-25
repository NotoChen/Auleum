import AppKit
import AuleumKit

extension SettingsWindowController {
    func makeUpdatesPage() -> NSView {
        for control in [autoUpdateCheckSwitch, autoUpdateInstallSwitch] {
            control.controlSize = .small
            control.translatesAutoresizingMaskIntoConstraints = false
        }

        updateCheckButton.target = self
        updateCheckButton.action = #selector(checkForUpdatesClicked)
        updateInstallButton.target = self
        updateInstallButton.action = #selector(installUpdateClicked)
        updateReleaseButton.target = self
        updateReleaseButton.action = #selector(openUpdateReleaseClicked)

        updateVersionLabel.font = .monospacedSystemFont(
            ofSize: 10.5,
            weight: .medium
        )
        updateLatestLabel.font = .monospacedSystemFont(
            ofSize: 10.5,
            weight: .medium
        )
        updateStatusLabel.font = .systemFont(ofSize: 11)
        updateStatusLabel.textColor = AuleumTheme.secondaryInk
        updateStatusLabel.maximumNumberOfLines = 0
        updateStatusLabel.isSelectable = true
        updateStatusLabel.stringValue = "尚未检查更新"
        updateInstallButton.isHidden = true
        updateReleaseButton.isHidden = true

        let preferences = card(containing: [
            AuleumSettingRow(
                title: "自动检查更新",
                detail: "启动后和每 6 小时查询一次 GitHub Releases。",
                control: autoUpdateCheckSwitch
            ),
            AuleumSettingRow(
                title: "自动下载并安装",
                detail: "校验 SHA-256 和签名后，在幕帘关闭且未录制时安装并重启。",
                control: autoUpdateInstallSwitch
            ),
            diagnosticRow(title: "当前版本", valueView: updateVersionLabel),
            diagnosticRow(title: "最新版本", valueView: updateLatestLabel),
        ])

        let buttonRow = AuleumTheme.stack(
            [updateCheckButton, updateInstallButton, updateReleaseButton],
            orientation: .horizontal,
            spacing: 8,
            alignment: .centerY
        )
        let statusStack = AuleumTheme.stack(
            [updateStatusLabel, buttonRow],
            spacing: 12
        )
        let statusCard = AuleumCardView()
        statusCard.contentView.addSubview(statusStack)
        pin(statusStack, to: statusCard.contentView)
        updateStatusLabel.widthAnchor.constraint(
            equalTo: statusStack.widthAnchor
        ).isActive = true
        buttonRow.widthAnchor.constraint(
            lessThanOrEqualTo: statusStack.widthAnchor
        ).isActive = true

        updateNotesLabel.font = .systemFont(ofSize: 10.5)
        updateNotesLabel.textColor = AuleumTheme.secondaryInk
        updateNotesLabel.maximumNumberOfLines = 0
        updateNotesLabel.isSelectable = true
        let notesCard = AuleumCardView()
        notesCard.contentView.addSubview(updateNotesLabel)
        pin(updateNotesLabel, to: notesCard.contentView)
        notesCard.isHidden = true
        updateNotesCard = notesCard

        let privacy = AuleumTheme.label(
            "更新只从 github.com/NotoChen/Auleum 的 Releases 下载，先校验 Release 提供的 SHA-256，再校验 app 签名和版本号。Auleum 不会上传设备信息；检查请求只带版本号作为 User-Agent。",
            size: 10.5,
            color: AuleumTheme.tertiaryInk
        )
        privacy.maximumNumberOfLines = 0

        return page(
            views: [preferences, statusCard, notesCard, privacy],
            spacing: AuleumTheme.sectionSpacing
        )
    }

    func applyUpdateState(_ state: UpdateState) {
        currentUpdateState = state
        guard hasLoadedValues else { return }
        updateVersionLabel.stringValue = state.currentVersion
        updateLatestLabel.stringValue = state.latestVersion ?? "—"
        updateStatusLabel.stringValue = state.message ?? "尚未检查更新"
        updateStatusLabel.textColor = state.phase == .failed
            ? AuleumTheme.danger
            : AuleumTheme.secondaryInk

        updateCheckButton.isEnabled = state.phase != .checking
            && state.phase != .downloading
            && state.phase != .installing
        updateCheckButton.setTitle(
            state.phase == .failed ? "重试" : "检查更新"
        )

        switch state.phase {
        case .available:
            updateInstallButton.isHidden = false
            updateInstallButton.isEnabled = true
            updateInstallButton.setTitle("下载并安装")
        case .ready:
            updateInstallButton.isHidden = false
            updateInstallButton.isEnabled = true
            updateInstallButton.setTitle("安装并重启")
        case .downloading, .installing:
            updateInstallButton.isHidden = false
            updateInstallButton.isEnabled = false
            updateInstallButton.setTitle(
                state.phase == .downloading ? "正在下载…" : "正在安装…"
            )
        case .failed where state.canInstall:
            updateInstallButton.isHidden = false
            updateInstallButton.isEnabled = true
            updateInstallButton.setTitle("安装并重启")
        default:
            updateInstallButton.isHidden = true
            updateInstallButton.isEnabled = false
        }

        updateReleaseButton.isHidden = state.releasePageURL == nil
        updateNotesLabel.stringValue = state.notes
        updateNotesCard?.isHidden = state.notes.isEmpty
    }

    @objc private func checkForUpdatesClicked() {
        onCheckForUpdates?()
    }

    @objc private func installUpdateClicked() {
        onInstallUpdate?()
    }

    @objc private func openUpdateReleaseClicked() {
        onOpenUpdateRelease?()
    }
}
