import zipfile

import pytest
from ebooklib import epub

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


# --- 여러 책 형식 (readme 5: 어떤 형식의 책이든) ---------------------------------

def make_pdf(path, pages):
    """외부 라이브러리 없이 텍스트가 든 최소 PDF 를 만든다."""
    objs = ["<< /Type /Catalog /Pages 2 0 R >>", None,
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
    kids = []
    for text in pages:
        stream = f"BT /F1 12 Tf 72 720 Td ({text}) Tj ET"
        objs.append(f"<< /Length {len(stream)} >>\nstream\n{stream}\nendstream")
        objs.append(f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
                    f"/Resources << /Font << /F1 3 0 R >> >> /Contents {len(objs)} 0 R >>")
        kids.append(f"{len(objs)} 0 R")
    objs[1] = f"<< /Type /Pages /Kids [{' '.join(kids)}] /Count {len(kids)} >>"
    out, offsets = b"%PDF-1.4\n", []
    for i, o in enumerate(objs, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n{o}\nendobj\n".encode()
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    out += b"".join(f"{o:010d} 00000 n \n".encode() for o in offsets)
    out += f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF".encode()
    path.write_bytes(out)


def test_markdown_syntax_is_removed(tmp_path):
    p = tmp_path / "a.md"
    p.write_text("# 제목\n\n**굵게** 그리고 [링크](http://x)", encoding="utf-8")
    assert load_book(p).text == "제목\n\n굵게 그리고 링크"


def test_html_keeps_visible_text_and_uses_title(tmp_path):
    p = tmp_path / "a.html"
    p.write_text("<html><head><title>T</title><style>x{}</style></head>"
                 "<body><h1>Head</h1><p>One</p><script>bad()</script><p>Two</p></body></html>")
    book = load_book(p)
    assert book.title == "T"
    assert book.text == "Head\n\nOne\n\nTwo"


def test_pdf_text_from_all_pages_in_order(tmp_path):
    p = tmp_path / "a.pdf"
    make_pdf(p, ["Hello page one", "Second page"])
    text = load_book(p).text
    assert text.index("Hello page one") < text.index("Second page")


def test_epub_chapters_in_spine_order_with_title(tmp_path):
    b = epub.EpubBook()
    b.set_identifier("id1")
    b.set_title("My Epub")
    b.set_language("ko")
    c1 = epub.EpubHtml(title="1", file_name="c1.xhtml", content="<h1>장 1</h1><p>첫 문장</p>")
    c2 = epub.EpubHtml(title="2", file_name="c2.xhtml", content="<p>둘째 장</p>")
    for c in (c1, c2):
        b.add_item(c)
    b.add_item(epub.EpubNcx())
    b.add_item(epub.EpubNav())
    b.spine = [c1, c2]
    p = tmp_path / "a.epub"
    epub.write_epub(str(p), b)
    book = load_book(p)
    assert book.title == "My Epub"
    assert book.text == "장 1\n\n첫 문장\n\n둘째 장"


def test_docx_paragraphs(tmp_path):
    p = tmp_path / "a.docx"
    ns = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
    xml = (f"<w:document {ns}><w:body>"
           "<w:p><w:r><w:t>첫 </w:t></w:r><w:r><w:t>문단</w:t></w:r></w:p>"
           "<w:p><w:r><w:t>둘째</w:t></w:r></w:p></w:body></w:document>")
    with zipfile.ZipFile(p, "w") as z:
        z.writestr("word/document.xml", xml)
    assert load_book(p).text == "첫 문단\n\n둘째"


def test_broken_file_of_known_format_is_rejected(tmp_path):
    p = tmp_path / "broken.epub"
    p.write_bytes(b"not a zip")
    with pytest.raises(UnsupportedFormatError):
        load_book(p)
