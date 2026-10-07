import EyeReaderKit
import SwiftUI
import UIKit

/// 읽기 화면의 상태. 초당 30번 Face ID 카메라 값을 받아 ReadingSession 을 한 걸음씩 돌린다.
@MainActor
final class ReaderModel: ObservableObject {
    struct Toast: Identifiable {
        let id = UUID()
        let alert: EyeReaderKit.Alert  // SwiftUI 의 Alert 와 이름이 같아서 모듈 이름을 붙인다
        let until: TimeInterval
    }

    static let fontSize: CGFloat = 21
    @Published private(set) var frame = 0  // 바뀔 때마다 화면을 다시 그린다
    @Published private(set) var toasts: [Toast] = []
    @Published var showHeatmap = false
    @Published var showGaze = true
    private(set) var session: ReadingSession?
    private(set) var textArea = Rect(x: 0, y: 0, width: 0, height: 0)
    private var size: CGSize = .zero
    private var timer: Timer?
    private weak var face: FaceTracker?
    var calibrator: Calibrator?

    /// 화면 크기에 맞춰 책을 페이지로 나눈다(전체 화면 좌표, 위는 다이내믹 아일랜드, 아래는 상태줄 자리).
    func setUp(book: Book, size: CGSize, face: FaceTracker, calibrator: Calibrator?) {
        self.face = face
        self.calibrator = calibrator
        guard session == nil || self.size != size, size.width > 0 else { return }
        self.size = size
        let area = Rect(x: 24, y: 80, width: Double(size.width) - 48, height: Double(size.height) - 80 - 130)
        textArea = area
        let font = UIFont.systemFont(ofSize: Self.fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        func width(_ s: String) -> Double { Double((s as NSString).size(withAttributes: attrs).width) }
        let pages = paginate(book.text, width: area.width, height: area.height, measure: width,
                             lineHeight: Double((font.lineHeight * 2.1).rounded()),  // 줄 간격을 넓혀 세로 오차를 흡수
                             spaceWidth: width(" "), origin: Point(x: area.x, y: area.y))
        session = ReadingSession(pages: pages, heatmapWidth: Double(size.width), heatmapHeight: Double(size.height),
                                 heatmapCell: 30)
    }

    func start() {
        face?.start()
        UIApplication.shared.isIdleTimerDisabled = true  // 읽는 동안 화면이 꺼지지 않게
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        face?.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func tick() {
        guard let session else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let measure = face?.current(at: now)
        let gaze = measure?.gazeFeature.flatMap { calibrator?.predict($0) }
        let reading = measure.map { FaceReading($0) }
        let alerts = session.step(gaze: gaze, face: reading, t: now, textArea: textArea)
        toasts.removeAll { $0.until < now }
        toasts += alerts.map { Toast(alert: $0, until: now + 6) }
        frame &+= 1
    }

    func turn(_ delta: Int) {
        guard let session else { return }
        session.goTo(session.pageIndex + delta)
        frame &+= 1
    }

    var statusText: String {
        guard let s = session else { return "" }
        let st = s.coach.status
        let focus = st.focus.map(String.init) ?? "-"
        let posture = st.postureOK.map { $0 ? "좋음" : "확인 필요" } ?? "-"
        let distance = st.distanceCm.map { "\(Int($0.rounded()))cm" } ?? "-"
        return "\(s.pageIndex + 1)/\(s.pages.count)쪽 · \(Int(s.speed.wpm)) WPM · 집중 \(focus) · 자세 \(posture) · 거리 \(distance) · 독서 \(Int(st.readingMinutes))분"
    }

    func finish(title: String) -> ReadingReport? {
        stop()
        guard let session else { return nil }
        return session.coach.report(title: title, heatmaps: session.heatmaps)
    }

    /// 읽기 화면 그리기: 읽는 줄(노랑)·단어(주황)·읽은 단어(회색)·heatmap·시선 점
    func draw(_ ctx: GraphicsContext) {
        guard let s = session else { return }
        let tracker = s.tracker
        if let li = tracker.lineIndex, li < tracker.lines.count {
            let first = tracker.lines[li].words.first!.frame, last = tracker.lines[li].words.last!.frame
            let rect = CGRect(x: first.x - 6, y: first.y, width: last.maxX - first.x + 12, height: first.height)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(Theme.lineHighlight))
        }
        if let w = tracker.word {
            let rect = CGRect(x: w.frame.x - 3, y: w.frame.y + 4, width: w.frame.width + 6, height: w.frame.height - 8)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(Theme.wordHighlight))
        }
        let furthest = tracker.furthest?.index ?? -1
        for word in s.page.words {
            let color = word.index < furthest && word != tracker.word ? Theme.read : Theme.text
            ctx.draw(Text(word.text).font(.system(size: Self.fontSize)).foregroundColor(color),
                     at: CGPoint(x: word.frame.x, y: word.center.y), anchor: .leading)
        }
        if showHeatmap {
            let map = s.heatmaps.page(s.pageIndex)
            for (r, row) in map.normalized().enumerated() {
                for (c, value) in row.enumerated() where value > 0 {
                    let rect = CGRect(x: Double(c) * map.cell, y: Double(r) * map.cell, width: map.cell, height: map.cell)
                    ctx.fill(Path(rect), with: .color(Theme.heat.opacity(0.15 + 0.5 * value)))
                }
            }
        }
        if showGaze, let g = s.gaze {
            ctx.stroke(Path(ellipseIn: CGRect(x: g.x - 9, y: g.y - 9, width: 18, height: 18)), with: .color(.red), lineWidth: 2)
        }
    }
}
