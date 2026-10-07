/// 읽기 자세: 화면과 얼굴의 거리, 화면을 보는 각도, 고개 기울기 (readme 11)
public struct HeadPose: Equatable, Sendable {
    public var distanceCm: Double
    public var yaw: Double  // 좌우로 돌린 각도(도)
    public var pitch: Double  // 숙이거나 젖힌 각도(도)
    public var roll: Double  // 옆으로 기울인 각도(도)
    public init(distanceCm: Double, yaw: Double, pitch: Double, roll: Double) {
        self.distanceCm = distanceCm; self.yaw = yaw; self.pitch = pitch; self.roll = roll
    }

    public init(_ m: FaceMeasure) {
        self.init(distanceCm: m.distanceCm, yaw: m.yawDeg, pitch: m.pitchDeg, roll: m.rollDeg)
    }
}

/// 나쁜 자세가 hold 초 넘게 이어지면 알린다.
///
/// 폰을 보는 고개 각도는 사람마다 달라서, 처음 baselineSamples 개 자세의 중간값을
/// 그 사람의 평소 각도로 삼고 그보다 maxHeadAngle 도 넘게 숙이거나 젖히면 알린다.
public final class PostureMonitor {
    public static let title = "독서 자세가 좋지 않습니다."
    public var minDistance: Double
    public var maxRoll: Double
    public var maxYaw: Double
    public var maxHeadAngle: Double
    public private(set) var baselinePitch: Double?
    private let baselineSamples: Int
    private var pitches: [Double] = []
    private var gate: Persistence

    public init(minDistance: Double = 30, maxRoll: Double = 15, maxYaw: Double = 25, maxHeadAngle: Double = 20,
                hold: Double = 10, cooldown: Double = 300, baselineSamples: Int = 30) {
        self.minDistance = minDistance
        self.maxRoll = maxRoll
        self.maxYaw = maxYaw
        self.maxHeadAngle = maxHeadAngle
        self.baselineSamples = baselineSamples
        gate = Persistence(hold: hold, cooldown: cooldown)
    }

    /// (종류, 지금 문제인가, 메시지)
    public func problems(_ p: HeadPose) -> [(kind: String, active: Bool, message: String)] {
        let angleOff = baselinePitch.map { abs(p.pitch - $0) > maxHeadAngle } ?? false
        return [
            ("too_close", p.distanceCm < minDistance, "화면과 얼굴이 너무 가깝습니다. (약 \(Int(p.distanceCm.rounded()))cm)"),
            ("tilted", abs(p.roll) > maxRoll, "고개가 한쪽으로 기울어져 있습니다."),
            ("turned", abs(p.yaw) > maxYaw, "화면을 비스듬히 보고 있습니다. 화면 정면에서 봐 주세요."),
            ("head_angle", angleOff, "고개를 평소보다 많이 숙이거나 젖히고 있습니다."),
        ]
    }

    public func update(_ pose: HeadPose?, t: Double) -> [Alert] {
        guard let p = pose else { gate.clear(); return [] }
        if baselinePitch == nil {
            pitches.append(p.pitch)
            if pitches.count >= baselineSamples { baselinePitch = pitches.sorted()[pitches.count / 2] }
        }
        return problems(p).compactMap { item in
            gate.check(item.kind, active: item.active, t: t) ? Alert(kind: item.kind, title: Self.title, message: item.message) : nil
        }
    }
}
