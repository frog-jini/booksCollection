"""읽기 속도(WPM) 측정과, 속도에 맞춘 페이지 넘김 대기 시간."""

from __future__ import annotations


class ReadingSpeed:
    def __init__(self, window: float = 60.0, default_wpm: float = 200.0):
        self.window = window  # 최근 몇 초의 기록으로 속도를 잴지
        self.default_wpm = default_wpm  # 아직 잴 수 없을 때 쓰는 값
        self._samples: list[tuple[float, int]] = []  # (시각, 누적 전진 단어 수)
        self._max_index: int | None = None
        self._progress = 0

    def update(self, word_index: int, t: float) -> None:
        if self._max_index is None:
            self._max_index = word_index
        elif word_index > self._max_index:  # 되돌아 읽기는 전진으로 치지 않는다
            self._progress += word_index - self._max_index
            self._max_index = word_index
        self._samples.append((t, self._progress))
        cutoff = t - self.window
        while len(self._samples) > 1 and self._samples[0][0] < cutoff:
            self._samples.pop(0)

    def wpm(self) -> float:
        if len(self._samples) < 2:
            return 0.0
        (t0, p0), (t1, p1) = self._samples[0], self._samples[-1]
        if t1 <= t0:
            return 0.0
        return (p1 - p0) / (t1 - t0) * 60

    def seconds_for(self, words: int) -> float:
        return words / (self.wpm() or self.default_wpm) * 60

    def turn_dwell(self, words: int = 3, low: float = 0.6, high: float = 2.0) -> float:
        """마지막 단어를 이만큼 보면 페이지를 넘긴다: 단어 몇 개를 읽는 시간."""
        return min(high, max(low, self.seconds_for(words)))
