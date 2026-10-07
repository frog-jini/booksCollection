import Foundation
import Testing
@testable import EyeReaderKit

let searchJSON = """
{"count": 1, "results": [{"id": 11, "title": "Alice's Adventures in Wonderland",
 "authors": [{"name": "Carroll, Lewis"}], "languages": ["en"]}]}
"""

let opdsXML = """
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
<entry><id>https://www.gutenberg.org/ebooks/authors/search.opds/?query=alice</id>
<title>Authors</title><content type="text">145 author names match</content></entry>
<entry><id>https://www.gutenberg.org/ebooks/11.opds</id>
<title>Alice&apos;s Adventures in Wonderland</title><content type="text">Lewis Carroll</content></entry>
</feed>
"""

/// URL 앞부분으로 응답을 고르는 가짜 네트워크
func fakeFetch(_ routes: [String: (Int, String)], log: Recorder? = nil) -> GutenbergClient.Fetch {
    { url in
        await log?.add(url.absoluteString)
        for (prefix, (status, body)) in routes where url.absoluteString.hasPrefix(prefix) {
            return (Data(body.utf8), status)
        }
        return (Data(), 404)
    }
}

actor Recorder {
    var urls: [String] = []
    func add(_ u: String) { urls.append(u) }
}

let alice = GutenbergBook(id: 11, title: "Alice's Adventures in Wonderland", authors: ["Carroll, Lewis"], languages: ["en"])

@Test func searchUsesFreeGutendexWithLanguageFilter() async throws {
    let log = Recorder()
    let client = GutenbergClient(fetch: fakeFetch(["https://gutendex.com/books": (200, searchJSON)], log: log))
    #expect(try await client.search("alice in", language: "en") == [alice])
    let url = await log.urls[0]
    #expect(url.contains("search=alice%20in") && url.contains("languages=en"))
}

@Test func searchFallsBackToOfficialCatalogWhenGutendexIsDown() async throws {
    let client = GutenbergClient(fetch: fakeFetch([
        "https://gutendex.com/books": (503, ""),
        "https://www.gutenberg.org/ebooks/search.opds/": (200, opdsXML),
    ]))
    #expect(try await client.search("alice") == [
        GutenbergBook(id: 11, title: "Alice's Adventures in Wonderland", authors: ["Lewis Carroll"], languages: []),
    ])
}

@Test func searchFailsWhenBothSourcesFail() async {
    let client = GutenbergClient(fetch: fakeFetch([:]))
    await #expect(throws: GutenbergError.self) { try await client.search("alice") }
}

@Test func downloadGivesCleanBookText() async throws {
    let raw = "license\n*** START OF THE PROJECT GUTENBERG EBOOK ALICE ***\nCHAPTER I.\nDown the Rabbit-Hole\n*** END OF THE PROJECT GUTENBERG EBOOK ALICE ***\n"
    let client = GutenbergClient(fetch: fakeFetch(["https://www.gutenberg.org/cache/epub/11/pg11.txt": (200, raw)]))
    let book = try await client.download(alice)
    #expect(book.title == "Alice's Adventures in Wonderland")
    #expect(book.text == "CHAPTER I. Down the Rabbit-Hole")
}

@Test func downloadOfMissingBookFails() async {
    let client = GutenbergClient(fetch: fakeFetch([:]))
    await #expect(throws: GutenbergError.self) { try await client.download(alice) }
}
