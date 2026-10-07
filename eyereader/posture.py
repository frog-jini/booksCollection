"""읽기 자세 측정: 얼굴과 화면의 거리, 화면을 보는 각도, 고개 기울기.

책 내용과 상관없이 얼굴만 보고 판단하므로 어떤 독서 앱을 쓰든 동작한다.

카메라 보정 없이 평균적인 얼굴 치수로 어림한다:
- 두 눈동자 사이 거리 AVG_IPD_CM(6.3cm)가 사진에서 얼마나 크게 보이는지로 거리를 잰다.
- 코끝이 눈 높이보다 NOSE_DOWN_CM 아래, NOSE_FRONT_CM 앞에 있다고 보고
  코끝이 어느 쪽으로 밀려 보이는지로 고개를 돌린 각도(yaw)·숙인 각도(pitch)를 잰다.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

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
