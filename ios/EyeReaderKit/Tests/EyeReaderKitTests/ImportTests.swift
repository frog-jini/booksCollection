import Foundation
import Testing
@testable import EyeReaderKit

// --- 압축 풀기(deflate) ---

@Test(arguments: [("stored", Fixtures.deflateStored), ("dynamic", Fixtures.deflateDynamic)])
func inflateMatchesZlib(kind: String, data: Data) throws {
    #expect(String(decoding: try Inflate.decompress(data), as: UTF8.self) == Fixtures.text)
}

@Test func inflateFixedHuffmanBlock() throws {
    let expected = Data(Fixtures.text.utf8.prefix(300))
    #expect(try Inflate.decompress(Fixtures.deflateFixed) == expected)
}

@Test func brokenCompressedDataThrows() {
    #expect(throws: (any Error).self) { try Inflate.decompress(Data([0xFF, 0xFF, 0xFF])) }
}

// --- zip ---

@Test func zipListsAndReadsFiles() throws {
    let zip = try ZipArchive(Fixtures.epub)
    #expect(zip.names.contains("mimetype") && zip.names.contains("OEBPS/text/ch 2.xhtml"))
    #expect(String(decoding: try zip.read("mimetype"), as: UTF8.self) == "application/epub+zip")
    #expect(throws: (any Error).self) { try ZipArchive(Data("not a zip".utf8)) }
}

// --- HTML → 글 ---

@Test func htmlBecomesParagraphTextWithoutTagsRubyOrScripts() {
    let html = "<html><head><title>T</title><style>x{}</style></head><body><h1>Head</h1><p>One &amp; two</p>"
        + "<script>bad()</script><p><ruby>漢字<rt>かんじ</rt></ruby>です<br/>次</p></body></html>"
    let (title, text) = HTMLText.extract(html)
    #expect(title == "T")
    #expect(BookText.normalize(text) == "Head\n\nOne & two\n\n漢字です\n\n次")
}

@Test func htmlEntitiesAreDecoded() {
    #expect(HTMLText.decodeEntities("&lt;a&gt; &quot;b&quot; &apos;c&apos; &#8212; &#x263A; &nbsp;x") == "<a> \"b\" 'c' — ☺ \u{00A0}x")
}

// --- EPUB ---

@Test func epubChaptersInSpineOrderWithTitle() throws {
    let book = try Book.load(data: Fixtures.epub, fileName: "neko.epub")
    #expect(book.title == "吾輩は猫である & 친구")
    #expect(book.text == "第一章\n\n吾輩は猫である。\n\nTom & Jerry\u{00A0}— ☺\n\n둘째 장입니다.\n\n다음 줄")
}

@Test func bookLoadPicksReaderByExtension() throws {
    #expect(try Book.load(data: Data("<p>A</p><p>B</p>".utf8), fileName: "x.html").text == "A\n\nB")
    #expect(try Book.load(data: Data("plain\ntext".utf8), fileName: "story.txt").text == "plain text")
    #expect(try Book.load(data: Data("plain".utf8), fileName: "story.txt").title == "story")
    #expect(throws: (any Error).self) { try Book.load(data: Data("nope".utf8), fileName: "bad.epub") }
}
