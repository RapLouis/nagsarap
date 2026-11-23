import { Head, router } from '@inertiajs/react';
import type { FaceLandmarker } from '@mediapipe/tasks-vision';
import {
    AlertTriangle,
    ArrowLeft,
    ArrowRight,
    CheckCircle2,
    Loader2,
    RotateCcw,
    Shield,
    Sun,
} from 'lucide-react';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import {
    DIRECTION_SIGN,
    FLASH_CAPTURE_AT_MS,
    FLASH_CSS_COLORS,
    FLASH_DURATION_MS,
    LIVE_FRAME_OPTIONS,
    REFERENCE_MAX_BRIGHTNESS,
    REFERENCE_MIN_BRIGHTNESS,
    VIDEO_CONSTRAINTS,
    calculateYaw,
    captureFrameScaled,
    describeCameraError,
    getPlacementIssue,
    getSharedLandmarker,
    isFlashColor,
    measureBrightness,
} from '@/lib/liveness';
import type { Direction, FlashColor, Landmark } from '@/lib/liveness';

/* -------------------------------------------------------------------------- */
/* Types                                                                      */
/* -------------------------------------------------------------------------- */

type Props = {
    student: { student_id: number; firstname: string; surname: string };
    /**
     * Server-issued and one-time. The server decides the flash colors and the turn direction;
     * the browser only follows them.
     */
    challenge?: {
        nonce: string;
        direction: Direction;
        flash_colors: string[];
    };
};

type Step =
    | 'INTRO'
    | 'ALIGN'
    | 'FLASHING'
    | 'TURN'
    | 'REFRESH'
    | 'SUBMITTING'
    | 'DONE'
    | 'FAILED';

type WakeLockHandle = { release: () => Promise<void> };

/* -------------------------------------------------------------------------- */
/* Configuration                                                              */
/* -------------------------------------------------------------------------- */

const PROCESS_EVERY_N_FRAMES = 3; // run face detection on every Nth animation frame
const FRONTAL_YAW_MAX = 0.12; // "looking straight" (0 = facing the camera)
const FRONTAL_HOLD_FRAMES = 8; // processed frames the face must stay valid (~0.8s)

const FLASH_FRAME_COUNT = 3; // must match FLASH_FRAME_COUNT in app.py
const FLASH_GAP_MS = 150; // short dark pause before each flash so the camera exposure settles
const FLASH_YAW_TOLERANCE = 1.5; // looser pose limit while the screen is flashing

const TURN_YAW_MIN = 0.10; // yaw needed before peak frame is taken
const TURN_YAW_MAX = 0.70; // upper limit for extreme angles
const TURN_HOLD_FRAMES = 2; // consecutive processed frames inside window
const WRONG_WAY_YAW = 0.10; // turned opposite way
const TURN_TIMEOUT_MS = 20_000;

const IDLE_BG = '#1B1F5C';
const NEUTRAL_BG = '#000000'; // screen color between flashes

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/* -------------------------------------------------------------------------- */
/* Helpers                                                                    */
/* -------------------------------------------------------------------------- */

function nextVideoFrame(video: HTMLVideoElement, timeoutMs = 250): Promise<void> {
    return new Promise((resolve) => {
        const target = video as HTMLVideoElement & {
            requestVideoFrameCallback?: (callback: () => void) => number;
        };

        if (typeof target.requestVideoFrameCallback !== 'function') {
            setTimeout(resolve, 60);
            return;
        }

        const timer = setTimeout(resolve, timeoutMs);
        target.requestVideoFrameCallback(() => {
            clearTimeout(timer);
            resolve();
        });
    });
}

