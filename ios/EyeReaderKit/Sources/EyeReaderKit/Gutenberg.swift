import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 무료 전자책: Project Gutenberg (readme 4·6)
/// - 검색: Gutendex 무료 JSON API(키 불필요). 자주 503 이 나서 실패하면 공식 OPDS 검색으로 대신한다.
/// - 다운로드: 공식 미러의 plain text (pg{id}.txt)
public struct GutenbergBook: Equatable, Sendable, Codable, Identifiable {
    public let id: Int
    public let title: String
    public let authors: [String]
    public let languages: [String]
    public init(id: Int, title: String, authors: [String], languages: [String]) {
        self.id = id; self.title = title; self.authors = authors; self.languages = languages
    }
}

public struct GutenbergError: Error, Equatable {
    public let message: String
}

public struct GutenbergClient: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> (Data, Int)
    let fetch: Fetch

    public init(fetch: @escaping Fetch = GutenbergClient.network) { self.fetch = fetch }

    public static let network: Fetch = { url in
        try await withCheckedThrowingContinuation { cont in
            URLSession.shared.dataTask(with: url) { data, response, error in
                if let error { return cont.resume(throwing: error) }
                cont.resume(returning: (data ?? Data(), (response as? HTTPURLResponse)?.statusCode ?? 0))
            }.resume()
        }
    }

    private func get(_ url: URL) async throws -> Data {
        let (data, status): (Data, Int)
        do { (data, status) = try await fetch(url) } catch { throw GutenbergError(message: "요청 실패: \(error)") }
        guard status == 200 else { throw GutenbergError(message: "요청 실패 (\(status)): \(url)") }
        return data
    }

    public func search(_ query: String, language: String? = nil) async throws -> [GutenbergBook] {
        do {
            return try await searchGutendex(query, language: language)
        } catch {
            do { return try await searchOPDS(query) } catch { throw GutenbergError(message: "검색 실패: \(error)") }
        }
    }

    private func searchGutendex(_ query: String, language: String?) async throws -> [GutenbergBook] {
        var c = URLComponents(string: "https://gutendex.com/books")!
        c.queryItems = [URLQueryItem(name: "search", value: query)] + (language.map { [URLQueryItem(name: "languages", value: $0)] } ?? [])
        struct Response: Decodable {
            struct Item: Decodable {
                struct Person: Decodable { let name: String }
                let id: Int; let title: String; let authors: [Person]?; let languages: [String]?
            }
            let results: [Item]
        }
        let r = try JSONDecoder().decode(Response.self, from: try await get(c.url!))
        return r.results.map { GutenbergBook(id: $0.id, title: $0.title, authors: ($0.authors ?? []).map(\.name), languages: $0.languages ?? []) }
    }

    private func searchOPDS(_ query: String) async throws -> [GutenbergBook] {
        var c = URLComponents(string: "https://www.gutenberg.org/ebooks/search.opds/")!
        c.queryItems = [URLQueryItem(name: "query", value: query)]
        let xml = String(decoding: try await get(c.url!), as: UTF8.self)
        func first(_ pattern: String, in s: String) -> String? {
            guard let r = s.range(of: pattern, options: .regularExpression) else { return nil }
            return String(s[r])
        }
        func inner(_ tag: String, in s: String) -> String? {
            first("<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", in: s).map {
                $0.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&apos;", with: "'").replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        var books: [GutenbergBook] = []
        var rest = xml[...]
        while let r = rest.range(of: "<entry>[\\s\\S]*?</entry>", options: .regularExpression) {
            let entry = String(rest[r])
            rest = rest[r.upperBound...]
            guard let idTag = first("/ebooks/[0-9]+\\.opds</id>", in: entry),  // '저자 목록' 같은 항목은 건너뜀
                  let id = Int(idTag.filter(\.isNumber)) else { continue }
            let author = inner("content", in: entry) ?? ""
            books.append(GutenbergBook(id: id, title: inner("title", in: entry) ?? "", authors: author.isEmpty ? [] : [author], languages: []))
        }
        return books
    }

    public func download(_ book: GutenbergBook) async throws -> Book {
        let url = URL(string: "https://www.gutenberg.org/cache/epub/\(book.id)/pg\(book.id).txt")!
        return Book(title: book.title, rawText: BookText.decode(try await get(url)))
    }
}
