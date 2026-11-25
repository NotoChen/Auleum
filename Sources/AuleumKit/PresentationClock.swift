import AppKit
import Foundation

public enum PresentationClockStyle: String, CaseIterable, Codable {
    case digital
    case analog
    case editorial

    public var displayName: String {
        switch self {
        case .digital: return "数字"
        case .analog: return "表盘"
        case .editorial: return "日历"
        }
    }

    public static func storedValue(_ raw: String) -> PresentationClockStyle {
        PresentationClockStyle(rawValue: raw) ?? .digital
    }
}

public struct PresentationStatus: Equatable {
    /// 用于表盘指针和后续动画，不直接展示。
    public var now: Date
    public var timeText: String
    /// 带前导冒号，便于把秒数排成更小的字号。
    public var secondsText: String
    public var dateText: String
    public var weekdayText: String
    public var lunarText: String
    public var elapsedText: String
    public var messageText: String
    public var returnText: String

    public init(now: Date,
                timeText: String,
                secondsText: String,
                dateText: String,
                weekdayText: String,
                lunarText: String,
                elapsedText: String,
                messageText: String = "",
                returnText: String = "") {
        self.now = now
        self.timeText = timeText
        self.secondsText = secondsText
        self.dateText = dateText
        self.weekdayText = weekdayText
        self.lunarText = lunarText
        self.elapsedText = elapsedText
        self.messageText = messageText
        self.returnText = returnText
    }
}

public enum PresentationClockFormatter {
    private static let weekdayNames = [
        "星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六",
    ]

    public static func status(at date: Date = Date(),
                              startedAt: Date?,
                              messageText: String = "",
                              returnText: String = "",
                              timeZone: TimeZone = .current) -> PresentationStatus {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .weekday],
            from: date
        )
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0
        let weekdayIndex = max(1, min(7, components.weekday ?? 1)) - 1
        let elapsed = startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return PresentationStatus(
            now: date,
            timeText: String(format: "%02d:%02d", hour, minute),
            secondsText: String(format: ":%02d", second),
            dateText: String(format: "%04d年%02d月%02d日", year, month, day),
            weekdayText: weekdayNames[weekdayIndex],
            lunarText: lunarText(for: date, timeZone: timeZone),
            elapsedText: "已保护 \(elapsedText(elapsed))",
            messageText: messageText,
            returnText: returnText
        )
    }

    public static func elapsedText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// 用中文农历月份和日名，避免 `DateFormatter` 在不同系统语言下
    /// 返回不同的日期格式。
    public static func lunarText(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.month, .day, .isLeapMonth],
            from: date
        )
        guard let month = components.month,
              let day = components.day,
              (1...12).contains(month),
              (1...30).contains(day) else {
            return "农历"
        }
        let monthNames = [
            "正月", "二月", "三月", "四月", "五月", "六月",
            "七月", "八月", "九月", "十月", "冬月", "腊月",
        ]
        let dayNames = [
            "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
            "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
            "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
        ]
        let leap = components.isLeapMonth == true ? "闰" : ""
        return "农历\(leap)\(monthNames[month - 1])\(dayNames[day - 1])"
    }
}

/// 三种展示样式共用同一份时间状态，切换样式不会丢字段。
/// 时钟里可以单独取舍的组件。版式决定放在哪，组件决定显示什么。
public struct PresentationClockWidgets: Equatable {
    public var showsSeconds: Bool
    public var showsLunar: Bool
    public var showsElapsed: Bool

    public init(showsSeconds: Bool = true,
                showsLunar: Bool = true,
                showsElapsed: Bool = true) {
        self.showsSeconds = showsSeconds
        self.showsLunar = showsLunar
        self.showsElapsed = showsElapsed
    }
}

public final class PresentationClockView: NSView {
    public private(set) var style: PresentationClockStyle
    private var compact: Bool
    private var widgets: PresentationClockWidgets
    private var ink: PresentationInk
    private var status: PresentationStatus?
    private var analogFace: AnalogClockFace?
    private var timeLabel: NSTextField?
    private var secondsLabel: NSTextField?
    private var dateLabel: NSTextField?
    private var weekdayLabel: NSTextField?
    private var lunarLabel: NSTextField?
    private var elapsedBadge: ElapsedBadgeView?

