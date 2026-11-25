import AppKit
import AuleumKit

enum SettingsPage: CaseIterable {
    case general
    case automation
    case scenes
    case presentation
    case updates
    case permissions
    case diagnostics

    var title: String {
        switch self {
        case .general: return "幕帘"
        case .automation: return "自动化"
        case .scenes: return "场景"
        case .presentation: return "展示模式"
        case .updates: return "更新"
        case .permissions: return "权限"
        case .diagnostics: return "诊断"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "rectangle.inset.filled"
        case .automation: return "clock.badge.checkmark"
        case .scenes: return "rectangle.3.group"
        case .presentation: return "photo.on.rectangle.angled"
        case .updates: return "arrow.triangle.2.circlepath"
        case .permissions: return "checkmark.shield"
        case .diagnostics: return "stethoscope"
        }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class PermissionStateRowView: NSView {
    private let tile: AuleumIconTile
    private let pill: AuleumStatusPillView
    private let detail: NSTextField

    init(symbol: String, title: String, detail: String, granted: Bool) {
        tile = AuleumIconTile(
            symbol: symbol,
            color: granted ? AuleumTheme.success : AuleumTheme.warning,
            size: 38
        )
        pill = AuleumStatusPillView(
            text: granted ? "已授权" : "未授权",
            color: granted ? AuleumTheme.success : AuleumTheme.warning
        )
        self.detail = AuleumTheme.label(
            detail,
            size: 10.5,
            color: AuleumTheme.secondaryInk
        )
        super.init(frame: .zero)
        let titleLabel = AuleumTheme.label(title, size: 12.5, weight: .semibold)
        let textStack = AuleumTheme.stack([titleLabel, self.detail], spacing: 3)
        let row = AuleumTheme.stack(
            [tile, textStack, pill],
            orientation: .horizontal,
            spacing: 14,
            alignment: .centerY
        )
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pill.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 58),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setGranted(_ granted: Bool) {
        tile.setColor(granted ? AuleumTheme.success : AuleumTheme.warning)
        pill.update(
            text: granted ? "已授权" : "未授权",
            color: granted ? AuleumTheme.success : AuleumTheme.warning
        )
    }
}

/// 只作视觉提示，不拦截下面画布的拖拽。
private final class AuleumPassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class AuleumPresentationPreviewView: NSView {
    var onCustomLayoutChange: ((PresentationCustomLayout) -> Void)?
    private let canvas: PresentationCanvasView
    private let blackoutLabel = NSTextField(labelWithString: "纯黑幕帘")
    private let editHintContainer = AuleumPassthroughView()
    private var loadedImagePath: String?
    private var loadedImage: CGImage?

    override init(frame frameRect: NSRect) {
        canvas = PresentationCanvasView(
            color: .black,
            image: nil,
            clockStyle: .digital,
            status: nil,
            compact: true
        )
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        canvas.translatesAutoresizingMaskIntoConstraints = false
        addSubview(canvas)
        canvas.onCustomLayoutChange = { [weak self] layout in
            self?.onCustomLayoutChange?(layout)
        }
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            canvas.topAnchor.constraint(equalTo: topAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        blackoutLabel.font = .systemFont(ofSize: 13, weight: .medium)
        blackoutLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        blackoutLabel.alignment = .center
        blackoutLabel.isHidden = true
        addSubview(blackoutLabel)
        blackoutLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blackoutLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            blackoutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        editHintContainer.wantsLayer = true
        editHintContainer.layer?.cornerRadius = 9
        editHintContainer.layer?.backgroundColor = NSColor.black
            .withAlphaComponent(0.56).cgColor
        editHintContainer.layer?.borderWidth = 0.6
        editHintContainer.layer?.borderColor = NSColor.white
            .withAlphaComponent(0.14).cgColor
        editHintContainer.isHidden = true
        let hintLabel = NSTextField(labelWithString: "拖动调整位置")
        hintLabel.font = .systemFont(ofSize: 9.5, weight: .medium)
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        editHintContainer.addSubview(hintLabel)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hintLabel.leadingAnchor.constraint(
                equalTo: editHintContainer.leadingAnchor,
                constant: 8
            ),
            hintLabel.trailingAnchor.constraint(
                equalTo: editHintContainer.trailingAnchor,
                constant: -8
            ),
            hintLabel.topAnchor.constraint(
                equalTo: editHintContainer.topAnchor,
                constant: 3
            ),
            hintLabel.bottomAnchor.constraint(
                equalTo: editHintContainer.bottomAnchor,
                constant: -3
            ),
        ])
        addSubview(editHintContainer)
        editHintContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            editHintContainer.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 10
            ),
            editHintContainer.topAnchor.constraint(
                equalTo: topAnchor,
                constant: 10
            ),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(color: NSColor,
                imagePath: String?,
                clockStyle: PresentationClockStyle,
                imageFocus: CGPoint = CGPoint(x: 0.5, y: 0.5),
                imageZoom: CGFloat = 1,
                imageDim: CGFloat = 0,
                layout: PresentationLayout = .centered,
                customLayout: PresentationCustomLayout = .default,
                componentBackground: PresentationComponentBackground = .auto,
                isCustomLayoutEditing: Bool = false,
                usesDefaultBackdrop: Bool = true,
                widgets: PresentationClockWidgets = PresentationClockWidgets(),
                startedAt: Date?,
                messageText: String = "",
                returnText: String = "",
                displayEnabled: Bool = true) {
        let srgb = color.usingColorSpace(.sRGB) ?? .black
        let veilColor = AuleumColor(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent)
        )
        canvas.setColor(veilColor)
        if loadedImagePath != imagePath {
            loadedImagePath = imagePath
            loadedImage = imagePath.flatMap {
                PresentationBackgroundLoader.load(path: $0, maxPixelSize: 1024)
            }
        }
        canvas.setBackgroundImage(
            loadedImage,
            focus: imageFocus,
            zoom: imageZoom,
            dim: imageDim
        )
        canvas.setClockStyle(clockStyle)
        canvas.setCustomLayout(customLayout)
        canvas.setLayout(layout)
        canvas.setComponentBackground(componentBackground)
        canvas.isCustomLayoutEditingEnabled = isCustomLayoutEditing
        canvas.setDefaultBackdropEnabled(usesDefaultBackdrop)
        canvas.setWidgets(widgets)
        canvas.isHidden = !displayEnabled
        blackoutLabel.isHidden = displayEnabled
        editHintContainer.isHidden = !displayEnabled
            || !isCustomLayoutEditing
            || layout != .custom
        canvas.update(
            status: PresentationClockFormatter.status(
                at: Date(),
                startedAt: startedAt,
                messageText: messageText,
                returnText: returnText
            )
        )
    }
}

