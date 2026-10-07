import Testing
@testable import EyeReaderKit

/// 글자당 10pt 고정폭 — UIKit 없이 테스트
let measure: @Sendable (String) -> Double = { Double($0.count) * 10 }

func pages(_ text: String, width: Double = 200, height: Double = 100,
           origin: Point = Point(x: 0, y: 0)) -> [Page] {
    paginate(text, width: width, height: height, measure: measure, lineHeight: 20, spaceWidth: 10, origin: origin)
}

let hundredWords = (0..<100).map { "w\($0)" }.joined(separator: " ")

@Test func allWordsKeptInOrderWithGlobalIndex() {
    let all = pages(hundredWords).flatMap(\.words)
    #expect(all.map(\.text) == hundredWords.split(separator: " ").map(String.init))
    #expect(all.map(\.index) == Array(0..<100))
}

@Test func linesFitWidthAndPagesHoldOnlyWhatFits() {
    let ps = pages(hundredWords)
    #expect(ps.count > 1)
    for p in ps {
        #expect(p.lines.count <= 5)
        for line in p.lines { #expect(line.words.last!.frame.maxX <= 200) }
    }
}

@Test func wordBoxesMoveRightThenDown() {
    let p = pages("aa bb cc dd", width: 60)[0]
    #expect(p.lines.map { $0.words.map(\.text) } == [["aa", "bb"], ["cc", "dd"]])
    let aa = p.lines[0].words[0], bb = p.lines[0].words[1]
    #expect(aa.frame == Rect(x: 0, y: 0, width: 20, height: 20))
    #expect(bb.frame.x == 30)
    #expect(p.lines[1].words[0].frame.y == 20)
    #expect(aa.center == Point(x: 10, y: 10))
}

@Test func newlineStartsLineAndBlankLineKeepsGap() {
    let ys = Dictionary(uniqueKeysWithValues: pages("a\nb\n\nc")[0].words.map { ($0.text, $0.frame.y) })
    #expect(ys == ["a": 0, "b": 20, "c": 60])
}

@Test func originShiftsEveryBox() {
    #expect(pages("a b", origin: Point(x: 5, y: 7))[0].words[0].frame.origin == Point(x: 5, y: 7))
}

@Test func overlongWordIsBrokenToFitInsteadOfRunningOffScreen() {
    let long = String(repeating: "y", count: 50)  // 500pt > 폭 200pt
    let p = pages("x \(long) z", height: 400)[0]
    for line in p.lines { #expect(line.words.last!.frame.maxX <= 200) }
    #expect(p.text.replacingOccurrences(of: "\n", with: "") == "x \(long) z".replacingOccurrences(of: " ", with: "")
            || p.words.map(\.text).joined().contains(long))
    #expect(p.words.map(\.text).joined() == "x" + long + "z")
}

@Test func pageTextAndEmptyText() {
    #expect(pages("aa bb\ncc")[0].text == "aa bb\ncc")
    let empty = pages("")
    #expect(empty.count == 1 && empty[0].words.isEmpty)
}


// --- 띄어쓰기가 없는 언어(일본어·중국어) ---

let japaneseLine = "吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。"

@Test func japaneseWrapsAtScreenWidthWithoutAddingSpaces() {
    let p = pages(japaneseLine, width: 100, height: 1000)[0]
    #expect(p.lines.count > 1)
    for line in p.lines { #expect(line.words.last!.frame.maxX <= 100) }
    #expect(p.text.replacingOccurrences(of: "\n", with: "") == japaneseLine)  // 글자 사이에 공백이 생기지 않음
}

@Test func cjkCharactersSitSideBySideWithoutGaps() {
    let line = pages("我们读书", width: 200, height: 100)[0].lines[0]
    for (a, b) in zip(line.words, line.words.dropFirst()) { #expect(b.frame.x == a.frame.maxX) }
}

@Test func closingPunctuationNeverStartsALine() {
    for width in stride(from: 60.0, through: 200, by: 10) {
        for line in pages(japaneseLine, width: width, height: 2000)[0].lines {
            #expect(!"。、」』）！？".contains(line.words[0].text.first!))
        }
    }
}

@Test func mixedScriptsKeepTheirSpaces() {
    #expect(pages("Tokyo 駅で book", width: 400)[0].text == "Tokyo 駅で book")
    #expect(pages("한국어 문장도 그대로", width: 400)[0].words.map(\.text) == ["한국어", "문장도", "그대로"])
}
