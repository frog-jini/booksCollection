import Testing
@testable import EyeReaderKit

let goodPose = HeadPose(distanceCm: 38, yaw: 0, pitch: 0, roll: 0)

func pose(distance: Double = 38, yaw: Double = 0, pitch: Double = 0, roll: Double = 0) -> HeadPose {
    HeadPose(distanceCm: distance, yaw: yaw, pitch: pitch, roll: roll)
}

/// seconds 동안 같은 자세를 0.5초마다 보내고 나온 알림을 모은다.
func feed(_ m: PostureMonitor, _ p: HeadPose?, from start: Double, for seconds: Double) -> ([Alert], Double) {
    var alerts: [Alert] = [], t = start
    while t < start + seconds { alerts += m.update(p, t: t); t += 0.5 }
    return (alerts, t)
}

func postureMonitor(minDistance: Double = 30) -> PostureMonitor {
    let m = PostureMonitor(minDistance: minDistance, hold: 10, cooldown: 300, baselineSamples: 4)
    _ = feed(m, goodPose, from: 0, for: 2)
    return m
}

@Test func goodPostureNeverAlerts() {
    #expect(feed(postureMonitor(), goodPose, from: 2, for: 600).0.isEmpty)
}

@Test func tooCloseAlertsOnlyAfterItLastsAndRespectsCooldown() {
    let m = postureMonitor()
    var (alerts, t) = feed(m, pose(distance: 22), from: 2, for: 9)
    #expect(alerts.isEmpty)
    (alerts, t) = feed(m, pose(distance: 22), from: t, for: 200)
    #expect(alerts.map(\.kind) == ["too_close"])
    #expect(alerts[0].title == "독서 자세가 좋지 않습니다.")
    #expect(alerts[0].message.contains("화면과 얼굴이 너무 가깝습니다") && alerts[0].message.contains("22cm"))
    (alerts, _) = feed(m, pose(distance: 22), from: t, for: 200)
    #expect(alerts.count == 1)  // 5분이 지나서 한 번 더
}

@Test func shortGoodMomentOrLostFaceRestartsTheClock() {
    let m = postureMonitor()
    var (_, t) = feed(m, pose(distance: 22), from: 2, for: 8)
    (_, t) = feed(m, goodPose, from: t, for: 1)
    var (alerts, t2) = feed(m, pose(distance: 22), from: t, for: 8)
    #expect(alerts.isEmpty)
    (_, t2) = feed(m, nil, from: t2, for: 5)
    (alerts, _) = feed(m, pose(distance: 22), from: t2, for: 8)
    #expect(alerts.isEmpty)
}

@Test(arguments: [
    (pose(roll: 25), "tilted", "기울어져"),
    (pose(yaw: -35), "turned", "비스듬히"),
    (pose(pitch: 30), "head_angle", "고개"),
    (pose(pitch: -30), "head_angle", "고개"),
])
func eachProblemHasItsOwnMessage(p: HeadPose, kind: String, words: String) {
    let alerts = feed(postureMonitor(), p, from: 2, for: 12).0
    #expect(alerts.map(\.kind) == [kind])
    #expect(alerts[0].message.contains(words))
}

@Test func headAngleIsJudgedAgainstReadersUsualPosture() {
    let m = PostureMonitor(hold: 10, baselineSamples: 4)
    _ = feed(m, pose(pitch: 20), from: 0, for: 2)  // 이 사람은 평소 20° 숙여서 폰을 본다
    #expect(feed(m, pose(pitch: 35), from: 2, for: 12).0.isEmpty)
    #expect(feed(m, pose(pitch: 50), from: 14, for: 12).0.map(\.kind) == ["head_angle"])
}

@Test func thresholdsCanBeChanged() {
    #expect(feed(postureMonitor(minDistance: 20), pose(distance: 22), from: 2, for: 12).0.isEmpty)
}

@Test func headPoseFromFaceMeasure() {
    let s = FaceSample(faceTransform: Mat4.pose(position: Vec3(0, 0, -0.3), yawDeg: 10, pitchDeg: 0, rollDeg: 0),
                       cameraTransform: .identity, lookAtPoint: Vec3(0, 0, 1), blinkLeft: 0, blinkRight: 0)
    let p = HeadPose(FaceMeasure(s))
    #expect(abs(p.distanceCm - 30) < 1e-6 && abs(abs(p.yaw) - 10) < 1e-6)
}
