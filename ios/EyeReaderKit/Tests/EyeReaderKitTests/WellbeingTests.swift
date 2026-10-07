import Testing
@testable import EyeReaderKit

let MIN = 60.0

func runTimer(_ timer: ReadingTimer, present: Bool, from start: Double, for seconds: Double) -> ([Alert], Double) {
    var alerts: [Alert] = [], t = start
    while t < start + seconds { alerts += timer.update(present: present, t: t); t += 0.5 }
    return (alerts, t)
}

// --- 휴식 권유와 화면 이탈 시간 ---

@Test func suggestsBreakAfterLongReadingAndRepeats() {
    let timer = ReadingTimer(breakAfter: 30 * MIN, repeatEvery: 10 * MIN)
    let alerts = runTimer(timer, present: true, from: 0, for: 41 * MIN).0
    #expect(alerts.map(\.message) == ["30분 동안 계속 독서 중입니다.", "40분 동안 계속 독서 중입니다."])
    #expect(alerts[0].title == "잠시 쉬어가는 건 어떨까요?")
}

@Test func shortGlanceIsNotARestButRealRestResets() {
    let timer = ReadingTimer(breakAfter: 30 * MIN, rest: 5 * MIN)
    var (_, t) = runTimer(timer, present: true, from: 0, for: 25 * MIN)
    (_, t) = runTimer(timer, present: false, from: t, for: 1 * MIN)
    #expect(timer.continuousSeconds > 24 * MIN)
    (_, t) = runTimer(timer, present: false, from: t, for: 5 * MIN)
    #expect(timer.continuousSeconds == 0)
}

@Test func measuresReadingAwayTimeAndLookAways() {
    let timer = ReadingTimer(lookAway: 1)
    var t = 0.0
    for (present, secs) in [(true, 60.0), (false, 0.5), (true, 30), (false, 4), (true, 10)] {
        t = runTimer(timer, present: present, from: t, for: secs).1
    }
    #expect(abs(timer.readingSeconds - 100) <= 1)
    #expect(abs(timer.awaySeconds - 4.5) <= 1)
    #expect(timer.lookAways == 1)
}

// --- 졸음 (ARKit 눈 깜빡임 값 → 눈 뜬 정도) ---

let OPEN = 0.9, CLOSED = 0.05

func stream(_ m: DrowsinessMonitor, _ pattern: [(Double?, Double)], from start: Double = 0) -> ([Alert], Double) {
    var alerts: [Alert] = [], t = start
    for (value, secs) in pattern {
        for _ in 0..<Int((secs * 30).rounded()) { alerts += m.update(openness: value, t: t); t += 1.0 / 30 }
    }
    return (alerts, t)
}

func normalReading(_ seconds: Double) -> [(Double?, Double)] {
    Array(repeating: [(OPEN, 3.8), (CLOSED, 0.2)], count: Int(seconds / 4)).flatMap { $0 }
}

@Test func blinksPerMinuteAndPerclos() {
    let m = DrowsinessMonitor(window: 60)
    #expect(stream(m, normalReading(60)).0.isEmpty)
    #expect(abs(m.blinkRate - 15) <= 1)
    #expect(abs(m.perclos - 0.05) <= 0.01)
}

@Test func eyesClosedOverASecondIsDrowsyWithCooldown() {
    let m = DrowsinessMonitor(microsleep: 1, cooldown: 120)
    let alerts = stream(m, Array(repeating: [(CLOSED, 1.5), (OPEN, 5)], count: 5).flatMap { $0 }).0
    #expect(alerts.map(\.kind) == ["drowsy"])
    #expect(alerts[0].title == "졸음이 감지되었습니다.")
    #expect(m.longClosures == 5)
}

@Test func highPerclosOverFullWindowIsDrowsy() {
    let m = DrowsinessMonitor(window: 60, perclosLimit: 0.15, microsleep: 10)
    #expect(stream(m, Array(repeating: [(OPEN, 3.2), (CLOSED, 0.8)], count: 5).flatMap { $0 }).0.isEmpty)
    let alerts = stream(m, Array(repeating: [(OPEN, 3.2), (CLOSED, 0.8)], count: 12).flatMap { $0 }, from: 20).0
    #expect(alerts.map(\.kind) == ["drowsy"])
}

@Test func lostFaceIsNotClosedEyes() {
    let m = DrowsinessMonitor(microsleep: 1)
    #expect(stream(m, [(OPEN, 2), (nil, 3), (OPEN, 2)]).0.isEmpty)
    #expect(m.perclos == 0)
}

// --- 집중도 ---

func feedFocus(_ m: FocusMeter, _ pattern: [(Bool, Double)], from start: Double = 0) -> Double {
    var t = start
    for (on, secs) in pattern { for _ in 0..<Int(secs / 0.5) { m.update(onTarget: on, t: t); t += 0.5 } }
    return t
}

@Test func focusScore() {
    let full = FocusMeter(window: 60)
    _ = feedFocus(full, [(true, 60)])
    #expect(full.score == 100)

    let distracted = FocusMeter(window: 60, lookAway: 1, penalty: 10)
    _ = feedFocus(distracted, Array(repeating: [(true, 18), (false, 2)], count: 3).flatMap { $0 })
    #expect(distracted.score == 60 && distracted.lookAways == 3)

    let early = FocusMeter(minData: 10)
    _ = feedFocus(early, [(true, 5)])
    #expect(early.score == nil)
}

@Test func focusHistoryPerMinute() {
    let m = FocusMeter(window: 60, lookAway: 1, penalty: 10)
    _ = feedFocus(m, [(true, 60)] + Array(repeating: [(true, 18), (false, 2)], count: 3).flatMap { $0 } + [(true, 0.5)])
    #expect(m.history.count == 2 && m.history[0] == 100 && (55...65).contains(m.history[1]))
}
