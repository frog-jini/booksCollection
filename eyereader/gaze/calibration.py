"""시선 특징 → 화면 좌표 보정(2차 다항 회귀)."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np


def calibration_points(width, height, margin=80):
    xs = (margin, width / 2, width - margin)
    ys = (margin, height / 2, height - margin)
    return [(x, y) for y in ys for x in xs]


def _design(features) -> np.ndarray:
    f = np.atleast_2d(np.asarray(features, dtype=float))
    h, v, nx, ny = f[:, 0], f[:, 1], f[:, 2], f[:, 3]
    return np.column_stack([np.ones_like(h), h, v, nx, ny, h * v, h * h, v * v])


class Calibrator:
    MIN_SAMPLES = 8  # 미지수(항) 개수

    def __init__(self):
        self._features: list = []
        self._targets: list = []
        self.coef: np.ndarray | None = None

    def add(self, feature, screen_xy):
        self._features.append(tuple(feature))
        self._targets.append(tuple(screen_xy))

    def fit(self):
        if len(self._features) < self.MIN_SAMPLES:
            raise ValueError(f"보정 샘플이 부족합니다 ({len(self._features)}/{self.MIN_SAMPLES})")
        self.coef, *_ = np.linalg.lstsq(_design(self._features), np.asarray(self._targets, float), rcond=None)

    def predict(self, feature):
        if self.coef is None:
            raise RuntimeError("보정(fit)을 먼저 해야 합니다")
        x, y = (_design(feature) @ self.coef)[0]
        return float(x), float(y)

    def save(self, path):
        Path(path).write_text(json.dumps({"coef": self.coef.tolist()}))

    @classmethod
    def load(cls, path):
        cal = cls()
        cal.coef = np.asarray(json.loads(Path(path).read_text())["coef"])
        return cal
