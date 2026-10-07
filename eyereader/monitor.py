"""감시 모드: 책 없이 카메라만으로, 다른 앱으로 읽는 동안 자세·휴식·졸음을 알린다.

화면에 무엇이 떠 있는지 전혀 보지 않는다. 얼굴만 본다.
"""

from __future__ import annotations

import time
from dataclasses import dataclass

from .coach import ReadingCoach
from .fatigue import eye_openness
from .gaze.features import eye_feature
from .notify import notify as system_notify
from .posture import DEFAULT_HFOV, HeadPose, head_pose

MAX_SCREEN_YAW = 35.0  # 이보다 고개를 돌리면 화면을 안 보는 것으로 본다


@dataclass
class FaceReading:
    present: bool
    pose: HeadPose | None = None
    openness: float | None = None
    feature: tuple | None = None  # 시선 보정용 특징


def analyze(frame, hfov_deg: float = DEFAULT_HFOV) -> FaceReading:
    if frame is None or frame.landmarks is None:
        return FaceReading(present=False)
    pose = head_pose(frame.landmarks, aspect=frame.aspect, hfov_deg=hfov_deg)
    return FaceReading(
        present=pose is not None,
        pose=pose,
        openness=eye_openness(frame.landmarks),
        feature=eye_feature(frame.landmarks),
    )


def looking_at_screen(pose: HeadPose | None) -> bool:
    return pose is not None and abs(pose.yaw) <= MAX_SCREEN_YAW


def _status_line(status: dict) -> str:
    focus = status["focus"] if status["focus"] is not None else "-"
    dist = f"{status['distance_cm']:.0f}cm" if status["distance_cm"] else "-"
    return (f"독서 {status['reading_minutes']:.0f}분 · 집중 {focus} · 거리 {dist} · "
            f"깜빡임 {status['blink_rate']:.0f}/분")


def run_monitor(source, coach: ReadingCoach, notify=system_notify, clock=time.monotonic, sleep=time.sleep,
                fps=10, max_frames=None, hfov_deg=DEFAULT_HFOV, status_every=60.0, echo=print) -> dict:
    frames, next_status = 0, None
    try:
        while max_frames is None or frames < max_frames:
            t = clock()
            r = analyze(source.read_frame(), hfov_deg)
            alerts = coach.update(t, pose=r.pose, openness=r.openness, present=r.present,
                                  on_target=r.present and looking_at_screen(r.pose))
            for alert in alerts:
                notify(alert.title, alert.message)
            if next_status is None:
                next_status = t + status_every
            elif t >= next_status:
                echo(_status_line(coach.status()))
                next_status += status_every
            frames += 1
            sleep(max(0.0, 1 / fps - (clock() - t)))
    except KeyboardInterrupt:
        pass
    finally:
        source.close()
    return coach.report("다른 앱 독서")
