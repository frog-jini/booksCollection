import pytest

from eyereader.gutenberg import BookInfo, GutenbergClient, GutenbergError, strip_boilerplate
from eyereader.loader import load_book

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


# --- 8b. 내려받아 파일로 저장하고, 그 파일을 다시 열어 읽기 (readme 6) -----------------

BOOK_TXT = (
    "The Project Gutenberg eBook of Alice\n\nlicense blah\n"
    "*** START OF THE PROJECT GUTENBERG EBOOK ALICE'S ADVENTURES ***\n"
    "CHAPTER I.\nDown the Rabbit-Hole\n"
    "*** END OF THE PROJECT GUTENBERG EBOOK ALICE'S ADVENTURES ***\n"
    "more license\n"
)
ALICE_TXT_URL = "https://www.gutenberg.org/cache/epub/11/pg11.txt"


def test_download_saves_book_text_without_license_boilerplate(tmp_path):
    session = FakeSession({ALICE_TXT_URL: FakeResponse(content=BOOK_TXT.encode())})
    path = GutenbergClient(session=session).download(11, tmp_path / "books")
    assert path == tmp_path / "books" / "pg11.txt"
    assert path.read_text(encoding="utf-8").strip() == "CHAPTER I.\nDown the Rabbit-Hole"


def test_downloaded_file_opens_as_a_book(tmp_path):
    session = FakeSession({ALICE_TXT_URL: FakeResponse(content=BOOK_TXT.encode())})
    book = load_book(GutenbergClient(session=session).download(11, tmp_path))
    assert book.text == "CHAPTER I. Down the Rabbit-Hole"


def test_already_downloaded_book_is_not_fetched_again(tmp_path):
    (tmp_path / "pg11.txt").write_text("cached", encoding="utf-8")
    session = FakeSession({})
    assert GutenbergClient(session=session).download(11, tmp_path).read_text() == "cached"
    assert session.calls == []


def test_download_of_missing_book_raises(tmp_path):
    with pytest.raises(GutenbergError):
        GutenbergClient(session=FakeSession({})).download(999999, tmp_path)


def test_strip_boilerplate_leaves_ordinary_text_alone():
    assert strip_boilerplate("just text") == "just text"


def test_gutenberg_file_saved_by_hand_is_also_cleaned_when_opened(tmp_path):
    p = tmp_path / "pg11.txt"  # 브라우저로 직접 받은 원본 파일
    p.write_text(BOOK_TXT, encoding="utf-8")
    assert load_book(p).text == "CHAPTER I. Down the Rabbit-Hole"
