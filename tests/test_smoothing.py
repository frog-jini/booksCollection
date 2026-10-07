import pytest

from eyereader.gaze.smoothing import GazeSmoother


def test_first_point_is_returned_as_is():
    assert GazeSmoother(alpha=0.3).update((100, 200)) == (100, 200)


def test_small_jitter_is_averaged():
    s = GazeSmoother(alpha=0.5)
    s.update((0, 0))
    assert s.update((10, 20)) == pytest.approx((5, 10))


def test_big_jump_is_followed_immediately():
    s = GazeSmoother(alpha=0.2, snap_distance=300)
    s.update((0, 0))
    assert s.update((1000, 0)) == (1000, 0)  # 다음 줄 첫머리로 눈을 옮김


def test_missing_point_keeps_last_value():
    s = GazeSmoother(alpha=0.5)
    s.update((10, 10))
    assert s.update(None) == (10, 10)


def test_reset_forgets_history():
    s = GazeSmoother(alpha=0.5)
    s.update((10, 10))
    s.reset()
    assert s.update(None) is None
    assert s.update((50, 50)) == (50, 50)
