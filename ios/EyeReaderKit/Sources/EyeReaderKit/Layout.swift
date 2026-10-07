/// 글을 화면 크기에 맞게 페이지/줄/단어 사각형으로 배치한다.
/// 글자 폭 측정 함수(measure)를 주입받으므로 UIKit 없이도 테스트할 수 있다.

public struct Word: Equatable, Sendable {
    public let text: String
    public let index: Int  // 책 전체에서의 단어 순번
    public let frame: Rect
    public var center: Point { frame.center }
}

public struct Line: Equatable, Sendable {
    public let y: Double
    public var words: [Word] = []
}

public struct Page: Equatable, Sendable {
    public var lines: [Line] = []
    public var words: [Word] { lines.flatMap(\.words) }
    public var text: String { lines.map { $0.words.map(\.text).joined(separator: " ") }.joined(separator: "\n") }
}

/// 원문 줄을 폭에 맞게 접는다. 빈 배열은 문단 사이 빈 줄.
func wrap(_ text: String, width: Double, measure: (String) -> Double, spaceWidth: Double) -> [[String]] {
    var rows: [[String]] = []
    for srcLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
        var row: [String] = []
        var used = 0.0
        for word in srcLine.split(whereSeparator: \.isWhitespace).map(String.init) {
            let w = measure(word)
            let needed = row.isEmpty ? w : used + spaceWidth + w
            if !row.isEmpty && needed > width {
                rows.append(row)
                row = [word]
                used = w
            } else {
                row.append(word)
                used = needed
            }
        }
        rows.append(row)
    }
    return rows
}

public func paginate(_ text: String, width: Double, height: Double, measure: (String) -> Double,
                     lineHeight: Double, spaceWidth: Double, origin: Point = Point(x: 0, y: 0)) -> [Page] {
    let maxLines = max(1, Int(height / lineHeight))
    var pages = [Page()]
    var index = 0
    for row in wrap(text, width: width, measure: measure, spaceWidth: spaceWidth) {
        if pages[pages.count - 1].lines.count >= maxLines { pages.append(Page()) }
        if row.isEmpty && pages[pages.count - 1].lines.isEmpty { continue }  // 페이지 맨 위 빈 줄은 버림
        let y = origin.y + Double(pages[pages.count - 1].lines.count) * lineHeight
        var line = Line(y: y)
        var x = origin.x
        for word in row {
            let w = measure(word)
            line.words.append(Word(text: word, index: index, frame: Rect(x: x, y: y, width: w, height: lineHeight)))
            index += 1
            x += w + spaceWidth
        }
        pages[pages.count - 1].lines.append(line)
    }
    for i in pages.indices {  // 끝에 남은 빈 줄 정리
        while let last = pages[i].lines.last, last.words.isEmpty { pages[i].lines.removeLast() }
    }
    if pages.count > 1 && pages[pages.count - 1].lines.isEmpty { pages.removeLast() }
    return pages
}
