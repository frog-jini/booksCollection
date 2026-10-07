/// 독서 시간과 휴식: 계속 읽은 시간, 화면에서 눈을 뗀 시간, 쉬어 가기 권유.
///
/// 잠깐 눈을 돌린 것(rest 초 미만)은 휴식이 아니다. rest 초 넘게 떠나 있으면 연속 독서 시간을 0으로 돌린다.
public final class ReadingTimer {
    public let breakAfter: Double
    public let repeatEvery: Double
    public let rest: Double
    public let lookAway: Double
    private let maxStep: Double
    public private(set) var continuousSeconds = 0.0
    public private(set) var readingSeconds = 0.0
    public private(set) var awaySeconds = 0.0
    public private(set) var lookAways = 0
    private var awayRun = 0.0
    private var nextReminder: Double
    private var lastT: Double?

    public init(breakAfter: Double = 30 * 60, repeatEvery: Double = 10 * 60, rest: Double = 5 * 60,
                lookAway: Double = 1, maxStep: Double = 1) {
        self.breakAfter = breakAfter
        self.repeatEvery = repeatEvery
        self.rest = rest
        self.lookAway = lookAway
        self.maxStep = maxStep
        nextReminder = breakAfter
    }

    public func update(present: Bool, t: Double) -> [Alert] {
        let dt = lastT.map { min(max(t - $0, 0), maxStep) } ?? 0
        lastT = t
        guard present else {
            if awayRun < lookAway && lookAway <= awayRun + dt { lookAways += 1 }
            awayRun += dt
            awaySeconds += dt
            if awayRun >= rest {
                continuousSeconds = 0
                nextReminder = breakAfter
            }
            return []
        }
        awayRun = 0
        continuousSeconds += dt
        readingSeconds += dt
        guard continuousSeconds >= nextReminder else { return [] }
        let minutes = Int((nextReminder / 60).rounded())
        nextReminder += repeatEvery
        return [Alert(kind: "break", title: "잠시 쉬어가는 건 어떨까요?", message: "\(minutes)분 동안 계속 독서 중입니다.")]
    }
}

/// 피로·졸음: 깜빡임 횟수, PERCLOS(최근 window 초 중 눈 감은 시간 비율, 15% 넘으면 졸림),
/// 1초 넘게 눈 감음(마이크로슬립).
public final class DrowsinessMonitor {
    static let drowsy = Alert(kind: "drowsy", title: "졸음이 감지되었습니다.", message: "눈을 감고 있는 시간이 길어요. 잠시 쉬어 가세요.")
    public let closedBelow: Double
    public let window: Double
    public let perclosLimit: Double
    public let microsleep: Double
    let maxBlink: Double
    let maxStep: Double
    public private(set) var longClosures = 0
    private var samples: [(t: Double, dt: Double, closed: Bool)] = []
    private var blinks: [Double] = []
    private var closedSince: Double?
    private var countedThisClosure = false
    private var lastT: Double?
    private var gate: Persistence

    /// openness: 1 = 활짝, 0 = 감음. ARKit 은 1 − 깜빡임 값.
    public init(closedBelow: Double = 0.4, window: Double = 60, perclosLimit: Double = 0.15, microsleep: Double = 1,
                maxBlink: Double = 0.5, cooldown: Double = 120, maxStep: Double = 0.5) {
        self.closedBelow = closedBelow
        self.window = window
        self.perclosLimit = perclosLimit
        self.microsleep = microsleep
        self.maxBlink = maxBlink
        self.maxStep = maxStep
        gate = Persistence(hold: 0, cooldown: cooldown)
    }

    private var covered: Double { samples.reduce(0) { $0 + $1.dt } }

    public var perclos: Double {
        let total = covered
        return total > 0 ? samples.filter(\.closed).reduce(0) { $0 + $1.dt } / total : 0
    }

    /// 분당 깜빡임 횟수
    public var blinkRate: Double { Double(blinks.count) * 60 / window }

    public func update(openness: Double?, t: Double) -> [Alert] {
        let dt = lastT.map { min(max(t - $0, 0), maxStep) } ?? 0
        lastT = t
        guard let o = openness else { closedSince = nil; return [] }  // 얼굴을 놓침
        let closed = o < closedBelow
        samples.append((t, dt, closed))
        samples.removeAll { $0.t < t - window }
        blinks.removeAll { $0 < t - window }

        var isDrowsy = false
        if closed {
            if let since = closedSince {
                if t - since >= microsleep && !countedThisClosure {
                    countedThisClosure = true
                    longClosures += 1
                    isDrowsy = true
                }
            } else {
                closedSince = t
                countedThisClosure = false
            }
        } else if let since = closedSince {
            if t - since <= maxBlink { blinks.append(t) }
            closedSince = nil
        }
        if covered >= window * 0.95 && perclos > perclosLimit { isDrowsy = true }
        return gate.check("drowsy", active: isDrowsy, t: t) ? [Self.drowsy] : []
    }
}

/// 독서 집중도: 최근 window 초 동안 책을 본 시간 비율 − 눈 돌린 횟수 × penalty (0~100)
public final class FocusMeter {
    public let window: Double
    public let lookAway: Double
    public let penalty: Double
    public let minData: Double
    let maxStep: Double
    public private(set) var history: [Int] = []  // 1분마다 점수(보고서용)
    private var samples: [(t: Double, dt: Double, on: Bool)] = []
    private var lookAwayTimes: [Double] = []
    private var offRun = 0.0
    private var start: Double?
    private var lastT: Double?

    public init(window: Double = 60, lookAway: Double = 1, penalty: Double = 10, minData: Double = 10, maxStep: Double = 1) {
        self.window = window
        self.lookAway = lookAway
        self.penalty = penalty
        self.minData = minData
        self.maxStep = maxStep
    }

    public func update(onTarget: Bool, t: Double) {
        let dt = lastT.map { min(max(t - $0, 0), maxStep) } ?? 0
        lastT = t
        if start == nil { start = t }
        if onTarget {
            offRun = 0
        } else {
            if offRun < lookAway && lookAway <= offRun + dt { lookAwayTimes.append(t) }
            offRun += dt
        }
        samples.append((t, dt, onTarget))
        samples.removeAll { $0.t <= t - window }
        lookAwayTimes.removeAll { $0 <= t - window }
        if t - start! >= Double(history.count + 1) * 60 { history.append(score ?? 0) }
    }

    public var lookAways: Int { lookAwayTimes.count }

    public var score: Int? {
        let covered = samples.reduce(0) { $0 + $1.dt }
        guard covered >= minData else { return nil }
        let on = samples.filter(\.on).reduce(0) { $0 + $1.dt } / covered
        return max(0, min(100, Int((on * 100 - penalty * Double(lookAways)).rounded())))
    }
}
