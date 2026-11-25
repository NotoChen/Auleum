import AppKit
import AuleumKit

enum UpdatePhase: Equatable {
    case idle
    case checking
    case upToDate
    case available
    case downloading
    case ready
    case installing
    case failed
}

struct UpdateState: Equatable {
    var phase: UpdatePhase = .idle
    var currentVersion = "0.0.0"
    var latestVersion: String?
    var title: String?
    var notes = ""
    var message: String?
    var releasePageURL: URL?
    var canInstall = false
    var isManual = false
}

/// 更新检查、下载和安装的协调器。网络和文件操作都在后台执行，
/// 状态统一回到主线程；真正退出应用交给 `onInstallScheduled`。
/// 可变状态只在主线程读写，后台任务只负责等待结果后投递回主线程，
/// 因此这里显式承担 Sendable 检查。
final class UpdateController: @unchecked Sendable {
    var onStateChange: ((UpdateState) -> Void)?
    var onInstallScheduled: (() -> Void)?
    var onAudit: ((String, [String: Any]) -> Void)?
    var isBusy: () -> Bool = { false }
    var isAutoCheckEnabled: () -> Bool = { true }
    var isAutoInstallEnabled: () -> Bool = { true }

    let currentVersion: String
    let currentBuild: String
    private(set) var state: UpdateState

    private var release: UpdateRelease?
    private var staged: StagedUpdate?
    private var checkTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var timer: Timer?
    private var initialTimer: Timer?
    private var started = false
    private var wantsInstall = false

    private let lastCheckKey = "io.github.notochen.auleum.lastUpdateCheck"
    private let checkInterval: TimeInterval = 6 * 60 * 60
    private let launchCheckDelay: TimeInterval = 8

    init(currentVersion: String, currentBuild: String) {
        self.currentVersion = currentVersion
        self.currentBuild = currentBuild
        state = UpdateState(currentVersion: currentVersion)
    }

    deinit {
        checkTask?.cancel()
        downloadTask?.cancel()
        timer?.invalidate()
        initialTimer?.invalidate()
    }

    func start() {
        guard !started else { return }
        started = true
        UpdateInstaller.cleanupOldUpdates()
        refreshSchedule()
    }

    func stop() {
        checkTask?.cancel()
        checkTask = nil
        downloadTask?.cancel()
        downloadTask = nil
        timer?.invalidate()
        timer = nil
        initialTimer?.invalidate()
        initialTimer = nil
    }

