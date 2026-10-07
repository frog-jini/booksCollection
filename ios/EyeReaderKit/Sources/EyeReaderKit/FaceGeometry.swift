import Foundation

/// ARKit 얼굴 추적 결과를 거리·각도·시선 위치로 바꾸는 계산.
/// simd/ARKit 없이 테스트할 수 있게 작은 벡터·행렬 타입을 직접 쓴다(앱에서 simd 값을 옮겨 담는다).

public struct Vec3: Equatable, Sendable {
    public var x, y, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }
    public var length: Double { (x * x + y * y + z * z).squareRoot() }
}

/// 4×4 변환 행렬. simd 처럼 열 우선: m[열][행].
public struct Mat4: Equatable, Sendable {
    public var m: [[Double]]
    public init(columns: [[Double]]) { m = columns }

    public static let identity = Mat4(columns: [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]])

    public var translation: Vec3 { Vec3(m[3][0], m[3][1], m[3][2]) }

    public func transform(point p: Vec3) -> Vec3 {
        Vec3(m[0][0] * p.x + m[1][0] * p.y + m[2][0] * p.z + m[3][0],
             m[0][1] * p.x + m[1][1] * p.y + m[2][1] * p.z + m[3][1],
             m[0][2] * p.x + m[1][2] * p.y + m[2][2] * p.z + m[3][2])
    }

    public func rotate(_ v: Vec3) -> Vec3 {
        Vec3(m[0][0] * v.x + m[1][0] * v.y + m[2][0] * v.z,
             m[0][1] * v.x + m[1][1] * v.y + m[2][1] * v.z,
             m[0][2] * v.x + m[1][2] * v.y + m[2][2] * v.z)
    }

    public static func * (a: Mat4, b: Mat4) -> Mat4 {
        var out = [[Double]](repeating: [0, 0, 0, 0], count: 4)
        for c in 0..<4 { for r in 0..<4 { out[c][r] = (0..<4).reduce(0) { $0 + a.m[$1][r] * b.m[c][$1] } } }
        return Mat4(columns: out)
    }

    /// 회전+이동만 있는 변환의 역행렬
    public func inverseRigid() -> Mat4 {
        var out = Mat4.identity.m
        for c in 0..<3 { for r in 0..<3 { out[c][r] = m[r][c] } }  // 회전은 전치
        let t = translation
        for r in 0..<3 { out[3][r] = -(out[0][r] * t.x + out[1][r] * t.y + out[2][r] * t.z) }
        return Mat4(columns: out)
    }

    /// 위치 + 회전(yaw → pitch → roll 순, 도 단위)으로 만든 변환. 테스트·시뮬레이션용.
    public static func pose(position p: Vec3, yawDeg: Double, pitchDeg: Double, rollDeg: Double) -> Mat4 {
        let (y, x, z) = (yawDeg * .pi / 180, pitchDeg * .pi / 180, rollDeg * .pi / 180)
        let ry = Mat4(columns: [[cos(y), 0, -sin(y), 0], [0, 1, 0, 0], [sin(y), 0, cos(y), 0], [0, 0, 0, 1]])
        let rx = Mat4(columns: [[1, 0, 0, 0], [0, cos(x), sin(x), 0], [0, -sin(x), cos(x), 0], [0, 0, 0, 1]])
        let rz = Mat4(columns: [[cos(z), sin(z), 0, 0], [-sin(z), cos(z), 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]])
        var out = ry * rx * rz
        out.m[3] = [p.x, p.y, p.z, 1]
        return out
    }
}

/// ARKit 한 장면에서 앱이 넘겨주는 값
public struct FaceSample: Sendable {
    public var faceTransform: Mat4  // ARFaceAnchor.transform (세계 좌표)
    public var cameraTransform: Mat4  // ARFrame.camera.transform (세계 좌표)
    public var lookAtPoint: Vec3  // ARFaceAnchor.lookAtPoint (얼굴 좌표)
    public var blinkLeft: Double  // blendShapes[.eyeBlinkLeft] 0…1
    public var blinkRight: Double
    public init(faceTransform: Mat4, cameraTransform: Mat4, lookAtPoint: Vec3, blinkLeft: Double, blinkRight: Double) {
        self.faceTransform = faceTransform
        self.cameraTransform = cameraTransform
        self.lookAtPoint = lookAtPoint
        self.blinkLeft = blinkLeft
        self.blinkRight = blinkRight
    }
}

/// 카메라(=폰 화면 평면) 기준으로 잰 얼굴 정보
public struct FaceMeasure: Sendable {
    public let headPosition: Vec3  // m, 카메라 기준
    public let distanceCm: Double
    public let yawDeg: Double  // 좌우로 돌린 각도
    public let pitchDeg: Double  // 숙이거나 젖힌 각도
    public let rollDeg: Double  // 옆으로 기울인 각도
    public let screenHit: Point?  // 시선이 화면 평면(카메라 z=0)에 닿는 점(m). 화면 반대쪽을 보면 nil
    public let eyeOpenness: Double  // 1 = 활짝, 0 = 감음

    public init(_ s: FaceSample) {
        let face = s.cameraTransform.inverseRigid() * s.faceTransform
        let pos = face.translation
        headPosition = pos
        distanceCm = pos.length * 100

        let forward = face.rotate(Vec3(0, 0, 1))  // 얼굴이 향하는 방향
        yawDeg = atan2(forward.x, forward.z) * 180 / .pi
        pitchDeg = atan2(-forward.y, (forward.x * forward.x + forward.z * forward.z).squareRoot()) * 180 / .pi
        // 돌림·숙임을 되돌린 뒤 남는 회전이 기울기
        let undo = Mat4.pose(position: Vec3(0, 0, 0), yawDeg: yawDeg, pitchDeg: pitchDeg, rollDeg: 0).inverseRigid()
        let side = undo.rotate(face.rotate(Vec3(1, 0, 0)))
        rollDeg = atan2(side.y, side.x) * 180 / .pi

        let dir = face.transform(point: s.lookAtPoint) - pos
        if abs(dir.z) > 1e-9, -pos.z / dir.z > 0 {
            let hit = pos + dir * (-pos.z / dir.z)
            screenHit = Point(x: hit.x, y: hit.y)
        } else {
            screenHit = nil
        }
        eyeOpenness = 1 - max(s.blinkLeft, s.blinkRight)
    }

    /// 보정에 쓰는 특징: 시선이 닿는 점 + 머리 위치
    public var gazeFeature: GazeFeature? {
        screenHit.map { GazeFeature(h: $0.x, v: $0.y, headX: headPosition.x, headY: headPosition.y) }
    }
}