    public init(style: PresentationClockStyle,
                compact: Bool = false,
                widgets: PresentationClockWidgets = PresentationClockWidgets(),
                ink: PresentationInk = .light) {
        self.style = style
        self.compact = compact
        self.widgets = widgets
        self.ink = ink
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override var intrinsicContentSize: NSSize {
        switch style {
        case .digital:
            return NSSize(width: compact ? 320 : 520, height: compact ? 122 : 214)
        case .analog:
            return NSSize(width: compact ? 340 : 520, height: compact ? 126 : 210)
        case .editorial:
            return NSSize(width: compact ? 330 : 520, height: compact ? 118 : 208)
        }
    }

    public func setStyle(_ style: PresentationClockStyle) {
        guard self.style != style else { return }
        self.style = style
        rebuild()
        applyStatus()
    }

    public func setCompact(_ compact: Bool) {
        guard self.compact != compact else { return }
        self.compact = compact
        rebuild()
        applyStatus()
    }

    public func setWidgets(_ widgets: PresentationClockWidgets) {
        guard self.widgets != widgets else { return }
        self.widgets = widgets
        rebuild()
        applyStatus()
    }

    /// 换幕布颜色后整体换文字与表盘配色，不需要重建画布。
    public func setInk(_ ink: PresentationInk) {
        guard self.ink != ink else { return }
        self.ink = ink
        rebuild()
        applyStatus()
    }

    public func update(status: PresentationStatus) {
        self.status = status
        applyStatus()
    }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        analogFace = nil
        timeLabel = nil
        secondsLabel = nil
        dateLabel = nil
        weekdayLabel = nil
        lunarLabel = nil
        elapsedBadge = nil

        let content: NSView
        switch style {
        case .digital:
            content = buildDigital()
        case .analog:
            content = buildAnalog()
        case .editorial:
            content = buildEditorial()
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            content.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
        invalidateIntrinsicContentSize()
    }

    private func buildDigital() -> NSView {
        let eyebrow = makeLabel(
            "当前时间",
            font: .systemFont(ofSize: compact ? 7 : 10, weight: .semibold),
            color: accent
        )
        let time = makeLabel(
            font: .monospacedDigitSystemFont(
                ofSize: compact ? 32 : 72,
                weight: .ultraLight
            ),
            color: ink.primary
        )
        let seconds = makeLabel(
            font: .monospacedDigitSystemFont(
                ofSize: compact ? 13 : 26,
                weight: .light
            ),
            color: ink.tertiary
        )
        let timeRow = makeStack(
            widgets.showsSeconds ? [time, seconds] : [time],
            orientation: .horizontal,
            spacing: compact ? 3 : 7,
            alignment: .lastBaseline
        )
        let date = makeLabel(
            font: .systemFont(ofSize: compact ? 9 : 18, weight: .medium),
            color: ink.secondary
        )
        let weekday = makeLabel(
            font: .systemFont(ofSize: compact ? 8 : 16, weight: .semibold),
            color: accent
        )
        let dateRow = makeStack(
            [date, makeDot(size: compact ? 3 : 4), weekday],
            orientation: .horizontal,
            spacing: compact ? 5 : 9,
            alignment: .centerY
        )
        let lunar = makeLabel(
            font: .systemFont(ofSize: compact ? 7 : 12, weight: .regular),
            color: ink.faint
        )
        let badge = ElapsedBadgeView(compact: compact, ink: ink)
        timeLabel = time
        secondsLabel = seconds
        dateLabel = date
        weekdayLabel = weekday
        lunarLabel = lunar
        elapsedBadge = badge
        var views: [NSView] = [eyebrow, timeRow, dateRow]
        if widgets.showsLunar {
            views.append(lunar)
        }
        if widgets.showsElapsed {
            views.append(badge)
        }
        return makeStack(
            views,
            spacing: compact ? 4 : 7,
            alignment: .centerX
        )
    }

    private func buildEditorial() -> NSView {
        let dateTitle = makeLabel(
            "日期",
            font: .systemFont(ofSize: compact ? 7 : 10, weight: .semibold),
            color: ink.faint
        )
        let date = makeLabel(
            font: .systemFont(ofSize: compact ? 19 : 38, weight: .semibold),
            color: ink.primary
        )
        let weekday = makeLabel(
            font: .systemFont(ofSize: compact ? 8 : 15, weight: .semibold),
            color: accent
        )
        let lunar = makeLabel(
            font: .systemFont(ofSize: compact ? 7 : 12, weight: .regular),
            color: ink.faint
        )
        var dateViews: [NSView] = [dateTitle, date, weekday]
        if widgets.showsLunar {
            dateViews.append(lunar)
        }
        let dateBlock = makeStack(
            dateViews,
            spacing: compact ? 3 : 7,
            alignment: .leading
        )

        let timeTitle = makeLabel(
            "现在",
            font: .systemFont(ofSize: compact ? 7 : 10, weight: .semibold),
            color: ink.faint
        )
        let time = makeLabel(
            font: .monospacedDigitSystemFont(
                ofSize: compact ? 26 : 54,
                weight: .light
            ),
            color: ink.primary
        )
        let seconds = makeLabel(
            font: .monospacedDigitSystemFont(
                ofSize: compact ? 10 : 20,
                weight: .regular
            ),
            color: ink.tertiary
        )
        let timeRow = makeStack(
            widgets.showsSeconds ? [time, seconds] : [time],
            orientation: .horizontal,
            spacing: compact ? 2 : 5,
            alignment: .lastBaseline
        )
        let badge = ElapsedBadgeView(compact: compact, ink: ink)
        var timeViews: [NSView] = [timeTitle, timeRow]
        if widgets.showsElapsed {
            timeViews.append(badge)
        }
        let timeBlock = makeStack(
            timeViews,
            spacing: compact ? 4 : 8,
            alignment: .leading
        )

        let divider = AuleumRuleView(ink: ink)
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: compact ? 286 : 468),
            divider.heightAnchor.constraint(equalToConstant: 1),
        ])

        timeLabel = time
        secondsLabel = seconds
        dateLabel = date
        weekdayLabel = weekday
        lunarLabel = lunar
        elapsedBadge = badge
        return makeStack(
            [dateBlock, divider, timeBlock],
            spacing: compact ? 7 : 10,
            alignment: .leading
        )
    }

    private func buildAnalog() -> NSView {
        let face = AnalogClockFace(compact: compact, ink: ink)
        let faceSize = compact ? 96.0 : 184.0
        face.widthAnchor.constraint(equalToConstant: faceSize).isActive = true
        face.heightAnchor.constraint(equalToConstant: faceSize).isActive = true
        analogFace = face

        let eyebrow = makeLabel(
            "当前时间",
            font: .systemFont(ofSize: compact ? 7 : 10, weight: .semibold),
            color: accent
        )
        let time = makeLabel(
            font: .monospacedDigitSystemFont(
                ofSize: compact ? 18 : 34,
                weight: .light
            ),
            color: ink.primary
        )
        let seconds = makeLabel(
            font: .monospacedDigitSystemFont(
                ofSize: compact ? 9 : 16,
                weight: .regular
            ),
            color: ink.tertiary
        )
        let timeRow = makeStack(
            widgets.showsSeconds ? [time, seconds] : [time],
            orientation: .horizontal,
            spacing: compact ? 2 : 4,
            alignment: .lastBaseline
        )
        let date = makeLabel(
            font: .systemFont(ofSize: compact ? 10 : 20, weight: .medium),
            color: ink.secondary
        )
        let weekday = makeLabel(
            font: .systemFont(ofSize: compact ? 8 : 15, weight: .semibold),
            color: accent
        )
        let lunar = makeLabel(
            font: .systemFont(ofSize: compact ? 7 : 12, weight: .regular),
            color: ink.faint
        )
        let badge = ElapsedBadgeView(compact: compact, ink: ink)
        timeLabel = time
        secondsLabel = seconds
        dateLabel = date
        weekdayLabel = weekday
        lunarLabel = lunar
        elapsedBadge = badge
        var infoViews: [NSView] = [eyebrow, timeRow, date, weekday]
        if widgets.showsLunar {
            infoViews.append(lunar)
        }
        if widgets.showsElapsed {
            infoViews.append(badge)
        }
        let info = makeStack(
            infoViews,
            spacing: compact ? 3 : 6,
            alignment: .leading
        )
        return makeStack(
            [face, info],
            orientation: .horizontal,
            spacing: compact ? 14 : 30,
            alignment: .centerY
        )
    }

    private func applyStatus() {
        guard let status else { return }
        analogFace?.update(date: status.now)
        timeLabel?.stringValue = status.timeText
        secondsLabel?.stringValue = status.secondsText
        dateLabel?.stringValue = status.dateText
        weekdayLabel?.stringValue = status.weekdayText
        lunarLabel?.stringValue = status.lunarText
        elapsedBadge?.update(status.elapsedText)
    }

    private var accent: NSColor {
        ink.accent
    }

    private func makeDot(size: CGFloat) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = accent.withAlphaComponent(0.8).cgColor
        dot.layer?.cornerRadius = size / 2
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: size),
            dot.heightAnchor.constraint(equalToConstant: size),
        ])
        return dot
    }

    private func makeLabel(_ text: String = "",
                           font: NSFont,
                           color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = .center
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func makeStack(
        _ views: [NSView],
        orientation: NSUserInterfaceLayoutOrientation = .vertical,
        spacing: CGFloat,
        alignment: NSLayoutConstraint.Attribute
    ) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = orientation
        stack.spacing = spacing
        stack.alignment = alignment
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
}

