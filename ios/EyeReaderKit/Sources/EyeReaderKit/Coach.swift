import Foundation

/// 독서 코치: 자세·휴식·졸음·집중도를 한 번에 돌리고, 독서가 끝나면 보고서를 만든다.
/// 책 내용은 보지 않는다(얼굴과 시선만 본다).
public final class ReadingCoach {
    public let posture: PostureMonitor
    public let timer: ReadingTimer
    public let drowsiness: DrowsinessMonitor
    public let focus: FocusMeter
    public private(set) var pose: HeadPose?
    public private(set) var alertCounts: [String: Int] = [:]
    private var distances: [Double] = []

    public init(posture: PostureMonitor = PostureMonitor(), timer: ReadingTimer = ReadingTimer(),
                drowsiness: DrowsinessMonitor = DrowsinessMonitor(), focus: FocusMeter = FocusMeter()) {
        self.posture = posture
        self.timer = timer
        self.drowsiness = drowsiness
        self.focus = focus
    }

    /// 한 프레임. present = 얼굴이 화면 앞에 있나, onTarget = 책을 보고 있나.
    public func update(t: Double, pose: HeadPose?, openness: Double?, present: Bool, onTarget: Bool) -> [Alert] {
        self.pose = pose
        if let p = pose { distances.append(p.distanceCm) }
        focus.update(onTarget: onTarget, t: t)
        let alerts = posture.update(pose, t: t) + timer.update(present: present, t: t)
            + drowsiness.update(openness: openness, t: t)
        for a in alerts { alertCounts[a.kind, default: 0] += 1 }
        return alerts
    }

    public struct Status: Equatable, Sendable {
        public let focus: Int?
        public let readingMinutes: Double
        public let continuousMinutes: Double
        public let blinkRate: Double
        public let distanceCm: Double?
        public let postureOK: Bool?
    }

    public var status: Status {
        Status(focus: focus.score,
               readingMinutes: timer.readingSeconds / 60,
               continuousMinutes: timer.continuousSeconds / 60,
               blinkRate: drowsiness.blinkRate,
               distanceCm: pose?.distanceCm,
               postureOK: pose.map { p in !posture.problems(p).contains { $0.active } })
    }

    public func report(title: String, heatmaps: PageHeatmaps? = nil) -> ReadingReport {
        let pages = (heatmaps?.pages ?? [:]).sorted { $0.key < $1.key }.map { page, map in
            ReadingReport.PageSummary(page: page + 1, seconds: map.totalSeconds, hottest: map.hottest(3))
        }
        let history = focus.history
        return ReadingReport(
            title: title,
            readingMinutes: timer.readingSeconds / 60,
            awayMinutes: timer.awaySeconds / 60,
            lookAways: timer.lookAways,
            focusPerMinute: history,
            focusAverage: history.isEmpty ? nil : Double(history.reduce(0, +)) / Double(history.count),
            blinkRatePerMinute: drowsiness.blinkRate,
            perclos: drowsiness.perclos,
            longEyeClosures: drowsiness.longClosures,
            averageDistanceCm: distances.isEmpty ? nil : distances.reduce(0, +) / Double(distances.count),
            alerts: alertCounts,
            pages: pages)
    }
}

/// 독서 보고서. 집중도·피로도 연구용 데이터로 쓸 수 있게 JSON 으로 저장한다.
public struct ReadingReport: Codable, Equatable, Sendable {
    public struct PageSummary: Codable, Equatable, Sendable {
        public let page: Int
        public let seconds: Double
        public let hottest: [HotCell]
    }

    public let title: String
    public let readingMinutes: Double
    public let awayMinutes: Double
    public let lookAways: Int
    public let focusPerMinute: [Int]
    public let focusAverage: Double?
    public let blinkRatePerMinute: Double
    public let perclos: Double
    public let longEyeClosures: Int
    public let averageDistanceCm: Double?
    public let alerts: [String: Int]
    public let pages: [PageSummary]

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func fileName(title: String, date: Date, calendar: Calendar = .current) -> String {
        var safe = ""
        for ch in title {
            if ch.isWhitespace || "\\/:*?\"<>|".contains(ch) {
                if !safe.hasSuffix("_") { safe.append("_") }
            } else {
                safe.append(ch)
            }
        }
        safe = safe.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(format: "%04d%02d%02d-%02d%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!)
        return "\(safe.isEmpty ? "reading" : safe)-\(stamp).json"
    }
}
