import EyeReaderKit
import SwiftUI
import UniformTypeIdentifiers

/// 첫 화면: 보정, 샘플 책, 내 책(가져온 파일·내려받은 책), 무료 책 검색
struct LibraryView: View {
    struct OpenBook: Identifiable {
        let id = UUID()
        let book: Book
    }

    @EnvironmentObject private var library: Library
    @State private var openBook: OpenBook?
    @State private var importing = false
    @State private var searching = false
    @State private var calibrating = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section("시작하기") {
                    Button {
                        calibrating = true
                    } label: {
                        Label(library.calibrator == nil ? "시선 보정하기 (처음 한 번)" : "시선 다시 보정하기", systemImage: "eye")
                    }
                    Button {
                        openBook = OpenBook(book: Book(title: SampleBook.title, rawText: SampleBook.text))
                    } label: {
                        Label("샘플 책 읽기", systemImage: "book")
                    }
                }
                Section("내 책") {
                    if library.books.isEmpty {
                        Text("아래 버튼으로 txt·pdf 파일을 가져오거나 무료 책을 검색하세요.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(library.books) { stored in
                        Button(stored.title) { openBook = OpenBook(book: library.load(stored)) }
                    }
                    .onDelete { offsets in
                        for book in offsets.map({ library.books[$0] }) { library.delete(book) }
                    }
                }
            }
            .navigationTitle("눈으로 읽기")
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { importing = true } label: { Label("파일 가져오기", systemImage: "square.and.arrow.down") }
                    Spacer()
                    Button { searching = true } label: { Label("무료 책 검색", systemImage: "magnifyingglass") }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text, .pdf]) { result in
                do {
                    try library.importFile(try result.get())
                } catch {
                    errorText = error.localizedDescription
                }
            }
            .sheet(isPresented: $searching) { GutenbergSearchView() }
            .fullScreenCover(isPresented: $calibrating) { CalibrationView() }
            .fullScreenCover(item: $openBook) { open in ReaderView(book: open.book) }
            .alert("오류", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }
}

/// 무료 책 검색(Project Gutenberg) → 내려받아 서재에 저장 (readme 4·6)
struct GutenbergSearchView: View {
    @EnvironmentObject private var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var englishOnly = true
    @State private var results: [GutenbergBook] = []
    @State private var busy = false
    @State private var message: String?
    private let client = GutenbergClient()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("제목이나 작가 (예: alice, sherlock)", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(search)
                    Toggle("영어 책만", isOn: $englishOnly)
                    Button("검색", action: search).disabled(busy)
                }
                if busy { ProgressView() }
                if let message { Text(message).foregroundStyle(.secondary) }
                ForEach(results) { book in
                    Button { download(book) } label: {
                        VStack(alignment: .leading) {
                            Text(book.title)
                            Text(book.authors.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(busy)
                }
            }
            .navigationTitle("무료 책")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        busy = true
        message = nil
        Task {
            do {
                results = try await client.search(q, language: englishOnly ? "en" : nil)
                message = results.isEmpty ? "검색 결과가 없습니다." : "책을 누르면 내려받아 서재에 넣습니다."
            } catch {
                message = "검색하지 못했습니다. 잠시 뒤 다시 해 보세요."
            }
            busy = false
        }
    }

    private func download(_ book: GutenbergBook) {
        busy = true
        message = "내려받는 중…"
        Task {
            do {
                let downloaded = try await client.download(book)
                try library.save(title: downloaded.title, text: downloaded.text)
                dismiss()
            } catch {
                message = "내려받지 못했습니다: \(error.localizedDescription)"
            }
            busy = false
        }
    }
}
