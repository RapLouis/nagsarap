import base64
import binascii
import math
import os

import cv2
import mediapipe as mp
import numpy as np
from flask import Flask, jsonify, request
from insightface.app import FaceAnalysis


# =============================================================================
# APPLICATION
# =============================================================================

app = Flask(__name__)

# Maximum biometric payload.
app.config["MAX_CONTENT_LENGTH"] = 25 * 1024 * 1024


# =============================================================================
# STRICT PRODUCTION BIOMETRIC PROFILE
# =============================================================================
MIN_BLUR_SCORE = 10.0

# Live-camera frame sharpness.
MIN_LIVENESS_BLUR_SCORE = 2.0

# InsightFace detection confidence.
MIN_DETECTION_SCORE = 0.30

# Same-person continuity between the five liveness frames.
# This is NOT the registered-student final face-match threshold.
LIVENESS_IDENTITY_THRESHOLD = 0.20

# Very wide initial/final center tolerance.
CENTER_YAW_LIMIT = 0.50

# Slight movement is enough to demonstrate head turn.
TURN_YAW_DELTA = 0.005

# Very wide return-to-center tolerance.
RETURN_YAW_DELTA = 0.50

# A tiny decrease in eye openness can trigger blink.
BLINK_RATIO = 0.995

# A tiny increase in mouth width can trigger smile.
SMILE_RATIO = 1.001
# =============================================================================
# INSIGHTFACE
# =============================================================================

print(
    "Loading InsightFace model...",
    flush=True,
)

face_analyzer = FaceAnalysis(
    name="buffalo_l",
    providers=[
        "CPUExecutionProvider",
    ],
)

face_analyzer.prepare(
    ctx_id=-1,
    det_size=(640, 640),
)

print(
    "InsightFace loaded.",
    flush=True,
)


# =============================================================================
# MEDIAPIPE
# =============================================================================

print(
    "Loading MediaPipe Face Mesh...",
    flush=True,
)

mp_face_mesh = mp.solutions.face_mesh

face_mesh = mp_face_mesh.FaceMesh(
    static_image_mode=True,
    max_num_faces=2,
    refine_landmarks=True,
    min_detection_confidence=0.5,
)

print(
    "MediaPipe Face Mesh loaded.",
    flush=True,
)


# =============================================================================
# IMAGE DECODING
# =============================================================================

def base64_to_image(encoded: str):
    if (
        not isinstance(encoded, str)
        or not encoded.strip()
    ):
        raise ValueError(
            "Image data is empty."
        )

    if "," in encoded:
        encoded = encoded.split(
            ",",
            1,
        )[1]

    try:
        image_bytes = base64.b64decode(
            encoded,
            validate=True,
        )

    except (
        ValueError,
        binascii.Error,
    ) as exc:
        raise ValueError(
            "Invalid base64 image data."
        ) from exc

    if not image_bytes:
        raise ValueError(
            "Decoded image is empty."
        )

    array = np.frombuffer(
        image_bytes,
        dtype=np.uint8,
    )

    image = cv2.imdecode(
        array,
        cv2.IMREAD_COLOR,
    )

    if image is None:
        raise ValueError(
            "Unable to decode image."
        )

    return image


# =============================================================================
# ANDROID CAMERA ORIENTATION
# =============================================================================

def orientation_candidates(image):
    """
    Android CameraX / Flutter camera JPEGs may be saved in a different
    orientation from the CameraPreview.

    Every biometric image is therefore tested in the four safe rotations.
    """

    return [
        (
            0,
            image,
        ),
        (
            90,
            cv2.rotate(
                image,
                cv2.ROTATE_90_CLOCKWISE,
            ),
        ),
        (
            -90,
            cv2.rotate(
                image,
                cv2.ROTATE_90_COUNTERCLOCKWISE,
            ),
        ),
        (
            180,
            cv2.rotate(
                image,
                cv2.ROTATE_180,
            ),
        ),
    ]


def prioritized_orientation_candidates(
    image,
    preferred_rotation=None,
):
    """
    Prefer the rotation selected for the initial center frame.

    This prevents:
        center   = rotation 0
        blink    = rotation -90
        turn     = rotation 90

    from being treated as authoritative orientations merely because one
    orientation obtained a slightly larger detector confidence.
    """

    candidates = orientation_candidates(
        image
    )

    if preferred_rotation is None:
        return candidates

    return sorted(
        candidates,
        key=lambda item: (
            0
            if item[0] == preferred_rotation
            else 1
        ),
    )


