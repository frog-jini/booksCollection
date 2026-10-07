import math

import pytest

from eyereader.posture import (
    AVG_IPD_CM, LEFT_IRIS, NOSE_TIP, RIGHT_IRIS, head_pose,
)

# 얼굴 모형(대략적인 평균값): 코끝은 눈 높이에서 4cm 아래, 3cm 앞에 있다.
NOSE_DOWN_CM, NOSE_FRONT_CM = 4.0, 3.0


def make_face(ipd=0.1, roll=0.0, yaw=0.0, pitch=0.0, aspect=1.0, center=(0.5, 0.45)):
    """주어진 자세의 얼굴을 카메라로 찍은 것처럼 정규화 랜드마크 478개를 만든다.

    ipd 는 '정면일 때' 두 눈동자 사이 거리(이미지 높이 단위).
    """
    pts = [(0.0, 0.0)] * 478
    cx, cy = center[0] * aspect, center[1]  # 이미지 높이 단위로 계산
    r = math.radians(roll)
    u = (math.cos(r), math.sin(r))  # 눈을 잇는 방향
    v = (-math.sin(r), math.cos(r))  # 그에 수직(아래쪽)
    half = ipd * math.cos(math.radians(yaw)) / 2  # 고개를 돌리면 눈 사이가 좁아 보인다
    scale = ipd / AVG_IPD_CM  # cm → 이미지 단위
    along = NOSE_FRONT_CM * math.sin(math.radians(yaw)) * scale
    p = math.radians(pitch)
    down = (NOSE_DOWN_CM * math.cos(p) + NOSE_FRONT_CM * math.sin(p)) * scale

    def put(i, a, d):
        x, y = cx + a * u[0] + d * v[0], cy + a * u[1] + d * v[1]
        pts[i] = (x / aspect, y)

    put(LEFT_IRIS, -half, 0)
    put(RIGHT_IRIS, half, 0)
    put(NOSE_TIP, along, down)
    return pts


def focal(aspect=1.0, fov=60.0):
    return (aspect / 2) / math.tan(math.radians(fov / 2))


def test_frontal_face_distance_from_eye_gap():
    pose = head_pose(make_face(ipd=0.1), aspect=1.0, hfov_deg=60)
    assert pose.distance_cm == pytest.approx(focal() * AVG_IPD_CM / 0.1)  # 약 54.6cm
    assert pose.distance_cm == pytest.approx(54.56, abs=0.05)
    assert (pose.yaw, pose.pitch, pose.roll) == pytest.approx((0, 0, 0), abs=1e-6)


def test_closer_face_looks_bigger_and_gives_shorter_distance():
    far = head_pose(make_face(ipd=0.08), aspect=1.0)
    near = head_pose(make_face(ipd=0.16), aspect=1.0)
    assert near.distance_cm == pytest.approx(far.distance_cm / 2)


def test_camera_field_of_view_changes_distance_estimate():
    wide = head_pose(make_face(ipd=0.1), aspect=1.0, hfov_deg=80)
    narrow = head_pose(make_face(ipd=0.1), aspect=1.0, hfov_deg=50)
    assert wide.distance_cm < narrow.distance_cm


@pytest.mark.parametrize("roll", [-20, 12, 30])
def test_head_tilt_is_roll_angle(roll):
    assert head_pose(make_face(roll=roll), aspect=1.0).roll == pytest.approx(roll, abs=0.01)


def test_roll_uses_real_pixel_shape_of_wide_camera_image():
    pose = head_pose(make_face(roll=20, aspect=16 / 9), aspect=16 / 9)
    assert pose.roll == pytest.approx(20, abs=0.01)


@pytest.mark.parametrize("yaw", [-30, 15, 35])
def test_turning_head_gives_yaw_and_does_not_fake_a_longer_distance(yaw):
    pose = head_pose(make_face(ipd=0.1, yaw=yaw), aspect=1.0)
    assert pose.yaw == pytest.approx(yaw, abs=0.01)
    assert pose.distance_cm == pytest.approx(54.56, abs=0.05)


@pytest.mark.parametrize("pitch", [-15, 10, 25])
def test_bowing_head_gives_positive_pitch(pitch):
    assert head_pose(make_face(pitch=pitch), aspect=1.0).pitch == pytest.approx(pitch, abs=0.01)


def test_pose_survives_tilt_and_turn_together():
    pose = head_pose(make_face(roll=15, yaw=20, pitch=10, aspect=4 / 3), aspect=4 / 3)
    assert (pose.roll, pose.yaw, pose.pitch) == pytest.approx((15, 20, 10), abs=0.01)


def test_no_face_gives_none():
    assert head_pose(None) is None
    assert head_pose([(0, 0)] * 10) is None
    assert head_pose([(0.5, 0.5)] * 478) is None  # 눈이 한 점에 겹침