private final class ElapsedBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()

    init(compact: Bool, ink: PresentationInk) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = compact ? 9 : 11
        layer?.backgroundColor = ink.badgeFill.cgColor
        layer?.borderWidth = 0.6
        layer?.borderColor = ink.badgeBorder.cgColor

        dot.wantsLayer = true
        dot.layer?.cornerRadius = compact ? 2 : 2.5
        dot.layer?.backgroundColor = ink.accent.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        label.font = .monospacedSystemFont(
            ofSize: compact ? 8 : 11,
            weight: .medium
        )
        label.textColor = ink.badgeText
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dot)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: compact ? 18 : 24),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: compact ? 8 : 10),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: compact ? 4 : 5),
            dot.heightAnchor.constraint(equalToConstant: compact ? 4 : 5),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: compact ? 5 : 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: compact ? -8 : -11),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(_ text: String) {
        label.stringValue = text
    }
}

private final class AuleumRuleView: NSView {
    init(ink: PresentationInk) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = ink.rule.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

private final class AnalogClockFace: NSView {
    private let compact: Bool
    private let ink: PresentationInk
    private var date = Date()

    init(compact: Bool, ink: PresentationInk) {
        self.compact = compact
        self.ink = ink
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }

    func update(date: Date) {
        self.date = date
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.5 - (compact ? 4 : 8)
        guard radius > 10 else { return }

        ink.ring.setStroke()
        let ring = NSBezierPath(
            ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        ring.lineWidth = compact ? 1 : 1.5
        ring.stroke()

        let tickColor = ink.tick
        tickColor.setStroke()
        for index in 0..<60 {
            let major = index % 5 == 0
            let outer = radius - (compact ? 2 : 4)
            let inner = outer - (major ? (compact ? 5 : 9) : (compact ? 2 : 4))
            let angle = CGFloat(index) / 60 * .pi * 2 - .pi / 2
            let path = NSBezierPath()
            path.move(to: point(center: center, angle: angle, radius: inner))
            path.line(to: point(center: center, angle: angle, radius: outer))
            path.lineWidth = major ? (compact ? 1.2 : 1.8) : (compact ? 0.6 : 0.8)
            path.stroke()
        }

        let components = Calendar.current.dateComponents(
            [.hour, .minute, .second],
            from: date
        )
        let hour = Double(components.hour ?? 0)
        let minute = Double(components.minute ?? 0)
        let second = Double(components.second ?? 0)
        let hourAngle = ((hour.truncatingRemainder(dividingBy: 12) + minute / 60 + second / 3600) / 12) * .pi * 2 - .pi / 2
        let minuteAngle = ((minute + second / 60) / 60) * .pi * 2 - .pi / 2
        let secondAngle = (second / 60) * .pi * 2 - .pi / 2

        drawHand(
            from: center,
            angle: hourAngle,
            length: radius * 0.46,
            width: compact ? 2.4 : 4,
            color: ink.hand
        )
        drawHand(
            from: center,
            angle: minuteAngle,
            length: radius * 0.69,
            width: compact ? 1.4 : 2.4,
            color: ink.hand
        )
        drawHand(
            from: center,
            angle: secondAngle,
            length: radius * 0.8,
            width: compact ? 0.8 : 1.2,
            color: ink.accent
        )

        ink.accent.setFill()
        let dotSize = compact ? 4.0 : 7.0
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - dotSize / 2,
                y: center.y - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
        ).fill()
    }

    private func drawHand(from center: CGPoint,
                          angle: CGFloat,
                          length: CGFloat,
                          width: CGFloat,
                          color: NSColor) {
        let end = point(center: center, angle: angle, radius: length)
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: center)
        path.line(to: end)
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
    }

    private func point(center: CGPoint, angle: CGFloat, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}
