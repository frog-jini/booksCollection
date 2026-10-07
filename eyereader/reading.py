"""시선 좌표로 지금 읽고 있는 단어를 추정한다.

웹캠 시선 추적은 세로 오차가 크므로:
- 줄 이동은 시선이 다른 줄에 line_switch_time 이상 머물러야 인정한다.
- 줄 끝까지 읽은 뒤 시선이 줄 앞쪽으로 돌아가면(return sweep) 다음 줄로 넘어간다.
"""

from __future__ import annotations

from .layout import Page, Word

NEAR_END = 0.7   # 줄 폭의 이 비율 이후면 '줄 끝 근처'
LINE_START = 0.3  # 줄 폭의 이 비율 이전이면 '줄 앞쪽'


class ReadingTracker:
    def __init__(self, page: Page, line_switch_time=0.35):
        self.line_switch_time = line_switch_time
        self.reset(page)

    def reset(self, page: Page):
        self.page = page
        self.lines = [l for l in page.lines if l.words]
        self.line_idx: int | None = None
        self.word: Word | None = None
        self.furthest: Word | None = None
        self._candidate: int | None = None
        self._candidate_since = 0.0
        self._near_end = False

    def _span(self, i):
        words = self.lines[i].words
        return words[0].x, words[-1].x + words[-1].w

    def _nearest_line(self, y):
        return min(range(len(self.lines)), key=lambda i: abs(self.lines[i].words[0].cy - y))

    def _go_to_line(self, i):
        self.line_idx = i
        self._near_end = False
        self._candidate = None

    def _choose_line(self, x, y, t):
        nearest = self._nearest_line(y)
        if self.line_idx is None:
            self._go_to_line(nearest)
            return
        start, end = self._span(self.line_idx)
        if self._near_end and x < start + LINE_START * (end - start):
            self._go_to_line(min(self.line_idx + 1, len(self.lines) - 1))
        elif nearest != self.line_idx:
            if self._candidate != nearest:
                self._candidate, self._candidate_since = nearest, t
            elif t - self._candidate_since >= self.line_switch_time:
                self._go_to_line(nearest)
        else:
            self._candidate = None

    def update(self, gaze, t: float):
        if not self.lines or gaze is None:
            return self.word
        x, y = gaze
        self._choose_line(x, y, t)
        line = self.lines[self.line_idx]
        self.word = min(line.words, key=lambda w: abs(w.cx - x))
        start, end = self._span(self.line_idx)
        if x >= start + NEAR_END * (end - start):
            self._near_end = True
        if self.furthest is None or self.word.index > self.furthest.index:
            self.furthest = self.word
        return self.word
