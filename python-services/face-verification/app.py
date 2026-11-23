"""
Biometric microservice: Flask + InsightFace, screen-reflection check, server-verified head turn.

Works with resources/js/pages/auth/verify-face.tsx and Laravel's BiometricService. The server decides
everything the browser must do in one attempt (flash colors and turn side). The browser only follows it.

POST /verify-liveness   JSON body
    frontal_image_base64       required   baseline frame
    flash_images_base64        required*  3 frames, same order as flash_colors
    flash_colors               required*  3 items: "red" | "green" | "blue"
    direction                  required** "left" | "right" (taken from the stored challenge)
    turn_peak_image_base64     required** frame taken at the peak of the turn
    reference_image_base64     optional   registered profile photo
    camera_label               optional   camera name, flagged for review only
  *  required while FLASH_REFLECTION_ENABLED=true     Missing data is REJECTED, never skipped.
  ** required while TURN_REQUIRED=true                Missing data is REJECTED, never skipped.

POST /extract-embedding {"image_base64": ...}  -> embedding + photo quality values
GET  /health                                   -> status and build only
GET  /health/config                            -> effective configuration (needs the token)
"""

import os
from dotenv import load_dotenv

# Explicitly load .env relative to app.py directory
env_path = os.path.join(os.path.dirname(__file__), '.env')
load_dotenv(dotenv_path=env_path)

BUILD = "liveness-v3-pose-calibrated-tuned"

if os.getenv("BIOMETRIC_THREADS"):
    os.environ.setdefault("OMP_NUM_THREADS", os.environ["BIOMETRIC_THREADS"])

import base64
import hashlib
import hmac
import io
import json
import logging
import math
import re
import threading
import time
import uuid
from contextlib import contextmanager
from dataclasses import dataclass, field
from logging.handlers import RotatingFileHandler
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np
from flask import Flask, jsonify, request
from insightface.app import FaceAnalysis
from PIL import Image, ImageOps
from werkzeug.exceptions import HTTPException

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("biometrics")

# --------------------------------------------------------------------------- #
# Configuration                                                               #
# --------------------------------------------------------------------------- #

CONFIG: Dict[str, object] = {}
_TRUE = {"1", "true", "yes", "on"}
_FALSE = {"0", "false", "no", "off"}


def _f(name: str, default: float) -> float:
    raw = os.getenv(name)
    try:
        value = float(default) if raw is None or raw.strip() == "" else float(raw)
    except ValueError:
        raise ValueError(f"{name} must be a number (got {raw!r})")
    CONFIG[name] = value
    return value


def _i(name: str, default: int) -> int:
    raw = os.getenv(name)
    try:
        value = int(default) if raw is None or raw.strip() == "" else int(raw)
    except ValueError:
        raise ValueError(f"{name} must be a whole number (got {raw!r})")
    CONFIG[name] = value
    return value


