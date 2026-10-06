import React, { useState, useRef, useEffect } from 'react';
import { router } from '@inertiajs/react';
import type { FaceLandmarker } from '@mediapipe/tasks-vision';
import {
    CheckCircle2,
    X,
    ArrowLeft,
    ArrowRight,
    Loader2,
    Eye,
    AlertTriangle,
} from 'lucide-react';
import {
    type Direction,
    type Landmark,
    VIDEO_CONSTRAINTS,
    DIRECTION_SIGN,
    calculateYaw,
    getPlacementIssue,
    captureFrame,
    randomDirection,
    describeCameraError,
    describeGeolocationError,
    getSharedLandmarker,
    distanceInMeters,
} from '@/lib/liveness';
import { type TimeSlot } from '@/lib/eventValidation';

type Event = {
    event_id: number;
    title: string;
    description?: string | null;
    event_date: string;
    start_time: string;
    end_time?: string | null;
    location?: string | null;
    is_active?: boolean;
    geofence_enabled?: boolean;
    latitude?: number | null;
    longitude?: number | null;
    radius_meters?: number | null;
};

type LivenessStep = 'LOOK_CENTER' | 'TURN' | 'VERIFYING' | 'PASSED';
type SetupStage = 'LOCATING' | 'STARTING_CAMERA' | 'READY';

const GOLD = '#C9973E';
const PROCESS_EVERY_N_FRAMES = 3;
const FRONTAL_YAW_MAX = 0.12;
const FRONTAL_HOLD_FRAMES = 8;
const TURN_YAW_MIN = 0.25;
const TURN_HOLD_FRAMES = 3;
const WRONG_WAY_YAW = 0.15;
const CHALLENGE_TIMEOUT_MS = 20_000;
const LOW_ACCURACY_WARNING_METERS = 100;

type CheckInModalProps = {
    event: Event;
    slot: TimeSlot;
    slotIndex: number;
    dateStr: string;
    type: 'in' | 'out';
    onClose: () => void;
};

