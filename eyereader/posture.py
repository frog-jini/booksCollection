"""읽기 자세 측정: 얼굴과 화면의 거리, 화면을 보는 각도, 고개 기울기.

책 내용과 상관없이 얼굴만 보고 판단하므로 어떤 독서 앱을 쓰든 동작한다.

카메라 보정 없이 평균적인 얼굴 치수로 어림한다:
- 두 눈동자 사이 거리 AVG_IPD_CM(6.3cm)가 사진에서 얼마나 크게 보이는지로 거리를 잰다.
- 코끝이 눈 높이보다 NOSE_DOWN_CM 아래, NOSE_FRONT_CM 앞에 있다고 보고
  코끝이 어느 쪽으로 밀려 보이는지로 고개를 돌린 각도(yaw)·숙인 각도(pitch)를 잰다.
"""

from __future__ import annotations

import math
import statistics
from dataclasses import dataclass

from .alerts import Alert, Persistence

LEFT_IRIS, RIGHT_IRIS, NOSE_TIP = 468, 473, 1
NUM_LANDMARKS = 478

AVG_IPD_CM = 6.3
NOSE_DOWN_CM = 4.0
NOSE_FRONT_CM = 3.0
DEFAULT_HFOV = 60.0  # 노트북 웹캠의 대략적인 가로 화각


@dataclass(frozen=True)
class HeadPose:
    distance_cm: float  # 얼굴(눈)과 카메라 사이 거리
    yaw: float  # 좌우로 돌린 각도(도). + 는 이미지 오른쪽
    pitch: float  # 숙인 각도(도). + 는 고개를 숙임
    roll: float  # 옆으로 기울인 각도(도)


def head_pose(landmarks, aspect: float = 16 / 9, hfov_deg: float = DEFAULT_HFOV) -> HeadPose | None:
    """정규화 랜드마크(x/폭, y/높이)와 이미지 가로세로비로 머리 자세를 어림한다."""
    if landmarks is None or len(landmarks) < NUM_LANDMARKS:
        return None
    # 실제 모양대로 계산하려고 x 를 이미지 높이 단위로 바꾼다
    (lx, ly), (rx, ry), (nx, ny) = (landmarks[i] for i in (LEFT_IRIS, RIGHT_IRIS, NOSE_TIP))
    lx, rx, nx = lx * aspect, rx * aspect, nx * aspect
    dx, dy = rx - lx, ry - ly
    seen_ipd = math.hypot(dx, dy)
    if seen_ipd <= 1e-9:
        return None
    roll = math.degrees(math.atan2(dy, dx))

    # 눈을 잇는 선 기준 좌표로 코끝 위치를 본다(기울기 영향 제거)
    ux, uy = dx / seen_ipd, dy / seen_ipd
    ox, oy = nx - (lx + rx) / 2, ny - (ly + ry) / 2
    along = ox * ux + oy * uy
    down = -ox * uy + oy * ux

    yaw_rad = math.atan(along / seen_ipd * AVG_IPD_CM / NOSE_FRONT_CM)
    true_ipd = seen_ipd / math.cos(yaw_rad)  # 돌린 만큼 좁아 보인 것을 되돌린다

    nose_radius = math.hypot(NOSE_DOWN_CM, NOSE_FRONT_CM)
    down_cm = down / true_ipd * AVG_IPD_CM
    phase = math.atan2(NOSE_FRONT_CM, NOSE_DOWN_CM)
    pitch_rad = phase - math.acos(max(-1.0, min(1.0, down_cm / nose_radius)))

    focal = (aspect / 2) / math.tan(math.radians(hfov_deg / 2))
    return HeadPose(
        distance_cm=focal * AVG_IPD_CM / true_ipd,
        yaw=math.degrees(yaw_rad),
        pitch=math.degrees(pitch_rad),
        roll=roll,
    )


POSTURE_TITLE = "독서 자세가 좋지 않습니다."


class PostureMonitor:
    """나쁜 자세가 hold 초 넘게 이어지면 알린다.

    고개 숙임은 카메라 위치에 따라 '정상'이 사람마다 달라서, 처음 baseline_samples 개
    자세의 중간값을 그 사람의 평소 자세로 삼고 그보다 max_head_down 도 넘게 숙이면 알린다.
    """

    def __init__(self, min_distance=40.0, max_roll=15.0, max_yaw=25.0, max_head_down=20.0,
                 hold=10.0, cooldown=300.0, baseline_samples=30):
        self.min_distance = min_distance
        self.max_roll = max_roll
        self.max_yaw = max_yaw
        self.max_head_down = max_head_down
        self.baseline_samples = baseline_samples
        self.baseline_pitch: float | None = None
        self._pitches: list[float] = []
        self._gate = Persistence(hold, cooldown)

    def _learn_baseline(self, pose: HeadPose):
        if self.baseline_pitch is None:
            self._pitches.append(pose.pitch)
            if len(self._pitches) >= self.baseline_samples:
                self.baseline_pitch = statistics.median(self._pitches)

    def problems(self, pose: HeadPose) -> dict[str, tuple[bool, str]]:
        head_down = self.baseline_pitch is not None and pose.pitch - self.baseline_pitch > self.max_head_down
        return {
            "too_close": (pose.distance_cm < self.min_distance,
                          f"화면과 얼굴이 너무 가깝습니다. (약 {pose.distance_cm:.0f}cm)"),
            "tilted": (abs(pose.roll) > self.max_roll, "고개가 한쪽으로 기울어져 있습니다."),
            "turned": (abs(pose.yaw) > self.max_yaw, "화면을 비스듬히 보고 있습니다. 화면 정면에 앉아 주세요."),
            "head_down": (head_down, "고개를 너무 숙이고 있습니다."),
        }

    def update(self, pose: HeadPose | None, t: float) -> list[Alert]:
        if pose is None:
            self._gate.clear()
            return []
        self._learn_baseline(pose)
        return [Alert(kind, POSTURE_TITLE, message)
                for kind, (active, message) in self.problems(pose).items()
                if self._gate.check(kind, active, t)]
