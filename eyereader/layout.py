"""글을 화면 크기에 맞게 페이지/줄/단어 사각형으로 배치한다.

글자 폭 측정 함수(measure)를 주입받으므로 pygame 없이도 테스트할 수 있다.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable


@dataclass
class Word:
    text: str
    index: int  # 책 전체에서의 단어 순번
    x: float
    y: float
    w: float
    h: float

    @property
    def cx(self):
        return self.x + self.w / 2

    @property
    def cy(self):
        return self.y + self.h / 2


@dataclass
class Line:
    y: float
    words: list[Word] = field(default_factory=list)


@dataclass
class Page:
    lines: list[Line] = field(default_factory=list)

    @property
    def words(self) -> list[Word]:
        return [w for line in self.lines for w in line.words]

    @property
    def text(self) -> str:
        return "\n".join(" ".join(w.text for w in line.words) for line in self.lines)


def _wrap(text: str, width: float, measure, space_width: float) -> list[list[str]]:
    """원문 줄을 폭에 맞게 접는다. 빈 목록은 문단 사이 빈 줄."""
    rows: list[list[str]] = []
    for src_line in text.split("\n"):
        row: list[str] = []
        used = 0.0
        for word in src_line.split():
            ww = measure(word)
            needed = ww if not row else used + space_width + ww
            if row and needed > width:
                rows.append(row)
                row, used = [word], ww
            else:
                row.append(word)
                used = needed
        rows.append(row)
    return rows


def paginate(
    text: str,
    width: float,
    height: float,
    measure: Callable[[str], float],
    line_height: float,
    space_width: float,
    origin: tuple[float, float] = (0, 0),
) -> list[Page]:
    ox, oy = origin
    max_lines = max(1, int(height // line_height))
    pages: list[Page] = [Page()]
    index = 0

    for row in _wrap(text, width, measure, space_width):
        page = pages[-1]
        if len(page.lines) >= max_lines:
            page = Page()
            pages.append(page)
        if not row and not page.lines:
            continue  # 페이지 맨 위의 빈 줄은 버린다
        y = oy + len(page.lines) * line_height
        line = Line(y=y)
        x = ox
        for word in row:
            ww = measure(word)
            line.words.append(Word(word, index, x, y, ww, line_height))
            index += 1
            x += ww + space_width
        page.lines.append(line)

    for page in pages:  # 끝에 남은 빈 줄 정리
        while page.lines and not page.lines[-1].words:
            page.lines.pop()
    if len(pages) > 1 and not pages[-1].lines:
        pages.pop()
    return pages
