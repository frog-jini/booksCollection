import Foundation
import Testing
@testable import EyeReaderKit

func near(_ a: Double, _ b: Double, _ tol: Double = 1e-6) -> Bool { abs(a - b) <= tol }

/// 카메라 기준 자세의 얼굴 (도 단위 회전: yaw → pitch → roll 순)
func faceAt(_ p: Vec3, yaw: Double = 0, pitch: Double = 0, roll: Double = 0) -> Mat4 {
    Mat4.pose(position: p, yawDeg: yaw, pitchDeg: pitch, rollDeg: roll)
}

func sample(face: Mat4, camera: Mat4 = .identity, lookAt: Vec3 = Vec3(0, 0, 1), blink: (Double, Double) = (0, 0)) -> FaceSample {
    FaceSample(faceTransform: face, cameraTransform: camera, lookAtPoint: lookAt, blinkLeft: blink.0, blinkRight: blink.1)
}

@Test func rigidInverseUndoesTransform() {
    let m = faceAt(Vec3(0.1, -0.2, -0.4), yaw: 20, pitch: -10, roll: 5)
    let p = Vec3(0.3, 0.1, 0.7)
    let back = m.inverseRigid().transform(point: m.transform(point: p))
    #expect(near(back.x, p.x) && near(back.y, p.y) && near(back.z, p.z))
}

@Test func distanceIsHowFarTheFaceIsFromTheCameraInCm() {
    let m = FaceMeasure(sample(face: faceAt(Vec3(0.03, -0.04, -0.35))))
    #expect(near(m.distanceCm, (0.03 * 0.03 + 0.04 * 0.04 + 0.35 * 0.35).squareRoot() * 100))
}

@Test func lookingStraightAtTheScreenHitsInFrontOfTheFace() {
    let m = FaceMeasure(sample(face: faceAt(Vec3(0.02, -0.05, -0.4))))
    let hit = try! #require(m.screenHit)
    #expect(near(hit.x, 0.02) && near(hit.y, -0.05))
}

@Test func lookingSidewaysMovesTheHitPoint() {
    // 얼굴에서 40cm 떨어진 화면에서 오른쪽 5cm, 위 2cm 를 봄
    let m = FaceMeasure(sample(face: faceAt(Vec3(0, 0, -0.4)), lookAt: Vec3(0.05, 0.02, 0.4)))
    let hit = try! #require(m.screenHit)
    #expect(near(hit.x, 0.05) && near(hit.y, 0.02))
}

@Test func lookingAwayFromTheScreenHasNoHit() {
    let m = FaceMeasure(sample(face: faceAt(Vec3(0, 0, -0.4)), lookAt: Vec3(0, 0, -1)))
    #expect(m.screenHit == nil)
}

@Test func headAnglesComeFromFaceRotation() {
    let m = FaceMeasure(sample(face: faceAt(Vec3(0, 0, -0.4), yaw: 20, pitch: 15, roll: -10)))
    #expect(near(abs(m.yawDeg), 20, 1e-6) && near(abs(m.pitchDeg), 15, 1e-6) && near(abs(m.rollDeg), 10, 1e-6))
    let straight = FaceMeasure(sample(face: faceAt(Vec3(0, 0, -0.4))))
    #expect(near(straight.yawDeg, 0) && near(straight.pitchDeg, 0) && near(straight.rollDeg, 0))
}

@Test func resultsDoNotDependOnWhereTheWorldOriginIs() {
    // ARKit 세계 좌표의 원점이 어디든, 카메라 기준으로 같은 얼굴이면 결과가 같아야 한다
    let world = faceAt(Vec3(1, 2, 3), yaw: 30, pitch: 5, roll: 0)
    let faceCam = faceAt(Vec3(0.02, -0.05, -0.4), yaw: 10)
    let a = FaceMeasure(sample(face: faceCam, lookAt: Vec3(0.05, 0.02, 0.4)))
    let b = FaceMeasure(sample(face: world * faceCam, camera: world, lookAt: Vec3(0.05, 0.02, 0.4)))
    #expect(near(a.distanceCm, b.distanceCm) && near(a.yawDeg, b.yawDeg))
    #expect(near(a.screenHit!.x, b.screenHit!.x) && near(a.screenHit!.y, b.screenHit!.y))
}

@Test func gazeFeatureForCalibrationCombinesHitAndHeadPosition() {
    let m = FaceMeasure(sample(face: faceAt(Vec3(0.02, -0.05, -0.4)), lookAt: Vec3(0.05, 0.02, 0.4)))
    let f = try! #require(m.gazeFeature)
    #expect(near(f.h, m.screenHit!.x) && near(f.v, m.screenHit!.y))
    #expect(near(f.headX, 0.02) && near(f.headY, -0.05))
}

@Test func eyeOpennessFromBlinkValues() {
    #expect(near(FaceMeasure(sample(face: faceAt(Vec3(0, 0, -0.4)), blink: (0.1, 0.3))).eyeOpenness, 0.7))
    #expect(near(FaceMeasure(sample(face: faceAt(Vec3(0, 0, -0.4)), blink: (1, 0.9))).eyeOpenness, 0))
}
