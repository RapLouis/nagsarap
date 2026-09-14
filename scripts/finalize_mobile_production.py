from pathlib import Path
import shutil
import sys


ROOT = Path(__file__).resolve().parents[1]


REGISTRATION_SCREEN = (
    ROOT
    / "mobile_app"
    / "lib"
    / "screens"
    / "auth"
    / "registration_face_verification_screen.dart"
)

ATTENDANCE_SCREEN = (
    ROOT
    / "mobile_app"
    / "lib"
    / "screens"
    / "attendance"
    / "attendance_face_verification_screen.dart"
)

ATTENDANCE_SERVICE = (
    ROOT
    / "mobile_app"
    / "lib"
    / "services"
    / "attendance_service.dart"
)

API_CONFIG = (
    ROOT
    / "mobile_app"
    / "lib"
    / "core"
    / "api_config.dart"
)

API_ROUTES = ROOT / "routes" / "api.php"

PYTHON_APP = (
    ROOT
    / "python-services"
    / "face-verification"
    / "app.py"
)

SERVICES_CONFIG = ROOT / "config" / "services.php"


def require_file(path: Path) -> None:
    if not path.exists():
        raise RuntimeError(
            f"Required file was not found:\n{path}"
        )


def backup(path: Path) -> None:
    backup_path = path.with_name(
        f"{path.name}.pre-production.bak"
    )

    if not backup_path.exists():
        shutil.copy2(
            path,
            backup_path,
        )

        print(
            f"[BACKUP] {backup_path}"
        )


def replace_exact(
    path: Path,
    old: str,
    new: str,
    description: str,
) -> None:
    text = path.read_text(
        encoding="utf-8"
    )

    count = text.count(old)

    if count != 1:
        raise RuntimeError(
            "\n"
            f"Unable to safely apply: {description}\n"
            f"File: {path}\n"
            f"Expected exactly 1 match, found {count}.\n"
            "No blind replacement was performed."
        )

    text = text.replace(
        old,
        new,
        1,
    )

    path.write_text(
        text,
        encoding="utf-8",
    )

    print(
        f"[UPDATED] {description}"
    )


def write_whole_file(
    path: Path,
    content: str,
    description: str,
) -> None:
    backup(path)

    path.write_text(
        content,
        encoding="utf-8",
    )

    print(
        f"[UPDATED] {description}"
    )


def verify_contains(
    path: Path,
    expected: str,
    description: str,
) -> None:
    text = path.read_text(
        encoding="utf-8"
    )

    if expected not in text:
        raise RuntimeError(
            "\n"
            f"Verification failed: {description}\n"
            f"File: {path}\n"
            f"Missing:\n{expected}"
        )

    print(
        f"[OK] {description}"
    )


def verify_not_contains(
    path: Path,
    forbidden: str,
    description: str,
) -> None:
    text = path.read_text(
        encoding="utf-8"
    )

    if forbidden in text:
        raise RuntimeError(
            "\n"
            f"Verification failed: {description}\n"
            f"File: {path}\n"
            f"Still contains:\n{forbidden}"
        )

    print(
        f"[OK] {description}"
    )


