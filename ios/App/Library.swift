import EyeReaderKit
import Foundation
import PDFKit

/// 서재: 앱의 문서 폴더(파일 앱에서도 보임)에 책(txt)·보고서(json)·보정값을 저장한다.
@MainActor
final class Library: ObservableObject {
    struct StoredBook: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
        var title: String { url.deletingPathExtension().lastPathComponent }
    }

    enum ImportError: LocalizedError {
        case unreadable
        var errorDescription: String? { "이 파일에서 글자를 읽을 수 없습니다(사진으로 스캔한 PDF 등)." }
    }

    @Published private(set) var books: [StoredBook] = []
    @Published var calibrator: Calibrator? {
        didSet {
            if let c = calibrator, let data = try? JSONEncoder().encode(c) {
                UserDefaults.standard.set(data, forKey: "calibration")
            }
        }
    }

    let booksDir: URL
    let reportsDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        booksDir = docs.appendingPathComponent("books", isDirectory: true)
        reportsDir = docs.appendingPathComponent("reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        if let data = UserDefaults.standard.data(forKey: "calibration") {
            calibrator = try? JSONDecoder().decode(Calibrator.self, from: data)
        }
        reload()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: booksDir, includingPropertiesForKeys: nil)) ?? []
        books = urls.filter { $0.pathExtension == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { StoredBook(url: $0) }
    }

    func load(_ book: StoredBook) -> Book {
        Book(title: book.title, rawText: BookText.decode((try? Data(contentsOf: book.url)) ?? Data()))
    }

    /// 파일 앱에서 고른 txt·pdf 를 서재로 가져온다(txt 로 저장).
    func importFile(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let text: String
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url), let s = doc.string, !s.isEmpty else { throw ImportError.unreadable }
            text = s
        } else {
            text = BookText.decode(try Data(contentsOf: url))
        }
        try save(title: url.deletingPathExtension().lastPathComponent, text: text)
    }

    func save(title: String, text: String) throws {
        let safe = title.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        try text.write(to: booksDir.appendingPathComponent(safe + ".txt"), atomically: true, encoding: .utf8)
        reload()
    }

    func delete(_ book: StoredBook) {
        try? FileManager.default.removeItem(at: book.url)
        reload()
    }

    func saveReport(_ report: ReadingReport) -> URL? {
        let url = reportsDir.appendingPathComponent(ReadingReport.fileName(title: report.title, date: Date()))
        do {
            try report.jsonData().write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
