import Foundation

public struct Book: Sendable {
    public let title: String
    public let text: String

    /// 파일에서 읽은 글을 정리해서 책으로 만든다(Gutenberg 라이선스 문구 제거, 문단 정리).
    public init(title: String, rawText: String) {
        self.title = title
        text = BookText.normalize(BookText.stripGutenberg(rawText))
    }
}

public enum BookText {
    /// 줄바꿈으로 잘린 문장은 잇고, 빈 줄로 나뉜 문단은 유지한다.
    public static func normalize(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        text = text.replacingOccurrences(of: #"(\w)-\n(\w)"#, with: "$1$2", options: .regularExpression)
        let paragraphs = text.components(separatedBy: "\n")
            .split { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        return paragraphs.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// UTF-8(BOM 포함) 우선, 안 되면 한국어 CP949(애플 기기), 그래도 안 되면 Latin-1.
    public static func decode(_ data: Data) -> String {
        var data = data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        if let s = String(data: data, encoding: .utf8) { return s }
        #if canImport(Darwin)
        let cp949 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: cp949)) { return s }
        #endif
        return String(decoding: data, as: UTF8.self)
    }

    /// Project Gutenberg 라이선스 머리말/꼬리말을 떼어낸다. 표시가 없으면 그대로 둔다.
    public static func stripGutenberg(_ text: String) -> String {
        func find(_ word: String) -> Range<String.Index>? {
            text.range(of: #"(?m)^\*\*\* ?"# + word + #" OF (THE|THIS) PROJECT GUTENBERG.*$"#,
                       options: [.regularExpression, .caseInsensitive])
        }
        let start = find("START"), end = find("END")
        guard start != nil || end != nil else { return text }
        let begin = start?.upperBound ?? text.startIndex
        let finish = end.map { $0.lowerBound > begin ? $0.lowerBound : text.endIndex } ?? text.endIndex
        return String(text[begin..<finish]).trimmingCharacters(in: .newlines)
    }
}
