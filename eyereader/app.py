"""눈동자 추적 책 리더 실행 진입점.

    python -m eyereader.app 책.pdf            # 웹캠으로 읽기
    python -m eyereader.app 책.epub --mouse   # 웹캠 없이 마우스로 시험
    python -m eyereader.app --search "alice"  # Project Gutenberg 에서 찾아 읽기
    python -m eyereader.app --monitor         # 다른 앱으로 읽는 동안 자세·휴식·졸음 알림
"""

from __future__ import annotations

import textwrap
import threading
import time
from datetime import datetime
from pathlib import Path

import numpy as np
import pygame

from .breaks import ReadingTimer
from .cli import parse_args, resolve_book_path
from .coach import ReadingCoach
from .gaze.calibration import Calibrator, calibration_points
from .heatmap import GazeHeatmap, PageHeatmaps
from .layout import paginate
from .llm import LLMClient, LLMError
from .loader import load_book
from .monitor import FaceReading, analyze, run_monitor
from .posture import DEFAULT_HFOV, PostureMonitor
from .report import save_report as write_report
from .session import ReadingSession

CACHE_DIR = Path.home() / ".cache" / "eyereader"
CALIBRATION_PATH = CACHE_DIR / "calibration.json"
FONT_NAMES = ["nanumgothic", "notosanscjkkr", "notosanscjk", "notosanskr", "malgungothic",
              "applesdgothicneo", "applegothic"]

BG = (250, 246, 236)
TEXT = (40, 40, 40)
READ = (160, 160, 160)
LINE_HL = (255, 243, 190)
WORD_HL = (255, 196, 80)
GAZE = (220, 50, 50)
PANEL = (35, 40, 50)
HEAT = (230, 60, 40)
TOAST_BG = (60, 70, 90)
MARGIN = 80
STATUS_H = 40
TOAST_SECONDS = 8
LLM_HELP = "무료 LLM 사용법: https://ollama.com 설치 후 `ollama pull llama3.2`"


def load_font(size):
    return pygame.font.Font(pygame.font.match_font(FONT_NAMES), size)


def _in_thread(fn):
    threading.Thread(target=fn, daemon=True).start()


