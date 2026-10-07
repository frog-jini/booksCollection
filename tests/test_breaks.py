import pytest

from eyereader.breaks import ReadingTimer

MIN = 60


def run(timer, present, start, seconds, step=0.5):
    alerts, t = [], start
    while t < start + seconds:
        alerts += timer.update(present, t)
        t += step
    return alerts, t


def test_suggests_a_break_after_long_continuous_reading():
    timer = ReadingTimer(break_after=38 * MIN)
    alerts, t = run(timer, True, 0, 38 * MIN - 5)
    assert alerts == []
    alerts, _ = run(timer, True, t, 10)
    assert len(alerts) == 1
    assert alerts[0].kind == "break"
    assert alerts[0].title == "잠시 쉬어가는 건 어떨까요?"
    assert alerts[0].message == "38분 동안 계속 독서 중입니다."


def test_reminds_again_if_reader_keeps_going():
    timer = ReadingTimer(break_after=30 * MIN, repeat=10 * MIN)
    alerts, _ = run(timer, True, 0, 41 * MIN)
    assert [a.message for a in alerts] == ["30분 동안 계속 독서 중입니다.", "40분 동안 계속 독서 중입니다."]


def test_short_glance_away_does_not_count_as_a_break():
    timer = ReadingTimer(break_after=30 * MIN, rest=5 * MIN)
    _, t = run(timer, True, 0, 20 * MIN)
    _, t = run(timer, False, t, 1 * MIN)  # 잠깐 딴 데 봄
    alerts, _ = run(timer, True, t, 10 * MIN + 5)
    assert len(alerts) == 1


def test_real_rest_resets_the_reading_clock():
    timer = ReadingTimer(break_after=30 * MIN, rest=5 * MIN)
    _, t = run(timer, True, 0, 25 * MIN)
    _, t = run(timer, False, t, 6 * MIN)  # 제대로 쉼
    assert timer.continuous_seconds == 0
    alerts, _ = run(timer, True, t, 25 * MIN)
    assert alerts == []


def test_measures_reading_time_and_time_looking_away():
    timer = ReadingTimer(look_away=1.0)
    _, t = run(timer, True, 0, 60)
    _, t = run(timer, False, t, 0.5)  # 너무 짧아서 '눈 돌림'으로 치지 않음
    _, t = run(timer, True, t, 30)
    _, t = run(timer, False, t, 4)
    _, t = run(timer, True, t, 10)
    assert timer.reading_seconds == pytest.approx(100, abs=1)
    assert timer.away_seconds == pytest.approx(4.5, abs=1)
    assert timer.look_aways == 1


def test_long_gap_between_updates_is_not_counted_as_reading():
    timer = ReadingTimer()
    timer.update(True, 0)
    timer.update(True, 3600)  # 컴퓨터가 잠자기에 들어갔다 깨어남
    assert timer.reading_seconds <= 1.0
