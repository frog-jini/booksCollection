import numpy as np
import pytest

from eyereader.gaze.calibration import Calibrator, calibration_points


def true_mapping(f):
    """실제 눈 → 화면 관계라고 가정한 2차 함수(머리 위치 영향 포함)."""
    h, v, nx, ny = f
    return (1920 * h + 300 * (h - 0.5) ** 2 - 400 * (nx - 0.5),
            1080 * v + 150 * h * v + 300 * (ny - 0.5))


def fitted(n=60, seed=0):
    rng = np.random.default_rng(seed)
    cal = Calibrator()
    for _ in range(n):
        f = tuple(rng.uniform([0.2, 0.2, 0.4, 0.5], [0.8, 0.8, 0.6, 0.7]))
        cal.add(f, true_mapping(f))
    cal.fit()
    return cal


def test_calibration_points_are_3x3_grid_inside_margins():
    pts = calibration_points(1000, 800, margin=100)
    assert len(pts) == 9
    assert sorted({x for x, _ in pts}) == [100, 500, 900]
    assert sorted({y for _, y in pts}) == [100, 400, 700]


def test_fit_learns_mapping_and_predicts_unseen_gaze():
    f = (0.41, 0.63, 0.52, 0.58)
    assert fitted().predict(f) == pytest.approx(true_mapping(f), abs=1.0)


def test_predict_before_fit_raises():
    with pytest.raises(RuntimeError):
        Calibrator().predict((0.5, 0.5, 0.5, 0.5))


def test_fit_needs_enough_samples():
    cal = Calibrator()
    cal.add((0.5, 0.5, 0.5, 0.5), (0, 0))
    with pytest.raises(ValueError):
        cal.fit()


def test_saved_calibration_can_be_reused(tmp_path):
    cal = fitted(30, seed=1)
    path = tmp_path / "cal.json"
    cal.save(path)
    f = (0.5, 0.5, 0.5, 0.5)
    assert Calibrator.load(path).predict(f) == pytest.approx(cal.predict(f))
