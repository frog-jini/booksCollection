import pytest

from eyereader.heatmap import GazeHeatmap, PageHeatmaps


def test_time_spent_looking_is_added_to_the_cell_under_gaze():
    h = GazeHeatmap(width=400, height=200, cell=100)
    h.add(150, 50, 0.5)
    h.add(160, 60, 0.25)
    h.add(350, 150, 1.0)
    assert h.grid.shape == (2, 4)  # 줄, 칸
    assert h.grid[0, 1] == pytest.approx(0.75)
    assert h.grid[1, 3] == pytest.approx(1.0)
    assert h.total_seconds == pytest.approx(1.75)


def test_gaze_outside_screen_or_missing_is_ignored():
    h = GazeHeatmap(width=400, height=200, cell=100)
    h.add(-5, 50, 1)
    h.add(50, 999, 1)
    h.add(None, None, 1)
    assert h.total_seconds == 0


def test_normalized_grid_is_between_zero_and_one():
    h = GazeHeatmap(width=200, height=100, cell=100)
    assert h.normalized().max() == 0  # 아직 본 곳이 없음
    h.add(10, 10, 2)
    h.add(110, 10, 1)
    assert h.normalized().tolist() == [[1.0, 0.5]]


def test_hottest_cells_tell_where_the_reader_stayed_longest():
    h = GazeHeatmap(width=300, height=100, cell=100)
    for x, secs in ((50, 1), (150, 5), (250, 3)):
        h.add(x, 50, secs)
    assert h.hottest(2) == [((150, 50), 5), ((250, 50), 3)]  # (칸 가운데 좌표, 초)


def test_each_page_has_its_own_heatmap():
    maps = PageHeatmaps(width=200, height=100, cell=100)
    maps.add(0, 50, 50, 1)
    maps.add(3, 150, 50, 2)
    maps.add(3, 150, 50, 2)
    assert sorted(maps.pages) == [0, 3]
    assert maps[3].total_seconds == 4
    assert maps.seconds_per_page() == {0: 1, 3: 4}
