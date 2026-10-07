"""독서 코치: 자세·휴식·졸음·집중도를 한 번에 돌리고, 독서가 끝나면 보고서를 만든다.

책 내용을 전혀 몰라도 동작한다(얼굴과 시선만 본다). 그래서 이 앱의 리더 화면뿐 아니라
다른 독서 앱(네이버 시리즈·리디·Kindle 등)을 쓰는 동안에도 쓸 수 있다.
"""

from __future__ import annotations

from collections import Counter

from .alerts import Alert
from .breaks import ReadingTimer
from .fatigue import DrowsinessMonitor
from .focus import FocusMeter
from .posture import HeadPose, PostureMonitor


class ReadingCoach:
    def __init__(self, posture=None, timer=None, drowsiness=None, focus=None):
        self.posture = posture or PostureMonitor()
        self.timer = timer or ReadingTimer()
        self.drowsiness = drowsiness or DrowsinessMonitor()
        self.focus = focus or FocusMeter()
        self.pose: HeadPose | None = None
        self.alert_counts: Counter[str] = Counter()
        self._distances: list[float] = []

    def update(self, t: float, *, pose: HeadPose | None, openness: float | None,
               present: bool, on_target: bool) -> list[Alert]:
        """한 프레임. present = 얼굴이 화면 앞에 있나, on_target = 책(화면)을 보고 있나."""
        self.pose = pose
        if pose is not None:
            self._distances.append(pose.distance_cm)
        self.focus.update(on_target, t)
        alerts = (self.posture.update(pose, t)
                  + self.timer.update(present, t)
                  + self.drowsiness.update(openness, t))
        self.alert_counts.update(a.kind for a in alerts)
        return alerts

    def status(self) -> dict:
        pose = self.pose
        return {
            "focus": self.focus.score(),
            "reading_minutes": self.timer.reading_seconds / 60,
            "continuous_minutes": self.timer.continuous_seconds / 60,
            "blink_rate": self.drowsiness.blink_rate(),
            "distance_cm": pose.distance_cm if pose else None,
            "posture_ok": None if pose is None else not any(
                active for active, _ in self.posture.problems(pose).values()),
        }

    def report(self, title: str, heatmaps=None) -> dict:
        pages = []
        if heatmaps is not None:
            for page_no, hm in sorted(heatmaps.pages.items()):
                pages.append({
                    "page": page_no + 1,
                    "seconds": round(hm.total_seconds, 1),
                    "hottest": [[list(centre), round(secs, 1)] for centre, secs in hm.hottest(3)],
                })
        avg_distance = sum(self._distances) / len(self._distances) if self._distances else None
        return {
            "title": title,
            "reading_minutes": round(self.timer.reading_seconds / 60, 2),
            "away_minutes": round(self.timer.away_seconds / 60, 2),
            "look_aways": self.timer.look_aways,
            "focus_per_minute": list(self.focus.history),
            "focus_avg": round(sum(self.focus.history) / len(self.focus.history), 1) if self.focus.history else None,
            "blink_rate_per_min": round(self.drowsiness.blink_rate(), 1),
            "perclos": round(self.drowsiness.perclos(), 3),
            "long_eye_closures": self.drowsiness.long_closures,
            "avg_distance_cm": round(avg_distance, 1) if avg_distance else None,
            "alerts": dict(self.alert_counts),
            "pages": pages,
        }
