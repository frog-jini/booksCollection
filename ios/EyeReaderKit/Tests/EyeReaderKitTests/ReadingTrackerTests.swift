import Testing
@testable import EyeReaderKit

// 글자당 10pt, 줄 높이 40pt. 한 줄 = "a0xx b0xx c0xx d0xx", 세 줄
func trackerPage() -> Page {
    let text = (0..<3).map { i in "abcd".map { "\($0)\(i)xx" }.joined(separator: " ") }.joined(separator: "\n")
    return paginate(text, width: 200, height: 400, measure: { Double($0.count) * 10 }, lineHeight: 40, spaceWidth: 10)[0]
}

func at(_ p: Page, _ line: Int, _ word: Int) -> Point { p.lines[line].words[word].center }

@Test func gazeOnWordSelectsWordAndLine() {
    let p = trackerPage()
    let tr = ReadingTracker(page: p)
    #expect(tr.update(gaze: at(p, 0, 2), t: 0)?.text == "c0xx")
    #expect(tr.lineIndex == 0)
}

@Test func briefGlanceIgnoredButStayingSwitchesLine() {
    let p = trackerPage()
    let tr = ReadingTracker(page: p, lineSwitchTime: 0.3)
    _ = tr.update(gaze: at(p, 0, 0), t: 0)
    #expect(tr.update(gaze: at(p, 2, 0), t: 0.1)?.text == "a0xx")
    #expect(tr.update(gaze: at(p, 2, 0), t: 0.5)?.text == "a2xx")
}

@Test func returnSweepGoesToNextLineDespiteVerticalError() {
    let p = trackerPage()
    let tr = ReadingTracker(page: p)
    _ = tr.update(gaze: at(p, 0, 0), t: 0)
    _ = tr.update(gaze: at(p, 0, 3), t: 1)
    let back = Point(x: at(p, 0, 0).x, y: at(p, 0, 0).y + 5)
    #expect(tr.update(gaze: back, t: 1.1)?.text == "a1xx")
}

@Test func lostGazeKeepsWordAndFurthestIgnoresRereading() {
    let p = trackerPage()
    let tr = ReadingTracker(page: p)
    _ = tr.update(gaze: at(p, 0, 3), t: 0)
    _ = tr.update(gaze: at(p, 0, 1), t: 0.2)
    #expect(tr.update(gaze: nil, t: 0.3)?.text == "b0xx")
    #expect(tr.furthest?.text == "d0xx")
}

func readLastLineToEnd(_ tr: ReadingTracker, _ p: Page) {
    _ = tr.update(gaze: at(p, 2, 0), t: 0)
    _ = tr.update(gaze: at(p, 2, 0), t: 0.2)
    _ = tr.update(gaze: at(p, 2, 3), t: 1.0)
}

@Test func stayingOnLastWordTurnsPage() {
    let p = trackerPage()
    let tr = ReadingTracker(page: p, lineSwitchTime: 0.1, turnDwell: 0.8)
    readLastLineToEnd(tr, p)
    _ = tr.update(gaze: at(p, 2, 3), t: 1.5)
    #expect(!tr.shouldTurn)
    _ = tr.update(gaze: at(p, 2, 3), t: 1.9)
    #expect(tr.shouldTurn)
}

@Test func returnSweepOnLastLineTurnsPageAndResetClears() {
    let p = trackerPage()
    let tr = ReadingTracker(page: p, lineSwitchTime: 0.1)
    readLastLineToEnd(tr, p)
    _ = tr.update(gaze: at(p, 0, 0), t: 1.1)
    #expect(tr.shouldTurn)
    tr.reset(page: p)
    #expect(!tr.shouldTurn && tr.word == nil)
}

@Test func emptyPageTurnsImmediately() {
    let empty = paginate("", width: 200, height: 400, measure: { _ in 10 }, lineHeight: 40, spaceWidth: 10)[0]
    let tr = ReadingTracker(page: empty)
    #expect(tr.update(gaze: Point(x: 0, y: 0), t: 0) == nil)
    #expect(tr.shouldTurn)
}
