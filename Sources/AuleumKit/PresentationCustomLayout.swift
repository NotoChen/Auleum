import Foundation

/// 自由排版里单个组件的中心位置，按画布宽高归一化。
/// x 0 是贴左、1 是贴右；y 0 是贴顶、1 是贴底。实际绘制时画布还会
/// 按组件尺寸再做一次内缩，避免把内容拖出屏幕。
public struct PresentationWidgetPlacement: Codable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = Self.sanitize(x)
        self.y = Self.sanitize(y)
    }

    private enum CodingKeys: String, CodingKey {
        case x, y
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = Self.sanitize(
            try container.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
        )
        y = Self.sanitize(
            try container.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
        )
    }

    public func sanitized() -> PresentationWidgetPlacement {
        PresentationWidgetPlacement(x: x, y: y)
    }

    private static func sanitize(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        let clamped = min(1, max(0, value))
        // 四位小数约等于千分之一像素，足够定位，也能让配置文件保持可读。
        return (clamped * 10_000).rounded() / 10_000
    }
}

/// 自由排版：时钟卡片、场景提示和预计返回时间各自独立摆放。
/// 默认位置在屏幕中轴线上，提示在上、返回时间在下。
public struct PresentationCustomLayout: Codable, Equatable {
    public var clock: PresentationWidgetPlacement
    public var message: PresentationWidgetPlacement
    public var returnTime: PresentationWidgetPlacement

    public static let `default` = PresentationCustomLayout(
        clock: PresentationWidgetPlacement(x: 0.5, y: 0.5),
        message: PresentationWidgetPlacement(x: 0.5, y: 0.18),
        returnTime: PresentationWidgetPlacement(x: 0.5, y: 0.82)
    )

    public init(clock: PresentationWidgetPlacement,
                message: PresentationWidgetPlacement,
                returnTime: PresentationWidgetPlacement) {
        self.clock = clock.sanitized()
        self.message = message.sanitized()
        self.returnTime = returnTime.sanitized()
    }

    private enum CodingKeys: String, CodingKey {
        case clock, message, returnTime
    }

    private struct PartialPlacement: Decodable {
        var x: Double?
        var y: Double?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = PresentationCustomLayout.default
        clock = Self.placement(
            in: container,
            forKey: .clock,
            fallback: fallback.clock
        )
        message = Self.placement(
            in: container,
            forKey: .message,
            fallback: fallback.message
        )
        returnTime = Self.placement(
            in: container,
            forKey: .returnTime,
            fallback: fallback.returnTime
        )
    }

    private static func placement(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys,
        fallback: PresentationWidgetPlacement
    ) -> PresentationWidgetPlacement {
        guard let partial = try? container.decodeIfPresent(
            PartialPlacement.self,
            forKey: key
        ) else {
            return fallback
        }
        return PresentationWidgetPlacement(
            x: partial.x ?? fallback.x,
            y: partial.y ?? fallback.y
        )
    }

    public func sanitized() -> PresentationCustomLayout {
        PresentationCustomLayout(
            clock: clock,
            message: message,
            returnTime: returnTime
        )
    }
}

/// 把画布坐标里的组件中心换算成保存用的归一化位置。
/// `center` 使用顶部原点；组件尺寸和画布尺寸都按点计算。
public enum PresentationPlacementResolver {
    public static func normalizedCenter(
        _ center: CGPoint,
        itemSize: CGSize,
        canvasSize: CGSize,
        margin: CGFloat
    ) -> PresentationWidgetPlacement {
        guard canvasSize.width > 1, canvasSize.height > 1 else {
            return PresentationWidgetPlacement(x: 0.5, y: 0.5)
        }
        let x = clamp(
            center.x,
            itemSize: itemSize.width,
            extent: canvasSize.width,
            margin: margin
        )
        let y = clamp(
            center.y,
            itemSize: itemSize.height,
            extent: canvasSize.height,
            margin: margin
        )
        return PresentationWidgetPlacement(
            x: Double(x / canvasSize.width),
            y: Double(y / canvasSize.height)
        )
    }

    private static func clamp(_ proposed: CGFloat,
                              itemSize: CGFloat,
                              extent: CGFloat,
                              margin: CGFloat) -> CGFloat {
        guard proposed.isFinite else { return extent / 2 }
        let lower = margin + itemSize / 2
        let upper = extent - margin - itemSize / 2
        guard lower <= upper else { return extent / 2 }
        return min(upper, max(lower, proposed))
    }
}
