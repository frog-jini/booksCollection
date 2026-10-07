/// 페이지별 시선 heatmap: 화면을 cell 크기 칸으로 나눠 칸마다 바라본 시간(초)을 모은다.
public struct HotCell: Equatable, Codable, Sendable {
    public let center: Point
    public let seconds: Double
}

public struct GazeHeatmap: Sendable {
    public let width: Double, height: Double, cell: Double
    public let rows: Int, columns: Int
    private var grid: [Double]

    public init(width: Double, height: Double, cell: Double = 40) {
        self.width = width
        self.height = height
        self.cell = cell
        rows = Int((height / cell).rounded(.up))
        columns = Int((width / cell).rounded(.up))
        grid = Array(repeating: 0, count: rows * columns)
    }

    public subscript(row: Int, column: Int) -> Double { grid[row * columns + column] }

    public var totalSeconds: Double { grid.reduce(0, +) }

    public mutating func add(_ p: Point, seconds: Double) {
        guard p.x >= 0, p.x < width, p.y >= 0, p.y < height else { return }
        grid[Int(p.y / cell) * columns + Int(p.x / cell)] += seconds
    }

    /// 0…1 로 정규화한 칸 값 [줄][칸]
    public func normalized() -> [[Double]] {
        let top = grid.max() ?? 0
        return (0..<rows).map { r in (0..<columns).map { c in top > 0 ? self[r, c] / top : 0 } }
    }

    /// 가장 오래 본 칸 n 개
    public func hottest(_ n: Int = 5) -> [HotCell] {
        grid.indices.filter { grid[$0] > 0 }.sorted { grid[$0] > grid[$1] }.prefix(n).map { i in
            HotCell(center: Point(x: (Double(i % columns) + 0.5) * cell, y: (Double(i / columns) + 0.5) * cell),
                    seconds: grid[i])
        }
    }
}

public struct PageHeatmaps: Sendable {
    public let width: Double, height: Double, cell: Double
    public private(set) var pages: [Int: GazeHeatmap] = [:]

    public init(width: Double, height: Double, cell: Double = 40) {
        self.width = width
        self.height = height
        self.cell = cell
    }

    public func page(_ n: Int) -> GazeHeatmap { pages[n] ?? GazeHeatmap(width: width, height: height, cell: cell) }

    public mutating func add(page n: Int, _ p: Point, seconds: Double) {
        var map = page(n)
        map.add(p, seconds: seconds)
        pages[n] = map
    }
}
