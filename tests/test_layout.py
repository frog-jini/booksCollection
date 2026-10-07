from eyereader.layout import paginate


def measure(s):  # 글자당 10px 고정폭 — pygame 없이 테스트
    return len(s) * 10


def params(**kw):
    base = dict(width=200, height=100, measure=measure, line_height=20, space_width=10)
    base.update(kw)
    return base


TEXT = " ".join(f"w{i}" for i in range(100))


def test_all_words_are_kept_in_order():
    pages = paginate(TEXT, **params())
    assert [w.text for p in pages for w in p.words] == TEXT.split()


def test_words_have_global_index_across_pages():
    pages = paginate(TEXT, **params())
    assert [w.index for p in pages for w in p.words] == list(range(100))


def test_lines_fit_in_width():
    for page in paginate(TEXT, **params()):
        for line in page.lines:
            last = line.words[-1]
            assert last.x + last.w <= 200


def test_page_holds_only_as_many_lines_as_fit():
    pages = paginate(TEXT, **params())
    assert len(pages) > 1
    assert all(len(p.lines) <= 100 // 20 for p in pages)


def test_word_boxes_move_right_then_down():
    page = paginate("aa bb cc dd", **params(width=60))[0]
    # "aa bb" = 20+10+20 = 50 <= 60, "cc" 는 다음 줄
    assert [[w.text for w in l.words] for l in page.lines] == [["aa", "bb"], ["cc", "dd"]]
    aa, bb = page.lines[0].words
    assert (aa.x, aa.y, aa.w, aa.h) == (0, 0, 20, 20)
    assert bb.x == 30
    assert page.lines[1].words[0].y == 20
    assert (aa.cx, aa.cy) == (10, 10)


def test_newline_starts_new_line_and_blank_line_keeps_gap():
    page = paginate("a\nb\n\nc", **params())[0]
    assert {w.text: w.y for w in page.words} == {"a": 0, "b": 20, "c": 60}


def test_origin_shifts_every_box():
    page = paginate("a b", **params(origin=(5, 7)))[0]
    assert (page.words[0].x, page.words[0].y) == (5, 7)


def test_overlong_word_gets_its_own_line():
    page = paginate("x " + "y" * 50 + " z", **params())[0]
    assert [[w.text for w in l.words] for l in page.lines] == [["x"], ["y" * 50], ["z"]]


def test_page_text_joins_words_and_lines():
    assert paginate("aa bb\ncc", **params())[0].text == "aa bb\ncc"


def test_empty_text_gives_one_empty_page():
    pages = paginate("", **params())
    assert len(pages) == 1 and pages[0].words == []
