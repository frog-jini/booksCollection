"""어떤 형식의 책이든 읽기용 평문으로 바꾼다."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path


class UnsupportedFormatError(ValueError):
    pass


@dataclass
class Book:
    title: str
    text: str


def normalize_text(text: str) -> str:
    """줄바꿈으로 잘린 문장은 잇고, 빈 줄로 나뉜 문단은 유지한다."""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"(\w)-\n(\w)", r"\1\2", text)
    paragraphs = (" ".join(p.split()) for p in re.split(r"\n\s*\n", text))
    return "\n\n".join(p for p in paragraphs if p)


def _decode(data: bytes) -> str:
    for enc in ("utf-8-sig", "cp949"):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            pass
    return data.decode("latin-1")


def _looks_binary(data: bytes) -> bool:
    return b"\x00" in data[:8192]


def _load_textual(path: Path):
    data = path.read_bytes()
    if _looks_binary(data):
        raise UnsupportedFormatError(f"지원하지 않는 형식입니다: {path.name}")
    return None, _decode(data)


def load_book(path) -> Book:
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(path)
    title, text = _load_textual(path)
    return Book(title=(title or "").strip() or path.stem, text=normalize_text(text))