# =============================================================================
# FACIAL LANDMARK METRICS
# =============================================================================

def distance(
    point_a,
    point_b,
) -> float:
    return math.sqrt(
        (
            point_a.x
            - point_b.x
        ) ** 2
        +
        (
            point_a.y
            - point_b.y
        ) ** 2
    )


def eye_openness(
    landmarks,
) -> float:
    left_horizontal = distance(
        landmarks[33],
        landmarks[133],
    )

    left_vertical = distance(
        landmarks[159],
        landmarks[145],
    )

    right_horizontal = distance(
        landmarks[362],
        landmarks[263],
    )

    right_vertical = distance(
        landmarks[386],
        landmarks[374],
    )

    if (
        left_horizontal <= 0
        or right_horizontal <= 0
    ):
        return 0.0

    left_ratio = (
        left_vertical
        / left_horizontal
    )

    right_ratio = (
        right_vertical
        / right_horizontal
    )

    return (
        left_ratio
        + right_ratio
    ) / 2.0


def yaw_proxy(
    landmarks,
) -> float:
    """
    Lightweight yaw/head-turn measurement.

    Positive/negative direction is not important because the challenge uses
    the absolute difference from the original centered position.
    """

    left_cheek = landmarks[234]
    right_cheek = landmarks[454]
    nose = landmarks[1]

    face_width = abs(
        right_cheek.x
        - left_cheek.x
    )

    if face_width <= 0:
        return 0.0

    center_x = (
        left_cheek.x
        + right_cheek.x
    ) / 2.0

    return (
        nose.x
        - center_x
    ) / face_width


def mouth_width_ratio(
    landmarks,
) -> float:
    mouth_width = distance(
        landmarks[61],
        landmarks[291],
    )

    face_width = distance(
        landmarks[234],
        landmarks[454],
    )

    if face_width <= 0:
        return 0.0

    return (
        mouth_width
        / face_width
    )


# =============================================================================
# EMBEDDING HELPERS
# =============================================================================

def normalize_embedding(
    embedding,
):
    vector = np.asarray(
        embedding,
        dtype=np.float32,
    )

    norm = np.linalg.norm(
        vector
    )

    if norm <= 0:
        raise ValueError(
            "Invalid facial embedding."
        )

    return (
        vector
        / norm
    )


def cosine_similarity(
    vector_a,
    vector_b,
) -> float:
    a = np.asarray(
        vector_a,
        dtype=np.float32,
    )

    b = np.asarray(
        vector_b,
        dtype=np.float32,
    )

    if (
        a.size == 0
        or b.size == 0
        or a.shape != b.shape
    ):
        return 0.0

    norm_a = np.linalg.norm(
        a
    )

    norm_b = np.linalg.norm(
        b
    )

    if (
        norm_a <= 0
        or norm_b <= 0
    ):
        return 0.0

    similarity = np.dot(
        a,
        b,
    ) / (
        norm_a
        * norm_b
    )

    return float(
        similarity
    )


# =============================================================================
# BLUR / IMAGE QUALITY
# =============================================================================

def calculate_face_blur(
    image,
    face,
) -> float:
    bbox = face.bbox.astype(
        int
    )

    x1, y1, x2, y2 = bbox

    height, width = image.shape[:2]

    x1 = max(
        0,
        x1,
    )

    y1 = max(
        0,
        y1,
    )

    x2 = min(
        width,
        x2,
    )

    y2 = min(
        height,
        y2,
    )

    crop = image[
        y1:y2,
        x1:x2,
    ]

    if crop.size == 0:
        return 0.0

    gray = cv2.cvtColor(
        crop,
        cv2.COLOR_BGR2GRAY,
    )

    gray = cv2.equalizeHist(
        gray
    )

    score = cv2.Laplacian(
        gray,
        cv2.CV_64F,
    ).var()

    return float(
        score
    )


