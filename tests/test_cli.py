from pathlib import Path

import pytest

from eyereader.cli import parse_args, resolve_book_path
from eyereader.gutenberg import BookInfo, GutenbergError


class FakeClient:
    def __init__(self, results=()):
        self.results = list(results)
        self.calls = []

    def search(self, query, language=None):
        self.calls.append(("search", query, language))
        return self.results

    def download(self, book_id, dest):
        self.calls.append(("download", book_id, str(dest)))
        return Path(dest) / f"pg{book_id}.txt"


def test_defaults():
    a = parse_args(["book.txt"])
    assert a.book == "book.txt" and a.books_dir == "books"
    assert (a.mouse, a.camera, a.font_size, a.window, a.reuse_calibration) == (False, 0, 30, None, False)


def test_window_size_option():
    assert parse_args(["b.txt", "--window", "1280x800"]).window == (1280, 800)


def test_local_file_is_used_as_is():
    assert resolve_book_path(parse_args(["my.epub"]), FakeClient()) == Path("my.epub")


def test_gutenberg_number_downloads_into_books_dir():
    client = FakeClient()
    path = resolve_book_path(parse_args(["--gutenberg", "11", "--books-dir", "lib"]), client)
    assert path == Path("lib/pg11.txt")
    assert client.calls == [("download", 11, "lib")]


def test_search_lets_user_pick_then_downloads():
    books = [BookInfo(11, "Alice"), BookInfo(12, "Looking-Glass")]
    client = FakeClient(books)
    path = resolve_book_path(parse_args(["--search", "alice", "--lang", "en"]), client,
                             choose=lambda found: found[1])
    assert client.calls[0] == ("search", "alice", "en")
    assert path == Path("books/pg12.txt")


def test_search_without_results_exits_with_message():
    with pytest.raises(SystemExit, match="검색 결과가 없습니다"):
        resolve_book_path(parse_args(["--search", "zzz"]), FakeClient([]), choose=lambda b: b[0])


def test_gutenberg_failure_exits_with_message():
    class Down(FakeClient):
        def download(self, *a):
            raise GutenbergError("503")

    with pytest.raises(SystemExit, match="책을 가져오지 못했습니다"):
        resolve_book_path(parse_args(["--gutenberg", "11"]), Down())


def test_no_book_source_is_an_error():
    with pytest.raises(SystemExit):
        parse_args([])


# --- 감시 모드와 독서 도우미 옵션 (readme 11) ------------------------------------

def test_monitor_mode_needs_no_book():
    a = parse_args(["--monitor"])
    assert a.monitor and a.book is None


def test_reading_coach_options_have_sensible_defaults():
    a = parse_args(["b.txt"])
    assert (a.camera_fov, a.min_distance, a.break_minutes, a.reports_dir) == (60.0, 40.0, 40.0, "reports")


def test_reading_coach_options_can_be_changed():
    a = parse_args(["--monitor", "--camera-fov", "70", "--min-distance", "35", "--break-minutes", "38"])
    assert (a.camera_fov, a.min_distance, a.break_minutes) == (70.0, 35.0, 38.0)
