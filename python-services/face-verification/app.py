import base64
import binascii
import math

import cv2
import mediapipe as mp
import numpy as np
from flask import Flask, jsonify, request
from insightface.app import FaceAnalysis


# ============================================================
# APP
# ============================================================

app = Flask(__name__)

# Allow five liveness images without allowing unnecessarily
# large requests.
app.config["MAX_CONTENT_LENGTH"] = 25 * 1024 * 1024


# ============================================================
# CONFIGURATION
# ============================================================

# ------------------------------------------------------------
# PRODUCTION / STRICT BIOMETRIC PROFILE
# ------------------------------------------------------------
#
# These are the stricter values used before the temporary
# offline-testing relaxation.
#
# We keep:
#
# - OpenCV image quality checks
# - MediaPipe liveness
# - InsightFace face detection
# - InsightFace facial embeddings
# - same-person verification
# - final registered-face matching in Laravel
#
# ------------------------------------------------------------

# Registration/reference image quality.
MIN_BLUR_SCORE = 30.0

# Live camera frames may naturally be softer.
MIN_LIVENESS_BLUR_SCORE = 12.0

# InsightFace detection confidence.
MIN_DETECTION_SCORE = 0.60

# All five liveness frames must contain the same person.
LIVENESS_IDENTITY_THRESHOLD = 0.45

# Face must be centered.
CENTER_YAW_LIMIT = 0.08

# Required movement for head turn.
TURN_YAW_DELTA = 0.06

# Returned face must be close to original center.
RETURN_YAW_DELTA = 0.06

# Blink must reduce eye openness substantially.
BLINK_RATIO = 0.72

# Smile must increase mouth width.
SMILE_RATIO = 1.04


# ============================================================
# INSIGHTFACE
# ============================================================

print("Loading InsightFace model...")

face_analyzer = FaceAnalysis(
    name="buffalo_l",
    providers=["CPUExecutionProvider"],
)

face_analyzer.prepare(
    ctx_id=-1,
    det_size=(640, 640),
)

print("InsightFace model loaded successfully.")


# ============================================================
# MEDIAPIPE
# ============================================================

print("Loading MediaPipe Face Mesh...")

mp_face_mesh = mp.solutions.face_mesh

face_mesh = mp_face_mesh.FaceMesh(
    static_image_mode=True,
    max_num_faces=2,
    refine_landmarks=True,
    min_detection_confidence=0.5,
)

print("MediaPipe Face Mesh loaded successfully.")


# ============================================================
# IMAGE HELPERS
# ============================================================

def base64_to_cv2(
    b64_str: str,
):
    if (
        not isinstance(b64_str, str)
        or not b64_str.strip()
    ):
        raise ValueError(
            "Image data is empty."
        )

    if "," in b64_str:
        b64_str = b64_str.split(
            ",",
            1,
        )[1]

    try:
        img_bytes = base64.b64decode(
            b64_str,
            validate=True,
        )

    except (
        ValueError,
        binascii.Error,
    ) as exc:
        raise ValueError(
            "Invalid base64 image data."
        ) from exc

    if not img_bytes:
        raise ValueError(
            "Decoded image is empty."
        )

    np_array = np.frombuffer(
        img_bytes,
        dtype=np.uint8,
    )

    image = cv2.imdecode(
        np_array,
        cv2.IMREAD_COLOR,
    )

    if image is None:
        raise ValueError(
            "Unable to decode the supplied image."
        )

    return image


def rotated_candidates(
    image,
):
    """
    Android front-camera JPEG orientation may differ from
    the orientation shown by CameraPreview.

    Try all safe orientations before declaring that there
    is no detectable face.
    """

    return [
        image,

        cv2.rotate(
            image,
            cv2.ROTATE_90_CLOCKWISE,
        ),

        cv2.rotate(
            image,
            cv2.ROTATE_90_COUNTERCLOCKWISE,
        ),

        cv2.rotate(
            image,
            cv2.ROTATE_180,
        ),
    ]


# ============================================================
# BLUR
# ============================================================

