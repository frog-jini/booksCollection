"""독서 도우미 알림 공통 부분."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Alert:
    kind: str  # 알림 종류(같은 종류는 쿨다운 동안 다시 내지 않는다)
    title: str
    message: str


class Persistence:
    """상태가 hold 초 넘게 이어질 때만 알리고, 같은 종류는 cooldown 초 동안 다시 알리지 않는다."""

    def __init__(self, hold: float, cooldown: float):
        self.hold = hold
        self.cooldown = cooldown
        self._since: dict[str, float] = {}
        self._last: dict[str, float] = {}

    def clear(self):
        """판단할 수 없을 때(얼굴을 놓침 등): 이어지던 시간을 버린다."""
        self._since.clear()

    def check(self, kind: str, active: bool, t: float) -> bool:
        if not active:
            self._since.pop(kind, None)
            return False
        since = self._since.setdefault(kind, t)
        if t - since < self.hold:
            return False
        if kind in self._last and t - self._last[kind] < self.cooldown:
            return False
        self._last[kind] = t
        return True