def main() -> None:
    files = [
        REGISTRATION_SCREEN,
        ATTENDANCE_SCREEN,
        ATTENDANCE_SERVICE,
        API_CONFIG,
        API_ROUTES,
        PYTHON_APP,
        SERVICES_CONFIG,
    ]

    for path in files:
        require_file(path)

    print("")
    print(
        "=========================================="
    )
    print(
        " CCIS PRODUCTION FINALIZER"
    )
    print(
        "=========================================="
    )
    print("")

    # ==========================================================
    # VERIFY SERVER BIOMETRICS BEFORE CHANGING MOBILE
    # ==========================================================

    python_source = PYTHON_APP.read_text(
        encoding="utf-8"
    )

    strict_python_values = [
        "MIN_BLUR_SCORE = 30.0",
        "MIN_LIVENESS_BLUR_SCORE = 12.0",
        "MIN_DETECTION_SCORE = 0.60",
        "LIVENESS_IDENTITY_THRESHOLD = 0.45",
        "CENTER_YAW_LIMIT = 0.08",
        "TURN_YAW_DELTA = 0.06",
        "RETURN_YAW_DELTA = 0.06",
        "BLINK_RATIO = 0.72",
        "SMILE_RATIO = 1.04",
    ]

    for setting in strict_python_values:
        if setting not in python_source:
            raise RuntimeError(
                "\n"
                "Python biometric profile is not the "
                "expected strict profile.\n"
                f"Missing: {setting}\n"
                "Stopping before changing Flutter."
            )

    print(
        "[OK] Python strict biometric profile preserved."
    )

    services_source = SERVICES_CONFIG.read_text(
        encoding="utf-8"
    )

    if (
        "'match_threshold' => (float) "
        "env('FACE_MATCH_THRESHOLD', 0.60)"
        not in services_source
    ):
        raise RuntimeError(
            "Expected FACE_MATCH_THRESHOLD 0.60 "
            "was not found."
        )

    if (
        "'enrollment_threshold' => (float) "
        "env('FACE_ENROLLMENT_THRESHOLD', 0.50)"
        not in services_source
    ):
        raise RuntimeError(
            "Expected FACE_ENROLLMENT_THRESHOLD 0.50 "
            "was not found."
        )

    print(
        "[OK] Laravel face-match thresholds preserved."
    )

    # ==========================================================
    # BACKUPS
    # ==========================================================

    backup(REGISTRATION_SCREEN)
    backup(ATTENDANCE_SCREEN)
    backup(ATTENDANCE_SERVICE)
    backup(API_ROUTES)

    # ==========================================================
    # REGISTRATION LIVENESS
    # ==========================================================

    replace_exact(
        REGISTRATION_SCREEN,
        "static const double blinkRatio = 0.88;",
        "static const double blinkRatio = 0.72;",
        "Registration blink threshold aligned with Python",
    )

    replace_exact(
        REGISTRATION_SCREEN,
        (
            "static const Duration normalCaptureInterval "
            "= Duration(milliseconds: 250);"
        ),
        (
            "static const Duration normalCaptureInterval "
            "= Duration(milliseconds: 450);"
        ),
        "Registration normal capture interval",
    )

    replace_exact(
        REGISTRATION_SCREEN,
        (
            "static const Duration blinkCaptureInterval "
            "= Duration(milliseconds: 80);"
        ),
        (
            "static const Duration blinkCaptureInterval "
            "= Duration(milliseconds: 160);"
        ),
        "Registration blink capture interval",
    )

    replace_exact(
        REGISTRATION_SCREEN,
        """Transform.scale(
                      scaleX: -1,
                      child: CameraPreview(controller),
                    ),""",
        """CameraPreview(controller),""",
        "Registration camera preview orientation",
    )

    # ==========================================================
    # ATTENDANCE LIVENESS
    # ==========================================================

    replace_exact(
        ATTENDANCE_SCREEN,
        "static const double blinkRatio = 0.88;",
        "static const double blinkRatio = 0.72;",
        "Attendance blink threshold aligned with Python",
    )

    replace_exact(
        ATTENDANCE_SCREEN,
        (
            "static const Duration normalCaptureInterval "
            "= Duration(milliseconds: 250);"
        ),
        (
            "static const Duration normalCaptureInterval "
            "= Duration(milliseconds: 450);"
        ),
        "Attendance normal capture interval",
    )

    replace_exact(
        ATTENDANCE_SCREEN,
        (
            "static const Duration blinkCaptureInterval "
            "= Duration(milliseconds: 80);"
        ),
        (
            "static const Duration blinkCaptureInterval "
            "= Duration(milliseconds: 160);"
        ),
        "Attendance blink capture interval",
    )

    replace_exact(
        ATTENDANCE_SCREEN,
        (
            "Transform.scale("
            "scaleX: -1, "
            "child: CameraPreview(camera)"
            ")"
        ),
        "CameraPreview(camera)",
        "Attendance camera preview orientation",
    )

    # ==========================================================
    # OFFLINE CANDIDATE SELECTION
    #
    # Keep offline candidate selection aligned with the same
    # strict Python profile instead of the temporary testing
    # profile.
    # ==========================================================

    replace_exact(
        ATTENDANCE_SERVICE,
        """  // Temporary offline-testing candidate-selection values.
  //
  // Final liveness verification is still performed by Laravel/Python.
  //
  // IMPORTANT:
  // Restore stricter production biometric settings during final hardening.
  static const double _centerLimit = 0.13;
  static const double _blinkRatio = 0.82;
  static const double _turnDelta = 0.04;
  static const double _smileRatio = 1.025;""",
        """  // Production candidate-selection values.
  //
  // These intentionally match the authoritative Python
  // liveness profile. Flutter only selects suitable evidence;
  // Laravel/Python still performs the final verification.
  static const double _centerLimit = 0.08;
  static const double _blinkRatio = 0.72;
  static const double _turnDelta = 0.06;
  static const double _smileRatio = 1.04;""",
        "Offline biometric candidate thresholds",
    )

    # ==========================================================
    # API CONFIG
    #
    # Development default remains emulator-safe.
    #
    # Production APK receives its public HTTPS URL using:
    #
    # --dart-define=API_BASE_URL=https://api.example.com
    # ==========================================================

    api_config_code = """class ApiConfig {
  ApiConfig._();

  /// Development default:
  /// Android Emulator -> Laravel running on the Mac.
  ///
  /// Production:
  /// Build the APK with:
  ///
  /// flutter build apk --release \\
  ///   --dart-define=API_BASE_URL=https://api.yourdomain.com
  ///
  /// The production URL must be public HTTPS.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const Duration connectTimeout =
      Duration(seconds: 20);

  static const Duration sendTimeout =
      Duration(seconds: 120);

  static const Duration receiveTimeout =
      Duration(seconds: 120);
}
"""

    write_whole_file(
        API_CONFIG,
        api_config_code,
        "Production-capable API configuration",
    )

    # ==========================================================
    # ROUTES
    #
    # Liveness frame analysis is intentionally more permissive
    # in request RATE, not biometric QUALITY.
    #
    # One authenticated user may send many short frame-analysis
    # requests during one challenge.
    #
    # Final verification/check-in remains separately limited.
    # ==========================================================

    routes_code = r"""<?php

use ​:contentReference[oaicite:7]{index=7}​