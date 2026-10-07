import pytest

from eyereader.gaze.features import LEFT_EYE, NOSE_TIP, RIGHT_EYE, eye_feature


def make_landmarks(iris_h=0.5, iris_v=0.5, openness=0.3, nose=(0.5, 0.6)):
    """두 눈 모두 (iris_h, iris_v) 비율 위치에 홍채가 있는 가짜 랜드마크 478개."""
    pts = [(0.0, 0.0)] * 478
    for eye, x0 in ((LEFT_EYE, 0.30), (RIGHT_EYE, 0.60)):
        width, height = 0.10, 0.10 * openness
        top_y = 0.40
        cy = top_y + height / 2
        pts[eye.corner_a] = (x0, cy)
        pts[eye.corner_b] = (x0 + width, cy)
        pts[eye.top] = (x0 + width / 2, top_y)
        pts[eye.bottom] = (x0 + width / 2, top_y + height)
        pts[eye.iris] = (x0 + width * iris_h, top_y + height * iris_v)
    pts[NOSE_TIP] = nose
    return pts


def test_centered_iris_gives_half_ratios_and_nose_position():
    assert eye_feature(make_landmarks()) == pytest.approx((0.5, 0.5, 0.5, 0.6))


def test_iris_moving_toward_corner_b_raises_horizontal_ratio():
    left = eye_feature(make_landmarks(iris_h=0.3))
    right = eye_feature(make_landmarks(iris_h=0.7))
    assert left[0] == pytest.approx(0.3) and right[0] == pytest.approx(0.7)


def test_lower_iris_raises_vertical_ratio():
    assert eye_feature(make_landmarks(iris_v=0.8))[1] == pytest.approx(0.8)


def test_nose_position_is_included_so_head_movement_can_be_corrected():
    f = eye_feature(make_landmarks(nose=(0.45, 0.62)))
    assert f[2:] == pytest.approx((0.45, 0.62))


def test_blink_returns_none():
    assert eye_feature(make_landmarks(openness=0.05)) is None


def test_no_face_or_too_few_landmarks_returns_none():
    assert eye_feature(None) is None
    assert eye_feature([(0, 0)] * 10) is None
