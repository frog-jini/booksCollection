/// 시선 좌표 떨림을 줄이는 지수 이동 평균 필터. 큰 점프(다음 줄로 눈을 옮김)는 바로 따라간다.
public final class GazeSmoother {
    public var alpha: Double
    public var snapDistance: Double
    private var value: Point?

    public init(alpha: Double = 0.35, snapDistance: Double = .infinity) {
        self.alpha = alpha
        self.snapDistance = snapDistance
    }

    public func reset() { value = nil }

    @discardableResult
    public func update(_ point: Point?) -> Point? {
        guard let p = point else { return value }
        if let v = value, p.distance(to: v) <= snapDistance {
            value = Point(x: alpha * p.x + (1 - alpha) * v.x, y: alpha * p.y + (1 - alpha) * v.y)
        } else {
            value = p
        }
        return value
    }
}