def _b(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None or raw.strip() == "":
        value = default
    elif raw.strip().lower() in _TRUE:
        value = True
    elif raw.strip().lower() in _FALSE:
        value = False
    else:
        raise ValueError(f"{name} must be true or false (got {raw!r})")
    CONFIG[name] = value
    return value


HOST = os.getenv("BIOMETRIC_HOST", "127.0.0.1")
PORT = int(os.getenv("BIOMETRIC_PORT", "5000"))
INTERNAL_API_TOKEN = os.getenv("INTERNAL_API_TOKEN", "")
ALLOW_NO_TOKEN = _b("ALLOW_NO_TOKEN", False)
MODEL_NAME = os.getenv("MODEL_NAME", "buffalo_l")
MODEL_ROOT = os.getenv("MODEL_ROOT", "~/.insightface")
ATTEMPT_LOG_PATH = os.getenv("ATTEMPT_LOG_PATH", "logs/attempts.jsonl").strip()

MAX_REQUEST_BYTES = _i("MAX_REQUEST_BYTES", 20 * 1024 * 1024)
MAX_B64_CHARS = _i("MAX_B64_CHARS", 4_000_000)
MAX_DECODED_PIXELS = _i("MAX_DECODED_PIXELS", 4_000_000)
MAX_IMAGE_SIDE = _i("MAX_IMAGE_SIDE", 1000)
STRICT_FRAME_SIZE = _b("STRICT_FRAME_SIZE", True)

MAX_CONCURRENT = _i("MAX_CONCURRENT", 2)
QUEUE_TIMEOUT_S = _f("QUEUE_TIMEOUT_S", 20)

CALIBRATION_MODE = _b("CALIBRATION_MODE", False)

DET_THRESH = _f("DET_THRESH", 0.35)
MIN_DET_SCORE = _f("MIN_DET_SCORE", 0.50)
MIN_FACE_PIXELS = _f("MIN_FACE_PIXELS", 90)
SECOND_FACE_RATIO = _f("SECOND_FACE_RATIO", 0.25)

REF_MATCH_MIN_SIM = _f("REF_MATCH_MIN_SIM", 0.50)

# --- Screen color reflection ---
FLASH_REFLECTION_ENABLED = _b("FLASH_REFLECTION_ENABLED", True)
FLASH_FRAME_COUNT = 3
VALID_FLASH_COLORS = {"red", "green", "blue"}
MIN_FLASH_COLOR_DELTA = _f("MIN_FLASH_COLOR_DELTA", 3.5)
MIN_FLASH_DOMINANCE_MARGIN = _f("MIN_FLASH_DOMINANCE_MARGIN", 0.5)
FLASH_MIN_PASSES = _i("FLASH_MIN_PASSES", 3)
MAX_FLASH_MOVE_RATIO = _f("MAX_FLASH_MOVE_RATIO", 0.20)
FLASH_USE_SKIN_MASK = _b("FLASH_USE_SKIN_MASK", True)
MIN_FLASH_CHROMA_SHIFT = _f("MIN_FLASH_CHROMA_SHIFT", 0.0)
FLASH_FACE_BG_ENABLED = _b("FLASH_FACE_BG_ENABLED", True)
MIN_FACE_BG_GAP = _f("MIN_FACE_BG_GAP", 0.8)
MIN_BG_PIXELS = _i("MIN_BG_PIXELS", 2000)
FLASH_IDENTITY_CHECK = _b("FLASH_IDENTITY_CHECK", True)
FLASH_IDENTITY_MIN_SIM = _f("FLASH_IDENTITY_MIN_SIM", 0.0)

# --- Head turn ---
TURN_REQUIRED = _b("TURN_REQUIRED", True)
VALID_DIRECTIONS = {"left", "right"}
POSE_ENABLED = _b("POSE_ENABLED", True)
LEFT_TURN_SIGN = _i("LEFT_TURN_SIGN", -1)
FRONTAL_MAX_RATIO = _f("FRONTAL_MAX_RATIO", 0.15)
MIN_TURN_RATIO = _f("MIN_TURN_RATIO", 0.08)  # Tuned to prevent browser/server threshold discrepancies[cite: 7]
MAX_TURN_RATIO = _f("MAX_TURN_RATIO", 0.75)
WRONG_WAY_RATIO = _f("WRONG_WAY_RATIO", 0.10)
MIN_TURN_DEG = _f("MIN_TURN_DEG", 8)
MAX_TURN_DEG = _f("MAX_TURN_DEG", 55)
MAX_PITCH_DELTA_DEG = _f("MAX_PITCH_DELTA_DEG", 25)
MAX_ROLL_DELTA_DEG = _f("MAX_ROLL_DELTA_DEG", 25)
TURN_IDENTITY_MIN_SIM = _f("TURN_IDENTITY_MIN_SIM", 0.30)
TURN_MIN_DET_SCORE = _f("TURN_MIN_DET_SCORE", 0.40)
TURN_MIN_FACE_PIXELS = _f("TURN_MIN_FACE_PIXELS", 70)
MIN_TURN_SHARPNESS = _f("MIN_TURN_SHARPNESS", 0.0)

PROFILE_QUALITY_ENFORCE = _b("PROFILE_QUALITY_ENFORCE", False)
PROFILE_MAX_YAW_DEG = _f("PROFILE_MAX_YAW_DEG", 30)
PROFILE_MIN_SHARPNESS = _f("PROFILE_MIN_SHARPNESS", 0.0)

SUSPICIOUS_CAMERA_PATTERN = re.compile(
    r"\bobs\b|virtual|manycam|snap camera|xsplit|vcam|splitcam|droidcam|iriun|epoccam|\bndi\b|fake|screen",
    re.IGNORECASE,
)

Image.MAX_IMAGE_PIXELS = MAX_DECODED_PIXELS

if LEFT_TURN_SIGN not in (1, -1):
    raise ValueError(f"LEFT_TURN_SIGN must be 1 or -1 (got {LEFT_TURN_SIGN})")
if MAX_CONCURRENT < 1:
    raise ValueError("MAX_CONCURRENT must be at least 1")
if not INTERNAL_API_TOKEN and not ALLOW_NO_TOKEN:
    raise RuntimeError(
        "INTERNAL_API_TOKEN is empty. Set it to the same value as BIOMETRIC_SERVICE_TOKEN in Laravel's .env."
    )

CONFIG_HASH = hashlib.sha256(json.dumps(CONFIG, sort_keys=True).encode()).hexdigest()[:12]

# --------------------------------------------------------------------------- #
# Logging setup                                                               #
# --------------------------------------------------------------------------- #

attempt_logger = logging.getLogger("biometrics.attempts")
attempt_logger.propagate = False
attempt_logger.setLevel(logging.INFO)
if ATTEMPT_LOG_PATH:
    os.makedirs(os.path.dirname(os.path.abspath(ATTEMPT_LOG_PATH)), exist_ok=True)
    _handler = RotatingFileHandler(ATTEMPT_LOG_PATH, maxBytes=5 * 1024 * 1024, backupCount=5, encoding="utf-8")
    _handler.setFormatter(logging.Formatter("%(message)s"))
    attempt_logger.addHandler(_handler)

# --------------------------------------------------------------------------- #
# Model Initialization                                                        #
# --------------------------------------------------------------------------- #

_modules = ["detection", "recognition"] + (["landmark_3d_68"] if POSE_ENABLED else [])
face_analyzer = FaceAnalysis(name=MODEL_NAME, root=MODEL_ROOT, allowed_modules=_modules)
face_analyzer.prepare(ctx_id=-1, det_thresh=DET_THRESH, det_size=(640, 640))

try:
    face_analyzer.get(np.zeros((480, 640, 3), dtype=np.uint8))
except Exception:
    logger.warning("Model warm-up failed (continuing)", exc_info=True)

INFERENCE_SLOTS = threading.BoundedSemaphore(MAX_CONCURRENT)

# --------------------------------------------------------------------------- #
# Data Types & Helpers                                                        #
# --------------------------------------------------------------------------- #

class FrameRejected(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass
class FrameAnalysis:
    label: str
    image: np.ndarray
    bbox: List[float]
    det_score: float
    embedding: np.ndarray
    kps: Optional[np.ndarray]
    pose: Optional[Tuple[float, float, float]]
    sharpness: float


@dataclass
class Attempt:
    request_id: str
    checks: Dict = field(default_factory=dict)
    flags: List[str] = field(default_factory=list)
    failures: List[Tuple[str, str]] = field(default_factory=list)
    timings: Dict[str, float] = field(default_factory=dict)

    def fail(self, code: str, message: str) -> None:
        self.failures.append((code, message))

    def flag(self, name: str) -> None:
        if name not in self.flags:
            self.flags.append(name)


@contextmanager
def timed(attempt: Attempt, name: str):
    start = time.perf_counter()
    try:
        yield
    finally:
        attempt.timings[name] = round((time.perf_counter() - start) * 1000, 1)


def _r(value: Optional[float], digits: int = 4) -> Optional[float]:
    return None if value is None else round(float(value), digits)


def _area(box) -> float:
    return max(float(box[2]) - float(box[0]), 0.0) * max(float(box[3]) - float(box[1]), 0.0)


def decode_image(b64_str) -> np.ndarray:
    if not isinstance(b64_str, str) or not b64_str:
        raise FrameRejected("invalid_image", "Invalid image uploaded.")

    if "," in b64_str[:100]:
        b64_str = b64_str.split(",", 1)[1]
    if len(b64_str) > MAX_B64_CHARS:
        raise FrameRejected("image_too_large", "The image is too large.")

    try:
        image = Image.open(io.BytesIO(base64.b64decode(b64_str)))
        fmt, width, height = image.format, image.width, image.height
    except Exception:
        raise FrameRejected("invalid_image", "Invalid image uploaded.")

    if fmt not in ("JPEG", "PNG"):
        raise FrameRejected("invalid_image", "Invalid image uploaded.")
    if width * height > MAX_DECODED_PIXELS:
        raise FrameRejected("image_too_large", "The image is too large.")

    try:
        image = ImageOps.exif_transpose(image).convert("RGB")
    except Exception:
        raise FrameRejected("invalid_image", "Invalid image uploaded.")

    longest = max(image.size)
    if longest > MAX_IMAGE_SIDE:
        ratio = MAX_IMAGE_SIDE / longest
        image = image.resize((int(image.width * ratio), int(image.height * ratio)), Image.LANCZOS)

    return cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)


def get_pose(face) -> Optional[Tuple[float, float, float]]:
    try:
        pitch, yaw, roll = (float(v) for v in face["pose"])
    except Exception:
        return None
    if any(not math.isfinite(v) or abs(v) > 360 for v in (pitch, yaw, roll)):
        return None
    return pitch, yaw, roll


def sharpness_score(img: np.ndarray, bbox: List[float]) -> float:
    height, width = img.shape[:2]
    x1, y1 = int(max(0, bbox[0])), int(max(0, bbox[1]))
    x2, y2 = int(min(width, bbox[2])), int(min(height, bbox[3]))
    if x2 - x1 < 8 or y2 - y1 < 8:
        return 0.0

    gray = cv2.cvtColor(img[y1:y2, x1:x2], cv2.COLOR_BGR2GRAY)
    new_height = max(8, int(gray.shape[0] * 128.0 / gray.shape[1]))
    gray = cv2.resize(gray, (128, new_height), interpolation=cv2.INTER_AREA)
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())


