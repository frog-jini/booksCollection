import pytest

from eyereader.coach import ReadingCoach
from eyereader.breaks import ReadingTimer
from eyereader.gaze.features import LEFT_EYE, RIGHT_EYE
from eyereader.gaze.sources import FaceFrame
from eyereader.monitor import analyze, looking_at_screen, run_monitor
from eyereader.notify import notify
from eyereader.posture import HeadPose, PostureMonitor
from tests.test_posture import make_face


def face(ipd=0.1, yaw=0.0, openness=0.3):
    pts = make_face(ipd=ipd, yaw=yaw)
    for eye, x0 in ((LEFT_EYE, 0.40), (RIGHT_EYE, 0.52)):  # 눈 모양(뜬 정도)
        pts[eye.corner_a], pts[eye.corner_b] = (x0, 0.45), (x0 + 0.06, 0.45)
        pts[eye.top], pts[eye.bottom] = (x0 + 0.03, 0.44), (x0 + 0.03, 0.44 + 0.06 * openness)
    return FaceFrame(landmarks=pts, aspect=1.0)


# --- 카메라 한 장면 분석 --------------------------------------------------------

def test_analyze_gives_pose_openness_and_gaze_feature():
    r = analyze(face(), hfov_deg=60)
    assert r.present
    assert r.pose.distance_cm == pytest.approx(54.6, abs=0.1)
    assert r.openness == pytest.approx(0.3)
    assert r.feature is not None


def test_analyze_without_face():
    r = analyze(FaceFrame(landmarks=None, aspect=1.0))
    assert not r.present and r.pose is None and r.openness is None and r.feature is None
    assert analyze(None).present is False


def test_looking_at_screen_means_facing_it():
    assert looking_at_screen(HeadPose(50, 10, 0, 0))
    assert not looking_at_screen(HeadPose(50, 50, 0, 0))  # 고개를 완전히 돌림(폰 보기 등)
    assert not looking_at_screen(None)


# --- 감시 모드: 다른 앱으로 읽는 동안 알림 ----------------------------------------

class FakeClock:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t

    def sleep(self, seconds):
        self.t += seconds


class ScriptedCamera:
    def __init__(self, frames, clock, then_stop=False):
        self.frames, self.clock, self.then_stop = list(frames), clock, then_stop
        self.closed = False

    def read_frame(self):
        if not self.frames:
            if self.then_stop:
                raise KeyboardInterrupt  # 사용자가 Ctrl+C
            return None
        return self.frames.pop(0)

    def close(self):
        self.closed = True


def test_monitor_sends_system_notification_for_bad_posture():
    clock, sent = FakeClock(), []
    frames = [face(ipd=0.1)] * 20 + [face(ipd=0.2)] * 150  # 다가와서 계속 가까이(약 27cm)
    coach = ReadingCoach(posture=PostureMonitor(hold=10, baseline_samples=5))
    run_monitor(ScriptedCamera(frames, clock), coach, notify=lambda t, m: sent.append((t, m)),
                clock=clock, sleep=clock.sleep, fps=10, max_frames=len(frames))
    assert len(sent) == 1
    assert sent[0][0] == "독서 자세가 좋지 않습니다." and "너무 가깝습니다" in sent[0][1]


def test_monitor_counts_reading_only_while_face_is_there():
    clock = FakeClock()
    frames = [face()] * 100 + [None] * 50
    coach = ReadingCoach()
    report = run_monitor(ScriptedCamera(frames, clock), coach, notify=lambda *a: None,
                         clock=clock, sleep=clock.sleep, fps=10, max_frames=150)
    assert report["reading_minutes"] == pytest.approx(10 / 60, abs=0.01)
    assert report["away_minutes"] == pytest.approx(5 / 60, abs=0.01)


def test_monitor_suggests_break_in_any_app():
    clock, sent = FakeClock(), []
    coach = ReadingCoach(timer=ReadingTimer(break_after=60))
    run_monitor(ScriptedCamera([face()] * 700, clock), coach, notify=lambda t, m: sent.append(t),
                clock=clock, sleep=clock.sleep, fps=10, max_frames=700)
    assert sent == ["잠시 쉬어가는 건 어떨까요?"]


def test_ctrl_c_stops_monitor_cleanly_and_returns_report():
    clock = FakeClock()
    cam = ScriptedCamera([face()] * 30, clock, then_stop=True)
    report = run_monitor(cam, ReadingCoach(), notify=lambda *a: None, clock=clock, sleep=clock.sleep, fps=10)
    assert cam.closed and report["title"] == "다른 앱 독서"


# --- 알림 ---------------------------------------------------------------------

def test_notify_uses_macos_notification_center():
    calls, printed = [], []
    notify('잠시 "쉬어" 가요', "38분\\독서", system="Darwin", run=lambda cmd, **k: calls.append(cmd),
           echo=printed.append)
    assert calls[0][:2] == ["osascript", "-e"]
    assert 'with title "잠시 \\"쉬어\\" 가요"' in calls[0][2]
    assert 'display notification "38분\\\\독서"' in calls[0][2]
    assert printed == ['[잠시 "쉬어" 가요] 38분\\독서']


def test_notify_elsewhere_only_prints():
    calls, printed = [], []
    notify("제목", "내용", system="Linux", run=lambda *a, **k: calls.append(a), echo=printed.append)
    assert calls == [] and printed == ["[제목] 내용"]
