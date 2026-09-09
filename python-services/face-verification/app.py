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

app.config["MAX_CONTENT_LENGTH"] = 25 * 1024 * 1024


# ============================================================
# CONFIGURATION
# ============================================================

# Reference-photo quality.
MIN_BLUR_SCORE = 30.0

# Live camera frames can naturally be softer.
MIN_LIVENESS_BLUR_SCORE = 12.0

MIN_DETECTION_SCORE = 0.60

# Makes sure every liveness frame belongs to the same person.
LIVENESS_IDENTITY_THRESHOLD = 0.45

# Face approximately centered.
CENTER_YAW_LIMIT = 0.08

# Required movement when turning head.
TURN_YAW_DELTA = 0.06

# Returned face should be close to original center.
RETURN_YAW_DELTA = 0.06

# Blink must significantly reduce eye openness.
BLINK_RATIO = 0.88

# Smile should widen the mouth compared with neutral frame.
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

def base64_to_cv2(b64_str: str):
    if not isinstance(b64_str, str) or not b64_str.strip():
        raise ValueError("Image data is empty.")

    if "," in b64_str:
        b64_str = b64_str.split(",", 1)[1]

    try:
        img_bytes = base64.b64decode(
            b64_str,
            validate=True,
        )
    except (ValueError, binascii.Error) as exc:
        raise ValueError(
            "Invalid base64 image data."
        ) from exc

    if not img_bytes:
        raise ValueError(
            "Decoded image is empty."
        )

    nparr = np.frombuffer(
        img_bytes,
        dtype=np.uint8,
    )

    image = cv2.imdecode(
        nparr,
        cv2.IMREAD_COLOR,
    )

    if image is None:
        raise ValueError(
            "Unable to decode the supplied image."
        )

    return image


def calculate_face_blur(image, face) -> float:
    bbox = face.bbox.astype(int)

    x1, y1, x2, y2 = bbox

    height, width = image.shape[:2]

    face_width = x2 - x1
    face_height = y2 - y1

    margin_x = int(face_width * 0.08)
    margin_y = int(face_height * 0.08)

    x1 = max(0, x1 - margin_x)
    y1 = max(0, y1 - margin_y)

    x2 = min(width, x2 + margin_x)
    y2 = min(height, y2 + margin_y)

    face_crop = image[y1:y2, x1:x2]

    if face_crop.size == 0:
        return 0.0

    gray = cv2.cvtColor(
        face_crop,
        cv2.COLOR_BGR2GRAY,
    )

    gray = cv2.equalizeHist(gray)

    blur_score = cv2.Laplacian(
        gray,
        cv2.CV_64F,
    ).var()

    return float(blur_score)


def normalize_embedding(embedding):
    embedding = np.asarray(
        embedding,
        dtype=np.float32,
    )

    norm = np.linalg.norm(embedding)

    if norm <= 0:
        raise ValueError(
            "Invalid facial feature vector generated."
        )

    return embedding / norm


def cosine_similarity(vec_a, vec_b) -> float:
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

    norm_a = np.linalg.norm(a)
    norm_b = np.linalg.norm(b)

    if norm_a <= 0 or norm_b <= 0:
        return 0.0

    return float(
        np.dot(a, b)
        / (norm_a * norm_b)
    )


def distance(point_a, point_b) -> float:
    return math.sqrt(
        (point_a.x - point_b.x) ** 2
        + (point_a.y - point_b.y) ** 2
    )


# ============================================================
# MEDIAPIPE METRICS
# ============================================================

def eye_openness(landmarks) -> float:
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


def yaw_proxy(landmarks) -> float:
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


def mouth_width_ratio(landmarks) -> float:
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

    return mouth_width / face_width


# ============================================================
# LIVENESS FRAME ANALYSIS
# ============================================================

