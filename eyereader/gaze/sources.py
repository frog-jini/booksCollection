"""시선 입력원: 웹캠(MediaPipe 홍채 추적) 또는 마우스(웹캠 없이 테스트용)."""

from __future__ import annotations

import urllib.request
from dataclasses import dataclass
from pathlib import Path

from .features import eye_feature

MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/face_landmarker/"
    "face_landmarker/float16/latest/face_landmarker.task"
)
MODEL_PATH = Path.home() / ".cache" / "eyereader" / "face_landmarker.task"


@dataclass
class FaceFrame:
    """카메라 한 장면의 얼굴 랜드마크(정규화 x/폭, y/높이). 얼굴이 없으면 landmarks=None."""

    landmarks: list | None
    aspect: float  # 이미지 가로/세로


def ensure_model(path: Path = MODEL_PATH) -> Path:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        print(f"얼굴 랜드마크 모델 다운로드 중… ({MODEL_URL})")
        urllib.request.urlretrieve(MODEL_URL, path)
    return path


class WebcamSource:
    """웹캠 프레임마다 얼굴 랜드마크(read_frame)와 시선 특징 벡터(read_feature, 보정 전)를 돌려준다."""

    needs_calibration = True

    def __init__(self, camera: int = 0):
        import cv2
        import mediapipe as mp
        from mediapipe.tasks.python import BaseOptions, vision

        self._cv2, self._mp = cv2, mp
        self.cap = cv2.VideoCapture(camera)
        if not self.cap.isOpened():
            raise RuntimeError(f"카메라 {camera} 를 열 수 없습니다. --mouse 옵션으로 마우스 모드를 써 보세요.")
        options = vision.FaceLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=str(ensure_model())),
            running_mode=vision.RunningMode.VIDEO,
            num_faces=1,
        )
        self.landmarker = vision.FaceLandmarker.create_from_options(options)
        self._ts = 0

    def read_frame(self) -> FaceFrame | None:
        ok, frame = self.cap.read()
        if not ok:
            return None
        h, w = frame.shape[:2]
        rgb = self._cv2.cvtColor(frame, self._cv2.COLOR_BGR2RGB)
        image = self._mp.Image(image_format=self._mp.ImageFormat.SRGB, data=rgb)
        self._ts += 33
        result = self.landmarker.detect_for_video(image, self._ts)
        landmarks = [(p.x, p.y) for p in result.face_landmarks[0]] if result.face_landmarks else None
        return FaceFrame(landmarks, w / h)

    def read_feature(self):
        frame = self.read_frame()
        return eye_feature(frame.landmarks) if frame is not None else None

    def close(self):
        self.cap.release()
        self.landmarker.close()


class MouseSource:
    """마우스 위치를 시선으로 간주한다. 보정 불필요."""

    needs_calibration = False

    def read_point(self):
        import pygame

        return pygame.mouse.get_pos() if pygame.mouse.get_focused() else None

    def close(self):
        pass
