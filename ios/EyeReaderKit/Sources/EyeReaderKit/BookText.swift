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

    /// 책 파일의 글자 인코딩을 알아내서 읽는다.
    /// 1) BOM(UTF-8/16/32) 2) UTF-8 3) BOM 없는 UTF-16 4) 옛 인코딩(한·일·중·서유럽) 중 가장 '자연스러운' 글.
    public static func decode(_ data: Data) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: data.dropFirst(3), as: UTF8.self) }
        if data.starts(with: [0xFF, 0xFE, 0, 0]), let s = String(data: data.dropFirst(4), encoding: .utf32LittleEndian) { return s }
        if data.starts(with: [0, 0, 0xFE, 0xFF]), let s = String(data: data.dropFirst(4), encoding: .utf32BigEndian) { return s }
        if data.starts(with: [0xFF, 0xFE]), let s = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) { return s }
        if data.starts(with: [0xFE, 0xFF]), let s = String(data: data.dropFirst(2), encoding: .utf16BigEndian) { return s }
        if let s = String(data: data, encoding: .utf8) { return s }
        if let enc = utf16WithoutBOM(data), let s = String(data: data, encoding: enc) { return s }

        var best: (score: Double, text: String)?
        for enc in Legacy.candidates {
            guard let s = String(data: data, encoding: enc) else { continue }
            let score = Legacy.plausibility(s, as: enc)
            if best == nil || score > best!.score { best = (score, s) }  // 점수가 같으면 앞 순서(한국어) 우선
        }
        return best?.text ?? String(decoding: data, as: UTF8.self)
    }

    /// 짝수/홀수 자리에 0 바이트가 몰려 있으면 BOM 없는 UTF-16 이다(공백·ASCII 의 앞/뒤 바이트).
    static func utf16WithoutBOM(_ data: Data) -> String.Encoding? {
        let bytes = Array(data.prefix(4096))
        guard bytes.count >= 4, bytes.count % 2 == 0 else { return nil }
        let pairs = Double(bytes.count / 2)
        let evenZeros = Double(stride(from: 0, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count)
        let oddZeros = Double(stride(from: 1, to: bytes.count, by: 2).filter { bytes[$0] == 0 }.count)
        if oddZeros / pairs > 0.15 && evenZeros / pairs < 0.02 { return .utf16LittleEndian }
        if evenZeros / pairs > 0.15 && oddZeros / pairs < 0.02 { return .utf16BigEndian }
        return nil
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

/// 옛 인코딩 판별: 같은 바이트를 여러 인코딩으로 읽어 보고, 그 언어에서 흔히 쓰는 글자가 많을수록 높은 점수.
/// (잘못 읽으면 거의 안 쓰는 한글 음절·낱자모·반각 가타카나·드문 한자가 쏟아진다)
enum Legacy {
    static let cp949 = String.Encoding(rawValue: 0x8000_0422)  // 한국어(통합형 완성형)
    static let eucKR = String.Encoding(rawValue: 0x8000_0940)  // KS X 1001: 자주 쓰는 한글 2350자·한자 4888자
    static let gb18030 = String.Encoding(rawValue: 0x8000_0632)  // 중국어 간체
    static let gb2312 = String.Encoding(rawValue: 0x8000_0930)  // 자주 쓰는 간체 6763자 (EUC-CN)
    static let big5 = String.Encoding(rawValue: 0x8000_0A03)  // 중국어 번체

    static let candidates: [String.Encoding] = [cp949, .shiftJIS, .japaneseEUC, gb18030, big5, .windowsCP1252]

    nonisolated(unsafe) private static var cache: [String: Bool] = [:]
    private static let lock = NSLock()

    private static func encodable(_ scalar: Unicode.Scalar, _ enc: String.Encoding, _ check: (Data) -> Bool = { _ in true }) -> Bool {
        let key = "\(enc.rawValue)-\(scalar.value)"
        lock.lock(); defer { lock.unlock() }
        if let v = cache[key] { return v }
        let v = String(Character(scalar)).data(using: enc).map(check) ?? false
        cache[key] = v
        return v
    }

    static func commonHangul(_ s: Unicode.Scalar) -> Bool { encodable(s, eucKR) }

    /// 그 인코딩을 쓰는 언어에서 자주 쓰는 한자인가
    static func commonHan(_ s: Unicode.Scalar, as enc: String.Encoding) -> Double {
        switch enc {
        case gb18030: return encodable(s, gb2312) ? 1 : -1
        case big5: return encodable(s, big5, { $0.first.map { (0xA4...0xC6).contains($0) } ?? false }) ? 1 : -1  // Big5 상용자
        case .shiftJIS, .japaneseEUC:  // JIS 제1수준 한자
            return encodable(s, .shiftJIS, { $0.first.map { (0x88...0x98).contains($0) } ?? false }) ? 1 : -1
        case cp949: return encodable(s, eucKR) ? 0.3 : -1  // 한국어 글에 한자가 많지는 않다
        default: return -1
        }
    }

    static func plausibility(_ text: String, as enc: String.Encoding) -> Double {
        var score = 0.0, n = 0
        for scalar in text.unicodeScalars.prefix(4000) {
            n += 1
            switch scalar.value {
            case 0x09, 0x0A, 0x0D, 0x20...0x7E: score += 1
            case 0x00...0x1F, 0x7F...0x9F: score -= 5  // 제어 문자
            case 0xA0...0x24F, 0x2000...0x206F, 0x20AC: score += 1  // 라틴 문자·문장부호
            case 0x3000...0x303F, 0xFF01...0xFF60: score += 1  // 한중일 문장부호·전각
            case 0x3041...0x30FF: score += 2  // 히라가나·가타카나
            case 0x3130...0x318F: score -= 3  // 한글 낱자모(깨진 글의 신호)
            case 0xAC00...0xD7A3: score += commonHangul(scalar) ? 1 : -3
            case 0x4E00...0x9FFF: score += commonHan(scalar, as: enc)
            case 0xFF61...0xFF9F: score -= 3  // 반각 가타카나(깨진 글의 신호)
            case 0xE000...0xF8FF, 0xFFFD: score -= 5
            default: score -= 1
            }
        }
        return n > 0 ? score / Double(n) : -10
    }
}
