import Testing
@testable import EyeReaderKit

// --- 읽기 속도 (readme 2) ---

@Test func wpmFromProgressIgnoringRereading() {
    let s = ReadingSpeed(window: 120)
    #expect(s.wpm == 0)
    s.update(wordIndex: 0, t: 0)
    s.update(wordIndex: 50, t: 30)
    s.update(wordIndex: 10, t: 40)  // 되돌아 읽기
    s.update(wordIndex: 60, t: 60)
    #expect(abs(s.wpm - 60) < 1e-9)
}

@Test func onlyRecentWindowCounts() {
    let s = ReadingSpeed(window: 10)
    s.update(wordIndex: 0, t: 0)
    s.update(wordIndex: 1000, t: 1)
    s.update(wordIndex: 1000, t: 20)
    s.update(wordIndex: 1010, t: 30)
    #expect(abs(s.wpm - 60) < 1e-9)
}

@Test func pageTurnWaitFollowsReadingSpeed() {
    #expect(ReadingSpeed(defaultWPM: 400).turnDwell() == 0.6)
    #expect(ReadingSpeed(defaultWPM: 60).turnDwell() == 2.0)
    #expect(abs(ReadingSpeed(defaultWPM: 150).turnDwell() - 1.2) < 1e-9)
}

// --- 시선 떨림 줄이기 (readme 8) ---

@Test func smootherAveragesJitterButFollowsBigJumps() {
    let s = GazeSmoother(alpha: 0.5, snapDistance: 300)
    #expect(s.update(Point(x: 0, y: 0)) == Point(x: 0, y: 0))
    #expect(s.update(Point(x: 10, y: 20)) == Point(x: 5, y: 10))
    #expect(s.update(Point(x: 1000, y: 10)) == Point(x: 1000, y: 10))
    #expect(s.update(nil) == Point(x: 1000, y: 10))
    s.reset()
    #expect(s.update(nil) == nil)
}
