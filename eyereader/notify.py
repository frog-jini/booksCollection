"""알림 보내기: macOS 는 알림 센터, 그 밖에는 터미널에 출력."""

from __future__ import annotations

import platform
import subprocess


def _quote(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')


def notify(title: str, message: str, system: str | None = None, run=subprocess.run, echo=print):
    echo(f"[{title}] {message}")
    if (system or platform.system()) == "Darwin":
        script = f'display notification "{_quote(message)}" with title "{_quote(title)}" sound name "Glass"'
        run(["osascript", "-e", script], check=False)