def landmark_blur(
    image,
    landmarks,
) -> float:
    height, width = image.shape[:2]

    xs = [
        point.x
        for point in landmarks
    ]

    ys = [
        point.y
        for point in landmarks
    ]

    if not xs or not ys:
        return 0.0

    x1 = max(
        0,
        int(
            min(xs)
            * width
        ),
    )

    y1 = max(
        0,
        int(
            min(ys)
            * height
        ),
    )

    x2 = min(
        width,
        int(
            max(xs)
            * width
        ),
    )

    y2 = min(
        height,
        int(
            max(ys)
            * height
        ),
    )

    crop = image[
        y1:y2,
        x1:x2,
    ]

    if crop.size == 0:
        return 0.0

    gray = cv2.cvtColor(
        crop,
        cv2.COLOR_BGR2GRAY,
    )

    gray = cv2.equalizeHist(
        gray
    )

    score = cv2.Laplacian(
        gray,
        cv2.CV_64F,
    ).var()

    return float(
        score
    )


# =============================================================================
# MEDIAPIPE DETECTION
# =============================================================================

def mediapipe_landmarks(
    image,
):
    rgb = cv2.cvtColor(
        image,
        cv2.COLOR_BGR2RGB,
    )

    result = face_mesh.process(
        rgb
    )

    return (
        result.multi_face_landmarks
        or []
    )


def find_mediapipe_face(
    image,
    frame_name,
    preferred_rotation=None,
):
    multiple_faces = False

    candidates = (
        prioritized_orientation_candidates(
            image,
            preferred_rotation,
        )
    )

    for rotation, candidate in candidates:
        faces = mediapipe_landmarks(
            candidate
        )

        if len(faces) > 1:
            multiple_faces = True
            continue

        if len(faces) == 1:
            print(
                f"[MEDIAPIPE] "
                f"{frame_name} "
                f"rotation={rotation}",
                flush=True,
            )

            return (
                candidate,
                faces[0].landmark,
                rotation,
            )

    if multiple_faces:
        raise ValueError(
            f"Multiple faces detected in "
            f"{frame_name} frame."
        )

    raise ValueError(
        f"No face detected in "
        f"{frame_name} frame."
    )


# =============================================================================
# INSIGHTFACE DETECTION
# =============================================================================

def find_insightface_face(
    image,
    frame_name,
    preferred_rotation=None,
):
    best_image = None
    best_face = None
    best_score = -1.0
    best_rotation = None

    multiple_faces = False

    candidates = (
        prioritized_orientation_candidates(
            image,
            preferred_rotation,
        )
    )

    for rotation, candidate in candidates:
        faces = face_analyzer.get(
            candidate
        )

        if len(faces) > 1:
            multiple_faces = True
            continue

        if len(faces) != 1:
            continue

        face = faces[0]

        score = float(
            getattr(
                face,
                "det_score",
                0.0,
            )
            or 0.0
        )

        # If preferred orientation works and its quality is valid,
        # use it immediately. This keeps orientation stable across
        # the complete liveness sequence.
        if (
            preferred_rotation is not None
            and rotation == preferred_rotation
            and score >= MIN_DETECTION_SCORE
        ):
            print(
                f"[INSIGHTFACE] "
                f"{frame_name} "
                f"rotation={rotation} "
                f"score={score:.4f} "
                f"[preferred]",
                flush=True,
            )

            return (
                candidate,
                face,
                rotation,
            )

        if score > best_score:
            best_score = score
            best_face = face
            best_image = candidate
            best_rotation = rotation

    if best_face is None:
        if multiple_faces:
            raise ValueError(
                f"Multiple faces detected in "
                f"{frame_name} frame."
            )

        raise ValueError(
            f"No face detected in "
            f"{frame_name} frame."
        )

    print(
        f"[INSIGHTFACE] "
        f"{frame_name} "
        f"rotation={best_rotation} "
        f"score={best_score:.4f}",
        flush=True,
    )

    return (
        best_image,
        best_face,
        best_rotation,
    )


# =============================================================================
# AUTHORITATIVE IDENTITY/LIVENESS FRAME
# =============================================================================

