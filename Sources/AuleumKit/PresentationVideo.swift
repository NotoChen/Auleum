import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// 展示模式视频背景的可用性检查。展示窗口负责渲染，这里只做轻量的
/// 文件/类型判断；真正的播放失败由 `PresentationVideoBackgroundView` 兜底。
public enum PresentationVideoLoader {
    public static let allowedContentTypes: [UTType] = [
        .movie, .mpeg4Movie, .quickTimeMovie, .video,
    ]

    public static func isLoadable(path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.isReadableFile(atPath: path) else {
            return false
        }
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }

    /// 选择文件后异步确认容器可播放且至少有一条视频轨。
    /// 只用于设置页提示，不在事件 tap 或起幕路径上阻塞。
    public static func isPlayable(path: String) async -> Bool {
        guard isLoadable(path: path) else { return false }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard (try? await asset.load(.isPlayable)) == true else {
            return false
        }
        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        return !tracks.isEmpty
    }
}

/// 循环、静音的视频背景。每个展示窗口一份播放器，避免依赖
/// 单个 AVPlayer 同时驱动多个 AVPlayerLayer 的未保证行为。
final class PresentationVideoBackgroundView: NSView {
    var onUnavailable: (() -> Void)?

    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var statusObservation: NSKeyValueObservation?
    private(set) var videoPath: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        playerLayer.contentsScale = window?.backingScaleFactor ?? 1
    }

    /// 返回 false 表示没有可播放路径。播放失败会异步回调 `onUnavailable`，
    /// 让画布回落到图片或默认背景，而不是留下一块黑屏。
    @discardableResult
    func setVideo(path: String?) -> Bool {
        clear()
        guard let path, !path.isEmpty else { return false }
        let item = AVPlayerItem(url: URL(fileURLWithPath: path))
        let player = AVQueuePlayer()
        // 幕帘视频只做视觉背景，任何音轨都静音，避免突然出声。
        player.isMuted = true
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = false
        let looper = AVPlayerLooper(player: player, templateItem: item)
        playerLayer.player = player
        self.player = player
        self.looper = looper
        videoPath = path
        statusObservation = item.observe(\.status, options: [.new]) {
            [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async {
                guard let self, self.videoPath == path else { return }
                self.onUnavailable?()
            }
        }
        player.play()
        return true
    }

    func setPlayback(active: Bool) {
        guard let player else { return }
        if active {
            player.play()
        } else {
            player.pause()
        }
    }

    func clear() {
        statusObservation = nil
        playerLayer.player = nil
        player?.pause()
        player = nil
        looper = nil
        videoPath = nil
    }

    deinit {
        clear()
    }
}