def analyze_image(label: str, img: np.ndarray, min_det_score: float, min_face_px: float) -> FrameAnalysis:
    faces = face_analyzer.get(img)

    if len(faces) == 0:
        raise FrameRejected("no_face", f"No face detected in the {label} image. Ensure proper lighting.")

    faces = sorted(faces, key=lambda f: _area(f.bbox), reverse=True)
    face = faces[0]
    if len(faces) > 1 and _area(faces[1].bbox) >= SECOND_FACE_RATIO * _area(face.bbox):
        raise FrameRejected("multiple_faces", f"Multiple faces detected in the {label} image.")

    det_score = float(face.det_score)
    if det_score < min_det_score:
        raise FrameRejected("low_quality", f"Face quality too low in the {label} image.")

    bbox = [float(v) for v in face.bbox]
    if (bbox[2] - bbox[0]) < min_face_px:
        raise FrameRejected("face_too_small", "Face too small in frame. Move closer.")

    raw = np.asarray(face.embedding, dtype=np.float64)
    norm = float(np.linalg.norm(raw))
    if norm == 0:
        raise FrameRejected("invalid_embedding", "Could not read facial features.")

    kps = getattr(face, "kps", None)

    return FrameAnalysis(
        label=label,
        image=img,
        bbox=bbox,
        det_score=det_score,
        embedding=raw / norm,
        kps=None if kps is None else np.asarray(kps, dtype=np.float64),
        pose=get_pose(face) if POSE_ENABLED else None,
        sharpness=sharpness_score(img, bbox),
    )