def analyze_authoritative_frame(
    image_base64,
    frame_name,
    preferred_rotation=None,
):
    """
    Used for:
      center
      turned
      smile
      returned

    These frames are stable enough for BOTH:
      MediaPipe liveness measurements
      InsightFace identity embeddings
    """

    original = base64_to_image(
        image_base64
    )

    candidates = (
        prioritized_orientation_candidates(
            original,
            preferred_rotation,
        )
    )

    best = None
    multiple_faces = False

    for rotation, candidate in candidates:
        insight_faces = face_analyzer.get(
            candidate
        )

        mesh_faces = mediapipe_landmarks(
            candidate
        )

        if (
            len(insight_faces) > 1
            or len(mesh_faces) > 1
        ):
            multiple_faces = True
            continue

        if (
            len(insight_faces) != 1
            or len(mesh_faces) != 1
        ):
            continue

        face = insight_faces[0]

        detection_score = float(
            getattr(
                face,
                "det_score",
                0.0,
            )
            or 0.0
        )

        current = {
            "image": candidate,
            "face": face,
            "landmarks":
                mesh_faces[0].landmark,
            "rotation":
                rotation,
            "detection_score":
                detection_score,
        }

        # Prefer the orientation established by center.
        if (
            preferred_rotation is not None
            and rotation == preferred_rotation
            and detection_score
            >= MIN_DETECTION_SCORE
        ):
            best = current
            break

        if (
            best is None
            or detection_score
            > best["detection_score"]
        ):
            best = current

    if best is None:
        if multiple_faces:
            raise ValueError(
                f"Multiple faces detected in "
                f"{frame_name} frame."
            )

        raise ValueError(
            f"No face detected in "
            f"{frame_name} frame."
        )

    detection_score = (
        best["detection_score"]
    )

    if (
        detection_score
        < MIN_DETECTION_SCORE
    ):
        raise ValueError(
            f"Face visibility is too low in "
            f"{frame_name} frame."
        )

    blur_score = calculate_face_blur(
        best["image"],
        best["face"],
    )

    if (
        blur_score
        < MIN_LIVENESS_BLUR_SCORE
    ):
        raise ValueError(
            f"{frame_name.capitalize()} "
            f"frame is too blurry."
        )

    raw_embedding = getattr(
        best["face"],
        "embedding",
        None,
    )

    if raw_embedding is None:
        raise ValueError(
            f"Unable to extract face from "
            f"{frame_name} frame."
        )

    embedding = normalize_embedding(
        raw_embedding
    )

    landmarks = best[
        "landmarks"
    ]

    print(
        f"[LIVENESS] "
        f"{frame_name} "
        f"rotation={best['rotation']} "
        f"score={detection_score:.4f}",
        flush=True,
    )

    return {
        "embedding":
            embedding,

        "yaw":
            float(
                yaw_proxy(
                    landmarks
                )
            ),

        "eye_openness":
            float(
                eye_openness(
                    landmarks
                )
            ),

        "mouth_width":
            float(
                mouth_width_ratio(
                    landmarks
                )
            ),

        "blur_score":
            float(
                blur_score
            ),

        "detection_score":
            float(
                detection_score
            ),

        "rotation":
            int(
                best["rotation"]
            ),
    }


# =============================================================================
# BLINK FRAME ANALYSIS
# =============================================================================

def analyze_blink_frame(
    image_base64,
    preferred_rotation=None,
):
    """
    Blink is intentionally analyzed with MediaPipe instead of requiring a
    strict InsightFace embedding.

    Why:
        During an actual blink the eyes are closed.
        This can alter InsightFace alignment and embedding similarity.

    Security is NOT disabled:
        - a real face must still be detected by MediaPipe
        - only one face is permitted
        - frame quality is checked
        - actual eye closure is measured
        - center / turn / smile / return still perform InsightFace identity
          continuity checks
        - Laravel still performs final registered-face verification
    """

    original = base64_to_image(
        image_base64
    )

    corrected, landmarks, rotation = (
        find_mediapipe_face(
            original,
            "blink",
            preferred_rotation,
        )
    )

    blur_score = landmark_blur(
        corrected,
        landmarks,
    )

    if (
        blur_score
        < MIN_LIVENESS_BLUR_SCORE
    ):
        raise ValueError(
            "Blink frame is too blurry."
        )

    eye = float(
        eye_openness(
            landmarks
        )
    )

    yaw = float(
        yaw_proxy(
            landmarks
        )
    )

    mouth = float(
        mouth_width_ratio(
            landmarks
        )
    )

    print(
        f"[LIVENESS] "
        f"blink "
        f"rotation={rotation} "
        f"eye={eye:.4f}",
        flush=True,
    )

    return {
        "yaw":
            yaw,

        "eye_openness":
            eye,

        "mouth_width":
            mouth,

        "blur_score":
            float(
                blur_score
            ),

        "rotation":
            int(
                rotation
            ),
    }


