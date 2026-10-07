"""어떤 형식의 책이든 읽기용 평문으로 바꾼다.

지원: .txt .md .html/.htm/.xhtml .pdf .epub .docx, 그 밖의 텍스트 파일.
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import dataclass
from pathlib import Path

from bs4 import BeautifulSoup

from .gutenberg import strip_boilerplate


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


# --- 형식별 추출기 -----------------------------------------------------------

_BLOCK_TAGS = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "blockquote",
               "pre", "tr", "section", "article", "br"]


def _html_to_text(html) -> tuple[str | None, str]:
    soup = BeautifulSoup(html, "html.parser")
    title = soup.title.get_text(strip=True) if soup.title else None
    for tag in soup(["script", "style", "head"]):
        tag.decompose()
    for tag in soup.find_all(_BLOCK_TAGS):
        tag.append("\n\n")  # 블록 사이를 문단으로 나눈다
    return title, soup.get_text("")


def _strip_markdown(text: str) -> str:
    text = re.sub(r"```.*?```", lambda m: m.group(0).strip("`"), text, flags=re.S)
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)      # 링크/이미지
    text = re.sub(r"^\s{0,3}#{1,6}\s*", "", text, flags=re.M)     # 제목
    text = re.sub(r"^\s*(?:[-*+]|\d+\.)\s+", "", text, flags=re.M)  # 목록
    text = re.sub(r"^\s*>\s?", "", text, flags=re.M)               # 인용
    text = re.sub(r"(\*\*|__|\*|_|`)(.+?)\1", r"\2", text)         # 강조/코드
    return text


def _load_pdf(path: Path):
    from pypdf import PdfReader

    reader = PdfReader(path)
    title = reader.metadata.title if reader.metadata else None
    return title, "\n\n".join(page.extract_text() or "" for page in reader.pages)


def _load_epub(path: Path):
    import ebooklib
    from ebooklib import epub

    book = epub.read_epub(str(path), options={"ignore_ncx": True})
    titles = book.get_metadata("DC", "title")
    parts = []
    for item_id, _ in book.spine:
        item = book.get_item_with_id(item_id)
        if item is not None and item.get_type() == ebooklib.ITEM_DOCUMENT:
            parts.append(_html_to_text(item.get_content())[1])
    return (titles[0][0] if titles else None), "\n\n".join(parts)


def _load_docx(path: Path):
    w = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
    with zipfile.ZipFile(path) as z:
        root = ET.fromstring(z.read("word/document.xml"))
    paras = ("".join(t.text or "" for t in p.iter(f"{w}t")) for p in root.iter(f"{w}p"))
    return None, "\n\n".join(paras)


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
    text = _decode(data)
    suffix = path.suffix.lower()
    if suffix in (".html", ".htm", ".xhtml"):
        return _html_to_text(text)
    if suffix in (".md", ".markdown"):
        return None, _strip_markdown(text)
    return None, strip_boilerplate(text)  # 직접 받은 Gutenberg 파일의 라이선스 문구


_LOADERS = {".pdf": _load_pdf, ".epub": _load_epub, ".docx": _load_docx}


def load_book(path) -> Book:
    path = Path(path)
    if not path.is_file():
        raise FileNotFoundError(path)
    loader = _LOADERS.get(path.suffix.lower(), _load_textual)
    try:
        title, text = loader(path)
    except UnsupportedFormatError:
        raise
    except Exception as e:  # 깨진 파일 등
        raise UnsupportedFormatError(f"{path.name} 을(를) 읽을 수 없습니다: {e}") from e
    return Book(title=(title or "").strip() or path.stem, text=normalize_text(text))