def detect_flash_face(label: str, img: np.ndarray) -> Tuple[List[float], float]:
    bboxes, _ = face_analyzer.det_model.detect(img, max_num=0, metric="default")
    count = 0 if bboxes is None else int(bboxes.shape[0])

    if count == 0:
        raise FrameRejected("flash_no_face", f"Your face was not visible during the screen flash ({label}).")

    order = sorted(range(count), key=lambda i: _area(bboxes[i]), reverse=True)
    main = bboxes[order[0]]
    if count > 1 and _area(bboxes[order[1]]) >= SECOND_FACE_RATIO * _area(main):
        raise FrameRejected("multiple_faces", f"Multiple faces detected during screen flash ({label}).")

    return [float(v) for v in main[:4]], float(main[4])


def bbox_shift_ratio(a: List[float], b: List[float]) -> float:
    width = max(a[2] - a[0], 1.0)
    shift = math.hypot((a[0] + a[2]) / 2 - (b[0] + b[2]) / 2, (a[1] + a[3]) / 2 - (b[1] + b[3]) / 2) / width
    size_change = abs((b[2] - b[0]) - (a[2] - a[0])) / width
    return max(shift, size_change)


def yaw_ratio(kps: Optional[np.ndarray]) -> Optional[float]:
    if kps is None or len(kps) < 3:
        return None

    eye_a, eye_b, nose = kps[0], kps[1], kps[2]
    eye_distance = abs(float(eye_b[0]) - float(eye_a[0]))
    if eye_distance < 1.0:
        return None

    eye_mid_x = (float(eye_a[0]) + float(eye_b[0])) / 2.0
    return (float(nose[0]) - eye_mid_x) / eye_distance


def _reflection(delta_b: float, delta_g: float, delta_r: float, target_color: str) -> Tuple[float, float, float]:
    deltas = {"red": delta_r, "green": delta_g, "blue": delta_b}
    target = deltas[target_color]
    others = [value for color, value in deltas.items() if color != target_color]
    return target - sum(others) / 2.0, target, max(others)


def _share(b: float, g: float, r: float, color: str) -> float:
    total = b + g + r
    if total <= 0:
        return 0.0
    return {"blue": b, "green": g, "red": r}[color] / total * 100.0


def background_mask(shape: Tuple[int, ...], bbox: List[float]) -> Optional[np.ndarray]:
    height, width = shape[:2]
    x1, _, x2, y2 = bbox
    pad = (x2 - x1) * 0.35

    mask = np.zeros((height, width), dtype=np.uint8)
    mask[0:int(min(height, max(y2, 0))), :] = 255
    mask[:, int(max(0, x1 - pad)):int(min(width, x2 + pad))] = 0

    return mask if cv2.countNonZero(mask) >= MIN_BG_PIXELS else None


