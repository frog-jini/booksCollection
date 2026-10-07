import json
import os
from datetime import datetime

import pytest

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")  # 모니터 없이 그리기 테스트
pygame = pytest.importorskip("pygame")

from eyereader.app import BG, WORD_HL, Reader  # noqa: E402
from eyereader.breaks import ReadingTimer  # noqa: E402
from eyereader.coach import ReadingCoach  # noqa: E402
from eyereader.llm import LLMError  # noqa: E402
from eyereader.loader import Book  # noqa: E402
from eyereader.monitor import FaceReading  # noqa: E402
from eyereader.posture import HeadPose  # noqa: E402

BOOK = Book("테스트", " ".join(f"word{i}" for i in range(2000)))


class FakeLLM:
    def __init__(self, fail=False):
        self.fail = fail

    def summarize(self, text):
        if self.fail:
            raise LLMError("연결 안 됨")
        return "요약입니다"

    def explain(self, word, context):
        return f"{word} 의 뜻"


def run_now(fn):  # 백그라운드 스레드 대신 바로 실행
    fn()


@pytest.fixture
def reader():
    pygame.font.init()
    return Reader(pygame.Surface((1000, 700)), BOOK, font_size=24, llm=FakeLLM(), background=run_now)


def first_word_center(r):
    w = r.session.page.words[0]
    return (w.cx, w.cy)


def test_book_is_split_into_several_pages(reader):
    assert len(reader.session.pages) > 3


def test_arrow_keys_turn_pages(reader):
    reader.handle_key(pygame.K_RIGHT)
    reader.handle_key(pygame.K_RIGHT)
    reader.handle_key(pygame.K_LEFT)
    assert reader.session.page_no == 1


def test_summary_opens_panel_and_pauses_reading_until_closed(reader):
    reader.handle_key(pygame.K_s)
    assert reader.panel == "요약입니다" and reader.session.paused
    assert reader.handle_key(pygame.K_RETURN) is True
    assert reader.panel is None and not reader.session.paused


def test_explain_current_word(reader):
    reader.handle_key(pygame.K_e)
    assert reader.panel is None  # 아직 읽는 단어가 없음
    reader.session.step(first_word_center(reader), t=0)
    reader.handle_key(pygame.K_e)
    assert reader.panel == "'word0': word0 의 뜻"


def test_llm_failure_explains_how_to_get_free_llm():
    pygame.font.init()
    r = Reader(pygame.Surface((1000, 700)), BOOK, llm=FakeLLM(fail=True), background=run_now)
    r.handle_key(pygame.K_s)
    assert "연결 안 됨" in r.panel and "ollama" in r.panel


def test_escape_closes_panel_first_then_quits(reader):
    reader.handle_key(pygame.K_s)
    assert reader.handle_key(pygame.K_ESCAPE) is True and reader.panel is None
    assert reader.handle_key(pygame.K_ESCAPE) is False


def test_g_toggles_gaze_marker(reader):
    reader.handle_key(pygame.K_g)
    assert reader.show_gaze is False


def test_word_being_read_is_highlighted_in_color(reader):
    reader.session.step(first_word_center(reader), t=0)
    reader.draw()
    w = reader.session.tracker.word
    pixels = {tuple(reader.screen.get_at((int(x), int(w.cy)))[:3]) for x in range(int(w.x - 3), int(w.x + w.w))}
    assert WORD_HL in pixels


# --- 18b. 독서 도우미를 리더 화면에 (readme 11) ----------------------------------

FACE = FaceReading(present=True, pose=HeadPose(55, 0, 0, 0), openness=0.3)


def watch(r, gaze, seconds, start=0.0, reading=FACE, step=0.1):
    t = start
    while t < start + seconds:
        r.session.step(gaze, t)
        r.observe(t, reading)
        t += step
    return t


def test_gaze_time_builds_heatmap_for_current_page(reader):
    watch(reader, first_word_center(reader), 3)
    hm = reader.heatmaps[0]
    assert hm.total_seconds == pytest.approx(3, abs=0.15)
    (x, y), _ = hm.hottest(1)[0]
    w = reader.session.page.words[0]
    assert abs(x - w.cx) <= hm.cell and abs(y - w.cy) <= hm.cell


def test_looking_at_text_counts_as_focused_reading(reader):
    watch(reader, first_word_center(reader), 15)
    assert reader.coach.focus.score() == 100


def test_coach_alerts_appear_on_screen_for_a_while():
    pygame.font.init()
    coach = ReadingCoach(timer=ReadingTimer(break_after=5))
    r = Reader(pygame.Surface((1000, 700)), BOOK, llm=FakeLLM(), background=run_now, coach=coach)
    t = watch(r, first_word_center(r), 6)
    assert [a.title for a in r.visible_toasts(t)] == ["잠시 쉬어가는 건 어떨까요?"]
    assert r.visible_toasts(t + 30) == []


def test_mouse_mode_without_face_still_measures_reading(reader):
    watch(reader, first_word_center(reader), 12, reading=None)
    assert reader.coach.timer.reading_seconds == pytest.approx(12, abs=0.2)


def test_status_line_shows_focus_posture_and_reading_time(reader):
    watch(reader, first_word_center(reader), 12)
    text = reader.status_text()
    assert "집중 100" in text and "자세 좋음" in text and "독서 0분" in text


def test_h_shows_heatmap_over_the_page(reader):
    watch(reader, (20, 20), 2)  # 글자가 없는 여백을 오래 봄
    reader.draw()
    assert tuple(reader.screen.get_at((20, 20)))[:3] == BG
    reader.handle_key(pygame.K_h)
    reader.draw()
    assert tuple(reader.screen.get_at((20, 20)))[:3] != BG


def test_finishing_saves_report_and_heatmap_images(reader, tmp_path):
    watch(reader, first_word_center(reader), 3)
    reader.handle_key(pygame.K_RIGHT)
    watch(reader, first_word_center(reader), 2, start=3)
    path = reader.save_report(tmp_path, now=datetime(2026, 10, 7, 15, 0))
    data = json.loads(path.read_text(encoding="utf-8"))
    assert data["title"] == "테스트"
    assert [p["page"] for p in data["pages"]] == [1, 2]
    images = sorted(p.name for p in (tmp_path / path.stem).iterdir())
    assert images == ["page-001.png", "page-002.png"]
