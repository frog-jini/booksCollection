import pytest

from eyereader.fatigue import DrowsinessMonitor, eye_openness
from eyereader.gaze.features import LEFT_EYE, RIGHT_EYE

OPEN, CLOSED = 0.30, 0.05
STEP = 1 / 30


def landmarks(openness):
    pts = [(0.0, 0.0)] * 478
    for eye, x0 in ((LEFT_EYE, 0.30), (RIGHT_EYE, 0.60)):
        pts[eye.corner_a], pts[eye.corner_b] = (x0, 0.4), (x0 + 0.1, 0.4)
        pts[eye.top], pts[eye.bottom] = (x0 + 0.05, 0.4), (x0 + 0.05, 0.4 + 0.1 * openness)
    return pts


def test_eye_openness_is_eye_height_over_width():
    assert eye_openness(landmarks(0.3)) == pytest.approx(0.3)
    assert eye_openness(None) is None


def stream(m, pattern, start=0.0):
    """pattern: [(openness, 초), ...] 를 30fps 로 흘려보낸다."""
    alerts, t = [], start
    for value, seconds in pattern:
        for _ in range(round(seconds / STEP)):
            alerts += m.update(value, t)
            t += STEP
    return alerts, t


def normal_reading(seconds):
    """4초마다 0.2초씩 깜빡이며 읽기 (분당 15회)."""
    return [(OPEN, 3.8), (CLOSED, 0.2)] * round(seconds / 4)


def test_blinks_are_counted_per_minute():
    m = DrowsinessMonitor(window=60)
    alerts, _ = stream(m, normal_reading(60))
    assert alerts == []
    assert m.blink_rate() == pytest.approx(15, abs=1)
    assert m.perclos() == pytest.approx(0.05, abs=0.01)  # 눈 감은 시간 비율


def test_eyes_closed_for_over_a_second_is_drowsiness():
    m = DrowsinessMonitor(microsleep=1.0)
    _, t = stream(m, normal_reading(20))
    alerts, _ = stream(m, [(CLOSED, 1.5), (OPEN, 1)], t)
    assert [a.kind for a in alerts] == ["drowsy"]
    assert alerts[0].title == "졸음이 감지되었습니다."
    assert m.long_closures == 1


def test_eyes_often_half_closed_raises_perclos_alert():
    m = DrowsinessMonitor(window=60, perclos_limit=0.15, microsleep=10)
    # 눈을 자주, 조금 길게(0.8초) 감음 → 감은 시간 비율 20%
    alerts, _ = stream(m, [(OPEN, 3.2), (CLOSED, 0.8)] * 16)
    assert m.perclos() == pytest.approx(0.2, abs=0.02)
    assert [a.kind for a in alerts] == ["drowsy"]


def test_perclos_needs_a_full_window_before_judging():
    m = DrowsinessMonitor(window=60, perclos_limit=0.15, microsleep=10)
    alerts, _ = stream(m, [(OPEN, 3.2), (CLOSED, 0.8)] * 5)  # 20초뿐
    assert alerts == []


def test_drowsy_alert_has_cooldown():
    m = DrowsinessMonitor(microsleep=1.0, cooldown=120)
    alerts, _ = stream(m, [(CLOSED, 1.5), (OPEN, 5)] * 5)
    assert len(alerts) == 1


def test_lost_face_is_not_counted_as_closed_eyes():
    m = DrowsinessMonitor(microsleep=1.0)
    alerts, _ = stream(m, [(OPEN, 2), (None, 3), (OPEN, 2)])
    assert alerts == [] and m.perclos() == 0
