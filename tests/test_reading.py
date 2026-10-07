from eyereader.layout import paginate
from eyereader.reading import ReadingTracker

# 글자당 10px, 줄 높이 40px. 한 줄 = "a0xx b0xx c0xx d0xx" (폭 190), 세 줄
TEXT = "\n".join(" ".join(f"{c}{i}xx" for c in "abcd") for i in range(3))


def page():
    return paginate(TEXT, width=200, height=400, measure=lambda s: len(s) * 10,
                    line_height=40, space_width=10)[0]


def at(p, line, word):
    w = p.lines[line].words[word]
    return (w.cx, w.cy)


# --- 6a. 지금 읽는 단어 ---------------------------------------------------------

def test_gaze_on_word_selects_that_word_and_line():
    p = page()
    tr = ReadingTracker(p)
    assert tr.update(at(p, 0, 2), t=0).text == "c0xx"
    assert tr.line_idx == 0


def test_brief_glance_at_another_line_is_ignored_but_staying_switches():
    p = page()
    tr = ReadingTracker(p, line_switch_time=0.3)
    tr.update(at(p, 0, 0), t=0)
    assert tr.update(at(p, 2, 0), t=0.1).text == "a0xx"  # 웹캠 세로 오차일 수 있다
    assert tr.update(at(p, 2, 0), t=0.5).text == "a2xx"


def test_return_sweep_moves_to_next_line_even_with_vertical_error():
    p = page()
    tr = ReadingTracker(p)
    y0 = at(p, 0, 0)[1]
    tr.update(at(p, 0, 0), t=0)
    tr.update(at(p, 0, 3), t=1)  # 줄 끝까지 읽고
    # 눈은 줄 처음으로 돌아왔는데 웹캠은 y 를 여전히 0번 줄로 본다
    assert tr.update((p.lines[0].words[0].cx, y0 + 5), t=1.1).text == "a1xx"


def test_lost_gaze_keeps_current_word():
    p = page()
    tr = ReadingTracker(p)
    tr.update(at(p, 0, 1), t=0)
    assert tr.update(None, t=0.1).text == "b0xx"


def test_furthest_word_tracks_progress_not_rereading():
    p = page()
    tr = ReadingTracker(p)
    tr.update(at(p, 0, 3), t=0)
    tr.update(at(p, 0, 1), t=0.2)  # 같은 줄 안에서 되돌아 읽기
    assert tr.word.text == "b0xx"
    assert tr.furthest.text == "d0xx"
