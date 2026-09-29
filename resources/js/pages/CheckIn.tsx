import React, { useState, useRef, useEffect } from 'react';
import { Head, Link, router } from '@inertiajs/react';
import type { FaceLandmarker } from '@mediapipe/tasks-vision';
import {
    Camera,
    CheckCircle2,
    Calendar,
    Clock,
    ShieldCheck,
    RefreshCw,
    X,
    ChevronRight,
    ArrowLeft,
    ArrowRight,
    Loader2,
    Check,
    Eye,
} from 'lucide-react';

type Event = {
    event_id: number;
    title: string;
    description?: string | null;
    event_date: string;
    start_time: string;
    end_time?: string | null;
    location?: string | null;
    is_active?: boolean;
};

type AttendanceLog = {
    attendance_id: number;
    logged_at: string;
    status: string;
    confidence_score: number;
    event: Event;
};

type Student = {
    student_id: number;
    firstname: string;
    surname: string;
    student_number: string;
    face_photo_url: string | null;
    attendances: AttendanceLog[];
};

type CheckInProps = {
    student: Student;
    activeEvents: Event[];
};

type Direction = 'left' | 'right';
type LivenessStep = 'LOOK_CENTER' | 'TURN' | 'VERIFYING' | 'PASSED';
type Landmark = { x: number; y: number };

const GOLD = '#C9973E';