# =============================================================================
# ROOT
# =============================================================================

@app.get("/")
def home():
    return jsonify({
        "success":
            True,

        "service":
            "CCIS Face Verification Service",

        "status":
            "running",

        "profile":
            "demo_friendly",
    }), 200


# =============================================================================
# HEALTH
# =============================================================================

@app.get("/health")
def health():
    return jsonify({
        "success":
            True,

        "service":
            "CCIS Face Verification",

        "opencv":
            "ready",

        "mediapipe":
            "ready",

        "insightface":
            "ready",

        "thresholds": {
            "blur":
                MIN_BLUR_SCORE,

            "liveness_blur":
                MIN_LIVENESS_BLUR_SCORE,

            "detection":
                MIN_DETECTION_SCORE,

            "identity":
                LIVENESS_IDENTITY_THRESHOLD,

            "center_yaw":
                CENTER_YAW_LIMIT,

            "turn_delta":
                TURN_YAW_DELTA,

            "return_delta":
                RETURN_YAW_DELTA,

            "blink_ratio":
                BLINK_RATIO,

            "smile_ratio":
                SMILE_RATIO,
        },
    }), 200


# =============================================================================
# EXTRACT FACIAL EMBEDDING
# =============================================================================

@app.post("/extract-embedding")
def extract_embedding():
    data = request.get_json(
        silent=True
    )

    if not data:
        return jsonify({
            "success":
                False,

            "detail":
                "Invalid or missing JSON request body.",
        }), 400

    image_base64 = data.get(
        "image_base64"
    )

    if not image_base64:
        return jsonify({
            "success":
                False,

            "detail":
                "Missing image_base64.",
        }), 400

    try:
        image = base64_to_image(
            image_base64
        )

        corrected, face, rotation = (
            find_insightface_face(
                image,
                "image",
            )
        )

        detection_score = float(
            getattr(
                face,
                "det_score",
                0.0,
            )
            or 0.0
        )

        if (
            detection_score
            < MIN_DETECTION_SCORE
        ):
            raise ValueError(
                "Face visibility is too low. "
                "Face the camera directly "
                "and improve the lighting."
            )

        blur_score = calculate_face_blur(
            corrected,
            face,
        )

        if (
            blur_score
            < MIN_BLUR_SCORE
        ):
            raise ValueError(
                "Image is too blurry. "
                "Hold the camera steady "
                "and try again."
            )

        raw_embedding = getattr(
            face,
            "embedding",
            None,
        )

        if raw_embedding is None:
            raise ValueError(
                "Unable to generate "
                "facial embedding."
            )

        embedding = normalize_embedding(
            raw_embedding
        )

        print(
            f"[FACE] "
            f"rotation={rotation} "
            f"detection="
            f"{detection_score:.4f} "
            f"blur="
            f"{blur_score:.2f}",
            flush=True,
        )

        return jsonify({
            "success":
                True,

            "status":
                "success",

            "embedding":
                embedding.tolist(),

            "quality": {
                "blur_score":
                    round(
                        blur_score,
                        2,
                    ),

                "detection_score":
                    round(
                        detection_score,
                        4,
                    ),

                "rotation":
                    rotation,
            },
        }), 200

    except ValueError as exc:
        print(
            "[FACE REJECTED]",
            str(exc),
            flush=True,
        )

        return jsonify({
            "success":
                False,

            "detail":
                str(exc),
        }), 422

    except Exception as exc:
        print(
            "[FACE ERROR]",
            repr(exc),
            flush=True,
        )

        return jsonify({
            "success":
                False,

            "detail":
                "Biometric processing failed.",
        }), 500


# =============================================================================
# ANALYZE ONE LIVE FRAME
# =============================================================================

