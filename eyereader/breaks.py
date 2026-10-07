"""독서 시간과 휴식: 계속 읽은 시간, 화면에서 눈을 뗀 시간, 쉬어 가기 권유."""

from __future__ import annotations

from .alerts import Alert


class ReadingTimer:
    """present = 지금 화면(책)을 보고 있는가.

    - 잠깐 눈을 돌린 것(rest 초 미만)은 휴식이 아니라서 연속 독서 시간이 이어진다.
    - rest 초 넘게 화면을 떠나 있으면 쉰 것으로 보고 연속 독서 시간을 0으로 돌린다.
    """

    def __init__(self, break_after=40 * 60.0, repeat=10 * 60.0, rest=5 * 60.0, look_away=1.0, max_step=1.0):
        self.break_after = break_after
        self.repeat = repeat
        self.rest = rest
        self.look_away = look_away  # 이보다 길게 눈을 떼면 '눈 돌림' 1회
        self.max_step = max_step
        self.continuous_seconds = 0.0
        self.reading_seconds = 0.0
        self.away_seconds = 0.0
        self.look_aways = 0
        self._away_run = 0.0
        self._next_reminder = break_after
        self._last_t: float | None = None

    def update(self, present: bool, t: float) -> list[Alert]:
        dt = 0.0 if self._last_t is None else min(max(t - self._last_t, 0.0), self.max_step)
        self._last_t = t
        if not present:
            if self._away_run < self.look_away <= self._away_run + dt:
                self.look_aways += 1
            self._away_run += dt
            self.away_seconds += dt
            if self._away_run >= self.rest:
                self.continuous_seconds = 0.0
                self._next_reminder = self.break_after
            return []
        self._away_run = 0.0
        self.continuous_seconds += dt
        self.reading_seconds += dt
        if self.continuous_seconds >= self._next_reminder:
            minutes = round(self._next_reminder / 60)
            self._next_reminder += self.repeat
            return [Alert("break", "잠시 쉬어가는 건 어떨까요?", f"{minutes}분 동안 계속 독서 중입니다.")]
        return []
