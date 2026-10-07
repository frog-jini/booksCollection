import pytest

from eyereader.speed import ReadingSpeed


def test_no_data_means_zero_wpm():
    assert ReadingSpeed().wpm() == 0


def test_hundred_words_in_a_minute_is_100_wpm():
    s = ReadingSpeed(window=120)
    s.update(0, t=0)
    s.update(100, t=60)
    assert s.wpm() == pytest.approx(100)


def test_rereading_does_not_count_as_progress():
    s = ReadingSpeed(window=120)
    s.update(0, t=0)
    s.update(50, t=30)
    s.update(10, t=40)  # 되돌아가 다시 읽기
    s.update(60, t=60)
    assert s.wpm() == pytest.approx(60)


def test_only_recent_window_counts():
    s = ReadingSpeed(window=10)
    s.update(0, t=0)
    s.update(1000, t=1)  # 오래전의 급격한 점프(페이지 건너뛰기 등)
    s.update(1000, t=20)
    s.update(1010, t=30)
    assert s.wpm() == pytest.approx(60)


def test_seconds_for_words_uses_measured_speed_or_default():
    s = ReadingSpeed(default_wpm=200)
    assert s.seconds_for(100) == pytest.approx(30)
    s.update(0, t=0)
    s.update(60, t=60)  # 60 WPM
    assert s.seconds_for(30) == pytest.approx(30)


# readme 2: 내 읽는 속도에 맞춰 — 느리게 읽으면 페이지도 천천히 넘긴다

def test_turn_dwell_follows_reading_speed_within_limits():
    fast, slow = ReadingSpeed(default_wpm=400), ReadingSpeed(default_wpm=60)
    assert fast.turn_dwell(words=3, low=0.6, high=2.0) == pytest.approx(0.6)  # 0.45초 → 최소값
    assert slow.turn_dwell(words=3, low=0.6, high=2.0) == pytest.approx(2.0)  # 3초 → 최대값
    mid = ReadingSpeed(default_wpm=150)
    assert mid.turn_dwell(words=3, low=0.6, high=2.0) == pytest.approx(1.2)
