import { Head, router } from '@inertiajs/react';
import type { FaceLandmarker } from '@mediapipe/tasks-vision';
import {
    AlertCircle,
    ArrowLeft,
    ArrowRight,
    CheckCircle2,
    Eye,
    Loader2,
    RefreshCw,
    Scan,
    ShieldAlert,
    ShieldCheck,
    Sparkles,
} from 'lucide-react';
import { useEffect, useRef, useState } from 'react';

/* -------------------------------------------------------------------------- */
/* Types                                                                      */
/* -------------------------------------------------------------------------- */

type StudentProps = {
    student_id: number;
    firstname: string;
    surname: string;
};

type Direction = 'left' | 'right';

type Props = {
    student: StudentProps;
    /**
     * Optional server-issued challenge. Once the Laravel challenge endpoint
     * exists, pass { nonce, direction } from the controller and this page will
     * use it. Until then a random direction is picked in the browser.
     */
    challenge?: { nonce: string; direction: Direction };
};

type LivenessStep = 'DETECT' | 'LOOK_CENTER' | 'TURN' | 'VERIFYING' | 'PASSED';
type DisplayStep = LivenessStep | 'LOADING';

type Landmark = { x: number; y: number };

/* -------------------------------------------------------------------------- */
/* Configuration                                                              */
/* -------------------------------------------------------------------------- */