@app.post("/analyze-liveness-frame")
def analyze_live_frame():
    """
    Lightweight MediaPipe endpoint used by Flutter while the challenge is
    running.

    It does NOT finalize identity.

    Final verification happens through /verify-liveness.
    """

    data = request.get_json(
        silent=True
    )

    if not data:
        return jsonify({
            "success":
                False,

            "face_detected":
                False,

            "detail":
                "Invalid request body.",
        }), 400

    image_base64 = data.get(
        "image_base64"
    )

    if not image_base64:
        return jsonify({
            "success":
                False,

            "face_detected":
                False,

            "detail":
                "Missing image_base64.",
        }), 400

    try:
        image = base64_to_image(
            image_base64
        )

        corrected, landmarks, rotation = (
            find_mediapipe_face(
                image,
                "live",
            )
        )

        blur_score = landmark_blur(
            corrected,
            landmarks,
        )

        if (
            blur_score
            < MIN_LIVENESS_BLUR_SCORE
        ):
            raise ValueError(
                "Camera frame is too blurry. "
                "Hold the phone steady."
            )

        yaw = float(
            yaw_proxy(
                landmarks
            )
        )

        eye = float(
            eye_openness(
                landmarks
            )
        )

        mouth = float(
            mouth_width_ratio(
                landmarks
            )
        )

        return jsonify({
            "success":
                True,

            "face_detected":
                True,

            "yaw":
                round(
                    yaw,
                    4,
                ),

            "eye_openness":
                round(
                    eye,
                    4,
                ),

            "mouth_width":
                round(
                    mouth,
                    4,
                ),

            "blur_score":
                round(
                    blur_score,
                    2,
                ),

            "detection_score":
                1.0,

            "rotation":
                rotation,
        }), 200

    except ValueError as exc:
        return jsonify({
            "success":
                False,

            "face_detected":
                False,

            "detail":
                str(exc),
        }), 422

    except Exception as exc:
        print(
            "[LIVE FRAME ERROR]",
            repr(exc),
            flush=True,
        )

        return jsonify({
            "success":
                False,

            "face_detected":
                False,

            "detail":
                "Unable to analyze live frame.",
        }), 500


# =============================================================================
# VERIFY COMPLETE LIVENESS
# =============================================================================

