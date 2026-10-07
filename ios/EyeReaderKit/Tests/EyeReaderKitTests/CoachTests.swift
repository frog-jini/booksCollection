import Foundation
import Testing
@testable import EyeReaderKit

// --- heatmap ---

@Test func heatmapAddsTimeToCellUnderGaze() {
    var h = GazeHeatmap(width: 400, height: 200, cell: 100)
    h.add(Point(x: 150, y: 50), seconds: 0.5)
    h.add(Point(x: 160, y: 60), seconds: 0.25)
    h.add(Point(x: 350, y: 150), seconds: 1)
    h.add(Point(x: -5, y: 50), seconds: 9)  // 화면 밖은 무시
    #expect(h.rows == 2 && h.columns == 4)
    #expect(h[0, 1] == 0.75 && h[1, 3] == 1)
    #expect(h.totalSeconds == 1.75)
    #expect(h.normalized()[0][1] == 0.75 && h.normalized()[1][3] == 1)
    #expect(h.hottest(1).map(\.center) == [Point(x: 350, y: 150)])
}

@Test func eachPageHasItsOwnHeatmap() {
    var maps = PageHeatmaps(width: 200, height: 100, cell: 100)
    maps.add(page: 0, Point(x: 50, y: 50), seconds: 1)
    maps.add(page: 3, Point(x: 150, y: 50), seconds: 2)
    maps.add(page: 3, Point(x: 150, y: 50), seconds: 2)
    #expect(maps.pages.keys.sorted() == [0, 3])
    #expect(maps.pages[3]!.totalSeconds == 4)
}

// --- 코치 ---

let good = HeadPose(distanceCm: 38, yaw: 0, pitch: 0, roll: 0)

func coached(_ c: ReadingCoach, for seconds: Double, from start: Double = 0, pose: HeadPose? = good,
             openness: Double? = 0.9, present: Bool = true, onTarget: Bool = true) -> ([Alert], Double) {
    var alerts: [Alert] = [], t = start
    while t < start + seconds {
        alerts += c.update(t: t, pose: pose, openness: openness, present: present, onTarget: onTarget)
        t += 0.5
    }
    return (alerts, t)
}

func testCoach() -> ReadingCoach {
    ReadingCoach(posture: PostureMonitor(hold: 5, baselineSamples: 2), timer: ReadingTimer(breakAfter: 60),
                 drowsiness: DrowsinessMonitor(microsleep: 1))
}

@Test func coachPassesOnAlertsFromEveryPart() {
    let c = testCoach()
    var (alerts, t) = coached(c, for: 2)
    alerts += coached(c, for: 8, from: t, pose: HeadPose(distanceCm: 20, yaw: 0, pitch: 0, roll: 0)).0
    t = 10
    alerts += coached(c, for: 60, from: t).0
    alerts += coached(c, for: 2, from: 70, openness: 0.05).0
    #expect(alerts.map(\.kind) == ["too_close", "break", "drowsy"])
}

@Test func coachStatusForScreen() {
    let c = testCoach()
    _ = coached(c, for: 30)
    let s = c.status
    #expect(s.focus == 100 && s.postureOK == true && s.distanceCm == 38)
    #expect(abs(s.readingMinutes - 0.5) < 0.02)
}

@Test func reportSummarizesSessionAndSavesAsJSON() throws {
    let c = testCoach()
    var t = coached(c, for: 2).1
    t = coached(c, for: 8, from: t, pose: HeadPose(distanceCm: 20, yaw: 0, pitch: 0, roll: 0)).1
    t = coached(c, for: 50, from: t).1
    t = coached(c, for: 10, from: t, pose: nil, openness: nil, present: false, onTarget: false).1
    _ = coached(c, for: 70, from: t)
    var maps = PageHeatmaps(width: 100, height: 100, cell: 50)
    maps.add(page: 0, Point(x: 10, y: 10), seconds: 3)

    let r = c.report(title: "앨리스", heatmaps: maps)
    #expect(r.title == "앨리스")
    #expect(abs(r.readingMinutes - 130.0 / 60) < 0.05)
    #expect(abs(r.awayMinutes - 10.0 / 60) < 0.05)
    #expect(r.lookAways == 1)
    #expect(r.alerts == ["too_close": 1, "break": 1])
    #expect(r.focusPerMinute.count == 2)
    #expect(r.pages.map(\.page) == [1] && r.pages[0].seconds == 3)

    let data = try r.jsonData()
    #expect(String(decoding: data, as: UTF8.self).contains("앨리스"))
    let back = try JSONDecoder().decode(ReadingReport.self, from: data)
    #expect(back == r)
}

@Test func reportFileNameIsSafeAndDated() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let date = cal.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 14, minute: 5))!
    #expect(ReadingReport.fileName(title: "앨리스: 1/2", date: date, calendar: cal) == "앨리스_1_2-20261007-1405.json")
}