def verify_color_reflection(
    baseline_img: np.ndarray,
    flash_img: np.ndarray,
    bbox: List[float],
    target_color: str,
) -> Tuple[bool, float, Dict]:
    if flash_img.shape != baseline_img.shape:
        flash_img = cv2.resize(flash_img, (baseline_img.shape[1], baseline_img.shape[0]))

    height, width = baseline_img.shape[:2]
    x1, y1, x2, y2 = bbox
    box_w, box_h = x2 - x1, y2 - y1

    sx1, sy1 = int(max(0, x1 + box_w * 0.20)), int(max(0, y1 + box_h * 0.20))
    sx2, sy2 = int(min(width, x2 - box_w * 0.20)), int(min(height, y2 - box_h * 0.20))

    base_skin = baseline_img[sy1:sy2, sx1:sx2]
    flash_skin = flash_img[sy1:sy2, sx1:sx2]

    if base_skin.size == 0 or flash_skin.size == 0:
        return False, 0.0, {"target_color": target_color, "error": "skin_crop_empty", "passed": False}

    skin_mask = None
    skin_ratio = None
    if FLASH_USE_SKIN_MASK:
        ycrcb = cv2.cvtColor(base_skin, cv2.COLOR_BGR2YCrCb)
        candidate = cv2.inRange(ycrcb, np.array([0, 133, 77], np.uint8), np.array([255, 173, 127], np.uint8))
        skin_ratio = cv2.countNonZero(candidate) / candidate.size
        if skin_ratio >= 0.25:
            skin_mask = candidate

    base_b, base_g, base_r = cv2.mean(base_skin, mask=skin_mask)[:3]
    flash_b, flash_g, flash_r = cv2.mean(flash_skin, mask=skin_mask)[:3]

    delta_r, delta_g, delta_b = flash_r - base_r, flash_g - base_g, flash_b - base_b
    reflection_delta, target_delta, best_other = _reflection(delta_b, delta_g, delta_r, target_color)
    dominance = target_delta - best_other
    chroma_shift = _share(flash_b, flash_g, flash_r, target_color) - _share(base_b, base_g, base_r, target_color)

    chroma_ok = MIN_FLASH_CHROMA_SHIFT <= 0 or chroma_shift >= MIN_FLASH_CHROMA_SHIFT
    color_ok = bool(
        reflection_delta >= MIN_FLASH_COLOR_DELTA and dominance >= MIN_FLASH_DOMINANCE_MARGIN and chroma_ok
    )

    metrics: Dict = {
        "target_color": target_color,
        "delta_r": round(delta_r, 2),
        "delta_g": round(delta_g, 2),
        "delta_b": round(delta_b, 2),
        "reflection_delta": round(reflection_delta, 2),
        "required_delta": MIN_FLASH_COLOR_DELTA,
        "dominance": round(dominance, 2),
        "required_dominance": MIN_FLASH_DOMINANCE_MARGIN,
        "chroma_shift": round(chroma_shift, 2),
        "skin_ratio": None if skin_ratio is None else round(skin_ratio, 3),
        "color_ok": color_ok,
    }

    face_bg_ok: Optional[bool] = None
    if FLASH_FACE_BG_ENABLED:
        mask = background_mask(baseline_img.shape, bbox)
        if mask is None:
            metrics["face_bg"] = "background_unavailable"
        else:
            bg_base_b, bg_base_g, bg_base_r = cv2.mean(baseline_img, mask=mask)[:3]
            bg_flash_b, bg_flash_g, bg_flash_r = cv2.mean(flash_img, mask=mask)[:3]
            bg_reflection, _, _ = _reflection(
                bg_flash_b - bg_base_b, bg_flash_g - bg_base_g, bg_flash_r - bg_base_r, target_color
            )
            gap = reflection_delta - bg_reflection
            face_bg_ok = bool(gap >= MIN_FACE_BG_GAP)
            metrics["bg_reflection_delta"] = round(bg_reflection, 2)
            metrics["face_bg_gap"] = round(gap, 2)
            metrics["required_face_bg_gap"] = MIN_FACE_BG_GAP
            metrics["face_bg_ok"] = face_bg_ok

    passed = bool(color_ok and face_bg_ok is not False)
    metrics["passed"] = passed
    return passed, reflection_delta, metrics


