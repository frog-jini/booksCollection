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

@Test func overlongWordGetsItsOwnLine() {
    let long = String(repeating: "y", count: 50)
    #expect(pages("x \(long) z")[0].lines.map { $0.words.map(\.text) } == [["x"], [long], ["z"]])
}

@Test func pageTextAndEmptyText() {
    #expect(pages("aa bb\ncc")[0].text == "aa bb\ncc")
    let empty = pages("")
    #expect(empty.count == 1 && empty[0].words.isEmpty)
}
