import Foundation
import Testing
@testable import EyeReaderKit

// 언어별 실제 문장. 각 언어에서 흔히 쓰던 옛 인코딩으로 저장된 파일도 원문 그대로 읽혀야 한다.
let korean = "그는 오래된 책장을 넘기며 창밖의 비를 바라보았다. 어린 시절의 기억이 하나둘 떠올랐고, 마음 한구석이 따뜻해졌다."
let japanese = "吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。"
let chineseSimplified = "我们在图书馆里读了很多有趣的书，老师说阅读可以让人变得更聪明，也能让生活更加丰富多彩。"
let chineseTraditional = "我們在圖書館裡讀了很多有趣的書，老師說閱讀可以讓人變得更聰明，也能讓生活更加豐富多彩。"
let french = "L'été dernier, nous avons visité un château près de la forêt. Le café était délicieux et les crêpes très sucrées — « voilà ! »"
let german = "Über den Wolken muss die Freiheit wohl grenzenlos sein. Die Größe der Straße überraschte die Mädchen."

extension String.Encoding {
    static let cp949 = String.Encoding(rawValue: 0x8000_0422)
    static let gb18030 = String.Encoding(rawValue: 0x8000_0632)
    static let big5 = String.Encoding(rawValue: 0x8000_0A03)
}

@Test(arguments: [
    (korean, String.Encoding.cp949),
    (japanese, .shiftJIS),
    (chineseSimplified, .gb18030),
    (chineseTraditional, .big5),
    (french, .windowsCP1252),
    (german, .windowsCP1252),
])
func legacyEncodedBooksAreReadCorrectly(text: String, encoding: String.Encoding) throws {
    let data = try #require(text.data(using: encoding))
    #expect(String(data: data, encoding: .utf8) == nil)  // UTF-8 로는 못 읽는 파일이어야 의미가 있다
    #expect(BookText.decode(data) == text)
}

@Test(arguments: [korean, japanese, chineseSimplified, french])
func utf8AndUtf16WithOrWithoutBOMAreRead(text: String) throws {
    #expect(BookText.decode(Data(text.utf8)) == text)
    #expect(BookText.decode(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)) == text)
    #expect(BookText.decode(try #require(text.data(using: .utf16))) == text)  // BOM 포함(Windows 메모장 '유니코드')
}

/// BOM 없는 UTF-16 은 드물지만, 띄어쓰기·ASCII 가 섞인 글이면 0 바이트 분포로 알아본다.
@Test(arguments: [korean, french])
func utf16WithoutBOMIsRecognizedForSpacedText(text: String) throws {
    #expect(BookText.decode(try #require(text.data(using: .utf16LittleEndian))) == text)
    #expect(BookText.decode(try #require(text.data(using: .utf16BigEndian))) == text)
}

@Test func unknownBytesStillGiveSomeText() {
    #expect(!BookText.decode(Data((0x80...0xFF).map { UInt8($0) })).isEmpty)
}
