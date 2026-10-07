import EyeReaderKit
import SwiftUI

/// 읽기 화면: 눈으로 읽는 위치 표시·자동 넘김 + 독서 도우미 알림(readme 11)
struct ReaderView: View {
    let book: Book
    @EnvironmentObject private var library: Library
    @EnvironmentObject private var face: FaceTracker
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ReaderModel()
    @State private var calibrating = false
    @State private var report: ReadingReport?
    @State private var reportURL: URL?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Theme.background
                Canvas { ctx, _ in
                    _ = model.frame  // frame 이 바뀔 때마다 다시 그린다
                    model.draw(ctx)
                }
                VStack(spacing: 8) {
                    ForEach(model.toasts) { toast in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(toast.alert.title).font(.subheadline.bold())
                            Text(toast.alert.message).font(.subheadline)
                        }
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(Theme.toast, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let error = face.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.white).padding(10)
                            .background(.red, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.top, 56)
                VStack(spacing: 10) {
                    Spacer()
                    Text(model.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 22) {
                        Button { model.turn(-1) } label: { Image(systemName: "chevron.left") }
                        Button { model.showGaze.toggle() } label: {
                            Image(systemName: model.showGaze ? "scope" : "circle.dashed")
                        }
                        Button { model.showHeatmap.toggle() } label: {
                            Image(systemName: model.showHeatmap ? "flame.fill" : "flame")
                        }
                        Button { calibrating = true } label: { Image(systemName: "eye") }
                        Button("끝내기") { finish() }.font(.body.bold())
                        Button { model.turn(1) } label: { Image(systemName: "chevron.right") }
                    }
                    .font(.title3)
                    .padding(.bottom, 34)
                }
            }
            .onAppear {
                model.setUp(book: book, size: geo.size, face: face, calibrator: library.calibrator)
                model.start()
                if library.calibrator == nil { calibrating = true }
            }
            .onDisappear { model.stop() }
        }
        .ignoresSafeArea()
        .gesture(DragGesture(minimumDistance: 40).onEnded { value in
            if value.translation.width < -60 { model.turn(1) }
            if value.translation.width > 60 { model.turn(-1) }
        })
        .fullScreenCover(isPresented: $calibrating, onDismiss: {
            model.calibrator = library.calibrator
            model.start()
        }) {
            CalibrationView()
        }
        .sheet(item: $report, onDismiss: { dismiss() }) { r in
            ReportView(report: r, fileURL: reportURL)
        }
    }

    private func finish() {
        guard let r = model.finish(title: book.title) else { return dismiss() }
        reportURL = library.saveReport(r)
        report = r
    }
}

extension ReadingReport: Identifiable {
    public var id: String { title + String(readingMinutes) }
}

/// 독서가 끝나면 보여 주는 요약. JSON 보고서는 공유(파일 앱·AirDrop 등)할 수 있다.
struct ReportView: View {
    let report: ReadingReport
    let fileURL: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("오늘의 독서") {
                    row("읽은 시간", "\(Int(report.readingMinutes.rounded()))분")
                    row("화면을 벗어난 시간", String(format: "%.1f분", report.awayMinutes) + " (\(report.lookAways)번)")
                    row("평균 집중도", report.focusAverage.map { "\(Int($0.rounded()))점" } ?? "-")
                    row("분당 깜빡임", String(format: "%.0f회", report.blinkRatePerMinute))
                    row("눈 감은 시간 비율(PERCLOS)", String(format: "%.0f%%", report.perclos * 100))
                    row("평균 화면 거리", report.averageDistanceCm.map { "\(Int($0.rounded()))cm" } ?? "-")
                }
                if !report.alerts.isEmpty {
                    Section("알림") {
                        ForEach(report.alerts.sorted { $0.key < $1.key }, id: \.key) { item in
                            row(Self.names[item.key] ?? item.key, "\(item.value)번")
                        }
                    }
                }
                if let fileURL {
                    Section { ShareLink("보고서(JSON) 공유", item: fileURL) }
                }
            }
            .navigationTitle(report.title)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
    }

    static let names = ["too_close": "화면에 너무 가까움", "tilted": "고개 기울어짐", "turned": "비스듬히 봄",
                        "head_angle": "고개 숙임·젖힘", "break": "휴식 권유", "drowsy": "졸음"]

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary) }
    }
}
