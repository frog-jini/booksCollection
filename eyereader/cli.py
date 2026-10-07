"""명령줄 옵션과 '어떤 책을 열지' 결정."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .gutenberg import GutenbergClient, GutenbergError


def _window(value: str) -> tuple[int, int]:
    try:
        w, h = value.lower().split("x")
        return int(w), int(h)
    except ValueError:
        raise argparse.ArgumentTypeError("창 크기는 1280x800 처럼 적어 주세요")


def parse_args(argv=None) -> argparse.Namespace:
    p = argparse.ArgumentParser(prog="eyereader", description="눈동자 추적 책 리더")
    p.add_argument("book", nargs="?", help="txt / md / html / pdf / epub / docx 파일")
    p.add_argument("--search", help="Project Gutenberg 에서 검색해 읽기")
    p.add_argument("--gutenberg", type=int, metavar="ID", help="Gutenberg 책 번호로 바로 읽기")
    p.add_argument("--lang", help="검색 언어 필터 (예: en, ko)")
    p.add_argument("--books-dir", default="books", help="내려받은 책 저장 위치")
    p.add_argument("--mouse", action="store_true", help="웹캠 대신 마우스를 시선으로 사용")
    p.add_argument("--camera", type=int, default=0, help="카메라 번호")
    p.add_argument("--font-size", type=int, default=30)
    p.add_argument("--window", type=_window, metavar="WxH", help="창 크기 (기본: 전체 화면)")
    p.add_argument("--reuse-calibration", action="store_true", help="지난 보정값 재사용")
    coach = p.add_argument_group("독서 도우미(자세·휴식·졸음·집중도)")
    coach.add_argument("--monitor", action="store_true",
                       help="책 없이 카메라만 켜서, 다른 앱(리디·Kindle·브라우저 등)으로 읽는 동안 알림")
    coach.add_argument("--camera-fov", type=float, default=60.0, help="웹캠 가로 화각(도). 거리 계산에 씀")
    coach.add_argument("--min-distance", type=float, default=40.0, help="이보다 가까우면 알림(cm)")
    coach.add_argument("--break-minutes", type=float, default=40.0, help="이만큼 계속 읽으면 휴식 권유(분)")
    coach.add_argument("--reports-dir", default="reports", help="독서 보고서 저장 위치")
    args = p.parse_args(argv)
    if not (args.book or args.search or args.gutenberg or args.monitor):
        p.error("책 파일 경로, --search, --gutenberg, --monitor 중 하나가 필요합니다")
    return args


def choose_interactively(books):
    for i, b in enumerate(books, 1):
        print(f"{i:2}. {b}")
    return books[int(input("번호를 고르세요: ").strip()) - 1]


def resolve_book_path(args, client=None, choose=choose_interactively) -> Path:
    if args.book:
        return Path(args.book)
    client = client or GutenbergClient()
    try:
        if args.gutenberg:
            return client.download(args.gutenberg, args.books_dir)
        print(f"Project Gutenberg 에서 '{args.search}' 검색 중…")
        books = client.search(args.search, language=args.lang)[:15]
        if not books:
            sys.exit("검색 결과가 없습니다.")
        return client.download(choose(books).id, args.books_dir)
    except GutenbergError as e:
        sys.exit(f"책을 가져오지 못했습니다: {e}")