@app.post("/verify-liveness")
def verify_liveness():
    data = request.get_json(
        silent=True
    )

    if not data:
        return jsonify({
            "success":
                False,

            "detail":
                "Invalid liveness request.",
        }), 400

    required_frames = [
        "center_frame",
        "blink_frame",
        "turned_frame",
        "smile_frame",
        "returned_frame",
    ]

    for key in required_frames:
        if not data.get(
            key
        ):
            return jsonify({
                "success":
                    False,

                "detail":
                    f"Missing {key}.",
            }), 400

    try:
        # =====================================================================
        # 1. INITIAL CENTER
        # =====================================================================

        center = (
            analyze_authoritative_frame(
                data["center_frame"],
                "center",
            )
        )

        # Once Android's JPEG orientation is determined from the first
        # centered frame, prefer that orientation for the remaining frames.
        preferred_rotation = center[
            "rotation"
        ]

        # =====================================================================
        # 2. BLINK
        # =====================================================================

        blink = analyze_blink_frame(
            data["blink_frame"],
            preferred_rotation=
                preferred_rotation,
        )

        # =====================================================================
        # 3. TURN
        # =====================================================================

        turned = (
            analyze_authoritative_frame(
                data["turned_frame"],
                "turned",
                preferred_rotation=
                    preferred_rotation,
            )
        )

        # =====================================================================
        # 4. SMILE
        # =====================================================================

        smile = (
            analyze_authoritative_frame(
                data["smile_frame"],
                "smile",
                preferred_rotation=
                    preferred_rotation,
            )
        )

        # =====================================================================
        # 5. RETURN CENTER
        # =====================================================================

        returned = (
            analyze_authoritative_frame(
                data[
                    "returned_frame"
                ],
                "returned",
                preferred_rotation=
                    preferred_rotation,
            )
        )

        # =====================================================================
        # SAME-PERSON IDENTITY CONTINUITY
        # =====================================================================
        #
        # DO NOT compare the closed-eye blink frame using InsightFace.
        #
        # Blink is a liveness gesture and is validated below with MediaPipe.
        #
        # Identity remains strictly verified across:
        #
        # center -> turn -> smile -> returned
        #
        # These frames retain sufficient stable facial geometry for reliable
        # InsightFace embeddings.
        # =====================================================================

        identity_scores = {}

        for frame_name, frame in [
            (
                "turned",
                turned,
            ),
            (
                "smile",
                smile,
            ),
            (
                "returned",
                returned,
            ),
        ]:
            similarity = (
                cosine_similarity(
                    center[
                        "embedding"
                    ],
                    frame[
                        "embedding"
                    ],
                )
            )

            identity_scores[
                frame_name
            ] = similarity

            print(
                f"[LIVENESS IDENTITY] "
                f"{frame_name}: "
                f"{similarity:.4f} "
                f"(minimum="
                f"{LIVENESS_IDENTITY_THRESHOLD:.4f})",
                flush=True,
            )

            if (
                similarity
                < LIVENESS_IDENTITY_THRESHOLD
            ):
                raise ValueError(
                    "The same person must remain "
                    "in front of the camera "
                    "during the entire liveness "
                    f"check ({frame_name})."
                )

        # =====================================================================
        # CENTER VALIDATION
        # =====================================================================

        if (
            abs(
                center[
                    "yaw"
                ]
            )
            > CENTER_YAW_LIMIT
        ):
            raise ValueError(
                "Start with your face centered "
                "and looking directly "
                "at the camera."
            )

        # =====================================================================
        # BLINK VALIDATION
        # =====================================================================

        blink_limit = (
            center[
                "eye_openness"
            ]
            * BLINK_RATIO
        )

        print(
            f"[BLINK] "
            f"center="
            f"{center['eye_openness']:.4f} "
            f"blink="
            f"{blink['eye_openness']:.4f} "
            f"maximum="
            f"{blink_limit:.4f}",
            flush=True,
        )

        if (
            blink[
                "eye_openness"
            ]
            > blink_limit
        ):
            raise ValueError(
                "Blink was not detected. "
                "Close both eyes fully "
                "when requested."
            )

        # =====================================================================
        # HEAD TURN VALIDATION
        # =====================================================================

        turn_delta = abs(
            turned[
                "yaw"
            ]
            - center[
                "yaw"
            ]
        )

        print(
            f"[TURN] "
            f"center="
            f"{center['yaw']:.4f} "
            f"turned="
            f"{turned['yaw']:.4f} "
            f"delta="
            f"{turn_delta:.4f}",
            flush=True,
        )

        if (
            turn_delta
            < TURN_YAW_DELTA
        ):
            raise ValueError(
                "Head turn was not detected. "
                "Turn clearly left or right."
            )

        # =====================================================================
        # SMILE VALIDATION
        # =====================================================================

        smile_limit = (
            center[
                "mouth_width"
            ]
            * SMILE_RATIO
        )

        print(
            f"[SMILE] "
            f"center="
            f"{center['mouth_width']:.4f} "
            f"smile="
            f"{smile['mouth_width']:.4f} "
            f"minimum="
            f"{smile_limit:.4f}",
            flush=True,
        )

        if (
            smile[
                "mouth_width"
            ]
            < smile_limit
        ):
            raise ValueError(
                "Smile was not detected. "
                "Smile clearly when requested."
            )

        # =====================================================================
        # RETURN TO CENTER VALIDATION
        # =====================================================================

        if (
            abs(
                returned[
                    "yaw"
                ]
            )
            > CENTER_YAW_LIMIT
        ):
            raise ValueError(
                "Return your face "
                "to the center."
            )

        return_delta = abs(
            returned[
                "yaw"
            ]
            - center[
                "yaw"
            ]
        )

        if (
            return_delta
            > RETURN_YAW_DELTA
        ):
            raise ValueError(
                "Your face did not return "
                "to the original "
                "centered position."
            )

        # =====================================================================
        # SUCCESS
        # =====================================================================

        return jsonify({
            "success":
                True,

            "status":
                "LIVENESS_PASSED",

            "message":
                "Liveness verification passed.",

            "metrics": {
                "rotation":
                    preferred_rotation,

                "center_yaw":
                    round(
                        center[
                            "yaw"
                        ],
                        4,
                    ),

                "turned_yaw":
                    round(
                        turned[
                            "yaw"
                        ],
                        4,
                    ),

                "turn_delta":
                    round(
                        turn_delta,
                        4,
                    ),

                "returned_yaw":
                    round(
                        returned[
                            "yaw"
                        ],
                        4,
                    ),

                "return_delta":
                    round(
                        return_delta,
                        4,
                    ),

                "center_eye_openness":
                    round(
                        center[
                            "eye_openness"
                        ],
                        4,
                    ),

                "blink_eye_openness":
                    round(
                        blink[
                            "eye_openness"
                        ],
                        4,
                    ),

                "blink_limit":
                    round(
                        blink_limit,
                        4,
                    ),

                "center_mouth_width":
                    round(
                        center[
                            "mouth_width"
                        ],
                        4,
                    ),

                "smile_mouth_width":
                    round(
                        smile[
                            "mouth_width"
                        ],
                        4,
                    ),

                "smile_limit":
                    round(
                        smile_limit,
                        4,
                    ),

                "identity": {
                    frame_name:
                        round(
                            score,
                            4,
                        )
                    for frame_name, score
                    in identity_scores.items()
                },
            },
        }), 200

    except ValueError as exc:
        print(
            "[LIVENESS REJECTED]",
            str(exc),
            flush=True,
        )

        return jsonify({
            "success":
                False,

            "detail":
                str(exc),
        }), 422

    except Exception as exc:
        print(
            "[LIVENESS ERROR]",
            repr(exc),
            flush=True,
        )

        return jsonify({
            "success":
                False,

            "detail":
                "Liveness processing failed.",
        }), 500