    /// 设置页保存后调用：自动检查开关变化时重建定时器。
    func refreshSchedule() {
        timer?.invalidate()
        timer = nil
        initialTimer?.invalidate()
        initialTimer = nil
        guard isAutoCheckEnabled() else { return }

        if shouldCheckOnLaunch {
            let timer = Timer(timeInterval: launchCheckDelay, repeats: false) {
                [weak self] _ in
                self?.check(manual: false)
            }
            RunLoop.main.add(timer, forMode: .common)
            initialTimer = timer
        }

        let timer = Timer(timeInterval: checkInterval, repeats: true) {
            [weak self] _ in
            self?.check(manual: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func check(manual: Bool) {
        guard checkTask == nil else {
            if manual {
                state.message = "正在检查更新…"
                publish()
            }
            return
        }
        guard manual || isAutoCheckEnabled() else { return }

        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
        state.phase = .checking
        state.isManual = manual
        state.message = manual ? "正在连接 GitHub…" : nil
        publish()
        onAudit?("update_check_started", ["manual": manual])

        checkTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await UpdateChecker.check(
                    currentVersion: self.currentVersion
                )
                guard !Task.isCancelled else { return }
                DispatchQueue.main.async {
                    self.finishCheck(result, manual: manual)
                    self.checkTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                DispatchQueue.main.async {
                    self.finishFailure(error, manual: manual, phase: .idle)
                    self.checkTask = nil
                }
            }
        }
    }

    /// 用户在发现新版本后点击下载/安装。
    func installAvailable(manual: Bool = true) {
        if staged != nil {
            wantsInstall = true
            _ = installIfPossible(manual: manual)
            return
        }
        guard release != nil else { return }
        wantsInstall = true
        downloadAndStage(manual: manual)
    }

    /// 撤幕或结束录制后调用：如果已经下载并通过校验，就在空闲时安装。
    func installIfIdle() {
        guard staged != nil, !isBusy() else { return }
        guard isAutoInstallEnabled() || wantsInstall else { return }
        _ = installIfPossible(manual: false)
    }

    func openReleasePage() {
        guard let url = state.releasePageURL else { return }
        NSWorkspace.shared.open(url)
    }

    private var shouldCheckOnLaunch: Bool {
        guard let last = UserDefaults.standard.object(
            forKey: lastCheckKey
        ) as? Date else {
            return true
        }
        return Date().timeIntervalSince(last) >= 60 * 60
    }

    private func finishCheck(
        _ result: UpdateCheckResult,
        manual: Bool
    ) {
        switch result {
        case let .upToDate(current, latest):
            release = nil
            staged = nil
            state.phase = .upToDate
            state.latestVersion = latest.description
            state.title = "已是最新版本"
            state.notes = ""
            state.message = "当前 v\(current)，最新 v\(latest)"
            state.releasePageURL = nil
            state.canInstall = false
            state.isManual = manual
            publish()
            onAudit?("update_up_to_date", [
                "current": current.description,
                "latest": latest.description,
                "manual": manual,
            ])
        case let .available(release):
            self.release = release
            staged = nil
            state.phase = .available
            state.latestVersion = release.version.description
            state.title = release.title
            state.notes = String(release.notes.prefix(8_000))
            state.message = "发现新版本 v\(release.version)"
            state.releasePageURL = release.pageURL
            state.canInstall = false
            state.isManual = manual
            publish()
            onAudit?("update_available", [
                "version": release.version.description,
                "manual": manual,
            ])
            if isAutoInstallEnabled() {
                wantsInstall = true
                downloadAndStage(manual: manual)
            }
        }
    }

    private func downloadAndStage(manual: Bool) {
        guard downloadTask == nil, let release else { return }
        state.phase = .downloading
        state.isManual = manual
        state.message = "正在下载并校验 v\(release.version)…"
        state.canInstall = false
        publish()
        onAudit?("update_download_started", [
            "version": release.version.description,
            "manual": manual,
        ])

        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let package = try await UpdateInstaller.downloadAndStage(release)
                guard !Task.isCancelled else { return }
                DispatchQueue.main.async {
                    self.finishDownload(package, manual: manual)
                    self.downloadTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                DispatchQueue.main.async {
                    self.finishFailure(
                        error,
                        manual: manual,
                        phase: .available
                    )
                    self.downloadTask = nil
                }
            }
        }
    }

    private func finishDownload(
        _ package: StagedUpdate,
        manual: Bool
    ) {
        staged = package
        state.phase = .ready
        state.title = "更新已下载"
        state.message = "v\(package.release.version) 已通过 SHA-256 和签名校验"
        state.canInstall = true
        state.isManual = manual
        publish()
        onAudit?("update_ready", [
            "version": package.release.version.description,
            "manual": manual,
        ])

        guard wantsInstall || isAutoInstallEnabled() else { return }
        if isBusy() {
            state.message = "更新已就绪；幕帘关闭或录制结束后自动安装"
            publish()
            return
        }
        _ = installIfPossible(manual: manual)
    }

    @discardableResult
    private func installIfPossible(manual: Bool) -> Bool {
        guard let staged else {
            state.message = "更新还没有下载完成"
            state.phase = .failed
            publish()
            return false
        }
        guard !isBusy() else {
            state.phase = .ready
            state.canInstall = true
            state.message = "幕帘开启或正在录制，结束后自动安装"
            state.isManual = manual
            publish()
            return false
        }

        do {
            _ = try UpdateInstaller.install(staged)
            state.phase = .installing
            state.canInstall = false
            state.message = "正在安装并重启…"
            state.isManual = manual
            publish()
            onAudit?("update_install_started", [
                "version": staged.release.version.description,
                "manual": manual,
            ])
            onInstallScheduled?()
            return true
        } catch {
            state.phase = .failed
            state.message = error.localizedDescription
            state.canInstall = true
            state.isManual = manual
            publish()
            onAudit?("update_install_failed", [
                "error": error.localizedDescription,
            ])
            return false
        }
    }

    private func finishFailure(
        _ error: Error,
        manual: Bool,
        phase: UpdatePhase
    ) {
        state.phase = manual ? .failed : phase
        state.isManual = manual
        state.message = error.localizedDescription
        publish()
        onAudit?("update_failed", [
            "error": error.localizedDescription,
            "manual": manual,
        ])
    }

    private func publish() {
        onStateChange?(state)
    }
}
