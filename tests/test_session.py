from eyereader.layout import paginate
from eyereader.session import ReadingSession
from eyereader.speed import ReadingSpeed

# 한 페이지 = 2줄 × 단어 4개, 총 3페이지. 글자당 10px, 줄 높이 40px.
TEXT = " ".join(f"w{i:02d}x" for i in range(24))


def pages():
    return paginate(TEXT, width=200, height=80, measure=lambda s: len(s) * 10,
                    line_height=40, space_width=10)


def at(session, line, word):
    w = session.page.lines[line].words[word]
    return (w.cx, w.cy)


def read_page(session, t=0.0):
    """사람처럼 한 페이지를 읽는다: 줄마다 처음→끝, 그리고 다음 줄 처음으로."""
    for line in range(len(session.page.lines)):
        for word in range(4):
            session.step(at(session, line, word), t)
            t += 0.3
    session.step(at(session, 0, 0), t)  # 다음 페이지 첫 줄로 가려는 눈
    return t + 0.3


def test_starts_on_first_page_and_highlights_word_under_gaze():
    s = ReadingSession(pages())
    assert s.page_no == 0
    s.step(at(s, 0, 2), t=0)
    assert s.tracker.word.text == "w02x"
    assert s.gaze == at(s, 0, 2)


def test_reading_to_end_of_page_turns_to_next_page_automatically():
    s = ReadingSession(pages())
    read_page(s)
    assert s.page_no == 1
    assert s.tracker.word is None  # 새 페이지는 처음부터


def test_never_turns_past_last_page():
    s = ReadingSession(pages())
    t = 0.0
    for _ in range(5):
        t = read_page(s, t)
    assert s.page_no == 2


def test_manual_page_moves_are_clamped():
    s = ReadingSession(pages())
    s.go_to(99)
    assert s.page_no == 2
    s.go_to(-5)
    assert s.page_no == 0


def test_lost_gaze_keeps_last_position():
    s = ReadingSession(pages())
    s.step(at(s, 0, 1), t=0)
    s.step(None, t=0.1)  # 깜빡임/얼굴 놓침
    assert s.gaze == at(s, 0, 1)
    assert s.tracker.word.text == "w01x"


def test_paused_session_neither_tracks_nor_turns():
    s = ReadingSession(pages())
    s.paused = True
    read_page(s)
    assert s.page_no == 0 and s.tracker.word is None


def test_reading_speed_is_measured_while_reading():
    s = ReadingSession(pages())
    read_page(s)
    assert s.speed.wpm() > 0


def test_page_turn_wait_follows_reading_speed():
    slow, fast = ReadingSession(pages()), ReadingSession(pages())
    slow.speed, fast.speed = ReadingSpeed(default_wpm=60), ReadingSpeed(default_wpm=400)
    slow.step(at(slow, 0, 0), t=0)
    fast.step(at(fast, 0, 0), t=0)
    assert slow.tracker.turn_dwell > fast.tracker.turn_dwell