def analyze_liveness_frame(
    image_base64: str,
    frame_name: str,
):
    image = base64_to_cv2(
        image_base64
    )

    # --------------------------------------------------------
    # InsightFace
    # --------------------------------------------------------

    faces = face_analyzer.get(
        image
    )

    if len(faces) == 0:
        raise ValueError(
            f"No face detected in {frame_name} frame."
        )

    if len(faces) > 1:
        raise ValueError(
            f"Multiple faces detected in {frame_name} frame."
        )

    face = faces[0]

    detection_score = float(
        getattr(
            face,
            "det_score",
            0.0,
        )
    )

    if detection_score < MIN_DETECTION_SCORE:
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
    # MediaPipe
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

    if len(detected_faces) == 0:
        raise ValueError(
            f"MediaPipe could not detect a face in {frame_name} frame."
        )

    if len(detected_faces) > 1:
        raise ValueError(
            f"MediaPipe detected multiple faces in {frame_name} frame."
        )

    landmarks = (
        detected_faces[0]
        .landmark
    )

    return {
        "embedding": embedding,
        "yaw": yaw_proxy(
            landmarks
        ),
        "eye_openness": eye_openness(
            landmarks
        ),
        "mouth_width": mouth_width_ratio(
            landmarks
        ),
        "blur_score": blur_score,
        "detection_score": detection_score,
    }


# ============================================================
# HEALTH
# ============================================================

@app.get("/health")
def health():
    return jsonify({
        "success": True,
        "service":
            "CCIS Face Verification",
        "mediapipe": "ready",
        "insightface": "ready",
        "opencv": "ready",
        "blur_threshold":
            MIN_BLUR_SCORE,
        "liveness_blur_threshold":
            MIN_LIVENESS_BLUR_SCORE,
        "detection_threshold":
            MIN_DETECTION_SCORE,
    }), 200


# ============================================================
# EXTRACT EMBEDDING
# ============================================================