def calculate_face_blur(
    image,
    face,
) -> float:
    bbox = face.bbox.astype(
        int
    )

    x1, y1, x2, y2 = bbox

    height, width = image.shape[:2]

    face_width = x2 - x1
    face_height = y2 - y1

    if (
        face_width <= 0
        or face_height <= 0
    ):
        return 0.0

    margin_x = int(
        face_width * 0.08
    )

    margin_y = int(
        face_height * 0.08
    )

    x1 = max(
        0,
        x1 - margin_x,
    )

    y1 = max(
        0,
        y1 - margin_y,
    )

    x2 = min(
        width,
        x2 + margin_x,
    )

    y2 = min(
        height,
        y2 + margin_y,
    )

    face_crop = image[
        y1:y2,
        x1:x2,
    ]

    if face_crop.size == 0:
        return 0.0

    gray = cv2.cvtColor(
        face_crop,
        cv2.COLOR_BGR2GRAY,
    )

    gray = cv2.equalizeHist(
        gray
    )

    blur_score = cv2.Laplacian(
        gray,
        cv2.CV_64F,
    ).var()

    return float(
        blur_score
    )


def calculate_landmark_face_blur(
    image,
    landmarks,
) -> float:
    """
    Used when MediaPipe detects the face before final
    InsightFace verification.
    """

    height, width = image.shape[:2]

    xs = [
        landmark.x
        for landmark in landmarks
    ]

    ys = [
        landmark.y
        for landmark in landmarks
    ]

    if (
        not xs
        or not ys
    ):
        return 0.0

    x1 = int(
        min(xs) * width
    )

    y1 = int(
        min(ys) * height
    )

    x2 = int(
        max(xs) * width
    )

    y2 = int(
        max(ys) * height
    )

    face_width = max(
        1,
        x2 - x1,
    )

    face_height = max(
        1,
        y2 - y1,
    )

    margin_x = int(
        face_width * 0.10
    )

    margin_y = int(
        face_height * 0.10
    )

    x1 = max(
        0,
        x1 - margin_x,
    )

    y1 = max(
        0,
        y1 - margin_y,
    )

    x2 = min(
        width,
        x2 + margin_x,
    )

    y2 = min(
        height,
        y2 + margin_y,
    )

    face_crop = image[
        y1:y2,
        x1:x2,
    ]

    if face_crop.size == 0:
        return 0.0

    gray = cv2.cvtColor(
        face_crop,
        cv2.COLOR_BGR2GRAY,
    )

    gray = cv2.equalizeHist(
        gray
    )

    blur_score = cv2.Laplacian(
        gray,
        cv2.CV_64F,
    ).var()

    return float(
        blur_score
    )


# ============================================================
# EMBEDDING HELPERS
# ============================================================

def normalize_embedding(
    embedding,
):
    embedding = np.asarray(
        embedding,
        dtype=np.float32,
    )

    norm = np.linalg.norm(
        embedding
    )

    if norm <= 0:
        raise ValueError(
            "Invalid facial feature vector generated."
        )

    return (
        embedding
        / norm
    )


