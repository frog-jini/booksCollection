/// 시선 특징 → 화면 좌표 보정(2차 다항 회귀).
///
/// 특징 = (눈 방향이 화면 평면에 닿는 가로·세로 위치, 머리 가로·세로 위치).
/// 머리 위치를 함께 넣어 머리가 조금 움직여도 보정이 따라가게 한다.
public struct GazeFeature: Codable, Equatable, Sendable {
    public var h: Double
    public var v: Double
    public var headX: Double
    public var headY: Double
    public init(h: Double, v: Double, headX: Double, headY: Double) {
        self.h = h; self.v = v; self.headX = headX; self.headY = headY
    }

    /// 회귀에 쓰는 항(상수항 제외)
    var terms: [Double] { [h, v, headX, headY, h * v, h * h, v * v] }
}

public enum CalibrationError: Error, Equatable {
    case notEnoughSamples(have: Int, need: Int)
}

public func calibrationPoints(width: Double, height: Double, margin: Double = 40) -> [Point] {
    let xs = [margin, width / 2, width - margin]
    let ys = [margin, height / 2, height - margin]
    return ys.flatMap { y in xs.map { Point(x: $0, y: y) } }
}

public struct Calibrator: Codable, Sendable {
    public static let minSamples = 8
    private var features: [GazeFeature] = []
    private var targets: [Point] = []
    // 학습 결과: 항을 표준화(평균 0, 표준편차 1)한 뒤의 선형 계수
    private var mean: [Double] = []
    private var scale: [Double] = []
    private var weights: [[Double]] = []  // [항][x, y]
    private var bias: [Double] = []

    enum CodingKeys: String, CodingKey { case mean, scale, weights, bias }

    public init() {}

    public var isFitted: Bool { !weights.isEmpty }

    public mutating func add(_ feature: GazeFeature, screen: Point) {
        features.append(feature)
        targets.append(screen)
    }

    public mutating func fit() throws {
        let n = features.count
        guard n >= Self.minSamples else { throw CalibrationError.notEnoughSamples(have: n, need: Self.minSamples) }
        let rows = features.map(\.terms)
        let k = rows[0].count
        mean = (0..<k).map { j in rows.reduce(0) { $0 + $1[j] } / Double(n) }
        scale = (0..<k).map { j in
            let sd = (rows.reduce(0) { $0 + ($1[j] - mean[j]) * ($1[j] - mean[j]) } / Double(n)).squareRoot()
            return sd > 1e-9 ? sd : 1  // 거의 변하지 않는 항(머리를 고정함)도 풀리게
        }
        let z = rows.map { r in (0..<k).map { (r[$0] - mean[$0]) / scale[$0] } }
        let ys = [targets.map(\.x), targets.map(\.y)]
        bias = ys.map { $0.reduce(0, +) / Double(n) }

        // 정규방정식 (ZᵀZ + λI) w = Zᵀ(y − ȳ). λ 는 아주 작게(수치 안정용).
        var a = [[Double]](repeating: [Double](repeating: 0, count: k), count: k)
        var b = [[Double]](repeating: [0, 0], count: k)
        for (i, row) in z.enumerated() {
            for p in 0..<k {
                for q in 0..<k { a[p][q] += row[p] * row[q] }
                for o in 0..<2 { b[p][o] += row[p] * (ys[o][i] - bias[o]) }
            }
        }
        for p in 0..<k { a[p][p] += 1e-8 * Double(n) }
        weights = solve(a, b)
    }

    public func predict(_ feature: GazeFeature) -> Point? {
        guard isFitted else { return nil }
        let t = feature.terms
        var out = bias
        for j in t.indices {
            let zj = (t[j] - mean[j]) / scale[j]
            out[0] += zj * weights[j][0]
            out[1] += zj * weights[j][1]
        }
        return Point(x: out[0], y: out[1])
    }
}

/// 가우스 소거법(부분 피벗)으로 A X = B 를 푼다. A 는 k×k, B 는 k×m.
func solve(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
    var a = a, b = b
    let k = a.count
    for col in 0..<k {
        let pivot = (col..<k).max { abs(a[$0][col]) < abs(a[$1][col]) }!
        a.swapAt(col, pivot)
        b.swapAt(col, pivot)
        for r in (col + 1)..<k where a[col][col] != 0 {
            let f = a[r][col] / a[col][col]
            for c in col..<k { a[r][c] -= f * a[col][c] }
            for c in b[r].indices { b[r][c] -= f * b[col][c] }
        }
    }
    var x = b
    for r in stride(from: k - 1, through: 0, by: -1) {
        for c in x[r].indices {
            var s = b[r][c]
            for j in (r + 1)..<k { s -= a[r][j] * x[j][c] }
            x[r][c] = a[r][r] != 0 ? s / a[r][r] : 0
        }
    }
    return x
}
