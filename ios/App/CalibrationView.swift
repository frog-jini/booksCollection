import EyeReaderKit
import SwiftUI

/// 시선 보정(readme 7): 빨간 점 9개를 차례로 바라보게 해서 '눈 방향 → 화면 좌표'를 배운다.
/// 읽기 화면과 같은 전체 화면 좌표를 쓴다.
struct CalibrationView: View {
    enum Phase { case intro, running, done }

    @EnvironmentObject private var library: Library
    @EnvironmentObject private var face: FaceTracker
    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.intro
    @State private var target: CGPoint?
    @State private var shrink = false
    @State private var failure: String?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.background
                switch phase {
                case .intro:
                    VStack(spacing: 20) {
                        Text("시선 보정").font(.title.bold())
                        Text("폰을 평소 책 읽는 자세로 들고, 머리는 그대로 둔 채 눈으로만 빨간 점을 따라가세요. 점이 작아질 때까지 점 가운데를 바라보면 됩니다.")
                            .multilineTextAlignment(.center)
                        if let failure { Text(failure).foregroundStyle(.red).multilineTextAlignment(.center) }
                        if let error = face.errorMessage { Text(error).foregroundStyle(.red) }
                        Button("시작") { phase = .running }.buttonStyle(.borderedProminent)
                        Button("취소") { dismiss() }
                    }
                    .padding(32)
                case .running:
                    if let target {
                        Circle()
                            .fill(Color.red)
                            .frame(width: shrink ? 14 : 30, height: shrink ? 14 : 30)
                            .position(target)
                            .animation(.easeOut(duration: 0.3), value: shrink)
                    }
                case .done:
                    VStack(spacing: 20) {
                        Text("보정 완료").font(.title.bold())
                        Text("이제 책을 열면 눈으로 읽을 수 있습니다. 자세가 바뀌거나 시선이 어긋나면 다시 보정하세요.")
                            .multilineTextAlignment(.center)
                        Button("닫기") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                    .padding(32)
                }
            }
            .task(id: phase) {
                if phase == .running { await run(size: geo.size) }
            }
        }
        .ignoresSafeArea()
        .onAppear { face.start() }
    }

    private func run(size: CGSize) async {
        var calibrator = Calibrator()
        for point in calibrationPoints(width: size.width, height: size.height, margin: 40) {
            target = CGPoint(x: point.x, y: point.y)
            shrink = false
            let start = ProcessInfo.processInfo.systemUptime
            var lastTime: TimeInterval = 0
            while true {
                let now = ProcessInfo.processInfo.systemUptime
                if now - start >= 2.0 { break }
                if now - start >= 0.7 {  // 처음 0.7초는 눈이 점으로 옮겨 가는 시간
                    shrink = true
                    if face.latestTime != lastTime, let feature = face.current(at: now)?.gazeFeature {
                        calibrator.add(feature, screen: point)
                        lastTime = face.latestTime
                    }
                }
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
        target = nil
        do {
            try calibrator.fit()
            library.calibrator = calibrator
            phase = .done
        } catch {
            failure = "보정에 실패했습니다. 얼굴이 화면 정면에 잘 보이는지 확인하고 다시 해 주세요."
            phase = .intro
        }
    }
}
