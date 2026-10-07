from eyereader.focus import FocusMeter

STEP = 0.5


def feed(m, pattern, start=0.0):
    t = start
    for on, seconds in pattern:
        for _ in range(round(seconds / STEP)):
            m.update(on, t)
            t += STEP
    return t


def test_full_attention_scores_100():
    m = FocusMeter(window=60)
    feed(m, [(True, 60)])
    assert m.score() == 100


def test_each_look_away_lowers_the_score():
    m = FocusMeter(window=60, look_away=1.0, penalty=10)
    feed(m, [(True, 18), (False, 2)] * 3)  # 1분에 2초씩 3번 딴 데 봄
    assert m.score() == 60  # 화면 본 비율 90% − 3회 × 10
    assert m.look_aways() == 3


def test_tiny_glances_are_not_penalized():
    m = FocusMeter(window=60, look_away=1.0)
    feed(m, [(True, 9.5), (False, 0.5)] * 6)
    assert m.look_aways() == 0 and m.score() == 95


def test_score_never_goes_below_zero():
    m = FocusMeter(window=60)
    feed(m, [(True, 1), (False, 2)] * 20)
    assert m.score() == 0


def test_not_enough_data_yet():
    m = FocusMeter(min_data=10)
    feed(m, [(True, 5)])
    assert m.score() is None


def test_only_recent_minute_counts():
    m = FocusMeter(window=60)
    feed(m, [(False, 60), (True, 60)])
    assert m.score() == 100


def test_score_history_per_minute_for_report():
    m = FocusMeter(window=60, look_away=1.0, penalty=10)
    # 첫 1분은 집중, 둘째 1분은 3번 딴 데 봄. 2분이 '지나야' 둘째 점수가 기록된다.
    feed(m, [(True, 60)] + [(True, 18), (False, 2)] * 3 + [(True, 0.5)])
    assert len(m.history) == 2
    assert m.history[0] == 100 and 55 <= m.history[1] <= 65
