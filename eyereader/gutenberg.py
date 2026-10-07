"""무료 전자책 소스: Project Gutenberg.

- 검색: Gutendex (https://gutendex.com) — Gutenberg 카탈로그용 무료 JSON API, 키 불필요.
  자주 503 이 나므로 실패하면 gutenberg.org 공식 OPDS 검색으로 대신한다.
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field

import requests

SEARCH_URL = "https://gutendex.com/books"
OPDS_SEARCH_URL = "https://www.gutenberg.org/ebooks/search.opds/"
_ATOM = "{http://www.w3.org/2005/Atom}"
_BOOK_ID = re.compile(r"/ebooks/(\d+)\.opds$")


class GutenbergError(RuntimeError):
    pass


@dataclass
class BookInfo:
    id: int
    title: str
    authors: list[str] = field(default_factory=list)
    languages: list[str] = field(default_factory=list)

    def __str__(self):
        who = "; ".join(self.authors) or "작자 미상"
        return f"[{self.id}] {self.title} — {who} ({','.join(self.languages)})"


class GutenbergClient:
    def __init__(self, session=None, timeout=60):
        self.session = session or requests.Session()
        self.timeout = timeout

    def _get(self, url, params=None):
        try:
            resp = self.session.get(url, params=params, timeout=self.timeout)
        except Exception as e:
            raise GutenbergError(f"요청 실패: {e}") from e
        if resp.status_code != 200:
            raise GutenbergError(f"요청 실패 ({resp.status_code}): {url}")
        return resp

    def search(self, query: str, language: str | None = None) -> list[BookInfo]:
        try:
            return self._search_gutendex(query, language)
        except GutenbergError as first:
            try:
                return self._search_opds(query)
            except GutenbergError as second:
                raise GutenbergError(f"검색 실패: {first} / {second}") from second

    def _search_gutendex(self, query: str, language: str | None) -> list[BookInfo]:
        params = {"search": query}
        if language:
            params["languages"] = language
        data = self._get(SEARCH_URL, params).json()
        return [
            BookInfo(
                id=b["id"],
                title=b["title"],
                authors=[a["name"] for a in b.get("authors", [])],
                languages=b.get("languages", []),
            )
            for b in data.get("results", [])
        ]

    def _search_opds(self, query: str) -> list[BookInfo]:
        resp = self._get(OPDS_SEARCH_URL, {"query": query})
        try:
            root = ET.fromstring(resp.content)
        except ET.ParseError as e:
            raise GutenbergError(f"OPDS 응답 파싱 실패: {e}") from e
        books = []
        for entry in root.iter(f"{_ATOM}entry"):
            m = _BOOK_ID.search(entry.findtext(f"{_ATOM}id", ""))
            if not m:
                continue  # '저자 목록' 같은 탐색용 항목
            author = entry.findtext(f"{_ATOM}content", "").strip()
            books.append(BookInfo(
                id=int(m.group(1)),
                title=entry.findtext(f"{_ATOM}title", "").strip(),
                authors=[author] if author else [],
            ))
        return books