def cosine_similarity(
    vec_a,
    vec_b,
) -> float:
    a = np.asarray(
        vec_a,
        dtype=np.float32,
    )

    b = np.asarray(
        vec_b,
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

    similarity = (
        np.dot(
            a,
            b,
        )
        / (
            norm_a
            * norm_b
        )
    )

    return float(
        similarity
    )


# ============================================================
# MEDIAPIPE METRICS
# ============================================================

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
    left_cheek = landmarks[234]
    right_cheek = landmarks[454]
    nose = landmarks[1]

    face_width = abs(
        right_cheek.x
        - left_cheek.x
    )

    if face_width <= 0:
        return 0.0

    face_center_x = (
        left_cheek.x
        + right_cheek.x
    ) / 2.0

    return (
        nose.x
        - face_center_x
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


# ============================================================
# MEDIAPIPE FACE DETECTION
# ============================================================

def detect_mediapipe_face(
    image,
    frame_name,
):
    """
    Finds a single face and handles Android JPEG rotation.
    """

    multiple_faces_found = False

    for candidate in rotated_candidates(
        image
    ):
        rgb = cv2.cvtColor(
            candidate,
            cv2.COLOR_BGR2RGB,
        )

        result = face_mesh.process(
            rgb
        )

        detected_faces = (
            result.multi_face_landmarks
            or []
        )

        if len(
            detected_faces
        ) > 1:
            multiple_faces_found = True
            continue

        if len(
            detected_faces
        ) == 1:
            return (
                candidate,
                detected_faces[
                    0
                ].landmark,
            )

    if multiple_faces_found:
        raise ValueError(
            f"Multiple faces detected in {frame_name} frame."
        )

    raise ValueError(
        f"No face detected in {frame_name} frame."
    )


# ============================================================
# INSIGHTFACE FACE DETECTION
# ============================================================

def detect_insightface_face(
    image,
    frame_name,
):
    """
    Finds exactly one InsightFace face and handles camera
    image rotation.
    """

    multiple_faces_found = False

    for candidate in rotated_candidates(
        image
    ):
        faces = face_analyzer.get(
            candidate
        )

        if len(
            faces
        ) > 1:
            multiple_faces_found = True
            continue

        if len(
            faces
        ) == 1:
            return (
                candidate,
                faces[0],
            )

    if multiple_faces_found:
        raise ValueError(
            f"Multiple faces detected in {frame_name} frame."
        )

    raise ValueError(
        f"No face detected in {frame_name} frame."
    )


# ============================================================
# LIVE/CANDIDATE FRAME ANALYSIS
# ============================================================

def analyze_live_candidate_frame(
    image_base64: str,
    frame_name: str = "live",
):
    """
    Lightweight frame analysis used while Flutter is performing
    the liveness sequence.

    MediaPipe evaluates:
      - face visibility
      - center / yaw
      - eye openness
      - mouth width

    Final verification still happens through /verify-liveness.
    """

    image = base64_to_cv2(
        image_base64
    )

    image, landmarks = (
        detect_mediapipe_face(
            image,
            frame_name,
        )
    )

    blur_score = (
        calculate_landmark_face_blur(
            image,
            landmarks,
        )
    )

    if (
        blur_score
        < MIN_LIVENESS_BLUR_SCORE
    ):
        raise ValueError(
            f"{frame_name.capitalize()} frame is too blurry. "
            "Hold the camera steady and try again."
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

    return {
        "face_detected":
            True,

        "yaw":
            yaw,

        "eye_openness":
            eye,

        "mouth_width":
            mouth,

        "blur_score":
            blur_score,

        # Final InsightFace verification occurs later.
        "detection_score":
            1.0,
    }


# ============================================================
# AUTHORITATIVE LIVENESS FRAME ANALYSIS
# ============================================================

def analyze_liveness_frame(
    image_base64: str,
    frame_name: str,
):
    """
    Final server-side biometric frame validation.

    Every final frame must pass:
      - InsightFace detection
      - detection confidence
      - image quality
      - embedding generation
      - MediaPipe face detection
      - MediaPipe liveness measurements
    """

    image = base64_to_cv2(
        image_base64
    )

    # --------------------------------------------------------
    # INSIGHTFACE
    # --------------------------------------------------------

    image, face = (
        detect_insightface_face(
            image,
            frame_name,
        )
    )

    detection_score = float(
        getattr(
            face,
            "det_score",
            0.0,
        )
    )

    if (
        detection_score
        < MIN_DETECTION_SCORE
    ):
        raise ValueError(
            f"Face visibility is too low in {frame_name} frame."
        )

    blur_score = calculate_face_blur(
        image,
        face,
    )

    if (
        blur_score
        < MIN_LIVENESS_BLUR_SCORE
    ):
        raise ValueError(
            f"{frame_name.capitalize()} frame is too blurry. "
            "Hold the camera steady and try again."
        )

    raw_embedding = getattr(
        face,
        "embedding",
        None,
    )

    if raw_embedding is None:
        raise ValueError(
            f"Unable to extract face from {frame_name} frame."
        )

    embedding = normalize_embedding(
        raw_embedding
    )

    # --------------------------------------------------------
    # MEDIAPIPE
    # --------------------------------------------------------

    rgb = cv2.cvtColor(
        image,
        cv2.COLOR_BGR2RGB,
    )

    result = face_mesh.process(
        rgb
    )

    detected_faces = (
        result.multi_face_landmarks
        or []
    )

    if len(
        detected_faces
    ) == 0:
        raise ValueError(
            f"MediaPipe could not detect a face in {frame_name} frame."
        )

    if len(
        detected_faces
    ) > 1:
        raise ValueError(
            f"MediaPipe detected multiple faces in {frame_name} frame."
        )

    landmarks = (
        detected_faces[0]
        .landmark
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
    }


# ============================================================
# ROOT
# ============================================================

@app.get("/")
def home():
    return jsonify({
        "success": True,

        "service":
            "CCIS Face Verification Service",

        "status":
            "running",

        "profile":
            "production_strict",
    }), 200


# ============================================================
# HEALTH
# ============================================================

@app.get("/health")
def health():
    return jsonify({
        "success":
            True,

        "service":
            "CCIS Face Verification",

        "mediapipe":
            "ready",

        "insightface":
            "ready",

        "opencv":
            "ready",

        "testing_profile":
            False,

        "blur_threshold":
            MIN_BLUR_SCORE,

        "liveness_blur_threshold":
            MIN_LIVENESS_BLUR_SCORE,

        "detection_threshold":
            MIN_DETECTION_SCORE,

        "identity_threshold":
            LIVENESS_IDENTITY_THRESHOLD,

        "center_yaw_limit":
            CENTER_YAW_LIMIT,

        "turn_yaw_delta":
            TURN_YAW_DELTA,

        "return_yaw_delta":
            RETURN_YAW_DELTA,

        "blink_ratio":
            BLINK_RATIO,

        "smile_ratio":
            SMILE_RATIO,
    }), 200


# ============================================================
# EXTRACT EMBEDDING
# ============================================================

@app.post(
    "/extract-embedding"
)
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
                "Missing image_base64 in request body.",
        }), 400

    try:
        image = base64_to_cv2(
            image_base64
        )

        height, width = (
            image.shape[:2]
        )

        image, primary_face = (
            detect_insightface_face(
                image,
                "image",
            )
        )

        detection_score = float(
            getattr(
                primary_face,
                "det_score",
                0.0,
            )
        )

        print(
            "[FACE] Detection score:",
            round(
                detection_score,
                4,
            ),
        )

        if (
            detection_score
            < MIN_DETECTION_SCORE
        ):
            return jsonify({
                "success":
                    False,

                "detail":
                    "Face visibility is too low. "
                    "Face the camera directly and improve the lighting.",

                "quality": {
                    "detection_score":
                        round(
                            detection_score,
                            4,
                        ),

                    "required_detection_score":
                        MIN_DETECTION_SCORE,
                },
            }), 400

        blur_score = (
            calculate_face_blur(
                image,
                primary_face,
            )
        )

        print(
            "[FACE] Blur score:",
            round(
                blur_score,
                2,
            ),
        )

        if (
            blur_score
            < MIN_BLUR_SCORE
        ):
            return jsonify({
                "success":
                    False,

                "detail":
                    "Image is too blurry. "
                    "Hold the camera steady and try again.",

                "quality": {
                    "blur_score":
                        round(
                            blur_score,
                            2,
                        ),

                    "required_blur_score":
                        MIN_BLUR_SCORE,

                    "detection_score":
                        round(
                            detection_score,
                            4,
                        ),
                },
            }), 400

        raw_embedding = getattr(
            primary_face,
            "embedding",
            None,
        )

        if raw_embedding is None:
            return jsonify({
                "success":
                    False,

                "detail":
                    "InsightFace could not generate a facial embedding.",
            }), 400

        normalized_embedding = (
            normalize_embedding(
                raw_embedding
            )
        )

        bbox = (
            primary_face
            .bbox
            .astype(int)
            .tolist()
        )

        return jsonify({
            "success":
                True,

            "status":
                "success",

            "embedding":
                normalized_embedding.tolist(),

            "quality": {
                "blur_score":
                    round(
                        blur_score,
                        2,
                    ),

                "required_blur_score":
                    MIN_BLUR_SCORE,

                "detection_score":
                    round(
                        detection_score,
                        4,
                    ),

                "required_detection_score":
                    MIN_DETECTION_SCORE,

                "image_width":
                    width,

                "image_height":
                    height,

                "face_bbox":
                    bbox,
            },
        }), 200

    except ValueError as exc:
        print(
            "[FACE] Validation error:",
            exc,
        )

        return jsonify({
            "success":
                False,

            "detail":
                str(exc),
        }), 400

    except Exception as exc:
        print(
            "[FACE] Processing error:",
            exc,
        )

        return jsonify({
            "success":
                False,

            "detail":
                "Biometric processing failed.",
        }), 500


# ============================================================
# ANALYZE SINGLE LIVE FRAME
# ============================================================

@app.post(
    "/analyze-liveness-frame"
)
def analyze_liveness_frame_endpoint():
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
        frame = (
            analyze_live_candidate_frame(
                image_base64,
                "live",
            )
        )

        return jsonify({
            "success":
                True,

            "face_detected":
                True,

            "yaw":
                round(
                    frame["yaw"],
                    4,
                ),

            "eye_openness":
                round(
                    frame[
                        "eye_openness"
                    ],
                    4,
                ),

            "mouth_width":
                round(
                    frame[
                        "mouth_width"
                    ],
                    4,
                ),

            "blur_score":
                round(
                    frame[
                        "blur_score"
                    ],
                    2,
                ),

            "detection_score":
                round(
                    frame[
                        "detection_score"
                    ],
                    4,
                ),
        }), 200

    except ValueError as exc:
        print(
            "[LIVE FRAME REJECTED]",
            str(exc),
        )

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
            exc,
        )

        return jsonify({
            "success":
                False,

            "face_detected":
                False,

            "detail":
                "Unable to analyze live frame.",
        }), 500


