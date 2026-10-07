"""페이지별 시선 heatmap: 화면을 cell 크기 칸으로 나눠, 칸마다 바라본 시간(초)을 모은다."""

from __future__ import annotations

import numpy as np


class GazeHeatmap:
    def __init__(self, width: int, height: int, cell: int = 40):
        self.width, self.height, self.cell = width, height, cell
        self.grid = np.zeros((-(-height // cell), -(-width // cell)))  # 올림 나눗셈

    @property
    def total_seconds(self) -> float:
        return float(self.grid.sum())

    def add(self, x, y, seconds: float):
        if x is None or y is None or not (0 <= x < self.width and 0 <= y < self.height):
            return
        self.grid[int(y // self.cell), int(x // self.cell)] += seconds

    def normalized(self) -> np.ndarray:
        top = self.grid.max()
        return self.grid / top if top > 0 else self.grid.copy()

    def hottest(self, n: int = 5) -> list[tuple[tuple[float, float], float]]:
        """가장 오래 본 칸 n 개: [((가운데 x, 가운데 y), 초), ...]"""
        order = np.argsort(self.grid, axis=None)[::-1][:n]
        cells = []
        for flat in order:
            row, col = divmod(int(flat), self.grid.shape[1])
            if self.grid[row, col] > 0:
                centre = ((col + 0.5) * self.cell, (row + 0.5) * self.cell)
                cells.append((centre, float(self.grid[row, col])))
        return cells


class PageHeatmaps:
    def __init__(self, width: int, height: int, cell: int = 40):
        self.width, self.height, self.cell = width, height, cell
        self.pages: dict[int, GazeHeatmap] = {}

    def __getitem__(self, page_no: int) -> GazeHeatmap:
        if page_no not in self.pages:
            self.pages[page_no] = GazeHeatmap(self.width, self.height, self.cell)
        return self.pages[page_no]

    def add(self, page_no: int, x, y, seconds: float):
        self[page_no].add(x, y, seconds)

    def seconds_per_page(self) -> dict[int, float]:
        return {p: h.total_seconds for p, h in sorted(self.pages.items())}
