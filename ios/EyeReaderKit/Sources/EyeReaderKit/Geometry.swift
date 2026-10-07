/// 화면 좌표(pt). CoreGraphics 없이도 테스트할 수 있게 직접 정의한다.
public struct Point: Equatable, Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }

    public func distance(to other: Point) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

public struct Rect: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public var origin: Point { Point(x: x, y: y) }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var center: Point { Point(x: x + width / 2, y: y + height / 2) }

    public func contains(_ p: Point) -> Bool { p.x >= x && p.x < maxX && p.y >= y && p.y < maxY }
    public func insetBy(_ d: Double) -> Rect { Rect(x: x + d, y: y + d, width: width - 2 * d, height: height - 2 * d) }
}
