/// 독서 도우미 알림
public struct Alert: Equatable, Sendable, Codable {
    public let kind: String  // 같은 종류는 쿨다운 동안 다시 내지 않는다
    public let title: String
    public let message: String
}

/// 상태가 hold 초 넘게 이어질 때만 알리고, 같은 종류는 cooldown 초 동안 다시 알리지 않는다.
struct Persistence {
    let hold: Double
    let cooldown: Double
    private var since: [String: Double] = [:]
    private var last: [String: Double] = [:]

    init(hold: Double, cooldown: Double) {
        self.hold = hold
        self.cooldown = cooldown
    }

    /// 판단할 수 없을 때(얼굴을 놓침 등): 이어지던 시간을 버린다.
    mutating func clear() { since.removeAll() }

    mutating func check(_ kind: String, active: Bool, t: Double) -> Bool {
        guard active else { since[kind] = nil; return false }
        let start = since[kind] ?? t
        since[kind] = start
        if t - start < hold { return false }
        if let l = last[kind], t - l < cooldown { return false }
        last[kind] = t
        return true
    }
}
