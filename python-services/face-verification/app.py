"""
Biometric microservice (Flask + InsightFace).

Endpoints
---------
GET  /health              Liveness probe for the service itself.
POST /extract-embedding   Single image -> L2-normalised 512-D embedding (unchanged contract).
POST /verify-liveness     Rotation liveness check over 2-3 frames -> pass/fail + frontal embedding.

/verify-liveness is stateless. Laravel owns the challenge (nonce, expiry, one-time use,
rate limits) and tells this service which direction was requested. This service only
answers: "do these frames show one real person who turned toward that side?"

Run in production behind gunicorn, not the Flask dev server, e.g.:
    gunicorn -w 2 -b 127.0.0.1:5000 --timeout 60 app:app
"""

import base64
import hmac
import io
import logging
import os
from dataclasses import dataclass
from typing import Optional

import cv2
import numpy as np
from flask import Flask, jsonify, request
from insightface.app import FaceAnalysis
from PIL import Image, ImageOps

log_level = os.getenv("LOG_LEVEL", "INFO").upper()

logging.basicConfig(
    level=log_level,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("biometrics")


# --------------------------------------------------------------------------- #
# Configuration (override any of these with environment variables)            #
# --------------------------------------------------------------------------- #

def _env_float(name: str, default: float) -> float:
    return float(os.getenv(name, default))


# Network / security
HOST = os.getenv("BIOMETRIC_HOST", "127.0.0.1")  # was 0.0.0.0; Laravel calls 127.0.0.1
PORT = int(os.getenv("BIOMETRIC_PORT", "5000"))
INTERNAL_API_TOKEN = os.getenv("INTERNAL_API_TOKEN", "")  # if set, requests must send X-Internal-Token
MAX_REQUEST_BYTES = int(os.getenv("MAX_REQUEST_BYTES", str(20 * 1024 * 1024)))
MAX_IMAGE_SIDE = int(os.getenv("MAX_IMAGE_SIDE", "1000"))  # larger images are downscaled

# Face quality
MIN_DET_SCORE = _env_float("MIN_DET_SCORE", 0.50)  # frontal frames / profile photos
MIN_DET_SCORE_TURN = _env_float("MIN_DET_SCORE_TURN", 0.40)  # turned faces score lower
MIN_FACE_PIXELS = _env_float("MIN_FACE_PIXELS", 90)  # minimum face box width

# Rotation checks. Starting points, NOT calibrated values: tune them using the
# metrics that /verify-liveness logs and returns under "checks".
FRONTAL_MAX_YAW_RATIO = _env_float("FRONTAL_MAX_YAW_RATIO", 0.18)
MIN_TURN_RATIO_DELTA = _env_float("MIN_TURN_RATIO_DELTA", 0.15)
MIN_POSE_YAW_DELTA_DEG = _env_float("MIN_POSE_YAW_DELTA_DEG", 10.0)
PROGRESSION_TOLERANCE = _env_float("PROGRESSION_TOLERANCE", 0.05)

# Same person across frames. Turned faces score lower than frontal ones, so this is
# deliberately looser than the profile-photo match threshold Laravel applies.
IDENTITY_MIN_SIM = _env_float("IDENTITY_MIN_SIM", 0.35)

# Optional passive anti-spoof (MiniFASNet ONNX). Off by default; see AntiSpoof below.
ANTISPOOF_ENABLED = os.getenv("ANTISPOOF_ENABLED", "false").lower() == "true"
ANTISPOOF_MODEL_PATHS = [p.strip() for p in os.getenv("ANTISPOOF_MODEL_PATHS", "").split(",") if p.strip()]
ANTISPOOF_THRESHOLD = _env_float("ANTISPOOF_THRESHOLD", 0.80)  # frontal frame
ANTISPOOF_TURN_THRESHOLD = _env_float("ANTISPOOF_TURN_THRESHOLD", 0.60)  # turned frames

# Direction convention (matches the React page): the camera image is UNMIRRORED and the
# direction is from the PERSON'S point of view. Turning to your left moves your nose
# toward the right side of the image, which gives a POSITIVE yaw ratio.
DIRECTION_SIGN = {"left": 1.0, "right": -1.0}

# Pixels beyond this are rejected outright (decompression-bomb guard).
Image.MAX_IMAGE_PIXELS = 60_000_000


# --------------------------------------------------------------------------- #
# Model setup                                                                 #
# --------------------------------------------------------------------------- #

# Only load what we use. Skipping the 2D-106 landmark and gender/age models makes
# each frame noticeably cheaper on CPU. 'landmark_3d_68' provides face.pose.
face_analyzer = FaceAnalysis(
    name="buffalo_l",
    allowed_modules=["detection", "recognition", "landmark_3d_68"],
)
face_analyzer.prepare(ctx_id=-1, det_size=(640, 640))


class AntiSpoof:
    """
    Passive presentation-attack detector using MiniFASNet models exported to ONNX
    (from the Silent-Face-Anti-Spoofing project).

    IMPORTANT: this preprocessing follows that project's conventions from memory
    (crop scale taken from the filename prefix, 80x80 BGR input, no /255 scaling,
    class index 1 = real). Validate it on real and spoof samples (printed photos,
    phone screens) before trusting it, and tune the thresholds from those results.

    Model files must be named with their crop scale first, for example:
        2.7_80x80_MiniFASNetV2.onnx
        4.0_80x80_MiniFASNetV1SE.onnx
    """

    REAL_CLASS_INDEX = 1
    INPUT_SIZE = 80

    def __init__(self, model_paths: list[str]):
        if not model_paths:
            raise RuntimeError("ANTISPOOF_ENABLED=true but ANTISPOOF_MODEL_PATHS is empty.")

        import onnxruntime as ort  # installed as an InsightFace dependency

        self.models = []
        for path in model_paths:
            name = os.path.basename(path)
            try:
                scale = float(name.split("_")[0])
            except ValueError:
                raise RuntimeError(
                    f"Anti-spoof model name must start with its crop scale, e.g. 2.7_80x80_MiniFASNetV2.onnx (got {name})."
                )
            session = ort.InferenceSession(path, providers=["CPUExecutionProvider"])
            self.models.append((session, session.get_inputs()[0].name, scale))

    def _crop(self, img: np.ndarray, bbox, scale: float) -> np.ndarray:
        src_h, src_w = img.shape[:2]
        x1, y1, x2, y2 = [float(v) for v in bbox]
        box_w, box_h = max(x2 - x1, 1.0), max(y2 - y1, 1.0)

        scale = min((src_h - 1) / box_h, (src_w - 1) / box_w, scale)
        new_w, new_h = box_w * scale, box_h * scale
        cx, cy = x1 + box_w / 2, y1 + box_h / 2

        left, top = cx - new_w / 2, cy - new_h / 2
        right, bottom = cx + new_w / 2, cy + new_h / 2

        if left < 0:
            right -= left
            left = 0
        if top < 0:
            bottom -= top
            top = 0
        if right > src_w - 1:
            left -= right - (src_w - 1)
            right = src_w - 1
        if bottom > src_h - 1:
            top -= bottom - (src_h - 1)
            bottom = src_h - 1

        crop = img[max(int(top), 0): int(bottom) + 1, max(int(left), 0): int(right) + 1]
        return cv2.resize(crop, (self.INPUT_SIZE, self.INPUT_SIZE))

    def real_score(self, img: np.ndarray, bbox) -> float:
        """Average probability (0..1) that the face is a live person."""
        scores = []
        for session, input_name, scale in self.models:
            patch = self._crop(img, bbox, scale)
            blob = patch.astype(np.float32).transpose(2, 0, 1)[None]  # BGR, CHW, no /255
            logits = session.run(None, {input_name: blob})[0][0]
            exp = np.exp(logits - np.max(logits))
            scores.append(float(exp[self.REAL_CLASS_INDEX] / exp.sum()))
        return float(np.mean(scores))


# Fail closed: if anti-spoof is switched on but broken, refuse to start rather than
# silently skipping the check.
anti_spoof: Optional[AntiSpoof] = AntiSpoof(ANTISPOOF_MODEL_PATHS) if ANTISPOOF_ENABLED else None


# --------------------------------------------------------------------------- #
# Image and face helpers                                                      #
# --------------------------------------------------------------------------- #

class FrameRejected(Exception):
    """A frame failed a check. `message` is safe to show to the end user."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass
class FrameAnalysis:
    label: str
    image: np.ndarray  # BGR
    bbox: list
    det_score: float
    embedding: np.ndarray  # L2-normalised, 512-D
    yaw_ratio: Optional[float]  # signed; positive = person turned to THEIR left
    pose_yaw_deg: Optional[float]  # InsightFace yaw in degrees (sign not relied upon)


def decode_image(b64_str: str) -> np.ndarray:
    """Base64 (optionally a data URL) -> OpenCV BGR image, with EXIF orientation fixed."""
    if not isinstance(b64_str, str) or not b64_str:
        raise FrameRejected("invalid_image", "Invalid image uploaded.")

    if "," in b64_str[:100]:
        b64_str = b64_str.split(",", 1)[1]

    try:
        image = Image.open(io.BytesIO(base64.b64decode(b64_str)))
        image = ImageOps.exif_transpose(image).convert("RGB")
    except Exception:
        raise FrameRejected("invalid_image", "Invalid image uploaded.")

    longest = max(image.size)
    if longest > MAX_IMAGE_SIDE:
        ratio = MAX_IMAGE_SIDE / longest
        image = image.resize((int(image.width * ratio), int(image.height * ratio)), Image.LANCZOS)

    return cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)


def compute_yaw_ratio(kps) -> float:
    """
    Signed left/right head turn from InsightFace's 5 keypoints
    [image-left eye, image-right eye, nose, image-left mouth, image-right mouth].

    Measures how far the nose sits from the centre of the face, along the eye axis
    (so head roll doesn't matter), divided by the eye distance (so distance from the
    camera doesn't matter). Positive = nose toward the image's right = the person
    turned to THEIR left. This sign comes from image geometry, not from a model.
    """
    left_eye, right_eye, nose, left_mouth, right_mouth = [np.asarray(p, dtype=np.float64) for p in kps]

    eye_vec = right_eye - left_eye
    eye_dist = float(np.linalg.norm(eye_vec))
    if eye_dist < 1e-6:
        return 0.0

    axis = eye_vec / eye_dist
    centre = ((left_eye + right_eye) / 2 + (left_mouth + right_mouth) / 2) / 2
    return float(np.dot(nose - centre, axis) / eye_dist)


def analyze_frame(label: str, b64_image: str, min_det_score: float) -> FrameAnalysis:
    img = decode_image(b64_image)
    faces = face_analyzer.get(img)

    if len(faces) == 0:
        raise FrameRejected("no_face", "No face detected. Make sure your face is well lit and fully visible.")
    if len(faces) > 1:
        raise FrameRejected("multiple_faces", "More than one face was detected. Only you should be in view.")

    face = faces[0]
    det_score = float(face.det_score)
    if det_score < min_det_score:
        raise FrameRejected("low_quality", "Your face was not clear enough. Improve the lighting and try again.")

    x1, _, x2, _ = [float(v) for v in face.bbox]
    if (x2 - x1) < MIN_FACE_PIXELS:
        raise FrameRejected("face_too_small", "Your face is too small in the frame. Move closer to the camera.")

    raw = np.asarray(face.embedding, dtype=np.float64)
    norm = float(np.linalg.norm(raw))
    if norm == 0:
        raise FrameRejected("invalid_embedding", "Could not read your facial features. Please try again.")

    pose = getattr(face, "pose", None)
    kps = getattr(face, "kps", None)

    return FrameAnalysis(
        label=label,
        image=img,
        bbox=[float(v) for v in face.bbox],
        det_score=det_score,
        embedding=raw / norm,
        yaw_ratio=compute_yaw_ratio(kps) if kps is not None else None,
        pose_yaw_deg=float(pose[1]) if pose is not None else None,  # pose = (pitch, yaw, roll)
    )


def _r(value: Optional[float]) -> Optional[float]:
    return None if value is None else round(float(value), 4)


# --------------------------------------------------------------------------- #
# Request hooks                                                               #
# --------------------------------------------------------------------------- #

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = MAX_REQUEST_BYTES

if not INTERNAL_API_TOKEN and HOST not in ("127.0.0.1", "localhost", "::1"):
    logger.warning("Service is reachable from the network and INTERNAL_API_TOKEN is not set.")


@app.before_request
def require_internal_token():
    """Optional shared-secret check so only Laravel can call this service."""
    if not INTERNAL_API_TOKEN or request.path == "/health":
        return None
    supplied = request.headers.get("X-Internal-Token", "")
    if not hmac.compare_digest(supplied, INTERNAL_API_TOKEN):
        return jsonify({"detail": "Unauthorized."}), 401
    return None


@app.errorhandler(413)
def payload_too_large(_error):
    return jsonify({"detail": "Uploaded data is too large."}), 413


# --------------------------------------------------------------------------- #
# Endpoints                                                                   #
# --------------------------------------------------------------------------- #

@app.get("/health")
def health():
    return jsonify({"status": "ok", "anti_spoof_enabled": anti_spoof is not None}), 200


@app.post("/extract-embedding")
def extract_embedding():
    data = request.get_json(silent=True)
    if not data or "image_base64" not in data:
        return jsonify({"detail": "Missing image_base64 in request body."}), 400

    try:
        frame = analyze_frame("image", data["image_base64"], MIN_DET_SCORE)
    except FrameRejected as rejection:
        return jsonify({"detail": rejection.message}), 400
    except Exception:
        logger.exception("extract-embedding failed")
        return jsonify({"detail": "Biometric processing error. Please try again."}), 500

    return jsonify({"status": "success", "embedding": frame.embedding.tolist()}), 200


@app.post("/analyze-liveness-frame")
def analyze_liveness_frame():
    data = request.get_json(silent=True) or {}
    image_b64 = data.get("image_base64")
    if not image_b64:
        return jsonify({"detail": "Missing image_base64 in request body."}), 400

    try:
        frame = analyze_frame("live", image_b64, MIN_DET_SCORE_TURN)
    except FrameRejected as rejection:
        return jsonify({"detail": rejection.message}), 422
    except Exception:
        logger.exception("analyze-liveness-frame failed")
        return jsonify({"detail": "Biometric processing error. Please try again."}), 500

    h, w = frame.image.shape[:2]
    x1, y1, x2, y2 = frame.bbox
    center_x = ((x1 + x2) / 2) / max(w, 1)
    center_y = ((y1 + y2) / 2) / max(h, 1)
    face_width = max(x2 - x1, 1.0)
    return jsonify({
        "success": True,
        "face_detected": True,
        "yaw": frame.yaw_ratio,
        "pose_yaw_deg": frame.pose_yaw_deg,
        "face_center_x": center_x,
        "face_center_y": center_y,
        "face_in_comfortable_zone": 0.12 <= center_x <= 0.88 and 0.12 <= center_y <= 0.88,
        "detection_score": frame.det_score,
        "face_width": face_width,
    }), 200


@app.post("/verify-liveness")
def verify_liveness():
    """
    Request JSON:
        direction:              "left" | "right"   (side the person was asked to turn to)
        frontal_image_base64:   straight-on frame (required)
        peak_image_base64:      frame at the turn's peak (required)
        mid_image_base64:       frame partway through the turn (optional)

    Always answers 200 with {"passed": true|false, ...} for a completed check, and 4xx/5xx
    only for malformed requests or server errors. On success it includes
    "frontal_embedding" for Laravel's profile match and duplicate check. "checks" holds
    the raw metrics for logging and tuning; do not forward it to the browser.
    """
    data = request.get_json(silent=True) or {}

    direction = data.get("direction")
    frontal_b64 = data.get("frontal_image_base64")
    peak_b64 = data.get("peak_image_base64")
    mid_b64 = data.get("mid_image_base64")

    if direction not in DIRECTION_SIGN:
        return jsonify({"detail": "direction must be 'left' or 'right'."}), 400
    if not frontal_b64 or not peak_b64:
        return jsonify({"detail": "frontal_image_base64 and peak_image_base64 are required."}), 400

    checks: dict = {"direction": direction}

    def reject(code: str, message: str):
        logger.info("liveness REJECTED code=%s checks=%s", code, checks)
        return jsonify({
            "status": "rejected",
            "passed": False,
            "reason_code": code,
            "detail": message,
            "checks": checks,
        }), 200

    try:
        try:
            frontal = analyze_frame("frontal", frontal_b64, MIN_DET_SCORE)
            peak = analyze_frame("peak", peak_b64, MIN_DET_SCORE_TURN)
            mid = analyze_frame("mid", mid_b64, MIN_DET_SCORE_TURN) if mid_b64 else None
        except FrameRejected as rejection:
            return reject(rejection.code, rejection.message)

        frames = [f for f in (frontal, mid, peak) if f is not None]
        checks["frames"] = {
            f.label: {
                "det_score": _r(f.det_score),
                "yaw_ratio": _r(f.yaw_ratio),
                "pose_yaw_deg": _r(f.pose_yaw_deg),
            }
            for f in frames
        }

        # 1. Landmarks are needed for the pose maths.
        if any(f.yaw_ratio is None for f in frames):
            return reject("no_landmarks", "We could not read your face position. Please try again.")

        # 2. The first frame must be straight-on (it is also the frame matched to the profile photo).
        if abs(frontal.yaw_ratio) > FRONTAL_MAX_YAW_RATIO:
            return reject("frontal_not_straight", "Look straight at the camera, then turn when asked.")

        # 3. The turn must go the requested way and be big enough.
        sign = DIRECTION_SIGN[direction]
        frontal_t = frontal.yaw_ratio * sign
        peak_t = peak.yaw_ratio * sign
        turn_delta = peak_t - frontal_t
        checks["turn_delta"] = _r(turn_delta)

        if turn_delta <= -MIN_TURN_RATIO_DELTA:
            return reject("turn_wrong_direction", f"Please turn your head to your {direction}.")
        if turn_delta < MIN_TURN_RATIO_DELTA:
            return reject("turn_too_small", "Please turn your head a little further.")

        # 3b. Second opinion from InsightFace's 3D pose. Only the size of the change is used
        #     (its sign convention is not relied on), so this can't flip the direction.
        if frontal.pose_yaw_deg is not None and peak.pose_yaw_deg is not None:
            pose_change = abs(peak.pose_yaw_deg - frontal.pose_yaw_deg)
            checks["pose_yaw_change_deg"] = _r(pose_change)
            if pose_change < MIN_POSE_YAW_DELTA_DEG:
                return reject("turn_too_small", "Please turn your head a little further.")

        # 4. The optional mid frame must sit between frontal and peak (a real turn is continuous).
        if mid is not None:
            mid_t = mid.yaw_ratio * sign
            in_between = (frontal_t - PROGRESSION_TOLERANCE) <= mid_t <= (peak_t + PROGRESSION_TOLERANCE)
            checks["mid_in_between"] = in_between
            if not in_between:
                return reject("turn_not_progressive", "The head turn was not smooth. Please try again.")

        # 5. Every frame must show the same person.
        identity = {"frontal_peak": float(np.dot(frontal.embedding, peak.embedding))}
        if mid is not None:
            identity["frontal_mid"] = float(np.dot(frontal.embedding, mid.embedding))
        checks["identity_similarity"] = {k: _r(v) for k, v in identity.items()}

        if min(identity.values()) < IDENTITY_MIN_SIM:
            return reject("identity_mismatch", "We could not confirm the same person throughout the check. Please try again.")

        # 6. Passive anti-spoof on each frame (screens, prints, low-quality replays).
        if anti_spoof is not None:
            spoof_scores = {}
            for f in frames:
                score = anti_spoof.real_score(f.image, f.bbox)
                spoof_scores[f.label] = score
                required = ANTISPOOF_THRESHOLD if f.label == "frontal" else ANTISPOOF_TURN_THRESHOLD
                if score < required:
                    checks["anti_spoof"] = {k: _r(v) for k, v in spoof_scores.items()}
                    return reject("spoof_suspected", "Verification failed. Please try again in good lighting.")
            checks["anti_spoof"] = {k: _r(v) for k, v in spoof_scores.items()}
        else:
            checks["anti_spoof"] = "disabled"

    except Exception:
        logger.exception("verify-liveness failed")
        return jsonify({"detail": "Biometric processing error. Please try again."}), 500

    logger.info("liveness PASSED checks=%s", checks)
    return jsonify({
        "status": "success",
        "passed": True,
        "frontal_embedding": frontal.embedding.tolist(),
        "checks": checks,
    }), 200


if __name__ == "__main__":
    # Development only. In production use gunicorn (see the module docstring).
    app.run(host=HOST, port=PORT, debug=False)