"""시선 좌표 떨림을 줄이는 지수 이동 평균 필터."""

from __future__ import annotations

import math


class GazeSmoother:
    def __init__(self, alpha=0.3, snap_distance=float("inf")):
        self.alpha = alpha
        self.snap_distance = snap_distance  # 이보다 큰 점프(도약 안구 운동)는 바로 따라간다
        self._value = None

    def reset(self):
        self._value = None

    def update(self, point):
        if point is None:
            return self._value
        if self._value is None or math.dist(point, self._value) > self.snap_distance:
            self._value = tuple(point)
        else:
            a = self.alpha
            self._value = tuple(a * p + (1 - a) * v for p, v in zip(point, self._value))
        return self._value
