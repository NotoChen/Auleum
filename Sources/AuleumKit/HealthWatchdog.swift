import Foundation

/// 把 tap/权限检查放到后台队列，同时用主线程心跳发现主线程卡死。
///
/// 只要幕帘还在，主线程卡死就意味着用户看不见屏幕、也无法通过菜单撤幕。
/// 这时后台看门狗会主动结束进程，让 WindowServer 销毁幕帘窗口，恢复物理输入；
/// LaunchAgent 如果已安装，会在进程退出后重新拉起。
public final class HealthWatchdog {
    public var interval: TimeInterval = 0.5
    public var mainThreadTimeout: TimeInterval = 8.0
    /// 失效持续期间重复上报的间隔；幕帘不会因为失效被撤下，重试需要持续进行。
    public var repeatInterval: TimeInterval = 5.0
    public var check: (() -> String?)?
    public var onFailure: ((String) -> Void)?
    public var onHealthy: (() -> Void)?
    public var onMainThreadStalled: (() -> Void)?

    private let queue = DispatchQueue(label: "io.github.notochen.auleum.health-watchdog", qos: .utility)
    private let lock = NSLock()
    private var source: DispatchSourceTimer?
    private var mainTimer: Timer?
    private var lastHeartbeat = Date()
    private var lastTickAt = Date()
    private var lastFailureReportedAt: Date?
    private var stallReported = false
    private var running = false

    public init() {}

    public func start() {
        stop()
        let now = Date()
        lock.lock()
        running = true
        lastHeartbeat = now
        lastTickAt = now
        lastFailureReportedAt = nil
        stallReported = false
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            let timer = Timer(timeInterval: self.interval, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.lastHeartbeat = Date()
                self.lock.unlock()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.mainTimer = timer
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in self?.tick() }
        source = timer
        timer.resume()
    }

    public func stop() {
        lock.lock()
        running = false
        lock.unlock()

        source?.setEventHandler {}
        source?.cancel()
        source = nil

        if Thread.isMainThread {
            mainTimer?.invalidate()
            mainTimer = nil
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.mainTimer?.invalidate()
                self?.mainTimer = nil
            }
        }
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    private func tick() {
        let now = Date()
        lock.lock()
        guard running else {
            lock.unlock()
            return
        }
        // 后台队列自己都停摆超过主线程阈值，说明整机睡过一觉；
        // 重置心跳，不要把睡眠误判成主线程卡死。主线程卡死时后台队列仍会按时 tick。
        let suspended = now.timeIntervalSince(lastTickAt) > mainThreadTimeout
        lastTickAt = now
        if suspended {
            lastHeartbeat = now
            stallReported = false
            lock.unlock()
            return
        }
        let heartbeat = lastHeartbeat
        lock.unlock()

        if now.timeIntervalSince(heartbeat) > mainThreadTimeout {
            lock.lock()
            let shouldReport = !stallReported
            stallReported = true
            lock.unlock()
            if shouldReport {
                onMainThreadStalled?()
            }
            return
        }

        guard let failure = check?() else {
            lock.lock()
            let wasFailing = lastFailureReportedAt != nil
            lastFailureReportedAt = nil
            stallReported = false
            lock.unlock()
            if wasFailing {
                DispatchQueue.main.async { [weak self] in
                    self?.onHealthy?()
                }
            }
            return
        }

        lock.lock()
        let shouldReport = lastFailureReportedAt.map {
            now.timeIntervalSince($0) >= repeatInterval
        } ?? true
        if shouldReport {
            lastFailureReportedAt = now
        }
        lock.unlock()
        if shouldReport {
            DispatchQueue.main.async { [weak self] in
                self?.onFailure?(failure)
            }
        }
    }
}
