/// 글을 화면 크기에 맞게 페이지/줄/단어 사각형으로 배치한다.
/// 글자 폭 측정 함수(measure)를 주입받으므로 UIKit 없이도 테스트할 수 있다.

public struct Word: Equatable, Sendable {
    public let text: String
    public let index: Int  // 책 전체에서의 단어 순번
    public let frame: Rect
    public var spaceBefore = true  // 앞 단어와 띄어 쓰는가(일본어·중국어 글자 사이는 false)
    public var center: Point { frame.center }
}

public struct Line: Equatable, Sendable {
    public let y: Double
    public var words: [Word] = []
}

public struct Page: Equatable, Sendable {
    public var lines: [Line] = []
    public var words: [Word] { lines.flatMap(\.words) }
    public var text: String { lines.map { joinWords($0.words) }.joined(separator: "\n") }
}

func joinWords(_ words: [Word]) -> String {
    var out = ""
    for w in words { out += (out.isEmpty || !w.spaceBefore ? "" : " ") + w.text }
    return out
}

/// 배치할 낱말 하나. 일본어·중국어는 글자 하나하나가 낱말이고, 사이에 공백을 넣지 않는다.
struct Token: Equatable {
    var text: String
    var spaceBefore: Bool
}

enum Script {
    static func isCJK(_ c: Character) -> Bool {
        c.unicodeScalars.contains { s in
            switch s.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x3000...0x303F, 0xFF00...0xFFEF: true
            default: false
            }
        }
    }
    static let closing: Set<Character> = ["。", "、", "，", "．", "！", "？", "」", "』", "）", "〕", "】", "》", "〉", "”", "’", "・", "ー", "…",
                                          ",", ".", "!", "?", ")", ":", ";"]
    static let opening: Set<Character> = ["「", "『", "（", "〔", "【", "《", "〈", "“", "‘", "("]
}

/// 한 줄을 낱말로 나눈다. 띄어쓰기 언어는 공백 기준, 일본어·중국어는 글자 단위(문장부호는 붙여서).
func tokenize(_ line: Substring) -> [Token] {
    var tokens: [Token] = []
    for chunk in line.split(whereSeparator: \.isWhitespace) {
        guard chunk.contains(where: Script.isCJK) else {
            tokens.append(Token(text: String(chunk), spaceBefore: true))
            continue
        }
        var units: [String] = []
        var pendingOpen = ""
        for c in chunk {
            if Script.closing.contains(c), !units.isEmpty {
                units[units.count - 1].append(c)  // 닫는 부호는 앞 글자에 붙여 줄 맨 앞에 오지 않게
            } else if Script.opening.contains(c) {
                pendingOpen.append(c)  // 여는 부호는 다음 글자에 붙인다
            } else if !Script.isCJK(c), let last = units.last?.last, !Script.isCJK(last), pendingOpen.isEmpty {
                units[units.count - 1].append(c)  // 한자 사이의 영문·숫자는 한 덩어리
            } else {
                units.append(pendingOpen + String(c))
                pendingOpen = ""
            }
        }
        if !pendingOpen.isEmpty { units.append(pendingOpen) }
        tokens += units.enumerated().map { Token(text: $1, spaceBefore: $0 == 0) }
    }
    return tokens
}

/// 폭보다 긴 낱말은 글자 단위로 잘라 여러 조각으로 만든다(화면 밖으로 나가지 않게).
func breakLong(_ token: Token, width: Double, measure: (String) -> Double) -> [Token] {
    guard measure(token.text) > width, token.text.count > 1 else { return [token] }
    var pieces: [Token] = []
    var current = ""
    for c in token.text {
        if !current.isEmpty && measure(current + String(c)) > width {
            pieces.append(Token(text: current, spaceBefore: pieces.isEmpty ? token.spaceBefore : false))
            current = ""
        }
        current.append(c)
    }
    pieces.append(Token(text: current, spaceBefore: pieces.isEmpty ? token.spaceBefore : false))
    return pieces
}

/// 원문 줄을 폭에 맞게 접는다. 빈 배열은 문단 사이 빈 줄.
func wrap(_ text: String, width: Double, measure: (String) -> Double, spaceWidth: Double) -> [[Token]] {
    var rows: [[Token]] = []
    for srcLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
        var row: [Token] = []
        var used = 0.0
        for token in tokenize(srcLine).flatMap({ breakLong($0, width: width, measure: measure) }) {
            let w = measure(token.text)
            let gap = token.spaceBefore ? spaceWidth : 0
            if !row.isEmpty && used + gap + w > width {
                rows.append(row)
                row = [token]
                used = w
            } else {
                used += (row.isEmpty ? 0 : gap) + w
                row.append(token)
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
        for (i, token) in row.enumerated() {
            if i > 0 && token.spaceBefore { x += spaceWidth }
            let w = measure(token.text)
            line.words.append(Word(text: token.text, index: index, frame: Rect(x: x, y: y, width: w, height: lineHeight),
                                   spaceBefore: token.spaceBefore))
            index += 1
            x += w
        }
        pages[pages.count - 1].lines.append(line)
    }
    for i in pages.indices {  // 끝에 남은 빈 줄 정리
        while let last = pages[i].lines.last, last.words.isEmpty { pages[i].lines.removeLast() }
    }
    if pages.count > 1 && pages[pages.count - 1].lines.isEmpty { pages.removeLast() }
    return pages
}