# ============================================================
# VERIFY COMPLETE LIVENESS
# ============================================================

@app.post(
    "/verify-liveness"
)
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
        # ====================================================
        # ANALYZE FIVE AUTHORITATIVE FRAMES
        # ====================================================

        center = analyze_liveness_frame(
            data["center_frame"],
            "center",
        )

        blink = analyze_liveness_frame(
            data["blink_frame"],
            "blink",
        )

        turned = analyze_liveness_frame(
            data["turned_frame"],
            "turned",
        )

        smile = analyze_liveness_frame(
            data["smile_frame"],
            "smile",
        )

        returned = analyze_liveness_frame(
            data["returned_frame"],
            "returned",
        )

        # ====================================================
        # SAME PERSON ACROSS ALL FRAMES
        # ====================================================

        reference_embedding = (
            center["embedding"]
        )

        identity_scores = {}

        for frame_name, frame in [
            (
                "blink",
                blink,
            ),
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
                    reference_embedding,
                    frame[
                        "embedding"
                    ],
                )
            )

            identity_scores[
                frame_name
            ] = similarity

            if (
                similarity
                < LIVENESS_IDENTITY_THRESHOLD
            ):
                raise ValueError(
                    "The same person must remain "
                    "in front of the camera during "
                    f"the entire liveness check ({frame_name})."
                )

        # ====================================================
        # CENTER
        # ====================================================

        if (
            abs(
                center["yaw"]
            )
            > CENTER_YAW_LIMIT
        ):
            raise ValueError(
                "Start with your face centered "
                "and looking directly at the camera."
            )

        # ====================================================
        # BLINK
        # ====================================================

        blink_limit = (
            center[
                "eye_openness"
            ]
            * BLINK_RATIO
        )

        if (
            blink[
                "eye_openness"
            ]
            > blink_limit
        ):
            raise ValueError(
                "Blink was not detected. "
                "Close both eyes fully when requested."
            )

        # ====================================================
        # HEAD TURN
        # ====================================================

        turn_delta = abs(
            turned["yaw"]
            - center["yaw"]
        )

        if (
            turn_delta
            < TURN_YAW_DELTA
        ):
            raise ValueError(
                "Head turn was not detected. "
                "Turn your head clearly left or right."
            )

        # ====================================================
        # SMILE
        # ====================================================

        smile_limit = (
            center[
                "mouth_width"
            ]
            * SMILE_RATIO
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

        # ====================================================
        # RETURN CENTER
        # ====================================================

        if (
            abs(
                returned["yaw"]
            )
            > CENTER_YAW_LIMIT
        ):
            raise ValueError(
                "Return your face to the center "
                "before verification."
            )

        return_delta = abs(
            returned["yaw"]
            - center["yaw"]
        )

        if (
            return_delta
            > RETURN_YAW_DELTA
        ):
            raise ValueError(
                "Your face did not return "
                "to the original centered position."
            )

        # ====================================================
        # SUCCESS
        # ====================================================

        return jsonify({
            "success":
                True,

            "status":
                "LIVENESS_PASSED",

            "message":
                "Liveness verification passed.",

            "metrics": {
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
                    name:
                        round(
                            score,
                            4,
                        )
                    for name, score
                    in identity_scores.items()
                },
            },
        }), 200

    except ValueError as exc:
        print(
            "[LIVENESS REJECTED]",
            str(exc),
        )

        return jsonify({
            "success":
                False,

            "detail":
                str(exc),
        }), 422

    except Exception as exc:
        print(
            "[LIVENESS] Processing error:",
            exc,
        )

        return jsonify({
            "success":
                False,

            "detail":
                "Liveness processing failed.",
        }), 500


