import pytest

from eyereader.loader import UnsupportedFormatError, load_book, normalize_text


# --- 문단 정리 ----------------------------------------------------------------

def test_wrapped_lines_are_joined_but_paragraphs_are_kept():
    assert normalize_text("a\nb\r\n\r\n\n c  d\n") == "a b\n\nc d"


def test_hyphenated_line_breaks_are_rejoined():
    assert normalize_text("exam-\nple text") == "example text"


# --- 텍스트 파일 --------------------------------------------------------------

def test_txt_file_becomes_book_titled_after_file_name(tmp_path):
    p = tmp_path / "my_book.txt"
    p.write_text("첫 줄\n이어짐\n\n둘째 문단", encoding="utf-8")
    book = load_book(p)
    assert book.title == "my_book"
    assert book.text == "첫 줄 이어짐\n\n둘째 문단"


def test_korean_cp949_file_is_decoded(tmp_path):
    p = tmp_path / "a.txt"
    p.write_bytes("한글 소설".encode("cp949"))
    assert load_book(p).text == "한글 소설"


def test_utf8_bom_is_removed(tmp_path):
    p = tmp_path / "a.txt"
    p.write_bytes("﻿BOM text".encode("utf-8"))
    assert load_book(p).text == "BOM text"


def test_unknown_extension_that_is_text_is_read_as_text(tmp_path):
    p = tmp_path / "story.log"
    p.write_text("plain story", encoding="utf-8")
    assert load_book(p).text == "plain story"


def test_binary_file_of_unknown_format_is_rejected(tmp_path):
    p = tmp_path / "image.png"
    p.write_bytes(b"\x89PNG\x00\x00\x01\x02")
    with pytest.raises(UnsupportedFormatError):
        load_book(p)


def test_missing_file_raises(tmp_path):
    with pytest.raises(FileNotFoundError):
        load_book(tmp_path / "nope.txt")
