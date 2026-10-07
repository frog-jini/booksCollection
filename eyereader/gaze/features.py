"""MediaPipe Face Landmarker(478점) 랜드마크 → 시선 특징 벡터.

특징 = (홍채 가로 비율, 홍채 세로 비율, 코끝 x, 코끝 y).
코끝 위치를 함께 넣어 머리가 조금 움직여도 보정 모델이 따라가게 한다.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Eye:
    corner_a: int  # 이미지 왼쪽 눈꼬리
    corner_b: int  # 이미지 오른쪽 눈꼬리
    top: int
    bottom: int
    iris: int


LEFT_EYE = Eye(corner_a=33, corner_b=133, top=159, bottom=145, iris=468)
RIGHT_EYE = Eye(corner_a=362, corner_b=263, top=386, bottom=374, iris=473)
NOSE_TIP = 1

BLINK_OPENNESS = 0.12  # 눈 높이/폭 비율이 이보다 작으면 깜빡임으로 본다
NUM_LANDMARKS = 478


def _ratios(pts, eye: Eye):
    ax, _ = pts[eye.corner_a]
    bx, _ = pts[eye.corner_b]
    _, ty = pts[eye.top]
    _, by = pts[eye.bottom]
    ix, iy = pts[eye.iris]
    width, height = bx - ax, by - ty
    if width <= 0 or height / width < BLINK_OPENNESS:
        return None
    return (ix - ax) / width, (iy - ty) / height


def eye_feature(landmarks):
    if landmarks is None or len(landmarks) < NUM_LANDMARKS:
        return None
    left, right = _ratios(landmarks, LEFT_EYE), _ratios(landmarks, RIGHT_EYE)
    if left is None or right is None:
        return None
    nx, ny = landmarks[NOSE_TIP]
    return ((left[0] + right[0]) / 2, (left[1] + right[1]) / 2, nx, ny)