final class AuleumSliderField: NSView {
    var onChange: (() -> Void)?
    var isEnabled = true {
        didSet {
            slider.isEnabled = isEnabled
            alphaValue = isEnabled ? 1 : 0.45
        }
    }

    private let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "")
    private let formatter: (Double) -> String

    var value: Double {
        get { slider.doubleValue }
        set {
            slider.doubleValue = min(slider.maxValue, max(slider.minValue, newValue))
            updateLabel()
        }
    }

    init(minimum: Double,
         maximum: Double,
         value: Double,
         width: CGFloat = 230,
         sliderWidth: CGFloat = 168,
         formatter: @escaping (Double) -> String) {
        slider = NSSlider(
            value: min(maximum, max(minimum, value)),
            minValue: minimum,
            maxValue: maximum,
            target: nil,
            action: nil
        )
        self.formatter = formatter
        super.init(frame: .zero)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(changed)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        valueLabel.textColor = AuleumTheme.secondaryInk
        valueLabel.alignment = .right
        addSubview(slider)
        addSubview(valueLabel)
        slider.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 30),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            slider.widthAnchor.constraint(equalToConstant: sliderWidth),
            valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 10),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func changed() {
        updateLabel()
        onChange?()
    }

    private func updateLabel() {
        valueLabel.stringValue = formatter(slider.doubleValue)
    }
}