# ============================================================
# ERROR HANDLERS
# ============================================================

@app.errorhandler(
    413
)
def request_too_large(
    _error,
):
    return jsonify({
        "success":
            False,

        "detail":
            "Uploaded biometric data is too large.",
    }), 413


@app.errorhandler(
    404
)
def route_not_found(
    _error,
):
    return jsonify({
        "success":
            False,

        "detail":
            "Face verification endpoint not found.",
    }), 404


@app.errorhandler(
    405
)
def method_not_allowed(
    _error,
):
    return jsonify({
        "success":
            False,

        "detail":
            "HTTP method is not allowed for this endpoint.",
    }), 405


# ============================================================
# START SERVER
# ============================================================

if __name__ == "__main__":
    print("")
    print(
        "=========================================="
    )
    print(
        " CCIS Face Verification Service"
    )
    print(
        " MediaPipe + OpenCV + InsightFace"
    )
    print(
        " PRODUCTION ACCURACY PROFILE"
    )
    print(
        "=========================================="
    )

    print(
        f" MIN_BLUR_SCORE: "
        f"{MIN_BLUR_SCORE}"
    )

    print(
        f" MIN_LIVENESS_BLUR_SCORE: "
        f"{MIN_LIVENESS_BLUR_SCORE}"
    )

    print(
        f" MIN_DETECTION_SCORE: "
        f"{MIN_DETECTION_SCORE}"
    )

    print(
        f" LIVENESS_IDENTITY_THRESHOLD: "
        f"{LIVENESS_IDENTITY_THRESHOLD}"
    )

    print(
        f" CENTER_YAW_LIMIT: "
        f"{CENTER_YAW_LIMIT}"
    )

    print(
        f" TURN_YAW_DELTA: "
        f"{TURN_YAW_DELTA}"
    )

    print(
        f" RETURN_YAW_DELTA: "
        f"{RETURN_YAW_DELTA}"
    )

    print(
        f" BLINK_RATIO: "
        f"{BLINK_RATIO}"
    )

    print(
        f" SMILE_RATIO: "
        f"{SMILE_RATIO}"
    )

    print(
        "=========================================="
    )

    print(
        " Server: http://127.0.0.1:5000"
    )

    print(
        "=========================================="
    )

    app.run(
        host="127.0.0.1",
        port=5000,
        debug=True,
        use_reloader=False,
        threaded=False,
    )