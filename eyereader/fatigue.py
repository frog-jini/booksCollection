"""피로·졸음 감지: 깜빡임 횟수, PERCLOS, 긴 눈 감음.

- 눈 뜬 정도(openness) = 눈 높이 / 눈 폭. 0.12 보다 작으면 감은 것으로 본다.
- PERCLOS = 최근 window 초 중 눈을 감고 있던 시간의 비율. 졸음 연구에서 널리 쓰는 지표로
  보통 15% 를 넘으면 졸린 상태로 본다.
- 1초 넘게 눈을 감고 있으면(마이크로슬립) 바로 졸음으로 본다.
"""

from __future__ import annotations

from collections import deque

from .alerts import Alert, Persistence
from .gaze.features import BLINK_OPENNESS, LEFT_EYE, NUM_LANDMARKS, RIGHT_EYE

DROWSY = Alert("drowsy", "졸음이 감지되었습니다.", "눈을 감고 있는 시간이 길어요. 잠시 쉬어 가세요.")


def _openness(pts, eye):
    width = pts[eye.corner_b][0] - pts[eye.corner_a][0]
    return (pts[eye.bottom][1] - pts[eye.top][1]) / width if width > 0 else None


def eye_openness(landmarks) -> float | None:
    if landmarks is None or len(landmarks) < NUM_LANDMARKS:
        return None
    values = [v for v in (_openness(landmarks, LEFT_EYE), _openness(landmarks, RIGHT_EYE)) if v is not None]
    return sum(values) / len(values) if values else None


class DrowsinessMonitor:
    def __init__(self, closed_below=BLINK_OPENNESS, window=60.0, perclos_limit=0.15, microsleep=1.0,
                 max_blink=0.5, cooldown=120.0, max_step=0.5):
        self.closed_below = closed_below
        self.window = window
        self.perclos_limit = perclos_limit
        self.microsleep = microsleep
        self.max_blink = max_blink  # 이보다 짧게 감았다 뜨면 깜빡임
        self.max_step = max_step
        self.long_closures = 0
        self._samples: deque[tuple[float, float, bool]] = deque()  # (시각, 길이, 감음)
        self._blinks: deque[float] = deque()
        self._closed_since: float | None = None
        self._counted_this_closure = False
        self._last_t: float | None = None
        self._gate = Persistence(hold=0, cooldown=cooldown)

    def _forget_old(self, t):
        while self._samples and self._samples[0][0] < t - self.window:
            self._samples.popleft()
        while self._blinks and self._blinks[0] < t - self.window:
            self._blinks.popleft()

    def perclos(self) -> float:
        total = sum(dt for _, dt, _ in self._samples)
        return sum(dt for _, dt, closed in self._samples if closed) / total if total else 0.0

    def blink_rate(self) -> float:
        """분당 깜빡임 횟수."""
        return len(self._blinks) * 60 / self.window

    def _covered(self) -> float:
        return sum(dt for _, dt, _ in self._samples)

    def update(self, openness: float | None, t: float) -> list[Alert]:
        dt = 0.0 if self._last_t is None else min(max(t - self._last_t, 0.0), self.max_step)
        self._last_t = t
        if openness is None:  # 얼굴을 놓침: 감은 것으로 치지 않는다
            self._closed_since = None
            return []
        closed = openness < self.closed_below
        self._samples.append((t, dt, closed))
        self._forget_old(t)

        drowsy = False
        if closed:
            if self._closed_since is None:
                self._closed_since, self._counted_this_closure = t, False
            elif t - self._closed_since >= self.microsleep and not self._counted_this_closure:
                self._counted_this_closure = True
                self.long_closures += 1
                drowsy = True
        elif self._closed_since is not None:
            if t - self._closed_since <= self.max_blink:
                self._blinks.append(t)
            self._closed_since = None

        if self._covered() >= self.window * 0.95 and self.perclos() > self.perclos_limit:
            drowsy = True
        return [DROWSY] if self._gate.check("drowsy", drowsy, t) else []
