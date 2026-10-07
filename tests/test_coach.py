import json
from datetime import datetime

import pytest

from eyereader.breaks import ReadingTimer
from eyereader.coach import ReadingCoach
from eyereader.fatigue import DrowsinessMonitor
from eyereader.heatmap import PageHeatmaps
from eyereader.posture import HeadPose, PostureMonitor
from eyereader.report import save_report

GOOD = HeadPose(55, 0, 0, 0)
CLOSE = HeadPose(30, 0, 0, 0)


def coach():
    return ReadingCoach(
        posture=PostureMonitor(hold=5, baseline_samples=2),
        timer=ReadingTimer(break_after=60),
        drowsiness=DrowsinessMonitor(microsleep=1.0),
    )


def run(c, seconds, start=0.0, step=0.5, **frame):
    alerts, t = [], start
    frame = {"pose": GOOD, "openness": 0.3, "present": True, "on_target": True, **frame}
    while t < start + seconds:
        alerts += c.update(t, **frame)
        t += step
    return alerts, t


def test_good_reading_gives_no_alerts():
    alerts, _ = run(coach(), 50)
    assert alerts == []


def test_alerts_from_posture_breaks_and_drowsiness_all_come_through():
    c = coach()
    _, t = run(c, 2)
    alerts, t = run(c, 8, t, pose=CLOSE)
    alerts += run(c, 60, t)[0]
    alerts += run(c, 2, 70, openness=0.05)[0]
    assert [a.kind for a in alerts] == ["too_close", "break", "drowsy"]


def test_status_for_screen_display():
    c = coach()
    run(c, 30)
    s = c.status()
    assert s["focus"] == 100
    assert s["reading_minutes"] == pytest.approx(0.5, abs=0.02)
    assert s["distance_cm"] == pytest.approx(55)
    assert s["posture_ok"] is True


def test_report_summarizes_the_reading_session():
    c = coach()
    _, t = run(c, 2)
    _, t = run(c, 8, t, pose=CLOSE)
    _, t = run(c, 50, t)
    _, t = run(c, 10, t, present=False, on_target=False, pose=None, openness=None)
    _, t = run(c, 70, t)
    maps = PageHeatmaps(100, 100, 50)
    maps.add(0, 10, 10, 3)
    r = c.report("앨리스", heatmaps=maps)
    assert r["title"] == "앨리스"
    assert r["reading_minutes"] == pytest.approx(130 / 60, abs=0.05)
    assert r["away_minutes"] == pytest.approx(10 / 60, abs=0.05)
    assert r["look_aways"] == 1
    assert r["alerts"] == {"too_close": 1, "break": 1}
    assert r["avg_distance_cm"] == pytest.approx((55 * 244 + 30 * 16) / 260, abs=0.5)  # 0.5초마다 1번 측정
    assert len(r["focus_per_minute"]) == 2
    assert r["pages"] == [{"page": 1, "seconds": 3.0, "hottest": [[[25.0, 25.0], 3.0]]}]


def test_report_is_saved_as_readable_json(tmp_path):
    path = save_report({"title": "앨리스: 1/2", "x": 1}, tmp_path, now=datetime(2026, 10, 7, 14, 5))
    assert path.name == "앨리스_1_2-20261007-1405.json"
    assert json.loads(path.read_text(encoding="utf-8")) == {"title": "앨리스: 1/2", "x": 1}
    assert "앨리스" in path.read_text(encoding="utf-8")  # 한글이 \\uXXXX 로 깨지지 않게