def stage_flash(a: Attempt, frontal: FrameAnalysis, flash_imgs: List[np.ndarray], colors: List[str]) -> None:
    per_flash: List[Dict] = []
    passes = 0
    failures_before = len(a.failures)

    for index, (img, color) in enumerate(zip(flash_imgs, colors), start=1):
        try:
            bbox, _ = detect_flash_face(f"{color} flash", img)
        except FrameRejected as rejection:
            per_flash.append({"target_color": color, "passed": False, "error": rejection.code})
            a.fail(rejection.code, rejection.message)
            continue

        move_ratio = bbox_shift_ratio(frontal.bbox, bbox)
        if move_ratio > MAX_FLASH_MOVE_RATIO:
            per_flash.append({"target_color": color, "passed": False, "move_ratio": _r(move_ratio)})
            a.checks["moved_at_flash"] = index
            a.fail("moved_during_flash", "Hold still while the screen flashes.")
            continue

        passed, _, metrics = verify_color_reflection(frontal.image, img, frontal.bbox, color)
        metrics["move_ratio"] = _r(move_ratio)
        per_flash.append(metrics)
        if metrics.get("face_bg") == "background_unavailable":
            a.flag("background_unavailable")
        if passed:
            passes += 1

    a.checks["flash_sequence"] = per_flash
    a.checks["flash_passes"] = passes
    a.checks["flash_required_passes"] = FLASH_MIN_PASSES

    if passes < FLASH_MIN_PASSES and len(a.failures) == failures_before:
        a.fail(
            "flash_reflection_failed",
            "The lighting check failed. Raise your screen brightness and try again.",
        )

    if FLASH_IDENTITY_CHECK and len(flash_imgs) > 1:
        try:
            probe = analyze_image("flash", flash_imgs[1], 0.30, 60)
            similarity = float(np.dot(probe.embedding, frontal.embedding))
            a.checks["flash_identity_similarity"] = _r(similarity)
            if FLASH_IDENTITY_MIN_SIM > 0 and similarity < FLASH_IDENTITY_MIN_SIM:
                a.fail("flash_identity_mismatch", "Your face did not stay consistent during the lighting check.")
        except FrameRejected as rejection:
            a.checks["flash_identity_similarity"] = f"unavailable:{rejection.code}"
            if FLASH_IDENTITY_MIN_SIM > 0:
                a.fail("flash_identity_mismatch", "Your face did not stay consistent during the lighting check.")


def stage_turn(
    a: Attempt,
    frontal: FrameAnalysis,
    peak_img: np.ndarray,
    direction: str,
    reference: Optional[FrameAnalysis],
) -> None:
    try:
        peak = analyze_image("turn", peak_img, TURN_MIN_DET_SCORE, TURN_MIN_FACE_PIXELS)
    except FrameRejected as rejection:
        a.fail(f"turn_{rejection.code}", rejection.message)
        return

    front_ratio = yaw_ratio(frontal.kps)
    peak_ratio = yaw_ratio(peak.kps)
    turn: Dict = {
        "direction": direction,
        "frontal_ratio": _r(front_ratio),
        "peak_ratio": _r(peak_ratio),
        "required": MIN_TURN_RATIO,
        "max_allowed": MAX_TURN_RATIO,
        "peak_det_score": _r(peak.det_score),
        "peak_sharpness": _r(peak.sharpness, 1),
        "frontal_sharpness": _r(frontal.sharpness, 1),
    }
    a.checks["turn"] = turn

    if front_ratio is None or peak_ratio is None:
        a.fail("turn_pose_unreadable", "Could not read your head position. Please try again.")
        return

    if abs(front_ratio) > FRONTAL_MAX_RATIO:
        a.fail("frontal_not_straight", "Look straight at the camera at the start of the check.")

    sign = LEFT_TURN_SIGN if direction == "left" else -LEFT_TURN_SIGN
    turned = (peak_ratio - front_ratio) * sign
    turn["turned"] = _r(turned)

    direction_failed = False
    if turned <= -WRONG_WAY_RATIO:
        a.fail("turn_wrong_direction", f"Turn your head to your {direction}, not the other way.")
        direction_failed = True
    elif turned < MIN_TURN_RATIO:
        a.fail("turn_too_small", f"Turn your head further to your {direction}.")
        direction_failed = True
    elif turned > MAX_TURN_RATIO:
        a.fail("turn_too_large", "Turn your head a little less. A quarter turn is enough.")
        direction_failed = True

    if POSE_ENABLED:
        if frontal.pose and peak.pose:
            d_pitch = peak.pose[0] - frontal.pose[0]
            d_yaw = peak.pose[1] - frontal.pose[1]
            d_roll = peak.pose[2] - frontal.pose[2]
            turn["pose"] = {
                "frontal": [round(v, 1) for v in frontal.pose],
                "peak": [round(v, 1) for v in peak.pose],
                "d_pitch": round(d_pitch, 1),
                "d_yaw": round(d_yaw, 1),
                "d_roll": round(d_roll, 1),
            }

            if not direction_failed:
                if abs(d_yaw) < MIN_TURN_DEG:
                    a.fail("turn_too_small", f"Turn your head further to your {direction}.")
                elif abs(d_yaw) > MAX_TURN_DEG:
                    a.fail("turn_too_large", "Turn your head a little less.")

            if abs(d_pitch) > MAX_PITCH_DELTA_DEG or abs(d_roll) > MAX_ROLL_DELTA_DEG:
                a.fail("turn_head_tilted", "Turn sideways without tilting your head up or down.")

    turn_similarity = float(np.dot(peak.embedding, frontal.embedding))
    turn["identity_similarity"] = _r(turn_similarity)
    turn["identity_required"] = TURN_IDENTITY_MIN_SIM
    if turn_similarity < TURN_IDENTITY_MIN_SIM:
        a.fail("turn_identity_mismatch", "Your face did not stay consistent during the head turn.")

    if reference is not None:
        turn["reference_similarity"] = _r(float(np.dot(reference.embedding, peak.embedding)))


