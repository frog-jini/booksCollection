import Foundation
import Testing
@testable import EyeReaderKit

/// 실제 눈 → 화면 관계라고 가정한 2차 함수(머리 위치 영향 포함)
func trueMapping(_ f: GazeFeature) -> Point {
    Point(x: 390 * f.h + 120 * (f.h - 0.5) * (f.h - 0.5) - 80 * (f.headX - 0.5),
          y: 840 * f.v + 60 * f.h * f.v + 50 * (f.headY - 0.5))
}

/// 재현 가능한 의사 난수
struct LCG {
    var state: UInt64
    mutating func next(_ lo: Double, _ hi: Double) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return lo + (hi - lo) * Double(state >> 11) / Double(1 << 53)
    }
}

func fittedCalibrator(samples: Int = 60, seed: UInt64 = 1) throws -> Calibrator {
    var rng = LCG(state: seed)
    var cal = Calibrator()
    for _ in 0..<samples {
        let f = GazeFeature(h: rng.next(0.2, 0.8), v: rng.next(0.2, 0.8), headX: rng.next(0.4, 0.6), headY: rng.next(0.5, 0.7))
        cal.add(f, screen: trueMapping(f))
    }
    try cal.fit()
    return cal
}

@Test func calibrationPointsAre3x3GridInsideMargins() {
    let pts = calibrationPoints(width: 393, height: 852, margin: 40)
    #expect(pts.count == 9)
    #expect(Set(pts.map(\.x)) == [40, 196.5, 353])
    #expect(Set(pts.map(\.y)) == [40, 426, 812])
}

@Test func fitLearnsMappingAndPredictsUnseenGaze() throws {
    let cal = try fittedCalibrator()
    let f = GazeFeature(h: 0.41, v: 0.63, headX: 0.52, headY: 0.58)
    let p = try #require(cal.predict(f))
    #expect(p.distance(to: trueMapping(f)) < 1.0)
}

@Test func predictBeforeFitIsNilAndFitNeedsEnoughSamples() {
    var cal = Calibrator()
    #expect(cal.predict(GazeFeature(h: 0.5, v: 0.5, headX: 0.5, headY: 0.5)) == nil)
    cal.add(GazeFeature(h: 0.5, v: 0.5, headX: 0.5, headY: 0.5), screen: Point(x: 0, y: 0))
    #expect(throws: CalibrationError.self) { try cal.fit() }
}

@Test func headHeldStillStillFits() throws {
    // 보정 중 머리를 거의 안 움직이면 머리 위치 항이 상수처럼 된다 → 그래도 풀려야 한다
    var cal = Calibrator()
    var rng = LCG(state: 7)
    for _ in 0..<40 {
        let f = GazeFeature(h: rng.next(0.2, 0.8), v: rng.next(0.2, 0.8), headX: 0.5, headY: 0.6)
        cal.add(f, screen: trueMapping(f))
    }
    try cal.fit()
    let f = GazeFeature(h: 0.3, v: 0.7, headX: 0.5, headY: 0.6)
    #expect(try #require(cal.predict(f)).distance(to: trueMapping(f)) < 1.0)
}

@Test func savedCalibrationCanBeReused() throws {
    let cal = try fittedCalibrator(samples: 30, seed: 3)
    let data = try JSONEncoder().encode(cal)
    let loaded = try JSONDecoder().decode(Calibrator.self, from: data)
    let f = GazeFeature(h: 0.5, v: 0.5, headX: 0.5, headY: 0.5)
    #expect(loaded.predict(f) == cal.predict(f))
}