@app.post("/extract-embedding")
def extract_embedding():
    data = request.get_json(
        silent=True
    )

    if not data:
        return jsonify({
            "success": False,
            "detail":
                "Invalid or missing JSON request body.",
        }), 400

    image_base64 = data.get(
        "image_base64"
    )

    if not image_base64:
        return jsonify({
            "success": False,
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

        faces = face_analyzer.get(
            image
        )

        if len(faces) == 0:
            return jsonify({
                "success": False,
                "detail":
                    "No face detected in image. "
                    "Ensure your face is visible and the area is well lit.",
            }), 400

        if len(faces) > 1:
            return jsonify({
                "success": False,
                "detail":
                    "Multiple faces detected. "
                    "Only one face is allowed per frame.",
            }), 400

        primary_face = faces[0]

        detection_score = float(
            getattr(
                primary_face,
                "det_score",
                0.0,
            )
        )

        if (
            detection_score
            < MIN_DETECTION_SCORE
        ):
            return jsonify({
                "success": False,
                "detail":
                    "Face visibility is too low. "
                    "Face the camera directly and improve the lighting.",
            }), 400

        blur_score = calculate_face_blur(
            image,
            primary_face,
        )

        if blur_score < MIN_BLUR_SCORE:
            return jsonify({
                "success": False,
                "detail":
                    "Image is too blurry. "
                    "Hold the camera steady and try again.",
            }), 400

        raw_embedding = getattr(
            primary_face,
            "embedding",
            None,
        )

        if raw_embedding is None:
            return jsonify({
                "success": False,
                "detail":
                    "InsightFace could not generate a facial embedding.",
            }), 400

        normalized_embedding = (
            normalize_embedding(
                raw_embedding
            ).tolist()
        )

        bbox = (
            primary_face
            .bbox
            .astype(int)
            .tolist()
        )

        return jsonify({
            "success": True,
            "status": "success",
            "embedding":
                normalized_embedding,
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
                "image_width":
                    width,
                "image_height":
                    height,
                "face_bbox":
                    bbox,
            },
        }), 200

    except ValueError as exc:
        return jsonify({
            "success": False,
            "detail": str(exc),
        }), 400

    except Exception as exc:
        print(
            f"[FACE] Processing error: {exc}"
        )

        return jsonify({
            "success": False,
            "detail":
                "Biometric processing failed.",
        }), 500


# ============================================================
# VERIFY LIVENESS
# ============================================================

@app.post("/verify-liveness")
def verify_liveness():
    data = request.get_json(
        silent=True
    )

    if not data:
        return jsonify({
            "success": False,
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
        if not data.get(key):
            return jsonify({
                "success": False,
                "detail":
                    f"Missing {key}.",
            }), 400

    try:
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

        # ----------------------------------------------------
        # Same person in every challenge frame
        # ----------------------------------------------------

        reference_embedding = (
            center["embedding"]
        )

        for frame_name, frame in [
            ("blink", blink),
            ("turned", turned),
            ("smile", smile),
            ("returned", returned),
        ]:
            similarity = cosine_similarity(
                reference_embedding,
                frame["embedding"],
            )

            if (
                similarity
                < LIVENESS_IDENTITY_THRESHOLD
            ):
                raise ValueError(
                    "The same person must remain "
                    "in front of the camera during "
                    f"the entire liveness check ({frame_name})."
                )

        # ----------------------------------------------------
        # Center
        # ----------------------------------------------------

        if (
            abs(center["yaw"])
            > CENTER_YAW_LIMIT
        ):
            raise ValueError(
                "Start with your face centered "
                "and looking directly at the camera."
            )

        # ----------------------------------------------------
        # Blink
        # ----------------------------------------------------

        if (
            blink["eye_openness"]
            >
            center["eye_openness"]
            * BLINK_RATIO
        ):
            raise ValueError(
                "Blink was not detected. "
                "Close both eyes fully when requested."
            )

        # ----------------------------------------------------
        # Head turn
        # ----------------------------------------------------

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

        # ----------------------------------------------------
        # Smile
        # ----------------------------------------------------

        if (
            smile["mouth_width"]
            <
            center["mouth_width"]
            * SMILE_RATIO
        ):
            raise ValueError(
                "Smile was not detected. "
                "Smile clearly when requested."
            )

        # ----------------------------------------------------
        # Return to center
        # ----------------------------------------------------

        if (
            abs(returned["yaw"])
            > CENTER_YAW_LIMIT
        ):
            raise ValueError(
                "Return your face to the center "
                "before verification."
            )

        if (
            abs(
                returned["yaw"]
                - center["yaw"]
            )
            > RETURN_YAW_DELTA
        ):
            raise ValueError(
                "Your face did not return "
                "to the original centered position."
            )

        return jsonify({
            "success": True,
            "status":
                "LIVENESS_PASSED",
            "message":
                "Liveness verification passed.",
            "metrics": {
                "center_yaw":
                    round(
                        center["yaw"],
                        4,
                    ),
                "turned_yaw":
                    round(
                        turned["yaw"],
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
            },
        }), 200

    except ValueError as exc:
        return jsonify({
            "success": False,
            "detail": str(exc),
        }), 422

    except Exception as exc:
        print(
            f"[LIVENESS] Processing error: {exc}"
        )

        return jsonify({
            "success": False,
            "detail":
                "Liveness processing failed.",
        }), 500

@app.post("/analyze-liveness-frame")
def analyze_liveness_frame_endpoint():
    data = request.get_json(
        silent=True
    )

    if not data:
        return jsonify({
            "success": False,
            "detail":
                "Invalid request body.",
        }), 400

    image_base64 = data.get(
        "image_base64"
    )

    if not image_base64:
        return jsonify({
            "success": False,
            "detail":
                "Missing image_base64.",
        }), 400

    try:
        frame = analyze_liveness_frame(
            image_base64,
            "live",
        )

        return jsonify({
            "success": True,

            "face_detected": True,

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
        return jsonify({
            "success": False,
            "face_detected": False,
            "detail": str(exc),
        }), 422

    except Exception as exc:
        print(
            "[LIVE FRAME ERROR]",
            exc,
        )

        return jsonify({
            "success": False,
            "face_detected": False,
            "detail":
                "Unable to analyze live frame.",
        }), 500

# ============================================================
# RUN
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
    )