const MEDIAPIPE_VERSION = '0.10.21';
const WASM_URL = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MEDIAPIPE_VERSION}/wasm`;
const MODEL_URL = 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task';

const VIDEO_CONSTRAINTS: MediaStreamConstraints = {
    video: { width: { ideal: 480 }, height: { ideal: 360 }, facingMode: 'user' },
    audio: false,
};

const PROCESS_INTERVAL_MS = 65;
const FRONTAL_YAW_MAX = 0.12;
const FRONTAL_HOLD_FRAMES = 3;
const TURN_YAW_MIN = 0.25;
const TURN_HOLD_FRAMES = 3;
const WRONG_WAY_YAW = 0.15;
const CHALLENGE_TIMEOUT_MS = 20_000;

const MIN_FACE_WIDTH = 0.22;
const MAX_FACE_WIDTH = 0.6;
const MAX_CENTER_OFFSET_X = 0.12;
const MAX_CENTER_OFFSET_Y = 0.15;

const DIRECTION_SIGN: Record<Direction, 1 | -1> = { left: 1, right: -1 };
const NOSE_TIP = 1;
const LEFT_CHEEK = 234;
const RIGHT_CHEEK = 454;

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

function captureFrame(video: HTMLVideoElement): Promise<Blob | null> {
    const canvas = document.createElement('canvas');
    const width = Math.min(video.videoWidth || 480, 480);
    const height = Math.min(video.videoHeight || 360, 360);

    canvas.width = width;
    canvas.height = height;

    const context = canvas.getContext('2d', { alpha: false });
    if (!context) return Promise.resolve(null);

    context.drawImage(video, 0, 0, width, height);

    return new Promise((resolve) => {
        canvas.toBlob((blob) => resolve(blob), 'image/jpeg', 0.60);
    });
}

function describeCameraError(error: unknown): string {
    const name = (error as { name?: string })?.name;
    if (name === 'NotAllowedError' || name === 'SecurityError') {
        return 'Camera access was blocked. Allow camera permission in browser settings.';
    }
    if (name === 'NotFoundError' || name === 'OverconstrainedError') {
        return 'No front camera found on this device.';
    }
    if (name === 'NotReadableError') {
        return 'Camera is in use by another application.';
    }
    return 'Unable to access the camera.';
}

let cachedLandmarkerPromise: Promise<FaceLandmarker> | null = null;

function createLandmarker(): Promise<FaceLandmarker> {
    if (cachedLandmarkerPromise) return cachedLandmarkerPromise;

    cachedLandmarkerPromise = (async () => {
        const { FaceLandmarker, FilesetResolver } = await import('@mediapipe/tasks-vision');
        const vision = await FilesetResolver.forVisionTasks(WASM_URL);

        const create = (delegate: 'GPU' | 'CPU') =>
            FaceLandmarker.createFromOptions(vision, {
                baseOptions: { modelAssetPath: MODEL_URL, delegate },
                runningMode: 'VIDEO',
                numFaces: 1,
                minFaceDetectionConfidence: 0.5,
                minFacePresenceConfidence: 0.5,
                minTrackingConfidence: 0.5,
            });

        try {
            return await create('GPU');
        } catch (error) {
            return await create('CPU');
        }
    })();

    return cachedLandmarkerPromise;
}

function formatEventTime(startTime?: string | null, endTime?: string | null): string {
    if (!startTime) return '';
    const parseTime = (timeStr: string) => {
        const [hours, minutes] = timeStr.split(':').map(Number);
        const date = new Date();
        date.setHours(hours, minutes, 0);
        return date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit', hour12: true });
    };

    const formattedStart = parseTime(startTime);
    if (!endTime) return formattedStart;
    return `${formattedStart} - ${parseTime(endTime)}`;
}

export default function CheckIn({ student, activeEvents }: CheckInProps) {
    const [selectedEvent, setSelectedEvent] = useState<Event | null>(null);
    const [checkedInEventsCache, setCheckedInEventsCache] = useState<Set<number>>(() => new Set());

    const checkedInEventIds = new Set([
        ...student.attendances
            .filter((log) => log.status?.toLowerCase() === 'present' || log.status?.toLowerCase() === 'verified')
            .map((log) => log.event?.event_id),
        ...Array.from(checkedInEventsCache),
    ]);

    const handleCheckInSuccess = (eventId: number) => {
        setCheckedInEventsCache((prev) => new Set(prev).add(eventId));
    };

    useEffect(() => {
        setCheckedInEventsCache(new Set());
    }, [student]);

    return (
        <>
            <Head title="Student Check-in Hub" />

            <div className="w-full min-h-screen bg-gray-50 dark:bg-[#030712] text-gray-900 dark:text-white p-6 space-y-6 transition-colors duration-200">
                
                {/* HEADER INFO */}
                <div className="flex w-full items-center justify-between rounded-xl bg-white dark:bg-[#090d16] p-6 shadow-sm border border-gray-100 dark:border-slate-800/60">
                    <div>
                        <h1 className="text-xl font-bold text-gray-900 dark:text-white">
                            Attendance Check-In Hub
                        </h1>
                        <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                            Select an ongoing event below to verify your identity and record your attendance.
                        </p>
                    </div>
                    <div className="flex items-center gap-1.5 rounded-full bg-emerald-50 dark:bg-emerald-950/30 px-3 py-1.5 text-xs font-semibold text-emerald-700 dark:text-emerald-400 border border-emerald-200 dark:border-emerald-800/40">
                        <ShieldCheck className="h-4 w-4" />
                        <span>Biometrics ready</span>
                    </div>
                </div>

                {/* ACTIVE EVENTS GRID / LIST */}
                <div className="w-full rounded-xl bg-white dark:bg-[#090d16] shadow-sm border border-gray-100 dark:border-slate-800/60 overflow-hidden">
                    <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100 dark:border-slate-800/60">
                        <h2 className="text-base font-bold text-gray-900 dark:text-white">Events open for check-in</h2>
                        <span className="text-xs text-gray-400 dark:text-gray-500">{activeEvents.length} available</span>
                    </div>

                    {activeEvents.length === 0 ? (
                        <div className="flex flex-col items-center justify-center py-16 text-center">
                            <Calendar className="h-12 w-12 mb-3 stroke-1 text-gray-400 dark:text-gray-600" aria-hidden="true" />
                            <p className="text-sm font-medium text-gray-600 dark:text-gray-300">No active events right now</p>
                            <p className="text-xs text-gray-400 dark:text-gray-500 mt-1">Check back when your scheduled event window opens.</p>
                        </div>
                    ) : (
                        <ul className="divide-y divide-gray-100 dark:divide-slate-800/60">
                            {activeEvents.map((evt) => {
                                const isCheckedIn = checkedInEventIds.has(evt.event_id);
                                return (
                                    <li key={evt.event_id}>
                                        <div className="w-full flex items-center gap-4 px-6 py-5 text-left">
                                            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-indigo-50 dark:bg-slate-800/80 text-[#1B1F5C] dark:text-amber-400">
                                                <Clock className="h-5 w-5" aria-hidden="true" />
                                            </div>

                                            <div className="min-w-0 flex-1">
                                                <p className="text-sm font-bold text-gray-900 dark:text-white truncate">{evt.title}</p>
                                                <p className="mt-1 text-xs text-gray-500 dark:text-gray-400 truncate">
                                                    {evt.start_time && (
                                                        <span>{formatEventTime(evt.start_time, evt.end_time)}</span>
                                                    )}
                                                    {evt.location ? ` · ${evt.location}` : ' · Location TBA'}
                                                </p>
                                            </div>

                                            {isCheckedIn ? (
                                                <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 dark:bg-emerald-950/30 px-3.5 py-1.5 text-xs font-medium text-emerald-700 dark:text-emerald-400 border border-emerald-200 dark:border-emerald-800/40 shrink-0">
                                                    <CheckCircle2 className="h-4 w-4" aria-hidden="true" />
                                                    Checked in
                                                </span>
                                            ) : (
                                                <button
                                                    onClick={() => setSelectedEvent(evt)}
                                                    className="inline-flex items-center gap-1.5 rounded-lg px-5 py-2 text-xs font-semibold text-white shrink-0 transition-colors shadow-sm hover:opacity-95"
                                                    style={{ backgroundColor: GOLD }}
                                                >
                                                    <Camera className="h-4 w-4" />
                                                    Start Check-in
                                                </button>
                                            )}
                                        </div>
                                    </li>
                                );
                            })}
                        </ul>
                    )}
                </div>
            </div>

            {selectedEvent && (
                <CheckInModal 
                    event={selectedEvent} 
                    onClose={() => setSelectedEvent(null)} 
                    onSuccess={handleCheckInSuccess}
                />
            )}
        </>
    );
}

type CheckInModalProps = {
    event: Event;
    onClose: () => void;
    onSuccess: (eventId: number) => void;
};

function CheckInModal({ event, onClose, onSuccess }: CheckInModalProps) {
    const videoRef = useRef<HTMLVideoElement | null>(null);
    const landmarkerRef = useRef<FaceLandmarker | null>(null);
    const requestRef = useRef<number | null>(null);
    const mountedRef = useRef(true);

    const stepRef = useRef<LivenessStep>('LOOK_CENTER');
    const lastVideoTimeRef = useRef(-1);
    const lastProcessTimeRef = useRef(0);
    const holdCountRef = useRef(0);
    const turnHoldRef = useRef(0);
    const challengeStartRef = useRef<number | null>(null);
    const hasSubmittedRef = useRef(false);

    const frontalFrameRef = useRef<Promise<Blob | null> | null>(null);
    const peakFrameRef = useRef<Promise<Blob | null> | null>(null);

    const [step, setStep] = useState<LivenessStep>('LOOK_CENTER');
    const [streamStarted, setStreamStarted] = useState(false);
    const [modelReady, setModelReady] = useState(false);
    const [cameraError, setCameraError] = useState<string | null>(null);
    const [modalError, setModalError] = useState<string | null>(null);
    const [successMessage, setSuccessMessage] = useState<string | null>(null);
    const [hint, setHint] = useState<string | null>(null);
    const [isSubmitting, setIsSubmitting] = useState(false);

    const stopCameraStream = () => {
        if (videoRef.current?.srcObject) {
            const stream = videoRef.current.srcObject as MediaStream;
            stream.getTracks().forEach((track) => track.stop());
            videoRef.current.srcObject = null;
        }
    };
    
    const [direction] = useState<Direction>(() => {
        const bytes = new Uint8Array(1);
        crypto.getRandomValues(bytes);
        return bytes[0] % 2 === 0 ? 'left' : 'right';
    });

    const goToStep = (next: LivenessStep) => {
        if (stepRef.current === next) return;
        stepRef.current = next;
        setStep(next);
    };

    const resetChallenge = () => {
        holdCountRef.current = 0;
        turnHoldRef.current = 0;
        hasSubmittedRef.current = false;
        challengeStartRef.current = null;
        frontalFrameRef.current = null;
        peakFrameRef.current = null;
        goToStep('LOOK_CENTER');
    };

    const initializeCameraAndModel = async () => {
        setCameraError(null);
        setModalError(null);
        setStreamStarted(false);
        setModelReady(false);

        const landmarkerPromise = createLandmarker();

        try {
            let stream: MediaStream;
            try {
                stream = await navigator.mediaDevices.getUserMedia(VIDEO_CONSTRAINTS);
            } catch (err) {
                stream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
            }

            if (!mountedRef.current || !videoRef.current) {
                stream.getTracks().forEach((t) => t.stop());
                return;
            }

            videoRef.current.srcObject = stream;
        } catch (error) {
            if (mountedRef.current) {
                setCameraError(describeCameraError(error));
            }
            return;
        }

        try {
            const landmarker = await landmarkerPromise;
            if (!mountedRef.current) return;
            landmarkerRef.current = landmarker;
            setModelReady(true);
        } catch (error) {
            if (mountedRef.current) {
                setCameraError('Unable to load face detection model.');
            }
        }
    };

    useEffect(() => {
        mountedRef.current = true;
        initializeCameraAndModel();

        return () => {
            mountedRef.current = false;
            if (requestRef.current !== null) cancelAnimationFrame(requestRef.current);
            stopCameraStream();
            landmarkerRef.current = null;
        };
    }, []);

    useEffect(() => {
        if (!streamStarted || !modelReady || modalError !== null || successMessage !== null) return;

        let stopped = false;

        const tick = (now: DOMHighResTimeStamp) => {
            if (stopped) return;
            if (stepRef.current === 'VERIFYING' || stepRef.current === 'PASSED') return;

            requestRef.current = requestAnimationFrame(tick);

            if (now - lastProcessTimeRef.current < PROCESS_INTERVAL_MS) return;
            lastProcessTimeRef.current = now;

            const video = videoRef.current;
            const landmarker = landmarkerRef.current;
            if (!video || !landmarker || video.readyState < 2) return;

            if (video.currentTime === lastVideoTimeRef.current) return;
            lastVideoTimeRef.current = video.currentTime;

            let faces: Landmark[][];
            try {
                faces = landmarker.detectForVideo(video, now).faceLandmarks ?? [];
            } catch (error) {
                return;
            }

            if (faces.length === 0) {
                setHint(null);
                resetChallenge();
                return;
            }

            if (faces.length > 1) {
                setHint('Only one face should be visible.');
                resetChallenge();
                return;
            }

            const landmarks = faces[0];
            const yaw = calculateYaw(landmarks);
            const turned = yaw * DIRECTION_SIGN[direction];

            switch (stepRef.current) {
                case 'LOOK_CENTER': {
                    const placementIssue = getPlacementIssue(landmarks);
                    if (placementIssue) {
                        holdCountRef.current = 0;
                        setHint(placementIssue);
                        break;
                    }

                    if (Math.abs(yaw) > FRONTAL_YAW_MAX) {
                        holdCountRef.current = 0;
                        setHint('Look straight at the camera.');
                        break;
                    }

                    setHint(null);
                    holdCountRef.current += 1;

                    if (holdCountRef.current >= FRONTAL_HOLD_FRAMES) {
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
                        setHint('Time ran out. Let’s try again.');
                        break;
                    }

                    if (turned <= -WRONG_WAY_YAW) {
                        turnHoldRef.current = 0;
                        setHint(`Turn to your ${direction}, not the other way.`);
                        break;
                    }

                    setHint(null);

                    if (turned >= TURN_YAW_MIN) {
                        turnHoldRef.current += 1;
                        if (turnHoldRef.current >= TURN_HOLD_FRAMES) {
                            peakFrameRef.current = captureFrame(video);
                            void submitAttendance(frontalFrameRef.current, peakFrameRef.current);
                            return;
                        }
                    } else {
                        turnHoldRef.current = 0;
                    }
                    break;
                }
            }
        };

        requestRef.current = requestAnimationFrame(tick);

        return () => {
            stopped = true;
            if (requestRef.current !== null) cancelAnimationFrame(requestRef.current);
        };
    }, [streamStarted, modelReady, modalError, successMessage, direction]);

    const submitAttendance = async (
        frontalPromise: Promise<Blob | null> | null,
        peakPromise: Promise<Blob | null> | null
    ) => {
        if (hasSubmittedRef.current) return;
        hasSubmittedRef.current = true;
        
        stopCameraStream();
        
        goToStep('VERIFYING');
        setIsSubmitting(true);
        setHint(null);

        try {
            const [frontal, peak] = await Promise.all([frontalPromise, peakPromise]);
            if (!frontal || !peak) throw new Error('Failed to capture camera frames.');

            const formData = new FormData();
            formData.append('event_id', String(event.event_id));
            formData.append('live_camera_frame', frontal, 'frontal.jpg');
            formData.append('turn_peak_frame', peak, 'turn-peak.jpg');
            formData.append('direction', direction);

            router.post('/attendance/check-in', formData, {
                forceFormData: true,
                onSuccess: () => {
                    setIsSubmitting(false);
                    goToStep('PASSED');
                    setSuccessMessage('Successfully checked in!');
                    onSuccess(event.event_id);

                    // Tell Inertia to immediately fetch fresh props from the server
                    router.reload({ only: ['student', 'activeEvents'] });

                    setTimeout(() => onClose(), 1800);
                },
                onError: (errors: any) => {
                    setIsSubmitting(false);
                    setModalError(errors.attendance || errors.live_camera_frame || 'Verification failed.');
                },
            });
        
        } catch (err) {
            setIsSubmitting(false);
            setModalError('Failed to process frames.');
        }
    };

    const instruction = (() => {
        switch (step) {
            case 'LOOK_CENTER':
                return { text: 'Look straight at the camera', icon: Eye, spin: false };
            case 'TURN':
                return { text: `Turn your head to your ${direction}`, icon: direction === 'left' ? ArrowLeft : ArrowRight, spin: false };
            case 'VERIFYING':
                return { text: 'Verifying attendance...', icon: RefreshCw, spin: true };
            case 'PASSED':
                return { text: 'Checked in successfully!', icon: CheckCircle2, spin: false };
            default:
                return { text: 'Look straight at the camera', icon: Eye, spin: false };
        }
    })();
    const ActiveIcon = instruction.icon;

    return (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm" onClick={(e) => { if (e.target === e.currentTarget && !isSubmitting) onClose(); }}>
            <div className="w-full max-w-md rounded-2xl bg-white dark:bg-[#090d16] text-gray-900 dark:text-white shadow-2xl overflow-hidden border border-gray-100 dark:border-slate-800 relative">
                
                <div className="relative px-6 pt-6 pb-4 border-b border-gray-100 dark:border-slate-800">
                    <button onClick={onClose} disabled={isSubmitting} className="absolute right-4 top-4 rounded-full p-1 text-gray-400 hover:bg-gray-100 dark:hover:bg-slate-800">
                        <X className="h-5 w-5" />
                    </button>
                    <h2 className="text-lg font-bold pr-8">{event.title}</h2>
                    <p className="mt-1 text-xs text-gray-500">Active Liveness Attendance Check-in</p>
                </div>

                <div className="flex flex-col items-center px-6 py-6">
                    {successMessage ? (
                        <div className="flex flex-col items-center justify-center py-10 space-y-3 animate-fade-in">
                            <div className="flex h-16 w-16 items-center justify-center rounded-full bg-emerald-100 dark:bg-emerald-950 text-emerald-600 dark:text-emerald-400 border border-emerald-200 dark:border-emerald-800">
                                <Check className="h-8 w-8 animate-bounce" />
                            </div>
                            <h3 className="text-base font-bold text-gray-900 dark:text-white">{successMessage}</h3>
                            <p className="text-xs text-gray-500 dark:text-gray-400">Updating status...</p>
                        </div>
                    ) : (
                        <>
                            <div className={`relative h-48 w-48 overflow-hidden rounded-full border-4 ${step === 'PASSED' ? 'border-emerald-500' : 'border-[#1B1F5C] dark:border-amber-400'} bg-black mb-3 transition-colors duration-300`}>
                                <video 
                                    ref={videoRef} 
                                    autoPlay 
                                    playsInline 
                                    muted 
                                    onCanPlay={() => setStreamStarted(true)}
                                    className={`h-full w-full object-cover scale-x-[-1] transition-opacity duration-300 ${(!streamStarted || !modelReady) ? 'opacity-0' : 'opacity-100'}`} 
                                />

                                {(!streamStarted || !modelReady) && !cameraError && (
                                    <div className="absolute inset-0 flex flex-col items-center justify-center bg-gray-900/90 text-white p-4 text-center z-10">
                                        <Loader2 className="h-8 w-8 animate-spin text-[#C9973E] mb-2" />
                                        <p className="text-[11px] font-medium">
                                            {!streamStarted ? 'Opening camera...' : 'Initializing AI model...'}
                                        </p>
                                    </div>
                                )}

                                <div className="pointer-events-none absolute inset-2 rounded-full border-2 border-dashed border-[#F5A623] animate-pulse z-20" />
                                
                                {step === 'TURN' && (
                                    <div className={`absolute top-1/2 -translate-y-1/2 rounded-full bg-black/60 p-2 text-white z-30 ${direction === 'left' ? 'left-2' : 'right-2'}`}>
                                        <ActiveIcon className="h-6 w-6 animate-pulse" />
                                    </div>
                                )}
                            </div>

                            <div className={`flex items-center gap-2 rounded-lg px-3 py-2 text-xs font-semibold border mb-2 transition-colors duration-200 ${
                                step === 'PASSED' 
                                    ? 'bg-emerald-50 dark:bg-emerald-950/30 text-emerald-800 dark:text-emerald-400 border-emerald-200 dark:border-emerald-800/40' 
                                    : 'bg-amber-50 dark:bg-amber-950/30 text-amber-800 dark:text-amber-400 border-amber-200 dark:border-amber-800/40'
                            }`}>
                                <ActiveIcon className={`h-4 w-4 shrink-0 ${instruction.spin ? 'animate-spin' : ''}`} />
                                <span>{instruction.text}</span>
                            </div>

                            {hint && <p className="text-[11px] text-amber-600 dark:text-amber-400 text-center">{hint}</p>}
                            
                            {modalError && (
                                <div className="mt-2 flex flex-col items-center gap-2">
                                    <p className="text-[11px] text-red-600 text-center">{modalError}</p>
                                    <button 
                                        onClick={() => { setModalError(null); resetChallenge(); }}
                                        className="mt-1 rounded-full bg-gray-100 dark:bg-slate-800 px-3 py-1 text-[11px] font-semibold text-gray-700 dark:text-gray-300"
                                    >
                                        Try Again
                                    </button>
                                </div>
                            )}

                            {cameraError && (
                                <div className="mt-2 flex flex-col items-center gap-2">
                                    <p className="text-[11px] text-red-600 text-center">{cameraError}</p>
                                    <button 
                                        onClick={initializeCameraAndModel}
                                        className="mt-1 rounded-full bg-indigo-50 dark:bg-slate-800 px-4 py-1 text-[11px] font-semibold text-[#1B1F5C] dark:text-amber-400 border border-indigo-200 dark:border-slate-700"
                                    >
                                        Retry Camera
                                    </button>
                                </div>
                            )}
                        </>
                    )}
                </div>
            </div>
        </div>
    );
}