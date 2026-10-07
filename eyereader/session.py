"""화면 없이 돌아가는 읽기 흐름: 시선 → 읽는 단어 → 읽기 속도 → 자동 페이지 넘김.

pygame 화면(app.py)은 이 상태를 그리기만 한다.
"""

from __future__ import annotations

from .gaze.smoothing import GazeSmoother
from .layout import Page
from .reading import ReadingTracker
from .speed import ReadingSpeed


class ReadingSession:
    def __init__(self, pages: list[Page]):
        self.pages = pages
        self.page_no = 0
        self.tracker = ReadingTracker(pages[0])
        self.speed = ReadingSpeed()
        self.smoother = GazeSmoother(alpha=0.35, snap_distance=250)
        self.gaze = None
        self.paused = False  # 요약 패널 등을 보는 동안

    @property
    def page(self) -> Page:
        return self.pages[self.page_no]

    def go_to(self, page_no: int):
        self.page_no = max(0, min(page_no, len(self.pages) - 1))
        self.tracker.reset(self.page)

    def step(self, raw_gaze, t: float):
        self.gaze = self.smoother.update(raw_gaze)
        if self.paused:
            return
        self.tracker.turn_dwell = self.speed.turn_dwell()  # 읽는 속도에 맞춰 넘김 대기
        self.tracker.update(self.gaze, t)
        if self.tracker.furthest:
            self.speed.update(self.tracker.furthest.index, t)
        if self.tracker.should_turn and self.page_no < len(self.pages) - 1:
            self.go_to(self.page_no + 1)