// IMPORTANT: keep this equal to the installed @mediapipe/tasks-vision version
// (run `npm ls @mediapipe/tasks-vision`). A JS/WASM version mismatch causes
// odd failures. For best mobile performance, self-host these files instead.
const MEDIAPIPE_VERSION = '0.10.21';
const WASM_URL = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MEDIAPIPE_VERSION}/wasm`;
const MODEL_URL =
    'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task';

const VIDEO_CONSTRAINTS: MediaStreamConstraints = {
    video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: 'user' },
    audio: false,
};

// Run detection on every Nth animation frame (saves battery on phones).
const PROCESS_EVERY_N_FRAMES = 3;

// Yaw is a nose-to-cheek ratio in [-1, 1]; 0 means facing the camera.
const FRONTAL_YAW_MAX = 0.12; // "looking straight" while capturing the frontal frame
const FRONTAL_HOLD_FRAMES = 8; // processed frames held still (~0.8s on most phones)
const MID_TURN_YAW = 0.15; // capture a mid-turn frame here
const TURN_YAW_MIN = 0.25; // turn needed to pass
const TURN_HOLD_FRAMES = 3; // consecutive processed frames past the threshold
const WRONG_WAY_YAW = 0.15; // turned the opposite way from the request
const CHALLENGE_TIMEOUT_MS = 20_000; // time allowed for the turn

// Face size and position, as a fraction of the video frame.
const MIN_FACE_WIDTH = 0.22;
const MAX_FACE_WIDTH = 0.6;
const MAX_CENTER_OFFSET_X = 0.12;
const MAX_CENTER_OFFSET_Y = 0.15;

const JPEG_QUALITY = 0.70;

/**
 * Sign of the yaw value when the person turns toward each direction, seen from
 * the person's own point of view. The camera image is unmirrored, so turning to
 * your left gives a positive yaw. TEST THIS on iOS Safari and Android Chrome.
 * If "left" and "right" feel swapped, flip both signs here and nowhere else.
 */
const DIRECTION_SIGN: Record<Direction, 1 | -1> = { left: 1, right: -1 };

const NOSE_TIP = 1;
const LEFT_CHEEK = 234;
const RIGHT_CHEEK = 454;

/* -------------------------------------------------------------------------- */
/* Helpers                                                                    */
/* -------------------------------------------------------------------------- */

function calculateYaw(landmarks: Landmark[]): number {
    const nose = landmarks[NOSE_TIP];
    const left = landmarks[LEFT_CHEEK];
    const right = landmarks[RIGHT_CHEEK];
    if (!nose || !left || !right) return 0;

    const distanceLeft = Math.abs(nose.x - left.x);
    const distanceRight = Math.abs(nose.x - right.x);
    const total = distanceLeft + distanceRight;

    return total === 0 ? 0 : (distanceLeft - distanceRight) / total;
}

function getFaceBounds(landmarks: Landmark[]) {
    let minX = 1;
    let maxX = 0;
    let minY = 1;
    let maxY = 0;

    for (const point of landmarks) {
        if (point.x < minX) minX = point.x;
        if (point.x > maxX) maxX = point.x;
        if (point.y < minY) minY = point.y;
        if (point.y > maxY) maxY = point.y;
    }

    return {
        width: maxX - minX,
        centerX: (minX + maxX) / 2,
        centerY: (minY + maxY) / 2,
    };
}

/** Returns a hint if the face is badly placed, or null if it is fine. */
function getPlacementIssue(landmarks: Landmark[]): string | null {
    const { width, centerX, centerY } = getFaceBounds(landmarks);

    if (width < MIN_FACE_WIDTH) return 'Move closer to the camera.';
    if (width > MAX_FACE_WIDTH) return 'Move a little further from the camera.';
    if (
        Math.abs(centerX - 0.5) > MAX_CENTER_OFFSET_X ||
        Math.abs(centerY - 0.5) > MAX_CENTER_OFFSET_Y
    ) {
        return 'Center your face in the circle.';
    }
    return null;
}

/** Captures the current video frame (unmirrored) as a JPEG blob. */
function captureFrame(video: HTMLVideoElement): Promise<Blob | null> {
    const canvas = document.createElement('canvas');
    // Cap dimensions to max 640x480 to keep mobile payloads tiny
    const width = Math.min(video.videoWidth || 640, 640);
    const height = Math.min(video.videoHeight || 480, 480);
    
    canvas.width = width;
    canvas.height = height;

    const context = canvas.getContext('2d');
    if (!context) return Promise.resolve(null);

    context.drawImage(video, 0, 0, width, height);

    return new Promise((resolve) => {
        canvas.toBlob((blob) => resolve(blob), 'image/jpeg', 0.70);
    });
}

function randomDirection(): Direction {
    const bytes = new Uint8Array(1);
    crypto.getRandomValues(bytes);
    return bytes[0] % 2 === 0 ? 'left' : 'right';
}

function describeCameraError(error: unknown): string {
    const name = (error as { name?: string })?.name;

    if (name === 'NotAllowedError' || name === 'SecurityError') {
        return 'Camera access was blocked. Allow camera permission in your browser settings, then reload the page.';
    }
    if (name === 'NotFoundError' || name === 'OverconstrainedError') {
        return 'No front camera was found on this device.';
    }
    if (name === 'NotReadableError') {
        return 'The camera is being used by another app. Close it and reload the page.';
    }
    if (error instanceof Error && error.message) return error.message;
    return 'Unable to access the camera.';
}

async function createLandmarker(): Promise<FaceLandmarker> {
    const { FaceLandmarker, FilesetResolver } = await import('@mediapipe/tasks-vision');
    const vision = await FilesetResolver.forVisionTasks(WASM_URL);

    const create = (delegate: 'GPU' | 'CPU') =>
        FaceLandmarker.createFromOptions(vision, {
            baseOptions: { modelAssetPath: MODEL_URL, delegate },
            runningMode: 'VIDEO',
            // 2 so we can actually detect (and reject) a second face in view.
            numFaces: 2,
            minFaceDetectionConfidence: 0.5,
            minFacePresenceConfidence: 0.5,
            minTrackingConfidence: 0.5,
        });

    try {
        return await create('GPU');
    } catch (error) {
        console.warn('GPU delegate failed, falling back to CPU:', error);
        return await create('CPU');
    }
}

/* -------------------------------------------------------------------------- */
/* Component                                                                  */
/* -------------------------------------------------------------------------- */

export default function VerifyFace({ student, challenge: serverChallenge }: Props) {
    const videoRef = useRef<HTMLVideoElement | null>(null);
    const landmarkerRef = useRef<FaceLandmarker | null>(null);
    const requestRef = useRef<number | null>(null);
    const mountedRef = useRef(true);

    // Liveness state kept in refs so the detection loop never restarts on a step change.
    const stepRef = useRef<LivenessStep>('DETECT');
    const frameCountRef = useRef(0);
    const lastVideoTimeRef = useRef(-1);
    const holdCountRef = useRef(0);
    const turnHoldRef = useRef(0);
    const challengeStartRef = useRef<number | null>(null);
    const hasSubmittedRef = useRef(false);

    // Captured frames (promises, so capturing never blocks the loop).
    const frontalFrameRef = useRef<Promise<Blob | null> | null>(null);
    const midFrameRef = useRef<Promise<Blob | null> | null>(null);
    const peakFrameRef = useRef<Promise<Blob | null> | null>(null);

    const [step, setStep] = useState<LivenessStep>('DETECT');
    const [streamStarted, setStreamStarted] = useState(false);
    const [modelReady, setModelReady] = useState(false);
    const [cameraError, setCameraError] = useState<string | null>(null);
    const [modalError, setModalError] = useState<string | null>(null);
    const [hint, setHint] = useState<string | null>(null);
    const [holdProgress, setHoldProgress] = useState(0);
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [localDirection, setLocalDirection] = useState<Direction>(randomDirection);

    const challenge = serverChallenge ?? { nonce: null, direction: localDirection };
    const challengeRef = useRef(challenge);
    challengeRef.current = challenge;

    const isReady = streamStarted && modelReady;
    const isLoading = !isReady && !cameraError && step !== 'VERIFYING' && step !== 'PASSED';
    const displayStep: DisplayStep = isLoading ? 'LOADING' : step;

    const goToStep = (next: LivenessStep) => {
        if (stepRef.current === next) return;
        stepRef.current = next;
        setStep(next);
    };

    const resetChallenge = () => {
        holdCountRef.current = 0;
        turnHoldRef.current = 0;
        challengeStartRef.current = null;
        frontalFrameRef.current = null;
        midFrameRef.current = null;
        peakFrameRef.current = null;
        setHoldProgress(0);
        goToStep('DETECT');
    };

    /* ----------------------------- Camera control ---------------------------- */

    const stopCameraStream = () => {
        if (requestRef.current !== null) {
            cancelAnimationFrame(requestRef.current);
            requestRef.current = null;
        }

        const video = videoRef.current;
        if (video?.srcObject) {
            (video.srcObject as MediaStream).getTracks().forEach((track) => track.stop());
            video.srcObject = null;
        }

        setStreamStarted(false);
    };

    const startCameraStream = async () => {
        if (!navigator.mediaDevices?.getUserMedia) {
            throw new Error('Camera access is not supported by this browser.');
        }

        const stream = await navigator.mediaDevices.getUserMedia(VIDEO_CONSTRAINTS);

        if (!mountedRef.current || !videoRef.current) {
            stream.getTracks().forEach((track) => track.stop());
            return;
        }

        videoRef.current.srcObject = stream;
        await videoRef.current.play().catch(() => {});
        lastVideoTimeRef.current = -1;
        setStreamStarted(true);
    };

    /* ------------------------------ Initialization --------------------------- */

    useEffect(() => {
        mountedRef.current = true;

        async function initialize() {
            // Start loading the model and the camera in parallel.
            const landmarkerPromise = createLandmarker();
            landmarkerPromise.catch(() => {}); // handled below; avoids an unhandled rejection

            try {
                await startCameraStream();
            } catch (error) {
                console.error('Camera error:', error);
                if (mountedRef.current) setCameraError(describeCameraError(error));
                return;
            }

            try {
                const landmarker = await landmarkerPromise;

                if (!mountedRef.current) {
                    landmarker.close();
                    return;
                }

                landmarkerRef.current = landmarker;
                setModelReady(true);
            } catch (error) {
                console.error('Face detection init error:', error);
                if (mountedRef.current) {
                    setCameraError('Unable to load face detection. Check your connection and reload the page.');
                }
            }
        }

        initialize();

        return () => {
            mountedRef.current = false;
            stopCameraStream();
            landmarkerRef.current?.close();
            landmarkerRef.current = null;
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    /* ------------------------------ Detection loop --------------------------- */

    useEffect(() => {
        if (!isReady || modalError !== null) return;

        let stopped = false;

        const processFrame = () => {
            const video = videoRef.current;
            const landmarker = landmarkerRef.current;
            if (!video || !landmarker || video.readyState < 2) return;

            // Skip if the camera hasn't produced a new frame yet.
            if (video.currentTime === lastVideoTimeRef.current) return;
            lastVideoTimeRef.current = video.currentTime;

            let faces: Landmark[][];
            try {
                faces = landmarker.detectForVideo(video, performance.now()).faceLandmarks ?? [];
            } catch (error) {
                console.error('Face detection error:', error);
                return;
            }

            if (faces.length === 0) {
                setHint(null);
                resetChallenge();
                return;
            }

            if (faces.length > 1) {
                setHint('Only one face should be visible in the camera.');
                resetChallenge();
                return;
            }

            const landmarks = faces[0];
            const yaw = calculateYaw(landmarks);
            const { direction } = challengeRef.current;
            const turned = yaw * DIRECTION_SIGN[direction]; // positive = toward the requested side

            switch (stepRef.current) {
                case 'DETECT': {
                    goToStep('LOOK_CENTER');
                    break;
                }

                case 'LOOK_CENTER': {
                    const placementIssue = getPlacementIssue(landmarks);

                    if (placementIssue) {
                        holdCountRef.current = 0;
                        setHoldProgress(0);
                        setHint(placementIssue);
                        break;
                    }

                    if (Math.abs(yaw) > FRONTAL_YAW_MAX) {
                        holdCountRef.current = 0;
                        setHoldProgress(0);
                        setHint('Look straight at the camera.');
                        break;
                    }

                    setHint(null);
                    holdCountRef.current += 1;
                    setHoldProgress(Math.min(holdCountRef.current / FRONTAL_HOLD_FRAMES, 1));

                    if (holdCountRef.current >= FRONTAL_HOLD_FRAMES) {
                        // Best-quality frontal frame: this is the one matched against the profile photo.
                        frontalFrameRef.current = captureFrame(video);
                        challengeStartRef.current = performance.now();
                        turnHoldRef.current = 0;
                        goToStep('TURN');
                    }
                    break;
                }

                case 'TURN': {
                    const startedAt = challengeStartRef.current ?? performance.now();

                    if (performance.now() - startedAt > CHALLENGE_TIMEOUT_MS) {
                        resetChallenge();
                        setHint('Time ran out. Let\u2019s try again.');
                        break;
                    }

                    if (turned <= -WRONG_WAY_YAW) {
                        turnHoldRef.current = 0;
                        setHint(`Turn to your ${direction}, not the other way.`);
                        break;
                    }

                    setHint(null);

                    if (!midFrameRef.current && turned >= MID_TURN_YAW) {
                        midFrameRef.current = captureFrame(video);
                    }

                    if (turned >= TURN_YAW_MIN) {
                        turnHoldRef.current += 1;

                        if (turnHoldRef.current >= TURN_HOLD_FRAMES) {
                            peakFrameRef.current = captureFrame(video);
                            void submitChallenge();
                            return;
                        }
                    } else {
                        turnHoldRef.current = 0;
                    }
                    break;
                }
            }
        };

        const tick = () => {
            if (stopped) return;

            const current = stepRef.current;
            if (current === 'VERIFYING' || current === 'PASSED') return;

            frameCountRef.current += 1;
            if (frameCountRef.current % PROCESS_EVERY_N_FRAMES === 0) processFrame();

            // processFrame may have moved to VERIFYING; don't schedule another frame then.
            if (stepRef.current === 'VERIFYING') return;
            requestRef.current = requestAnimationFrame(tick);
        };

        requestRef.current = requestAnimationFrame(tick);

        return () => {
            stopped = true;
            if (requestRef.current !== null) {
                cancelAnimationFrame(requestRef.current);
                requestRef.current = null;
            }
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [isReady, modalError]);

    /* -------------------------------- Submission ----------------------------- */

    const submitChallenge = async () => {
        if (hasSubmittedRef.current) return;
        hasSubmittedRef.current = true;
        goToStep('VERIFYING');
        setHint(null);

        try {
            const [frontal, mid, peak] = await Promise.all([
                frontalFrameRef.current,
                midFrameRef.current,
                peakFrameRef.current,
            ]);

            if (!frontal || !peak) throw new Error('Unable to capture camera image.');

            stopCameraStream();
            setIsSubmitting(true);

            const { nonce, direction } = challengeRef.current;
            const formData = new FormData();

            // Same field name the current controller already validates.
            formData.append('live_camera_frame', frontal, 'frontal.jpg');

            // Extra fields for the upcoming server-side pose / anti-spoof checks.
            // The current controller ignores these, so nothing breaks in the meantime.
            if (mid) formData.append('turn_mid_frame', mid, 'turn-mid.jpg');
            formData.append('turn_peak_frame', peak, 'turn-peak.jpg');
            formData.append('direction', direction);
            if (nonce) formData.append('challenge_nonce', nonce);

            router.post('/register/verify-face', formData, {
                forceFormData: true,
                preserveState: true,
                preserveScroll: true,
                onSuccess: () => {
                    setIsSubmitting(false);
                    goToStep('PASSED');
                },
                onError: (errors: Record<string, string>) => {
                    console.error('Face verification errors:', errors);
                    setIsSubmitting(false);
                    setModalError(
                        errors.face ||
                            errors.live_camera_frame ||
                            errors.challenge_nonce ||
                            Object.values(errors)[0] ||
                            'Verification failed. Please try again.',
                    );
                },
                onFinish: () => setIsSubmitting(false),
            });
        } catch (error) {
            console.error('Capture error:', error);
            setIsSubmitting(false);
            stopCameraStream();
            setModalError('Unable to capture the camera image. Please try again.');
        }
    };

    /* ---------------------------------- Retry -------------------------------- */

    const handleRetry = () => {
        const restart = () => {
            hasSubmittedRef.current = false;
            setModalError(null);
            setCameraError(null);
            setIsSubmitting(false);
            setHint(null);
            resetChallenge();

            startCameraStream().catch((error) => {
                console.error('Camera restart failed:', error);
                setCameraError(describeCameraError(error));
            });
        };

        if (serverChallenge) {
            // A server challenge is one-time use, so fetch a fresh one before retrying.
            router.reload({ only: ['challenge'], onFinish: restart });
        } else {
            setLocalDirection(randomDirection());
            restart();
        }
    };

    /* ----------------------------------- UI ---------------------------------- */

    const instruction = (() => {
        switch (displayStep) {
            case 'LOADING':
                return { text: 'Loading face detection\u2026', icon: Loader2, spin: true };
            case 'DETECT':
                return { text: 'Position your face in the circle', icon: Scan, spin: false };
            case 'LOOK_CENTER':
                return { text: 'Look straight at the camera and hold still', icon: Eye, spin: false };
            case 'TURN':
                return {
                    text: `Slowly turn your head to your ${challenge.direction}`,
                    icon: challenge.direction === 'left' ? ArrowLeft : ArrowRight,
                    spin: false,
                };
            case 'VERIFYING':
                return { text: 'Verifying your face\u2026', icon: RefreshCw, spin: true };
            case 'PASSED':
                return { text: 'Verified. Redirecting\u2026', icon: CheckCircle2, spin: false };
        }
    })();
    const ActiveIcon = instruction.icon;

    const progressIndex =
        displayStep === 'LOADING' || displayStep === 'DETECT'
            ? 0
            : displayStep === 'LOOK_CENTER'
              ? 1
              : displayStep === 'TURN'
                ? 2
                : 3;

    const showHint = hint && !modalError && !cameraError;

    return (
        <div className="relative flex min-h-screen flex-col items-center justify-center bg-[#F5F6FA] p-4 font-sans text-black">
            <Head title="Live Face Verification" />

            {/* PROCESSING OVERLAY */}
            {isSubmitting && (
                <div className="fixed inset-0 z-50 flex flex-col items-center justify-center bg-black/75 text-white backdrop-blur-sm">
                    <div className="relative flex h-24 w-24 items-center justify-center rounded-full bg-white/10 p-4">
                        <Sparkles className="h-12 w-12 animate-pulse text-[#F5A623]" />
                        <div className="absolute inset-0 animate-spin rounded-full border-4 border-transparent border-t-[#F5A623]" />
                    </div>
                    <h3 className="mt-4 text-lg font-bold">Verifying your face</h3>
                    <p className="mt-1 text-xs text-gray-300">This only takes a few seconds.</p>
                </div>
            )}

            {/* ERROR MODAL */}
            {modalError && (
                <div
                    role="alertdialog"
                    aria-modal="true"
                    aria-labelledby="verify-error-title"
                    className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4 backdrop-blur-md animate-in fade-in duration-200"
                >
                    <div className="w-full max-w-sm rounded-2xl border border-red-100 bg-white p-6 text-center shadow-2xl">
                        <div className="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-full bg-red-100 text-red-600">
                            <ShieldAlert className="h-8 w-8" />
                        </div>
                        <h3 id="verify-error-title" className="text-lg font-bold text-gray-900">
                            Verification failed
                        </h3>
                        <p className="mt-2 text-xs font-medium leading-relaxed text-gray-600">{modalError}</p>
                        <div className="mt-6">
                            <button
                                type="button"
                                onClick={handleRetry}
                                className="w-full rounded-xl bg-[#1B1F5C] px-4 py-2.5 text-sm font-semibold text-white shadow-md transition-all hover:bg-[#131644] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#F5A623] active:scale-95"
                            >
                                Try again
                            </button>
                        </div>
                    </div>
                </div>
            )}

            {/* MAIN CARD */}
            <div className="w-full max-w-md rounded-2xl border border-gray-100 bg-white p-6 shadow-xl">
                <div className="mb-4 text-center">
                    <div className="mx-auto mb-2 flex h-12 w-12 items-center justify-center rounded-full bg-[#1B1F5C]/10 text-[#1B1F5C]">
                        <ShieldCheck className="h-6 w-6" />
                    </div>
                    <h2 className="text-xl font-bold text-[#1B1F5C]">Face verification</h2>
                    <p className="mt-1 text-xs text-gray-500">
                        Welcome <span className="font-semibold text-gray-800">{student.firstname}</span>. Follow the
                        prompts to confirm it&apos;s really you.
                    </p>
                </div>

                {/* CAMERA VIEWPORT */}
                <div className="relative mx-auto h-56 w-56 overflow-hidden rounded-full border-4 border-[#1B1F5C] bg-black shadow-inner">
                    <video
                        ref={videoRef}
                        autoPlay
                        playsInline
                        muted
                        className="h-full w-full scale-x-[-1] object-cover"
                    />
                    <div className="pointer-events-none absolute inset-3 flex items-center justify-center rounded-full border border-white/20">
                        <div
                            className={`h-full w-full rounded-full border-2 border-dashed transition-colors duration-300 ${
                                displayStep === 'PASSED'
                                    ? 'border-emerald-500 bg-emerald-500/10'
                                    : displayStep === 'VERIFYING'
                                      ? 'animate-spin border-[#F5A623]'
                                      : 'border-[#F5A623]'
                            }`}
                        />
                    </div>

                    {/* Direction cue: the preview is mirrored, so "left" is the left of the screen. */}
                    {displayStep === 'TURN' && (
                        <div
                            className={`pointer-events-none absolute top-1/2 -translate-y-1/2 rounded-full bg-black/50 p-1.5 text-white ${
                                challenge.direction === 'left' ? 'left-2' : 'right-2'
                            }`}
                        >
                            <ActiveIcon className="h-5 w-5 animate-pulse" />
                        </div>
                    )}
                </div>

                {/* PROGRESS */}
                <div className="mx-auto mt-5 flex w-40 gap-1.5" aria-hidden="true">
                    {[0, 1, 2].map((index) => (
                        <div
                            key={index}
                            className={`h-1 flex-1 rounded-full transition-colors duration-300 ${
                                index < progressIndex ? 'bg-emerald-500' : index === progressIndex ? 'bg-[#F5A623]' : 'bg-gray-200'
                            }`}
                        />
                    ))}
                </div>

                {/* STEP BADGE */}
                <div
                    role="status"
                    aria-live="polite"
                    className={`mt-4 flex items-center justify-center gap-2 rounded-lg border p-3 text-center text-xs font-semibold ${
                        displayStep === 'PASSED'
                            ? 'border-emerald-200 bg-emerald-50 text-emerald-700'
                            : 'border-amber-200 bg-amber-50 text-amber-800'
                    }`}
                >
                    <ActiveIcon className={`h-4 w-4 shrink-0 ${instruction.spin ? 'animate-spin' : ''}`} />
                    <span>{instruction.text}</span>
                </div>

                {/* HOLD-STILL PROGRESS */}
                {displayStep === 'LOOK_CENTER' && (
                    <div className="mt-2 h-1 w-full overflow-hidden rounded-full bg-gray-100" aria-hidden="true">
                        <div
                            className="h-full bg-[#1B1F5C] transition-[width] duration-150"
                            style={{ width: `${Math.round(holdProgress * 100)}%` }}
                        />
                    </div>
                )}

                {/* GUIDANCE HINT */}
                {showHint && <p className="mt-3 text-center text-xs font-medium text-amber-700">{hint}</p>}

                {/* CAMERA / SYSTEM ERROR */}
                {cameraError && !modalError && (
                    <div className="mt-4 rounded-lg border border-red-200 bg-red-50 p-3 text-xs text-red-600">
                        <div className="flex items-start gap-2">
                            <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
                            <span>{cameraError}</span>
                        </div>
                        <button
                            type="button"
                            onClick={() => window.location.reload()}
                            className="mt-3 w-full rounded-lg bg-red-600 px-3 py-2 text-xs font-semibold text-white transition-colors hover:bg-red-700"
                        >
                            Reload page
                        </button>
                    </div>
                )}
            </div>
        </div>
    );
}

VerifyFace.layout = {
    title: 'Face Verification',
};