# =============================================================================
# ERROR HANDLERS
# =============================================================================

@app.errorhandler(413)
def request_too_large(
    _error,
):
    return jsonify({
        "success":
            False,

        "detail":
            "Uploaded biometric data is too large.",
    }), 413


@app.errorhandler(404)
def route_not_found(
    _error,
):
    return jsonify({
        "success":
            False,

        "detail":
            "Face verification endpoint not found.",
    }), 404


@app.errorhandler(405)
def method_not_allowed(
    _error,
):
    return jsonify({
        "success":
            False,

        "detail":
            "HTTP method is not allowed.",
    }), 405


# =============================================================================
# DEVELOPMENT SERVER
# =============================================================================

if __name__ == "__main__":
    host = os.getenv(
        "FACE_BIND_HOST",
        "127.0.0.1",
    )

    port = int(
        os.getenv(
            "FACE_PORT",
            "5000",
        )
    )

    print("")
    print(
        "=============================================="
    )
    print(
        " CCIS Face Verification Service"
    )
    print(
        " MediaPipe + OpenCV + InsightFace"
    )
    print(
        " DEMO-FRIENDLY BIOMETRIC PROFILE"
    )
    print(
        "=============================================="
    )

    print(
        f" MIN_BLUR_SCORE="
        f"{MIN_BLUR_SCORE}"
    )

    print(
        f" MIN_LIVENESS_BLUR_SCORE="
        f"{MIN_LIVENESS_BLUR_SCORE}"
    )

    print(
        f" MIN_DETECTION_SCORE="
        f"{MIN_DETECTION_SCORE}"
    )

    print(
        f" LIVENESS_IDENTITY_THRESHOLD="
        f"{LIVENESS_IDENTITY_THRESHOLD}"
    )

    print(
        f" CENTER_YAW_LIMIT="
        f"{CENTER_YAW_LIMIT}"
    )

    print(
        f" TURN_YAW_DELTA="
        f"{TURN_YAW_DELTA}"
    )

    print(
        f" RETURN_YAW_DELTA="
        f"{RETURN_YAW_DELTA}"
    )

    print(
        f" BLINK_RATIO="
        f"{BLINK_RATIO}"
    )

    print(
        f" SMILE_RATIO="
        f"{SMILE_RATIO}"
    )

    print(
        "=============================================="
    )

    print(
        f" Server: "
        f"http://{host}:{port}"
    )

    print(
        "=============================================="
    )

    app.run(
        host=host,
        port=port,
        debug=False,
        use_reloader=False,
        threaded=True,
    )