export default function CheckInModal({ event, slot, slotIndex, dateStr, type, onClose }: CheckInModalProps) {
    const videoRef = useRef<HTMLVideoElement | null>(null);
    const landmarkerRef = useRef<FaceLandmarker | null>(null);
    const requestRef = useRef<number | null>(null);
    const mountedRef = useRef(true);

    const stepRef = useRef<LivenessStep>('LOOK_CENTER');
    const frameCountRef = useRef(0);
    const lastVideoTimeRef = useRef(-1);
    const holdCountRef = useRef(0);
    const turnHoldRef = useRef(0);
    const challengeStartRef = useRef<number | null>(null);
    const hasSubmittedRef = useRef(false);

    const frontalFrameRef = useRef<Promise<Blob | null> | null>(null);
    const peakFrameRef = useRef<Promise<Blob | null> | null>(null);

    const [step, setStep] = useState<LivenessStep>('LOOK_CENTER');
    const [setupStage, setSetupStage] = useState<SetupStage>('LOCATING');
    const [streamStarted, setStreamStarted] = useState(false);
    const [modelReady, setModelReady] = useState(false);
    const [cameraError, setCameraError] = useState<string | null>(null);
    const [locationError, setLocationError] = useState<string | null>(null);
    const [modalError, setModalError] = useState<string | null>(null);
    const [accuracyWarning, setAccuracyWarning] = useState<string | null>(null);
    const [hint, setHint] = useState<string | null>(null);
    const [holdProgress, setHoldProgress] = useState(0);
    const [turnProgress, setTurnProgress] = useState(0);
    const [retryToken, setRetryToken] = useState(0);

    const [userCoords, setUserCoords] = useState<{ latitude: number; longitude: number } | null>(null);
    const [direction, setDirection] = useState<Direction>(randomDirection);

    const isReady = setupStage === 'READY' && streamStarted && modelReady;
    const blockingError = locationError ?? cameraError ?? modalError;

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
        setHoldProgress(0);
        setTurnProgress(0);
        goToStep('LOOK_CENTER');
    };

    const stopCameraStream = () => {
        if (requestRef.current !== null) {
            cancelAnimationFrame(requestRef.current);
            requestRef.current = null;
        }
        if (videoRef.current?.srcObject) {
            (videoRef.current.srcObject as MediaStream).getTracks().forEach((t) => t.stop());
            videoRef.current.srcObject = null;
        }
        setStreamStarted(false);
    };

    useEffect(() => {
        mountedRef.current = true;
        setCameraError(null);
        setLocationError(null);
        setModalError(null);
        setAccuracyWarning(null);
        setSetupStage('LOCATING');

        const verifyLocationAndInitialize = async () => {
            if (!navigator.geolocation) {
                if (mountedRef.current) setLocationError('Geolocation is not supported by your browser.');
                return;
            }

            navigator.geolocation.getCurrentPosition(
                async (position) => {
                    if (!mountedRef.current) return;

                    const { latitude, longitude, accuracy } = position.coords;
                    setUserCoords({ latitude, longitude });

                    if (accuracy > LOW_ACCURACY_WARNING_METERS) {
                        setAccuracyWarning(
                            `Your GPS signal is weak (±${Math.round(accuracy)}m). Move outdoors or away from tall buildings for a more reliable check-in.`,
                        );
                    }

                    if (event.geofence_enabled && event.latitude && event.longitude && event.radius_meters) {
                        const distance = distanceInMeters(latitude, longitude, event.latitude, event.longitude);
                        if (distance > event.radius_meters) {
                            setLocationError(
                                `You are outside the event area. Move about ${Math.round(distance - event.radius_meters)}m closer to check in.`,
                            );
                            return;
                        }
                    }

                    setSetupStage('STARTING_CAMERA');
                    await initializeCameraAndModel();
                },
                (error) => {
                    if (mountedRef.current) setLocationError(describeGeolocationError(error));
                },
                { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 },
            );
        };

        async function initializeCameraAndModel() {
            const landmarkerPromise = getSharedLandmarker();
            landmarkerPromise.catch(() => {});

            try {
                const stream = await navigator.mediaDevices.getUserMedia(VIDEO_CONSTRAINTS);
                if (!mountedRef.current || !videoRef.current) {
                    stream.getTracks().forEach((t) => t.stop());
                    return;
                }
                videoRef.current.srcObject = stream;
                await videoRef.current.play().catch(() => {});
                lastVideoTimeRef.current = -1;
                setStreamStarted(true);
            } catch (error) {
                if (mountedRef.current) setCameraError(describeCameraError(error));
                return;
            }

            try {
                const landmarker = await landmarkerPromise;
                if (!mountedRef.current) return;
                landmarkerRef.current = landmarker;
                setModelReady(true);
                setSetupStage('READY');
            } catch (error) {
                if (mountedRef.current) setCameraError('Unable to load face detection. Check your connection and try again.');
            }
        }

        verifyLocationAndInitialize();

        return () => {
            mountedRef.current = false;
            stopCameraStream();
            landmarkerRef.current = null;
        };
    }, [event, retryToken]);

    useEffect(() => {
        if (!isReady || blockingError) return;

        let stopped = false;

        const processFrame = () => {
            const video = videoRef.current;
            const landmarker = landmarkerRef.current;

            if (!video || !landmarker || video.readyState < 2) return;
            if (video.currentTime === lastVideoTimeRef.current) return;

            lastVideoTimeRef.current = video.currentTime;

            let faces: Landmark[][] = [];

            try {
                const result = landmarker.detectForVideo(video, performance.now());
                faces = result.faceLandmarks ?? [];
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
                        setHoldProgress(0);
                        setHint(placementIssue);
                        return;
                    }

                    if (Math.abs(yaw) > FRONTAL_YAW_MAX) {
                        holdCountRef.current = 0;
                        setHoldProgress(0);
                        setHint('Look straight at the camera.');
                        return;
                    }

                    setHint(null);
                    holdCountRef.current += 1;
                    setHoldProgress(Math.min(holdCountRef.current / FRONTAL_HOLD_FRAMES, 1));

                    if (holdCountRef.current >= FRONTAL_HOLD_FRAMES) {
                        frontalFrameRef.current = captureFrame(video, { quality: 0.7 });
                        challengeStartRef.current = performance.now();
                        turnHoldRef.current = 0;
                        goToStep('TURN');
                    }
                    return;
                }

                case 'TURN': {
                    const startedAt = challengeStartRef.current ?? performance.now();
                    if (performance.now() - startedAt > CHALLENGE_TIMEOUT_MS) {
                        resetChallenge();
                        setHint("Time ran out. Let's try again.");
                        return;
                    }

                    if (turned <= -WRONG_WAY_YAW) {
                        turnHoldRef.current = 0;
                        setTurnProgress(0);
                        setHint(`Turn to your ${direction}, not the other way.`);
                        return;
                    }

                    setHint(null);
                    setTurnProgress(Math.min(Math.max(turned / TURN_YAW_MIN, 0), 1));

                    if (turned >= TURN_YAW_MIN) {
                        turnHoldRef.current += 1;
                        if (turnHoldRef.current >= TURN_HOLD_FRAMES) {
                            peakFrameRef.current = captureFrame(video, { quality: 0.7 });
                            void submitAttendance(frontalFrameRef.current, peakFrameRef.current);
                            return;
                        }
                    } else {
                        turnHoldRef.current = 0;
                    }
                    return;
                }

                case 'VERIFYING':
                case 'PASSED':
                    return;
            }
        };

        const tick = () => {
            if (stopped) return;
            if (String(stepRef.current) === 'VERIFYING' || String(stepRef.current) === 'PASSED') return;

            frameCountRef.current += 1;
            if (frameCountRef.current % PROCESS_EVERY_N_FRAMES === 0) {
                processFrame();
            }

            if (String(stepRef.current) === 'VERIFYING' || String(stepRef.current) === 'PASSED') return;
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
    }, [isReady, blockingError, direction]);

    const submitAttendance = async (
        frontalPromise: Promise<Blob | null> | null,
        peakPromise: Promise<Blob | null> | null,
    ) => {
        if (hasSubmittedRef.current) return;
        hasSubmittedRef.current = true;
        goToStep('VERIFYING');
        setHint(null);

        try {
            const [frontal, peak] = await Promise.all([frontalPromise, peakPromise]);
            if (!frontal || !peak) throw new Error('Failed to capture camera frames.');

            stopCameraStream();

            const formData = new FormData();
            formData.append('event_id', String(event.event_id));
            formData.append('slot_index', String(slotIndex));
            formData.append('type', type);
            formData.append('live_camera_frame', frontal, 'frontal.jpg');
            formData.append('turn_peak_frame', peak, 'turn-peak.jpg');
            formData.append('direction', direction);

            if (userCoords) {
                formData.append('latitude', String(userCoords.latitude));
                formData.append('longitude', String(userCoords.longitude));
            }

            router.post('/attendance/check-in', formData, {
                forceFormData: true,
                onSuccess: () => {
                    goToStep('PASSED');
                    setTimeout(() => {
                        stopCameraStream();
                        onClose();
                    }, 1200);
                },
                onError: (errors: Record<string, string>) => {
                    setModalError(errors.attendance || errors.live_camera_frame || 'Verification failed.');
                },
            });
        } catch {
            setModalError('Failed to process the camera frames. Please try again.');
        }
    };

    const handleRetry = () => {
        stopCameraStream();
        hasSubmittedRef.current = false;
        setModelReady(false);
        setDirection(randomDirection());
        resetChallenge();
        setRetryToken((n) => n + 1);
    };

    const instruction = (() => {
        if (setupStage === 'LOCATING') return { text: 'Acquiring GPS location...', icon: Loader2, spin: true };
        if (setupStage === 'STARTING_CAMERA') return { text: 'Starting camera...', icon: Loader2, spin: true };
        switch (step) {
            case 'LOOK_CENTER':
                return { text: 'Look straight at the camera', icon: Eye, spin: false };
            case 'TURN':
                return { text: `Turn your head to your ${direction}`, icon: direction === 'left' ? ArrowLeft : ArrowRight, spin: false };
            case 'VERIFYING':
                return { text: 'Verifying attendance...', icon: Loader2, spin: true };
            case 'PASSED':
                return { text: type === 'in' ? 'Checked in successfully!' : 'Checked out successfully!', icon: CheckCircle2, spin: false };
        }
    })();
    const ActiveIcon = instruction.icon;
    const isSettingUp = setupStage !== 'READY';

    return (
        <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="checkin-title"
            className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
            onClick={(e) => {
                if (e.target === e.currentTarget) {
                    stopCameraStream();
                    onClose();
                }
            }}
        >
            <div className="w-full max-w-md rounded-2xl bg-white dark:bg-[#090d16] text-gray-900 dark:text-white shadow-2xl overflow-hidden border border-gray-100 dark:border-slate-800">
                <div className="relative px-6 pt-6 pb-4 border-b border-gray-100 dark:border-slate-800">
                    <button onClick={() => { stopCameraStream(); onClose(); }} className="absolute right-4 top-4 rounded-full p-1 text-gray-400 hover:bg-gray-100 dark:hover:bg-slate-800">
                        <X className="h-5 w-5" />
                    </button>
                    <h2 id="checkin-title" className="text-lg font-bold pr-8">{event.title}</h2>
                    <p className="mt-1 text-xs text-gray-500">
                        {type === 'in' ? 'Slot Check-In' : 'Slot Check-Out'} ({dateStr})
                    </p>
                </div>

                <div className="flex flex-col items-center px-6 py-6">
                    <div className="relative h-48 w-48 overflow-hidden rounded-full border-4 border-[#1B1F5C] dark:border-amber-400 bg-black mb-3">
                        <video
                            ref={videoRef}
                            autoPlay
                            playsInline
                            muted
                            className={`h-full w-full object-cover scale-x-[-1] ${isSettingUp || blockingError ? 'opacity-0' : 'opacity-100'}`}
                        />

                        {isSettingUp && !blockingError && (
                            <div className="absolute inset-0 flex flex-col items-center justify-center bg-gray-900/90 text-white p-4 text-center z-10">
                                <Loader2 className="h-8 w-8 animate-spin text-[#C9973E] mb-2" />
                                <p className="text-[11px] font-medium">{instruction.text}</p>
                            </div>
                        )}

                        {blockingError && (
                            <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 bg-gray-900/95 text-white p-4 text-center z-10">
                                <AlertTriangle className="h-7 w-7 text-rose-400" />
                                <p className="text-[11px] font-medium leading-relaxed">{blockingError}</p>
                                <button
                                    type="button"
                                    onClick={handleRetry}
                                    className="mt-1 rounded-full px-4 py-1.5 text-xs font-semibold text-white"
                                    style={{ backgroundColor: GOLD }}
                                >
                                    Try again
                                </button>
                            </div>
                        )}

                        {!isSettingUp && !blockingError && (
                            <div className="pointer-events-none absolute inset-2 rounded-full border-2 border-dashed border-[#F5A623] animate-pulse" />
                        )}

                        {step === 'TURN' && !isSettingUp && !blockingError && (
                            <div className={`absolute top-1/2 -translate-y-1/2 rounded-full bg-black/60 p-2 text-white ${direction === 'left' ? 'left-2' : 'right-2'}`}>
                                <ActiveIcon className="h-6 w-6 animate-pulse" />
                            </div>
                        )}
                    </div>

                    {!blockingError && (
                        <div className="flex items-center gap-2 rounded-lg bg-amber-50 dark:bg-amber-950/30 px-3 py-2 text-xs font-semibold text-amber-800 dark:text-amber-400 border border-amber-200 dark:border-amber-800/40 mb-2">
                            <ActiveIcon className={`h-4 w-4 shrink-0 ${instruction.spin ? 'animate-spin' : ''}`} />
                            <span>{instruction.text}</span>
                        </div>
                    )}

                    {!blockingError && step === 'LOOK_CENTER' && !isSettingUp && (
                        <div className="h-1 w-40 overflow-hidden rounded-full bg-gray-100 dark:bg-slate-800" aria-hidden="true">
                            <div
                                className="h-full bg-[#1B1F5C] dark:bg-amber-400 transition-[width] duration-150"
                                style={{ width: `${Math.round(holdProgress * 100)}%` }}
                            />
                        </div>
                    )}
                    {!blockingError && step === 'TURN' && (
                        <div className="h-1 w-40 overflow-hidden rounded-full bg-gray-100 dark:bg-slate-800" aria-hidden="true">
                            <div
                                className="h-full bg-[#1B1F5C] dark:bg-amber-400 transition-[width] duration-150"
                                style={{ width: `${Math.round(turnProgress * 100)}%` }}
                            />
                        </div>
                        
                    )}

                    {accuracyWarning && !blockingError && (
                        <p className="mt-2 flex items-start gap-1.5 text-[11px] text-amber-600 dark:text-amber-400 text-center">
                            <AlertTriangle className="h-3.5 w-3.5 shrink-0 mt-0.5" />
                            <span>{accuracyWarning}</span>
                        </p>
                    )}

                    {hint && !blockingError && <p className="mt-2 text-[11px] text-amber-600 dark:text-amber-400 text-center">{hint}</p>}
                </div>
            </div>
        </div>
    );
}