"""독서 보고서(JSON) 저장. 집중도·피로도 연구용 데이터로 쓸 수 있다."""

from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path


def save_report(report: dict, directory, now: datetime | None = None) -> Path:
    now = now or datetime.now()
    safe = re.sub(r'[\\/:*?"<>|\s]+', "_", report.get("title", "")).strip("_") or "reading"
    path = Path(directory) / f"{safe}-{now:%Y%m%d-%H%M}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return path
