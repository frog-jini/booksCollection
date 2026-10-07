import ARKit
import EyeReaderKit

/// Face ID 카메라(TrueDepth)로 얼굴을 추적해 FaceMeasure(거리·각도·시선점·눈 뜬 정도)를 만든다.
/// 영상은 기기 밖으로 보내지 않는다.
@MainActor
final class FaceTracker: NSObject, ObservableObject {
    @Published private(set) var errorMessage: String?
    /// 화면을 매 프레임 다시 그리지 않도록 @Published 로 두지 않는다(읽는 쪽이 타이머로 가져간다).
    private(set) var latest: FaceMeasure?
    private(set) var latestTime: TimeInterval = 0
    private let session = ARSession()
    private var running = false

    static var isSupported: Bool { ARFaceTrackingConfiguration.isSupported }

    override init() {
        super.init()
        session.delegate = self
    }

    func start() {
        guard Self.isSupported else {
            errorMessage = "이 기기는 Face ID 카메라 얼굴 추적을 지원하지 않습니다."
            return
        }
        guard !running else { return }
        let config = ARFaceTrackingConfiguration()
        config.isLightEstimationEnabled = false
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        running = true
    }

    func stop() {
        session.pause()
        running = false
    }

    /// 0.3초 넘게 새 값이 없으면 얼굴을 놓친 것으로 본다.
    func current(at now: TimeInterval) -> FaceMeasure? {
        now - latestTime < 0.3 ? latest : nil
    }

    fileprivate func receive(_ measure: FaceMeasure) {
        latest = measure
        latestTime = ProcessInfo.processInfo.systemUptime
    }

    fileprivate func fail(_ message: String) {
        errorMessage = message
        running = false
    }
}

extension FaceTracker: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first, face.isTracked else { return }
        let sample = FaceSample(
            faceTransform: Mat4(face.transform),
            cameraTransform: Mat4(frame.camera.transform),
            lookAtPoint: Vec3(Double(face.lookAtPoint.x), Double(face.lookAtPoint.y), Double(face.lookAtPoint.z)),
            blinkLeft: face.blendShapes[.eyeBlinkLeft]?.doubleValue ?? 0,
            blinkRight: face.blendShapes[.eyeBlinkRight]?.doubleValue ?? 0)
        let measure = FaceMeasure(sample)
        Task { @MainActor in self.receive(measure) }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let message = "카메라를 쓸 수 없습니다: \(error.localizedDescription)"
        Task { @MainActor in self.fail(message) }
    }
}

extension Mat4 {
    init(_ m: simd_float4x4) {
        let cols = [m.columns.0, m.columns.1, m.columns.2, m.columns.3]
        self.init(columns: cols.map { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] })
    }
}
