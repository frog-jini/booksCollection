/// 카메라에서 받은 얼굴 정보(ARKit). 얼굴을 놓치면 nil.
public struct FaceReading: Sendable {
    public var pose: HeadPose?
    public var openness: Double?
    public init(pose: HeadPose?, openness: Double?) { self.pose = pose; self.openness = openness }
    public init(_ m: FaceMeasure) { self.init(pose: HeadPose(m), openness: m.eyeOpenness) }
}

/// 화면 없이 돌아가는 읽기 흐름: 시선 → 읽는 단어 → 읽기 속도 → 자동 페이지 넘김,
/// 그리고 독서 코치(자세·휴식·졸음·집중도)와 페이지별 heatmap. 화면(SwiftUI)은 이 상태를 그리기만 한다.
public final class ReadingSession {
    public let pages: [Page]
    public private(set) var pageIndex = 0
    public let tracker: ReadingTracker
    public let speed = ReadingSpeed()
    public let smoother = GazeSmoother(alpha: 0.35, snapDistance: 120)
    public let coach: ReadingCoach
    public private(set) var heatmaps: PageHeatmaps
    public private(set) var gaze: Point?
    public var paused = false  // 설명 창 등을 보는 동안
    private var lastT: Double?

    public init(pages: [Page], coach: ReadingCoach = ReadingCoach(),
                heatmapWidth: Double = 1000, heatmapHeight: Double = 2000, heatmapCell: Double = 40) {
        self.pages = pages.isEmpty ? [Page()] : pages
        tracker = ReadingTracker(page: self.pages[0])
        self.coach = coach
        heatmaps = PageHeatmaps(width: heatmapWidth, height: heatmapHeight, cell: heatmapCell)
    }

    public var page: Page { pages[pageIndex] }

    public func goTo(_ index: Int) {
        pageIndex = min(max(index, 0), pages.count - 1)
        tracker.reset(page: page)
    }

    /// 한 프레임. textArea 는 글이 있는 영역(이 안을 보면 '책을 보는 중').
    @discardableResult
    public func step(gaze raw: Point?, face: FaceReading?, t: Double, textArea: Rect) -> [Alert] {
        let dt = lastT.map { min(max(t - $0, 0), 0.5) } ?? 0
        lastT = t
        gaze = smoother.update(raw)
        let present = face != nil
        if present, let g = gaze { heatmaps.add(page: pageIndex, g, seconds: dt) }

        if !paused {
            tracker.update(gaze: gaze, t: t)
            if let f = tracker.furthest { speed.update(wordIndex: f.index, t: t) }
            tracker.turnDwell = speed.turnDwell()  // 방금 잰 읽기 속도에 맞춰 넘김 대기
            if tracker.shouldTurn && pageIndex < pages.count - 1 { goTo(pageIndex + 1) }
        }
        let onTarget = present && gaze.map { textArea.insetBy(-20).contains($0) } == true
        return coach.update(t: t, pose: face?.pose, openness: face?.openness, present: present, onTarget: onTarget)
    }
}
