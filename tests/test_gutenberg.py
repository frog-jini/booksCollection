import pytest

from eyereader.gutenberg import BookInfo, GutenbergClient, GutenbergError

SEARCH_JSON = {
    "count": 1,
    "results": [{
        "id": 11,
        "title": "Alice's Adventures in Wonderland",
        "authors": [{"name": "Carroll, Lewis"}],
        "languages": ["en"],
    }],
}

OPDS_XML = """<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
<entry><id>https://www.gutenberg.org/ebooks/authors/search.opds/?query=alice</id>
<title>Authors</title><content type="text">145 author names match</content></entry>
<entry><id>https://www.gutenberg.org/ebooks/11.opds</id>
<title>Alice's Adventures in Wonderland</title><content type="text">Lewis Carroll</content></entry>
</feed>"""


class FakeResponse:
    def __init__(self, status_code=200, payload=None, content=b""):
        self.status_code = status_code
        self._payload = payload
        self.content = content

    def json(self):
        return self._payload


class FakeSession:
    """URL 앞부분으로 응답을 고르는 가짜 requests.Session (네트워크 없이 테스트)."""

    def __init__(self, routes):
        self.routes = routes
        self.calls = []

    def get(self, url, params=None, timeout=None):
        self.calls.append((url, params))
        for prefix, resp in self.routes.items():
            if url.startswith(prefix):
                return resp
        return FakeResponse(404)


ALICE = BookInfo(id=11, title="Alice's Adventures in Wonderland", authors=["Carroll, Lewis"], languages=["en"])


# --- 8a. 책 검색 (readme 4: 책을 어디서 가져올지) ---------------------------------

def test_search_uses_free_gutendex_api_with_language_filter():
    session = FakeSession({"https://gutendex.com/books": FakeResponse(payload=SEARCH_JSON)})
    assert GutenbergClient(session=session).search("alice", language="en") == [ALICE]
    assert session.calls[0][1] == {"search": "alice", "languages": "en"}


def test_search_falls_back_to_official_catalog_when_gutendex_is_down():
    session = FakeSession({
        "https://gutendex.com/books": FakeResponse(503),
        "https://www.gutenberg.org/ebooks/search.opds/": FakeResponse(content=OPDS_XML.encode()),
    })
    books = GutenbergClient(session=session).search("alice")
    assert books == [BookInfo(id=11, title="Alice's Adventures in Wonderland", authors=["Lewis Carroll"])]


def test_search_raises_when_both_sources_fail():
    session = FakeSession({"https://gutendex.com/books": FakeResponse(503)})
    with pytest.raises(GutenbergError):
        GutenbergClient(session=session).search("alice")


def test_network_failure_becomes_gutenberg_error():
    class Broken:
        def get(self, *a, **k):
            raise TimeoutError("slow")

    with pytest.raises(GutenbergError):
        GutenbergClient(session=Broken()).search("alice")


def test_book_info_reads_nicely_in_a_list():
    assert str(ALICE) == "[11] Alice's Adventures in Wonderland — Carroll, Lewis (en)"
    assert str(BookInfo(1, "X")) == "[1] X — 작자 미상 ()"