# --------------------------------------------------------------------------- #
# Flask Endpoints & Responses                                                 #
# --------------------------------------------------------------------------- #

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = MAX_REQUEST_BYTES


@app.errorhandler(HTTPException)
def http_error(error: HTTPException):
    return jsonify({"detail": error.description or error.name}), error.code or 500


@app.errorhandler(Exception)
def unexpected_error(error: Exception):
    logger.exception("unhandled error")
    return jsonify({"detail": "Biometric processing error."}), 500


@app.before_request
def require_internal_token():
    if request.path == "/health" or not INTERNAL_API_TOKEN:
        return None
    supplied = request.headers.get("X-Internal-Token", "")
    if not hmac.compare_digest(supplied.encode("utf-8"), INTERNAL_API_TOKEN.encode("utf-8")):
        return jsonify({"detail": "Unauthorized."}), 401
    return None


@app.get("/health")
def health():
    return jsonify({"status": "ok", "build": BUILD, "config_hash": CONFIG_HASH}), 200


@app.get("/health/config")
def health_config():
    return jsonify({
        "status": "ok",
        "build": BUILD,
        "config_hash": CONFIG_HASH,
        "pose_available": POSE_ENABLED,
        "config": CONFIG,
    }), 200


@app.post("/extract-embedding")
def extract_embedding():
    data = request.get_json(silent=True)
    if not isinstance(data, dict) or "image_base64" not in data:
        return jsonify({"detail": "Missing image_base64."}), 400

    if not INFERENCE_SLOTS.acquire(timeout=QUEUE_TIMEOUT_S):
        return jsonify({"detail": "The service is busy. Please try again."}), 503

    try:
        img = decode_image(data["image_base64"])
        frame = analyze_image("profile", img, MIN_DET_SCORE, MIN_FACE_PIXELS)

        yaw_deg = frame.pose[1] if frame.pose else None
        quality = {
            "det_score": _r(frame.det_score),
            "face_width_px": round(frame.bbox[2] - frame.bbox[0], 1),
            "sharpness": _r(frame.sharpness, 1),
            "yaw_deg": _r(yaw_deg, 1),
            "yaw_ratio": _r(yaw_ratio(frame.kps)),
        }

        return jsonify({"status": "success", "embedding": frame.embedding.tolist(), "quality": quality}), 200
    except FrameRejected as rejection:
        return jsonify({"detail": rejection.message}), 400
    except Exception:
        logger.exception("extract-embedding failed")
        return jsonify({"detail": "Biometric processing error."}), 500
    finally:
        INFERENCE_SLOTS.release()


@app.post("/verify-liveness")
def verify_liveness():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"detail": "A JSON object body is required."}), 400
    if not data.get("frontal_image_base64"):
        return jsonify({"detail": "frontal_image_base64 is required."}), 400

    if not INFERENCE_SLOTS.acquire(timeout=QUEUE_TIMEOUT_S):
        return jsonify({"detail": "The service is busy. Please try again."}), 503

    attempt = Attempt(request_id=uuid.uuid4().hex[:12])
    try:
        return run_liveness(attempt, data)
    except Exception:
        logger.exception("verify-liveness failed request=%s", attempt.request_id)
        return jsonify({"detail": "Biometric processing error."}), 500
    finally:
        INFERENCE_SLOTS.release()


