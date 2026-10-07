import os

import pytest

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")  # 모니터 없이 그리기 테스트
pygame = pytest.importorskip("pygame")

from eyereader.app import WORD_HL, Reader  # noqa: E402
from eyereader.llm import LLMError  # noqa: E402
from eyereader.loader import Book  # noqa: E402

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
