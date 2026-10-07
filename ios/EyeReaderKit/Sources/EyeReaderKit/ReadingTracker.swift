/// 시선 좌표로 지금 읽고 있는 단어를 추정하고, 페이지 넘김 시점을 판단한다.
///
/// 시선 추적은 세로 오차가 크므로:
/// - 줄 이동은 시선이 다른 줄에 lineSwitchTime 이상 머물러야 인정한다.
/// - 줄 끝까지 읽은 뒤 시선이 줄 앞쪽으로 돌아가면(return sweep) 다음 줄로 넘어간다.
/// - 마지막 줄에서 return sweep 이 일어나거나 마지막 단어에 turnDwell 이상 머물면 페이지를 넘긴다.
public final class ReadingTracker {
    static let nearEnd = 0.7  // 줄 폭의 이 비율 이후면 '줄 끝 근처'
    static let lineStart = 0.3  // 줄 폭의 이 비율 이전이면 '줄 앞쪽'

    public var lineSwitchTime: Double
    public var turnDwell: Double
    public private(set) var lines: [Line] = []
    public private(set) var lineIndex: Int?
    public private(set) var word: Word?
    public private(set) var furthest: Word?
    public private(set) var shouldTurn = false
    private var candidate: Int?
    private var candidateSince = 0.0
    private var reachedEnd = false
    private var dwellStart: Double?

    public init(page: Page, lineSwitchTime: Double = 0.35, turnDwell: Double = 1.0) {
        self.lineSwitchTime = lineSwitchTime
        self.turnDwell = turnDwell
        reset(page: page)
    }

    public func reset(page: Page) {
        lines = page.lines.filter { !$0.words.isEmpty }
        lineIndex = nil
        word = nil
        furthest = nil
        shouldTurn = lines.isEmpty
        candidate = nil
        reachedEnd = false
        dwellStart = nil
    }

    private func span(_ i: Int) -> (start: Double, end: Double) {
        (lines[i].words.first!.frame.x, lines[i].words.last!.frame.maxX)
    }

    private func nearestLine(_ y: Double) -> Int {
        lines.indices.min { abs(lines[$0].words[0].center.y - y) < abs(lines[$1].words[0].center.y - y) }!
    }

    private func goTo(_ i: Int) {
        lineIndex = i
        reachedEnd = false
        candidate = nil
    }

    private func chooseLine(_ g: Point, _ t: Double) {
        let nearest = nearestLine(g.y)
        guard let current = lineIndex else { return goTo(nearest) }
        let (start, end) = span(current)
        if reachedEnd && g.x < start + Self.lineStart * (end - start) {
            if current == lines.count - 1 {
                shouldTurn = true  // 마지막 줄을 다 읽고 다음 페이지로 가려는 눈
            } else {
                goTo(current + 1)
            }
        } else if nearest != current {
            if candidate != nearest {
                candidate = nearest
                candidateSince = t
            } else if t - candidateSince >= lineSwitchTime {
                goTo(nearest)
            }
        } else {
            candidate = nil
        }
    }

    @discardableResult
    public func update(gaze: Point?, t: Double) -> Word? {
        guard !lines.isEmpty, let g = gaze else { return word }
        chooseLine(g, t)
        if shouldTurn { return word }
        let i = lineIndex!
        let line = lines[i]
        let w = line.words.min { abs($0.center.x - g.x) < abs($1.center.x - g.x) }!
        word = w
        let (start, end) = span(i)
        if g.x >= start + Self.nearEnd * (end - start) { reachedEnd = true }
        if furthest == nil || w.index > furthest!.index { furthest = w }
        if i == lines.count - 1 && w == line.words.last! {
            if let s = dwellStart {
                if t - s >= turnDwell { shouldTurn = true }
            } else {
                dwellStart = t
            }
        } else {
            dwellStart = nil
        }
        return w
    }
}