function inspectFace(
    landmarker: FaceLandmarker,
    video: HTMLVideoElement,
    yawMax = FRONTAL_YAW_MAX
): string | null {
    let faces: Landmark[][];
    try {
        faces = landmarker.detectForVideo(video, performance.now()).faceLandmarks ?? [];
    } catch (error) {
        console.error('Face detection error:', error);
        return 'Checking your face…';
    }

    if (faces.length === 0) return 'Position your face inside the guide circle.';
    if (faces.length > 1) return 'Multiple faces detected. Ensure only you are in frame.';

    const landmarks = faces[0];
    const placementIssue = getPlacementIssue(landmarks);
    if (placementIssue) return placementIssue;

    if (Math.abs(calculateYaw(landmarks)) > yawMax) return 'Look straight at the camera.';

    return null;
}

/* -------------------------------------------------------------------------- */
/* Main Page Component                                                        */
/* -------------------------------------------------------------------------- */

export default function VerifyFace({ student, challenge }: Props) {
    const videoRef = useRef<HTMLVideoElement | null>(null);
    const landmarkerRef = useRef<FaceLandmarker | null>(null);
    const mountedRef = useRef(true);
    const cameraLabelRef = useRef('');
    const wakeLockRef = useRef<WakeLockHandle | null>(null);

    const runIdRef = useRef(0);
    const sequenceActiveRef = useRef(false);
    const stableRef = useRef(0);

    const frontalBlobRef = useRef<Blob | null>(null);
    const flashBlobsRef = useRef<Blob[]>([]);

    const challengeRef = useRef(challenge);
    challengeRef.current = challenge;

    const [step, setStep] = useState<Step>('INTRO');
    const stepRef = useRef<Step>('INTRO');
    stepRef.current = step;

    const [cameraReady, setCameraReady] = useState(false);
    const [modelReady, setModelReady] = useState(false);
    const [cameraError, setCameraError] = useState<string | null>(null);
    const [modelError, setModelError] = useState<string | null>(null);
    const [hint, setHint] = useState<string | null>(null);
    const [notice, setNotice] = useState<string | null>(null);
    const [holdProgress, setHoldProgress] = useState(0);
    const [flashColor, setFlashColor] = useState<FlashColor | null>(null);
    const [serverError, setServerError] = useState<string | null>(null);

    const flashColors = challenge?.flash_colors;
    const challengeValid =
        !!challenge?.nonce &&
        (challenge?.direction === 'left' || challenge?.direction === 'right') &&
        Array.isArray(flashColors) &&
        flashColors.length === FLASH_FRAME_COUNT &&
        flashColors.every(isFlashColor);

    const systemError = cameraError ?? modelError;
    const isLoading =
        (step === 'INTRO' || step === 'ALIGN') && !systemError && !(cameraReady && modelReady);

    /* ------------------------------- Camera ---------------------------------- */

    const stopCamera = useCallback(() => {
        const video = videoRef.current;
        if (video?.srcObject) {
            (video.srcObject as MediaStream).getTracks().forEach((track) => track.stop());
            video.srcObject = null;
        }
        setCameraReady(false);
    }, []);

    const startCamera = useCallback(async (): Promise<boolean> => {
        setCameraError(null);

        try {
            if (!window.isSecureContext) {
                throw new Error(
                    'The camera requires a secure HTTPS connection. Please access the site using https://'
                );
            }
            if (!navigator.mediaDevices?.getUserMedia) {
                throw new Error(
                    'Camera access is not supported by this browser. Please use Chrome, Safari, or Edge.'
                );
            }

            stopCamera();

            const stream = await navigator.mediaDevices.getUserMedia(VIDEO_CONSTRAINTS);
            const video = videoRef.current;

            if (!mountedRef.current || !video) {
                stream.getTracks().forEach((track) => track.stop());
                return false;
            }

            cameraLabelRef.current = stream.getVideoTracks()[0]?.label ?? '';
            video.srcObject = stream;
            await video.play().catch(() => {});
            setCameraReady(true);
            return true;
        } catch (error) {
            console.error('Camera error:', error);
            if (mountedRef.current) setCameraError(describeCameraError(error));
            return false;
        }
    }, [stopCamera]);

    /* ------------------------------ Wake lock -------------------------------- */

    const acquireWakeLock = useCallback(async () => {
        try {
            const nav = navigator as unknown as {
                wakeLock?: { request: (type: 'screen') => Promise<WakeLockHandle> };
            };
            if (!nav.wakeLock || wakeLockRef.current) return;
            wakeLockRef.current = await nav.wakeLock.request('screen');
        } catch {
            /* best effort feature */
        }
    }, []);

    const releaseWakeLock = useCallback(() => {
        const lock = wakeLockRef.current;
        wakeLockRef.current = null;
        void lock?.release().catch(() => {});
    }, []);

    /* ------------------------ Restart (fresh challenge) ---------------------- */

    const restart = useCallback(
        (message: string | null) => {
            runIdRef.current += 1;
            sequenceActiveRef.current = false;
            stableRef.current = 0;
            setHoldProgress(0);
            setFlashColor(null);
            setHint(null);
            setServerError(null);
            setNotice(message);
            setStep('REFRESH');

            router.reload({
                only: ['challenge'],
                onFinish: () => {
                    if (!mountedRef.current) return;
                    void (async () => {
                        if (!videoRef.current?.srcObject) await startCamera();
                        if (mountedRef.current) setStep('ALIGN');
                    })();
                },
            });
        },
        [startCamera]
    );

    /* Start camera & face model in parallel */
    useEffect(() => {
        mountedRef.current = true;
        let cancelled = false;

        const modelPromise = getSharedLandmarker();
        modelPromise.catch(() => {});

        void (async () => {
            if (!(await startCamera())) return;

            try {
                const landmarker = await modelPromise;
                if (cancelled) return;
                landmarkerRef.current = landmarker;
                setModelReady(true);
            } catch (error) {
                console.error('Face detection init error:', error);
                if (!cancelled) {
                    setModelError(
                        'Unable to initialize face detection. Check network connection and reload.'
                    );
                }
            }
        })();

        return () => {
            cancelled = true;
            mountedRef.current = false;
            runIdRef.current += 1;
            stopCamera();
            releaseWakeLock();
            landmarkerRef.current = null;
        };
    }, [startCamera, stopCamera, releaseWakeLock]);

    /* Visibility tab switch handling */
    useEffect(() => {
        const onVisibility = () => {
            if (document.visibilityState === 'hidden') {
                if (stepRef.current === 'FLASHING' || stepRef.current === 'TURN') {
                    restart('The verification check was interrupted. Please try again.');
                }
                return;
            }

            wakeLockRef.current = null;
            if (
                stepRef.current === 'ALIGN' ||
                stepRef.current === 'FLASHING' ||
                stepRef.current === 'TURN'
            ) {
                void acquireWakeLock();
            }
        };

        document.addEventListener('visibilitychange', onVisibility);
        return () => document.removeEventListener('visibilitychange', onVisibility);
    }, [restart, acquireWakeLock]);

    /* ------------------------------ Submission ------------------------------- */

    const submit = useCallback(
        (frontal: Blob, flashes: Blob[], peak: Blob) => {
            setStep('SUBMITTING');
            setHint(null);
            setFlashColor(null);
            stopCamera();
            releaseWakeLock();

            const formData = new FormData();
            formData.append('challenge_nonce', challengeRef.current?.nonce ?? '');
            formData.append('live_camera_frame', frontal, 'frontal.jpg');
            flashes.forEach((blob, index) =>
                formData.append(`flash_frames[${index}]`, blob, `flash_${index}.jpg`)
            );
            formData.append('turn_peak_frame', peak, 'turn-peak.jpg');
            if (cameraLabelRef.current) formData.append('camera_label', cameraLabelRef.current);

            router.post('/register/verify-face', formData, {
                forceFormData: true,
                preserveScroll: true,
                onSuccess: () => setStep('DONE'),
                onError: (errors: Record<string, string>) => {
                    console.error('Face verification errors:', errors);
                    setServerError(
                        errors.face ||
                            errors.live_camera_frame ||
                            errors.flash_frames ||
                            errors.turn_peak_frame ||
                            errors.challenge_nonce ||
                            Object.values(errors)[0] ||
                            'Biometric liveness check failed. Please try again.'
                    );
                    setStep('FAILED');
                },
            });
        },
        [stopCamera, releaseWakeLock]
    );

    /* ----------------------------- Flash sequence ---------------------------- */

    const runSequence = useCallback(async () => {
        if (sequenceActiveRef.current) return;
        sequenceActiveRef.current = true;

        const runId = ++runIdRef.current;
        const alive = () => mountedRef.current && runIdRef.current === runId;
        const abort = (message: string) => {
            if (alive()) restart(message);
        };

        const video = videoRef.current;
        const landmarker = landmarkerRef.current;
        const colors = challengeRef.current?.flash_colors ?? [];

        if (!video || !landmarker || colors.length !== FLASH_FRAME_COUNT) {
            abort('The camera is not ready. Please try again.');
            return;
        }

        setNotice(null);
        setHint(null);

        try {
            const baseline = await captureFrameScaled(video, LIVE_FRAME_OPTIONS);
            if (!alive()) return;
            if (!baseline) {
                abort('Unable to capture initial camera frame. Please try again.');
                return;
            }

            setStep('FLASHING');

            const flashes: Blob[] = [];

            for (const color of colors) {
                if (!isFlashColor(color)) {
                    abort('The verification session was invalid. Please try again.');
                    return;
                }

                setFlashColor(null);
                await sleep(FLASH_GAP_MS);
                if (!alive()) return;

                setFlashColor(color);
                await sleep(FLASH_CAPTURE_AT_MS);
                await nextVideoFrame(video);
                if (!alive()) return;

                if (inspectFace(landmarker, video, FRONTAL_YAW_MAX * FLASH_YAW_TOLERANCE)) {
                    abort('Hold still while the screen flashes. Let\u2019s try again.');
                    return;
                }

                const blob = await captureFrameScaled(video, LIVE_FRAME_OPTIONS);
                if (!alive()) return;
                if (!blob) {
                    abort('Unable to capture flash frame. Please try again.');
                    return;
                }
                flashes.push(blob);

                await sleep(Math.max(FLASH_DURATION_MS - FLASH_CAPTURE_AT_MS, 0));
                if (!alive()) return;
            }

            frontalBlobRef.current = baseline;
            flashBlobsRef.current = flashes;
            setFlashColor(null);
            sequenceActiveRef.current = false;
            setStep('TURN');
        } catch (error) {
            console.error('Flash sequence error:', error);
            abort('Something went wrong during flash check. Please try again.');
        }
    }, [restart]);

    /* ------------------------------ Alignment loop --------------------------- */

    useEffect(() => {
        if (step !== 'ALIGN' || !cameraReady || !modelReady) return;

        let stopped = false;
        let raf = 0;
        let frameCount = 0;
        let lastVideoTime = -1;

        const processFrame = () => {
            const video = videoRef.current;
            const landmarker = landmarkerRef.current;
            if (!video || !landmarker || video.readyState < 2) return;

            if (video.currentTime === lastVideoTime) return;
            lastVideoTime = video.currentTime;

            let issue: string | null;
            const brightness = measureBrightness(video);

            if (brightness !== null && brightness < REFERENCE_MIN_BRIGHTNESS) {
                issue = 'Lighting is too dark. Move to a brighter area.';
            } else if (brightness !== null && brightness > REFERENCE_MAX_BRIGHTNESS) {
                issue = 'Lighting is too bright or backlit.';
            } else {
                issue = inspectFace(landmarker, video);
            }

            if (issue) {
                stableRef.current = 0;
                setHoldProgress(0);
                setHint(issue);
                return;
            }

            setHint(null);
            setNotice(null);
            stableRef.current += 1;
            setHoldProgress(Math.min(stableRef.current / FRONTAL_HOLD_FRAMES, 1));

            if (stableRef.current >= FRONTAL_HOLD_FRAMES) {
                stopped = true;
                cancelAnimationFrame(raf);
                void runSequence();
            }
        };

        const tick = () => {
            if (stopped) return;
            frameCount += 1;
            if (frameCount % PROCESS_EVERY_N_FRAMES === 0) processFrame();
            if (!stopped) raf = requestAnimationFrame(tick);
        };

        raf = requestAnimationFrame(tick);

        return () => {
            stopped = true;
            cancelAnimationFrame(raf);
        };
    }, [step, cameraReady, modelReady, runSequence]);

    /* -------------------------------- Turn loop ------------------------------ */

    useEffect(() => {
        if (step !== 'TURN' || !cameraReady || !modelReady) return;

        const runId = runIdRef.current;
        const alive = () => mountedRef.current && runIdRef.current === runId;

        let stopped = false;
        let raf = 0;
        let frameCount = 0;
        let lastVideoTime = -1;
        let hold = 0;
        const startedAt = performance.now();

        const finish = async (video: HTMLVideoElement) => {
            await nextVideoFrame(video);
            const peak = await captureFrameScaled(video, LIVE_FRAME_OPTIONS);
            if (!alive()) return;

            const frontal = frontalBlobRef.current;
            const flashes = flashBlobsRef.current;

            if (!peak || !frontal || flashes.length !== FLASH_FRAME_COUNT) {
                restart('Unable to capture peak turn frame. Please try again.');
                return;
            }

            submit(frontal, flashes, peak);
        };

        const processFrame = () => {
            const video = videoRef.current;
            const landmarker = landmarkerRef.current;
            const direction = challengeRef.current?.direction;
            if (!video || !landmarker || !direction || video.readyState < 2) return;

            if (performance.now() - startedAt > TURN_TIMEOUT_MS) {
                stopped = true;
                restart('Time limit reached. Let\u2019s try again.');
                return;
            }

            if (video.currentTime === lastVideoTime) return;
            lastVideoTime = video.currentTime;

            let faces: Landmark[][];
            try {
                faces = landmarker.detectForVideo(video, performance.now()).faceLandmarks ?? [];
            } catch (error) {
                console.error('Face detection error:', error);
                return;
            }

            if (faces.length === 0) {
                hold = 0;
                setHint('Keep your face visible inside the camera circle.');
                return;
            }
            if (faces.length > 1) {
                hold = 0;
                setHint('Multiple faces detected. Ensure only you are in frame.');
                return;
            }

            const turned = calculateYaw(faces[0]) * DIRECTION_SIGN[direction];

            if (turned <= -WRONG_WAY_YAW) {
                hold = 0;
                setHint(`Turn your head to your ${direction}, not the other way.`);
                return;
            }

            if (turned > TURN_YAW_MAX) {
                hold = 0;
                setHint('Turned too far. Adjust slightly back toward center.');
                return;
            }

            setHint(null);

            if (turned >= TURN_YAW_MIN) {
                hold += 1;
                if (hold >= TURN_HOLD_FRAMES) {
                    stopped = true;
                    void finish(video);
                }
            } else {
                hold = 0;
            }
        };

        const tick = () => {
            if (stopped) return;
            frameCount += 1;
            if (frameCount % PROCESS_EVERY_N_FRAMES === 0) processFrame();
            if (!stopped) raf = requestAnimationFrame(tick);
        };

        raf = requestAnimationFrame(tick);

        return () => {
            stopped = true;
            cancelAnimationFrame(raf);
        };
    }, [step, cameraReady, modelReady, restart, submit]);

    /* ----------------------------------- UI Render ---------------------------------- */

    const flashing = step === 'FLASHING';
    const direction: Direction = challenge?.direction ?? 'left';
    const TurnIcon = direction === 'left' ? ArrowLeft : ArrowRight;

    if (!challengeValid) {
        return (
            <div
                className="fixed inset-0 flex items-center justify-center overflow-y-auto p-4 font-sans text-gray-900 antialiased"
                style={{ backgroundColor: IDLE_BG }}
            >
                <Head title="Biometric Face Verification | 4ttnd System" />
                <div className="w-full max-w-md rounded-2xl border border-gray-100 bg-white p-6 text-center shadow-2xl sm:p-8">
                    <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-xl bg-red-50 text-red-600">
                        <AlertTriangle className="h-6 w-6" aria-hidden="true" />
                    </div>
                    <h1 className="text-lg font-bold text-gray-900">Session Error</h1>
                    <p className="mt-1.5 text-xs text-gray-600 leading-relaxed">
                        The biometric liveness challenge session could not be established or has expired.
                    </p>
                    <Button
                        type="button"
                        onClick={() => window.location.reload()}
                        className="mt-6 w-full min-h-[44px] bg-[#1B1F5C] text-xs font-bold text-white shadow-md hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                    >
                        Reload Verification Page
                    </Button>
                </div>
            </div>
        );
    }

    const backgroundColor = flashing
        ? flashColor
            ? FLASH_CSS_COLORS[flashColor]
            : NEUTRAL_BG
        : IDLE_BG;

    const progressIndex =
        step === 'INTRO' || step === 'ALIGN' || step === 'REFRESH'
            ? 0
            : step === 'FLASHING'
              ? 1
              : step === 'TURN'
                ? 2
                : 3;

    const ringClass =
        step === 'DONE'
            ? 'border-emerald-500 border-4'
            : step === 'FAILED'
              ? 'border-red-500 border-4'
              : flashing
                ? 'border-white/80'
                : step === 'TURN'
                  ? 'border-[#F5A623] animate-pulse'
                  : holdProgress >= 1
                    ? 'border-emerald-500'
                    : 'border-[#F5A623]';

    return (
        <div
            className="fixed inset-0 overflow-y-auto font-sans antialiased transition-colors duration-200"
            style={{ backgroundColor }}
        >
            <Head title="Biometric Face Verification | 4ttnd System" />

            <div className="flex min-h-full items-center justify-center p-4">
                <main
                    className={`relative w-full max-w-md rounded-2xl transition-all duration-300 ${
                        flashing
                            ? 'bg-transparent p-0 text-white shadow-none'
                            : 'border border-gray-200/80 bg-white p-6 text-gray-900 shadow-2xl sm:p-8'
                    }`}
                >
                    {!flashing && (
                        <header className="mb-4 text-center">
                            <div className="mb-1 flex items-center justify-center gap-2 text-[#1B1F5C]">
                                <Shield className="h-6 w-6 text-[#F5A623]" aria-hidden="true" />
                                <h1 className="text-xl font-black tracking-tight text-[#1B1F5C]">
                                    Liveness Verification
                                </h1>
                            </div>
                            <p className="text-xs font-medium text-gray-500">
                                Student:{' '}
                                <span className="font-bold text-gray-900">
                                    {student.firstname} {student.surname}
                                </span>
                            </p>
                        </header>
                    )}

                    {/* CAMERA VIEWPORT */}
                    <div
                        className={`relative mx-auto h-64 w-64 overflow-hidden rounded-full border-4 bg-black shadow-inner ${
                            flashing ? 'border-white/80' : 'my-4 border-[#1B1F5C]'
                        }`}
                    >
                        <video
                            ref={videoRef}
                            autoPlay
                            playsInline
                            muted
                            className="h-full w-full scale-x-[-1] object-cover"
                        />
                        <div
                            className={`pointer-events-none absolute inset-2 rounded-full border-2 border-dashed transition-colors duration-300 ${ringClass}`}
                        />

                        {/* Head Turn Direction Arrow */}
                        {step === 'TURN' && (
                            <div
                                className={`pointer-events-none absolute top-1/2 -translate-y-1/2 rounded-full bg-black/60 p-2 text-white shadow-lg ${
                                    direction === 'left' ? 'left-3' : 'right-3'
                                }`}
                            >
                                <TurnIcon className="h-6 w-6 animate-pulse text-[#F5A623]" />
                            </div>
                        )}

                        {/* Submitting Overlay */}
                        {step === 'SUBMITTING' && (
                            <div className="absolute inset-0 flex flex-col items-center justify-center bg-black/70 text-white backdrop-blur-sm">
                                <Loader2 className="mb-2 h-8 w-8 animate-spin text-[#F5A623]" />
                                <span className="text-xs font-bold tracking-wide">
                                    Verifying Biometrics…
                                </span>
                            </div>
                        )}

                        {/* Success State Overlay */}
                        {step === 'DONE' && (
                            <div className="absolute inset-0 flex flex-col items-center justify-center bg-emerald-600/90 text-white">
                                <CheckCircle2 className="mb-2 h-12 w-12" />
                                <span className="text-xs font-bold tracking-wide">Verified</span>
                            </div>
                        )}
                    </div>

                    {/* Flash Step Instruction Overlay */}
                    {flashing && (
                        <div className="mt-4 flex justify-center">
                            <span className="rounded-full bg-black/70 px-4 py-2 text-xs font-bold text-white shadow-md backdrop-blur-sm">
                                Hold Still & Keep Looking Forward
                            </span>
                        </div>
                    )}

                    {!flashing && (
                        <>
                            {/* STEP PROGRESS BARS */}
                            <div className="mx-auto mb-4 flex w-36 gap-1.5" aria-hidden="true">
                                {[0, 1, 2].map((index) => (
                                    <div
                                        key={index}
                                        className={`h-1.5 flex-1 rounded-full transition-colors duration-300 ${
                                            index < progressIndex
                                                ? 'bg-emerald-500'
                                                : index === progressIndex
                                                  ? 'bg-[#F5A623]'
                                                  : 'bg-gray-200'
                                        }`}
                                    />
                                ))}
                            </div>

                            {/* STATUS MESSAGES */}
                            <div
                                role="status"
                                aria-live="polite"
                                className="mb-4 flex min-h-[44px] flex-col items-center justify-center text-center"
                            >
                                {isLoading && (
                                    <p className="flex items-center gap-2 text-xs font-semibold text-gray-700">
                                        <Loader2 className="h-4 w-4 animate-spin text-[#1B1F5C]" />
                                        Initializing camera feed…
                                    </p>
                                )}
                                {step === 'ALIGN' && !isLoading && !systemError && (
                                    <p className="text-xs font-semibold text-gray-800">
                                        {hint || 'Look straight at the camera and hold still'}
                                    </p>
                                )}
                                {step === 'TURN' && (
                                    <p className="flex items-center gap-2 text-xs font-bold text-[#1B1F5C]">
                                        <TurnIcon className="h-4 w-4 text-[#F5A623]" />
                                        Slowly turn your head to your {direction}
                                    </p>
                                )}
                                {step === 'REFRESH' && (
                                    <p className="flex items-center gap-2 text-xs font-semibold text-gray-700">
                                        <Loader2 className="h-4 w-4 animate-spin text-[#1B1F5C]" />
                                        Preparing a new challenge session…
                                    </p>
                                )}
                                {step === 'SUBMITTING' && (
                                    <p className="text-xs font-medium text-gray-600">
                                        Processing biometric data with microservice…
                                    </p>
                                )}
                                {step === 'DONE' && (
                                    <p className="text-xs font-bold text-emerald-700">
                                        Biometric check passed! Redirecting…
                                    </p>
                                )}
                            </div>

                            {step === 'TURN' && hint && (
                                <p className="mb-3 text-center text-xs font-semibold text-amber-700 bg-amber-50 px-3 py-1.5 rounded-lg border border-amber-200">
                                    {hint}
                                </p>
                            )}

                            {/* STABILITY HOLD PROGRESS */}
                            {step === 'ALIGN' && !isLoading && !systemError && (
                                <div
                                    className="mb-4 h-1.5 w-full overflow-hidden rounded-full bg-gray-100"
                                    aria-hidden="true"
                                >
                                    <div
                                        className="h-full bg-[#1B1F5C] transition-all duration-150"
                                        style={{ width: `${Math.round(holdProgress * 100)}%` }}
                                    />
                                </div>
                            )}

                            {notice && (step === 'ALIGN' || step === 'REFRESH' || step === 'INTRO') && (
                                <p className="mb-4 text-center text-xs font-medium text-amber-700 bg-amber-50 px-3 py-2 rounded-lg border border-amber-200">
                                    {notice}
                                </p>
                            )}

                            {/* INTRO & PHOTOSENSITIVITY WARNING */}
                            {step === 'INTRO' && !systemError && (
                                <div className="mb-5 space-y-4">
                                    <ol className="list-decimal space-y-1.5 pl-5 text-xs text-gray-700 font-medium">
                                        <li>Look straight at the camera and hold still.</li>
                                        <li>The screen will flash red, green, and blue.</li>
                                        <li>Slowly turn your head to the indicated direction.</li>
                                    </ol>

                                    <div className="flex items-start gap-2.5 rounded-xl border border-amber-200 bg-amber-50/80 p-3.5 text-xs leading-relaxed text-amber-900 shadow-sm">
                                        <Sun className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" aria-hidden="true" />
                                        <span>
                                            <span className="font-bold">Flashing light warning:</span> This verification sequence flashes bright colors. If you are sensitive to flashing lights, ask staff for manual check-in.
                                        </span>
                                    </div>

                                    <Button
                                        type="button"
                                        disabled={!cameraReady || !modelReady}
                                        onClick={() => {
                                            void acquireWakeLock();
                                            restart(null);
                                        }}
                                        className="w-full min-h-[44px] bg-[#1B1F5C] text-xs font-bold text-white shadow-lg hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-50 transition-all"
                                    >
                                        I Understand, Start Verification →
                                    </Button>
                                </div>
                            )}

                            {/* SERVER ERROR */}
                            {step === 'FAILED' && serverError && (
                                <div
                                    role="alert"
                                    className="mb-4 flex items-start gap-2.5 rounded-xl border border-red-200 bg-red-50/90 p-3.5 text-xs font-semibold text-red-700 shadow-sm"
                                >
                                    <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-red-600" />
                                    <span>{serverError}</span>
                                </div>
                            )}

                            {/* SYSTEM / HARDWARE ERROR */}
                            {systemError && (
                                <div role="alert" className="mb-4 rounded-xl border border-red-200 bg-red-50 p-4 text-xs text-red-700">
                                    <div className="flex items-start gap-2">
                                        <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-red-600" />
                                        <span className="font-medium leading-relaxed">{systemError}</span>
                                    </div>
                                    <Button
                                        type="button"
                                        onClick={() => window.location.reload()}
                                        className="mt-3 w-full min-h-[40px] bg-red-600 text-xs font-bold text-white hover:bg-red-700 focus-visible:ring-2 focus-visible:ring-red-400"
                                    >
                                        Reload Page
                                    </Button>
                                </div>
                            )}

                            {/* RETRY & RESTART CONTROLS */}
                            {(step === 'ALIGN' || step === 'TURN' || step === 'FAILED') && !systemError && (
                                <Button
                                    type="button"
                                    onClick={() => restart(null)}
                                    className={
                                        step === 'FAILED'
                                            ? 'w-full min-h-[44px] bg-[#1B1F5C] text-xs font-bold text-white shadow-md hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623]'
                                            : 'w-full min-h-[44px] border border-gray-300 bg-white text-xs font-bold text-gray-800 shadow-sm transition-colors hover:border-gray-400 hover:bg-gray-100 focus-visible:ring-2 focus-visible:ring-[#F5A623]'
                                    }
                                >
                                    <RotateCcw className="mr-2 h-4 w-4" />
                                    {step === 'FAILED' ? 'Try Again' : 'Restart Verification'}
                                </Button>
                            )}
                        </>
                    )}
                </main>
            </div>
        </div>
    );
}