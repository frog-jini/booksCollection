import Foundation
import Testing
@testable import EyeReaderKit

// 한 페이지 = 2줄 × 단어 4개, 총 3페이지
func sessionPages() -> [Page] {
    let text = (0..<24).map { String(format: "w%02dx", $0) }.joined(separator: " ")
    return paginate(text, width: 200, height: 80, measure: { Double($0.count) * 10 }, lineHeight: 40, spaceWidth: 10)
}

let textArea = Rect(x: 0, y: 0, width: 200, height: 80)
let face = FaceReading(pose: HeadPose(distanceCm: 38, yaw: 0, pitch: 0, roll: 0), openness: 0.9)

@discardableResult
func look(_ s: ReadingSession, _ p: Point, from t: Double, for seconds: Double = 0.3, face f: FaceReading? = face) -> Double {
    var t = t
    for _ in 0..<Int((seconds * 30).rounded()) { s.step(gaze: p, face: f, t: t, textArea: textArea); t += 1.0 / 30 }
    return t
}

func center(_ s: ReadingSession, _ line: Int, _ word: Int) -> Point { s.page.lines[line].words[word].center }

func readPage(_ s: ReadingSession, from start: Double = 0) -> Double {
    var t = start
    for line in s.page.lines.indices { for w in 0..<4 { t = look(s, center(s, line, w), from: t) } }
    return look(s, center(s, 0, 0), from: t)
}

@Test func readingToEndOfPageTurnsAutomaticallyButNotPastLast() {
    let s = ReadingSession(pages: sessionPages())
    var t = readPage(s)
    #expect(s.pageIndex == 1)
    #expect(s.tracker.word?.text == "w08x")
    for _ in 0..<4 { t = readPage(s, from: t) }
    #expect(s.pageIndex == 2)
}

@Test func manualMovesClampAndPauseStopsTracking() {
    let s = ReadingSession(pages: sessionPages())
    s.goTo(99); #expect(s.pageIndex == 2)
    s.goTo(-3); #expect(s.pageIndex == 0)
    s.paused = true
    _ = readPage(s)
    #expect(s.pageIndex == 0 && s.tracker.word == nil)
}

@Test func speedAndTurnWaitFollowReader() {
    let s = ReadingSession(pages: sessionPages())
    _ = readPage(s)
    #expect(s.speed.wpm > 0)
    #expect(s.tracker.turnDwell == s.speed.turnDwell())
}

@Test func gazeTimeBuildsHeatmapAndFocus() {
    let s = ReadingSession(pages: sessionPages())
    look(s, center(s, 0, 0), from: 0, for: 15)
    #expect(abs(s.heatmaps.page(0).totalSeconds - 15) < 0.1)
    #expect(s.coach.focus.score == 100)
}

@Test func lookingOffTheTextLowersFocusAndLostFaceIsAway() {
    let s = ReadingSession(pages: sessionPages())
    var t = look(s, Point(x: 500, y: 500), from: 0, for: 15)  // 책 밖을 봄
    #expect(s.coach.focus.score == 0)
    t = look(s, center(s, 0, 0), from: t, for: 5, face: nil)  // 얼굴을 놓침
    #expect(s.coach.timer.awaySeconds > 4)
}

@Test func alertsComeBackFromStep() {
    let coach = ReadingCoach(timer: ReadingTimer(breakAfter: 5))
    let s = ReadingSession(pages: sessionPages(), coach: coach)
    var got: [Alert] = []
    var t = 0.0
    for _ in 0..<200 { got += s.step(gaze: center(s, 0, 0), face: face, t: t, textArea: textArea); t += 1.0 / 30 }
    #expect(got.map(\.kind) == ["break"])
}

// --- 책 텍스트 ---

@Test func bookTextNormalizesWrappedLinesAndParagraphs() {
    #expect(BookText.normalize("a\nb\r\n\r\n\n c  d\n") == "a b\n\nc d")
    #expect(BookText.normalize("exam-\nple text") == "example text")
}

@Test func bookTextDecodesUTF8AndRemovesBOM() {
    #expect(BookText.decode(Data("한글 소설".utf8)) == "한글 소설")
    #expect(BookText.decode(Data([0xEF, 0xBB, 0xBF]) + Data("BOM".utf8)) == "BOM")
}

@Test func gutenbergLicenseIsStripped() {
    let raw = "license\n*** START OF THE PROJECT GUTENBERG EBOOK X ***\nBody.\n*** END OF THE PROJECT GUTENBERG EBOOK X ***\nmore"
    #expect(BookText.stripGutenberg(raw) == "Body.")
    #expect(BookText.stripGutenberg("plain") == "plain")
    #expect(Book(title: "x", rawText: raw).text == "Body.")
}

// --- 일본어·중국어 문단 정리 ---

@Test func wrappedJapaneseLinesJoinWithoutSpacesAndIndentedLinesStartParagraphs() {
    let raw = "\u{3000}或日の暮方の事である。一人の下人が、羅生\n門の下で雨やみを待っていた。\n「何をしていた。」\n\u{3000}次の段落。\n"
    #expect(BookText.normalize(raw) ==
            "或日の暮方の事である。一人の下人が、羅生門の下で雨やみを待っていた。\n\n「何をしていた。」\n\n次の段落。")
}

@Test func chineseWrappedLinesJoinWithoutSpaces() {
    #expect(BookText.normalize("我们在图书馆\n里读书。\n\n第二段。") == "我们在图书馆里读书。\n\n第二段。")
}

@Test func koreanAndEnglishStillJoinWithSpaces() {
    #expect(BookText.normalize("첫 줄\n이어짐\n\n둘째") == "첫 줄 이어짐\n\n둘째")
}
