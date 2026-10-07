"""독서 집중도: 최근 window 초 동안 책(화면)을 본 시간 비율에서 눈 돌린 횟수만큼 깎은 점수."""

from __future__ import annotations

from collections import deque


class FocusMeter:
    def __init__(self, window=60.0, look_away=1.0, penalty=10, min_data=10.0, max_step=1.0):
        self.window = window
        self.look_away = look_away  # 이보다 길게 눈을 떼면 '눈 돌림' 1회
        self.penalty = penalty  # 눈 돌림 1회당 깎는 점수
        self.min_data = min_data
        self.max_step = max_step
        self.history: list[int] = []  # 1분마다의 점수(보고서용)
        self._samples: deque[tuple[float, float, bool]] = deque()
        self._look_aways: deque[float] = deque()
        self._off_run = 0.0
        self._start: float | None = None
        self._last_t: float | None = None

    def update(self, on_target: bool, t: float):
        dt = 0.0 if self._last_t is None else min(max(t - self._last_t, 0.0), self.max_step)
        self._last_t = t
        if self._start is None:
            self._start = t
        if on_target:
            self._off_run = 0.0
        else:
            if self._off_run < self.look_away <= self._off_run + dt:
                self._look_aways.append(t)
            self._off_run += dt
        self._samples.append((t, dt, on_target))
        while self._samples and self._samples[0][0] <= t - self.window:
            self._samples.popleft()
        while self._look_aways and self._look_aways[0] <= t - self.window:
            self._look_aways.popleft()
        if t - self._start >= (len(self.history) + 1) * 60:
            score = self.score()
            self.history.append(score if score is not None else 0)

    def look_aways(self) -> int:
        return len(self._look_aways)

    def score(self) -> int | None:
        covered = sum(dt for _, dt, _ in self._samples)
        if covered < self.min_data:
            return None
        on = sum(dt for _, dt, on in self._samples if on) / covered
        return max(0, min(100, round(on * 100 - self.penalty * self.look_aways())))