def run_liveness(a: Attempt, data: dict):
    started = time.perf_counter()

    frontal_b64 = data.get("frontal_image_base64")
    reference_b64 = data.get("reference_image_base64")
    turn_peak_b64 = data.get("turn_peak_image_base64")
    direction = str(data.get("direction") or "").lower()
    camera_label = str(data.get("camera_label") or "")[:200]

    flash_images_b64 = data.get("flash_images_base64") or []
    flash_colors_raw = data.get("flash_colors") or []
    if not isinstance(flash_images_b64, list):
        flash_images_b64 = []
    if not isinstance(flash_colors_raw, list):
        flash_colors_raw = []
    flash_colors = [str(color).lower() for color in flash_colors_raw]

    a.checks["build"] = BUILD
    a.checks["received"] = {
        "reference": bool(reference_b64),
        "flash_images": len(flash_images_b64),
        "flash_colors": flash_colors,
        "direction": direction,
        "turn_peak": bool(turn_peak_b64),
    }

    if camera_label:
        a.checks["camera_label"] = camera_label
        if SUSPICIOUS_CAMERA_PATTERN.search(camera_label):
            a.flag("suspicious_camera_label")

    if FLASH_REFLECTION_ENABLED:
        if len(flash_images_b64) != FLASH_FRAME_COUNT or len(flash_colors) != FLASH_FRAME_COUNT:
            return jsonify({
                "status": "rejected",
                "passed": False,
                "reason_code": "flash_missing",
                "detail": "The lighting check was not completed. Please try again.",
                "checks": a.checks,
                "review_flags": a.flags,
            }), 200
        if any(color not in VALID_FLASH_COLORS for color in flash_colors):
            return jsonify({
                "status": "rejected",
                "passed": False,
                "reason_code": "flash_colors_invalid",
                "detail": "The lighting check was invalid. Please try again.",
                "checks": a.checks,
                "review_flags": a.flags,
            }), 200

    if TURN_REQUIRED:
        if direction not in VALID_DIRECTIONS:
            return jsonify({
                "status": "rejected",
                "passed": False,
                "reason_code": "turn_invalid",
                "detail": "The head turn check was invalid. Please try again.",
                "checks": a.checks,
                "review_flags": a.flags,
            }), 200
        if not turn_peak_b64:
            return jsonify({
                "status": "rejected",
                "passed": False,
                "reason_code": "turn_missing",
                "detail": "The head turn check was not completed. Please try again.",
                "checks": a.checks,
                "review_flags": a.flags,
            }), 200

    try:
        with timed(a, "decode"):
            frontal_img = decode_image(frontal_b64)
            reference_img = decode_image(reference_b64) if reference_b64 else None
            flash_imgs = [decode_image(item) for item in flash_images_b64] if FLASH_REFLECTION_ENABLED else []
            peak_img = decode_image(turn_peak_b64) if TURN_REQUIRED else None
    except FrameRejected as rejection:
        return jsonify({
            "status": "rejected",
            "passed": False,
            "reason_code": rejection.code,
            "detail": rejection.message,
            "checks": a.checks,
            "review_flags": a.flags,
        }), 200

    try:
        with timed(a, "analyze_frontal"):
            frontal = analyze_image("live", frontal_img, MIN_DET_SCORE, MIN_FACE_PIXELS)
            reference = analyze_image("profile", reference_img, MIN_DET_SCORE, MIN_FACE_PIXELS) if reference_img is not None else None
    except FrameRejected as rejection:
        return jsonify({
            "status": "rejected",
            "passed": False,
            "reason_code": rejection.code,
            "detail": rejection.message,
            "checks": a.checks,
            "review_flags": a.flags,
        }), 200

    a.checks["frontal_det_score"] = _r(frontal.det_score)
    a.checks["frontal_sharpness"] = _r(frontal.sharpness, 1)

    if reference is not None:
        reference_similarity = float(np.dot(reference.embedding, frontal.embedding))
        a.checks["reference_similarity"] = _r(reference_similarity)
        if reference_similarity < REF_MATCH_MIN_SIM:
            a.fail("identity_mismatch", "Live face does not match the registered profile photo.")

    if FLASH_REFLECTION_ENABLED:
        with timed(a, "flash"):
            stage_flash(a, frontal, flash_imgs, flash_colors)

    if a.failures and not CALIBRATION_MODE:
        code, message = a.failures[0]
        return jsonify({
            "status": "rejected",
            "passed": False,
            "reason_code": code,
            "detail": message,
            "checks": a.checks,
            "review_flags": a.flags,
        }), 200

    if TURN_REQUIRED:
        with timed(a, "turn"):
            stage_turn(a, frontal, peak_img, direction, reference)

    if a.failures:
        code, message = a.failures[0]
        return jsonify({
            "status": "rejected",
            "passed": False,
            "reason_code": code,
            "detail": message,
            "checks": a.checks,
            "review_flags": a.flags,
        }), 200

    a.timings["total"] = round((time.perf_counter() - started) * 1000, 1)
    a.checks["timings_ms"] = a.timings

    record = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "request_id": a.request_id,
        "build": BUILD,
        "config_hash": CONFIG_HASH,
        "outcome": "passed",
        "reason_code": None,
        "review_flags": a.flags,
        "timings_ms": a.timings,
        "checks": a.checks,
    }
    if ATTEMPT_LOG_PATH:
        try:
            attempt_logger.info(json.dumps(record, default=str))
        except Exception:
            pass

    return jsonify({
        "status": "success",
        "passed": True,
        "frontal_embedding": frontal.embedding.tolist(),
        "checks": a.checks,
        "review_flags": a.flags,
    }), 200


if __name__ == "__main__":
    app.run(host=HOST, port=PORT, debug=False)