class Reader:
    """읽기 화면: ReadingSession 의 상태를 그리고 키 입력을 처리한다."""

    def __init__(self, screen, book, font_size=30, llm=None, background=_in_thread, coach=None, heat_cell=40):
        self.screen = screen
        self.book = book
        self.font = load_font(font_size)
        self.small = load_font(18)
        w, h = screen.get_size()
        pages = paginate(
            book.text,
            width=w - 2 * MARGIN,
            height=h - 2 * MARGIN - STATUS_H,
            measure=lambda s: self.font.size(s)[0],
            line_height=int(self.font.get_linesize() * 1.9),  # 줄 간격을 넓혀 웹캠 세로 오차를 흡수
            space_width=self.font.size(" ")[0],
            origin=(MARGIN, MARGIN),
        )
        self.session = ReadingSession(pages)
        self.llm = llm or LLMClient()
        self.background = background
        self.show_gaze = True
        self._panel: str | None = None
        # 독서 도우미(readme 11): 자세·휴식·졸음·집중도, 페이지별 시선 heatmap
        self.coach = coach or ReadingCoach()
        self.heatmaps = PageHeatmaps(w, h, heat_cell)
        self.show_heatmap = False
        self._toasts: list[tuple[object, float]] = []  # (알림, 사라질 시각)
        self._now: float | None = None

    @property
    def panel(self) -> str | None:
        return self._panel

    @panel.setter
    def panel(self, text):
        self._panel = text
        self.session.paused = text is not None  # 패널을 보는 동안 추적·넘김 중지

    # --- 입력 ---------------------------------------------------------------
    def handle_key(self, key) -> bool:
        """키 하나를 처리한다. 종료해야 하면 False."""
        s = self.session
        if self.panel is not None:
            if key in (pygame.K_RETURN, pygame.K_ESCAPE):
                self.panel = None
            return True
        if key == pygame.K_ESCAPE:
            return False
        if key in (pygame.K_RIGHT, pygame.K_PAGEDOWN):
            s.go_to(s.page_no + 1)
        elif key in (pygame.K_LEFT, pygame.K_PAGEUP):
            s.go_to(s.page_no - 1)
        elif key == pygame.K_s:
            self.ask_llm("summary")
        elif key == pygame.K_e:
            self.ask_llm("explain")
        elif key == pygame.K_g:
            self.show_gaze = not self.show_gaze
        elif key == pygame.K_h:
            self.show_heatmap = not self.show_heatmap
        return True

    # --- 독서 도우미 ---------------------------------------------------------
    def _text_area(self) -> pygame.Rect:
        w, h = self.screen.get_size()
        return pygame.Rect(MARGIN, MARGIN, w - 2 * MARGIN, h - 2 * MARGIN - STATUS_H).inflate(40, 40)

    def observe(self, t: float, reading: FaceReading | None):
        """한 프레임의 얼굴 정보(웹캠)를 독서 도우미에 넘긴다. 마우스 모드면 reading=None."""
        dt = 0.0 if self._now is None else min(max(t - self._now, 0.0), 0.5)
        self._now = t
        gaze = self.session.gaze
        present = reading.present if reading is not None else gaze is not None
        if present and gaze is not None:
            self.heatmaps.add(self.session.page_no, gaze[0], gaze[1], dt)
        alerts = self.coach.update(
            t,
            pose=reading.pose if reading else None,
            openness=reading.openness if reading else None,
            present=present,
            on_target=present and gaze is not None and self._text_area().collidepoint(gaze),
        )
        self._toasts += [(a, t + TOAST_SECONDS) for a in alerts]
        return alerts

    def visible_toasts(self, t: float):
        return [a for a, until in self._toasts if t < until]

    def status_text(self) -> str:
        sess, st = self.session, self.coach.status()
        focus = st["focus"] if st["focus"] is not None else "-"
        posture = {True: "좋음", False: "확인 필요", None: "-"}[st["posture_ok"]]
        return (f"{self.book.title}   {sess.page_no + 1}/{len(sess.pages)}   {sess.speed.wpm():.0f} WPM   "
                f"집중 {focus}   자세 {posture}   독서 {int(st['reading_minutes'])}분   "
                "←→ 페이지  S 요약  E 설명  H heatmap  C 재보정  G 시선점  ESC 종료")

    def heatmap_image(self, page_no: int) -> pygame.Surface:
        """보고서용: 그 페이지 글자 위에 heatmap 을 겹친 그림."""
        img = pygame.Surface(self.screen.get_size())
        img.fill(BG)
        for word in self.session.pages[page_no].words:
            glyph = self.font.render(word.text, True, TEXT)
            img.blit(glyph, (word.x, word.y + (word.h - glyph.get_height()) / 2))
        self._draw_heat(img, self.heatmaps[page_no])
        return img

    def save_report(self, directory, now: datetime | None = None) -> Path:
        """독서 보고서(JSON)와 페이지별 heatmap 그림(같은 이름의 폴더)을 저장한다."""
        path = write_report(self.coach.report(self.book.title, self.heatmaps), directory, now)
        image_dir = path.with_suffix("")
        image_dir.mkdir(parents=True, exist_ok=True)
        for page_no in sorted(self.heatmaps.pages):
            pygame.image.save(self.heatmap_image(page_no), str(image_dir / f"page-{page_no + 1:03d}.png"))
        return path

    def ask_llm(self, kind):
        word = self.session.tracker.word
        if kind == "explain" and word is None:
            return
        page_text = self.session.page.text
        self.panel = "LLM 에게 묻는 중…"

        def work():
            try:
                if kind == "summary":
                    self.panel = self.llm.summarize(page_text)
                else:
                    self.panel = f"'{word.text}': " + self.llm.explain(word.text, page_text)
            except LLMError as e:
                self.panel = f"{e}\n\n{LLM_HELP}"

        self.background(work)

    # --- 그리기 --------------------------------------------------------------
    def draw(self):
        s, tr = self.screen, self.session.tracker
        s.fill(BG)
        if tr.line_idx is not None and tr.lines:  # 읽는 줄
            line = tr.lines[tr.line_idx]
            first, last = line.words[0], line.words[-1]
            pygame.draw.rect(s, LINE_HL, (first.x - 8, first.y, last.x + last.w - first.x + 16, first.h),
                             border_radius=6)
        if tr.word is not None:  # 읽는 단어
            w = tr.word
            pygame.draw.rect(s, WORD_HL, (w.x - 4, w.y + 4, w.w + 8, w.h - 8), border_radius=6)
        furthest = tr.furthest.index if tr.furthest else -1
        for word in self.session.page.words:
            color = READ if word.index < furthest and word is not tr.word else TEXT  # 읽은 곳은 흐리게
            img = self.font.render(word.text, True, color)
            s.blit(img, (word.x, word.y + (word.h - img.get_height()) / 2))
        if self.show_heatmap:
            self._draw_heat(s, self.heatmaps[self.session.page_no])
        self.screen.blit(self.small.render(self.status_text(), True, READ),
                         (MARGIN, self.screen.get_height() - STATUS_H))
        if self.show_gaze and self.session.gaze:
            pygame.draw.circle(s, GAZE, [int(v) for v in self.session.gaze], 8, 2)
        if self._now is not None:
            self._draw_toasts(self.visible_toasts(self._now))
        if self.panel is not None:
            self._draw_panel(self.panel)

    def _draw_heat(self, surface, heatmap: GazeHeatmap):
        layer = pygame.Surface(surface.get_size(), pygame.SRCALPHA)
        c = heatmap.cell
        for (row, col), value in np.ndenumerate(heatmap.normalized()):
            if value > 0:
                layer.fill((*HEAT, int(40 + 150 * value)), (col * c, row * c, c, c))
        surface.blit(layer, (0, 0))

    def _draw_toasts(self, alerts):
        y = 16
        for alert in alerts[-3:]:
            lines = [alert.title, alert.message]
            width = max(self.small.size(l)[0] for l in lines) + 40
            rect = pygame.Rect((self.screen.get_width() - width) // 2, y, width,
                               len(lines) * self.small.get_linesize() + 20)
            pygame.draw.rect(self.screen, TOAST_BG, rect, border_radius=10)
            for i, line in enumerate(lines):
                self.screen.blit(self.small.render(line, True, (255, 255, 255)),
                                 (rect.x + 20, rect.y + 10 + i * self.small.get_linesize()))
            y = rect.bottom + 8

    def _draw_panel(self, text):
        sw, sh = self.screen.get_size()
        rect = pygame.Rect(MARGIN, sh // 2, sw - 2 * MARGIN, sh // 2 - MARGIN)
        pygame.draw.rect(self.screen, PANEL, rect, border_radius=12)
        y = rect.y + 20
        chars = max(20, (rect.w - 40) // self.small.size("가")[0])
        for para in (text + "\n\n(Enter/ESC 로 닫기)").split("\n"):
            for row in textwrap.wrap(para, chars) or [""]:
                self.screen.blit(self.small.render(row, True, (240, 240, 240)), (rect.x + 20, y))
                y += self.small.get_linesize()


def calibrate(screen, source, font) -> Calibrator | None:
    """9개 점을 차례로 바라보게 하며 보정 데이터를 모은다. ESC 면 None."""
    w, h = screen.get_size()
    clock = pygame.time.Clock()

    def message(text):
        screen.fill(BG)
        img = font.render(text, True, TEXT)
        screen.blit(img, img.get_rect(center=(w / 2, h / 2)))
        pygame.display.flip()

    message("보정: 머리를 고정하고 빨간 점을 바라보세요. SPACE 로 시작")
    waiting = True
    while waiting:
        for e in pygame.event.get():
            if e.type == pygame.QUIT or (e.type == pygame.KEYDOWN and e.key == pygame.K_ESCAPE):
                return None
            if e.type == pygame.KEYDOWN and e.key == pygame.K_SPACE:
                waiting = False
        clock.tick(30)

    cal = Calibrator()
    for point in calibration_points(w, h, margin=MARGIN):
        start = time.monotonic()
        while (elapsed := time.monotonic() - start) < 2.0:
            pygame.event.pump()
            screen.fill(BG)
            pygame.draw.circle(screen, GAZE, point, 18 if elapsed < 0.7 else 10)
            pygame.display.flip()
            feature = source.read_feature()
            if elapsed >= 0.7 and feature is not None:  # 처음 0.7초는 눈이 점으로 옮겨가는 시간
                cal.add(feature, point)
            clock.tick(30)
    try:
        cal.fit()
    except ValueError as e:
        message(f"보정 실패: {e} — 얼굴이 카메라에 보이는지 확인하세요")
        time.sleep(2)
        return None
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cal.save(CALIBRATION_PATH)
    return cal


def run(book, source, size=None, font_size=30, reuse_calibration=False, max_frames=None,
        coach=None, hfov_deg=DEFAULT_HFOV, reports_dir="reports"):
    pygame.init()
    screen = pygame.display.set_mode(size or (0, 0), 0 if size else pygame.FULLSCREEN)
    pygame.display.set_caption(f"EyeReader - {book.title}")
    reader = Reader(screen, book, font_size=font_size, coach=coach)

    cal = None
    if source.needs_calibration:
        if reuse_calibration and CALIBRATION_PATH.exists():
            cal = Calibrator.load(CALIBRATION_PATH)
        else:
            cal = calibrate(screen, source, reader.font)
            if cal is None:
                pygame.quit()
                return

    def read_gaze():
        """(시선 좌표, 얼굴 정보). 마우스 모드는 얼굴 정보가 없다."""
        if not source.needs_calibration:
            return source.read_point(), None
        reading = analyze(source.read_frame(), hfov_deg)
        return (cal.predict(reading.feature) if reading.feature is not None else None), reading

    clock = pygame.time.Clock()
    running, frames = True, 0
    while running and (max_frames is None or frames < max_frames):
        for e in pygame.event.get():
            if e.type == pygame.QUIT:
                running = False
            elif e.type == pygame.KEYDOWN:
                if e.key == pygame.K_c and source.needs_calibration and reader.panel is None:
                    cal = calibrate(screen, source, reader.font) or cal
                else:
                    running = reader.handle_key(e.key)
        gaze, reading = read_gaze()
        now = time.monotonic()
        reader.session.step(gaze, now)
        reader.observe(now, reading)
        reader.draw()
        pygame.display.flip()
        clock.tick(30)
        frames += 1
    source.close()
    path = reader.save_report(reports_dir)
    pygame.quit()
    print(f"독서 보고서: {path}  (페이지별 heatmap: {path.with_suffix('')}/)")


def build_coach(args) -> ReadingCoach:
    return ReadingCoach(posture=PostureMonitor(min_distance=args.min_distance),
                        timer=ReadingTimer(break_after=args.break_minutes * 60))


def main(argv=None):
    from .gaze.sources import MouseSource, WebcamSource

    args = parse_args(argv)
    if args.monitor:
        print("감시 모드: 다른 앱으로 읽는 동안 자세·휴식·졸음을 알려 드립니다. 끝내려면 Ctrl+C")
        report = run_monitor(WebcamSource(args.camera), build_coach(args), hfov_deg=args.camera_fov)
        print(f"독서 보고서: {write_report(report, args.reports_dir)}")
        return
    book = load_book(resolve_book_path(args))
    source = MouseSource() if args.mouse else WebcamSource(args.camera)
    run(book, source, size=args.window, font_size=args.font_size, reuse_calibration=args.reuse_calibration,
        coach=build_coach(args), hfov_deg=args.camera_fov, reports_dir=args.reports_dir)


if __name__ == "__main__":
    main()
