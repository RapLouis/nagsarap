import React, { useState, useRef, useEffect } from 'react';
import { Head, Link, router } from '@inertiajs/react';
import type { FaceLandmarker } from '@mediapipe/tasks-vision';
import {
    Camera,
    CheckCircle2,
    AlertCircle,
    Calendar,
    Clock,
    ShieldCheck,
    RefreshCw,
    MapPin,
    X,
    ChevronRight,
    TrendingUp,
    ListChecks,
    CalendarClock,
    Eye,
    ArrowLeft,
    ArrowRight,
    Loader2,
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

type DashboardProps = {
    student: Student;
    activeEvents: Event[];
    upcomingEvents?: Event[];
    totalExpectedEvents?: number;
};

type Direction = 'left' | 'right';
type LivenessStep = 'DETECT' | 'LOOK_CENTER' | 'TURN' | 'VERIFYING' | 'PASSED';
type Landmark = { x: number; y: number };

const GOLD = '#C9973E';
const GOLD_DARK = '#B0812E';

// MediaPipe Configuration Constants
const MEDIAPIPE_VERSION = '0.10.21';
const WASM_URL = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MEDIAPIPE_VERSION}/wasm`;
const MODEL_URL = 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task';

const VIDEO_CONSTRAINTS: MediaStreamConstraints = {
    video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: 'user' },
    audio: false,
};

const PROCESS_EVERY_N_FRAMES = 3;
const FRONTAL_YAW_MAX = 0.12;
const FRONTAL_HOLD_FRAMES = 8;
const MID_TURN_YAW = 0.15;
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
    const width = Math.min(video.videoWidth || 640, 640);
    const height = Math.min(video.videoHeight || 480, 480);
    
    canvas.width = width;
    canvas.height = height;

    const context = canvas.getContext('2d', { alpha: false });
    if (!context) return Promise.resolve(null);

    context.drawImage(video, 0, 0, width, height);

    return new Promise((resolve) => {
        canvas.toBlob((blob) => resolve(blob), 'image/jpeg', 0.70);
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

async function createLandmarker(): Promise<FaceLandmarker> {
    const { FaceLandmarker, FilesetResolver } = await import('@mediapipe/tasks-vision');
    const vision = await FilesetResolver.forVisionTasks(WASM_URL);

    const create = (delegate: 'GPU' | 'CPU') =>
        FaceLandmarker.createFromOptions(vision, {
            baseOptions: { modelAssetPath: MODEL_URL, delegate },
            runningMode: 'VIDEO',
            numFaces: 2,
            minFaceDetectionConfidence: 0.5,
            minFacePresenceConfidence: 0.5,
            minTrackingConfidence: 0.5,
        });

    try {
        return await create('GPU');
    } catch (error) {
        return await create('CPU');
    }
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

export default function Dashboard({
    student,
    activeEvents,
    upcomingEvents = [],
    totalExpectedEvents,
}: DashboardProps) {
    const [selectedEvent, setSelectedEvent] = useState<Event | null>(null);

    const checkedInEventIds = new Set(
        student.attendances
            .filter((log) => log.status?.toLowerCase() === 'present' || log.status?.toLowerCase() === 'verified')
            .map((log) => log.event?.event_id)
    );

    const eventsAttended = student.attendances.length;
    const attendanceRate =
        totalExpectedEvents && totalExpectedEvents > 0
            ? Math.round((eventsAttended / totalExpectedEvents) * 100)
            : null;

    const recentAttendances = [...student.attendances]
        .sort((a, b) => new Date(b.logged_at).getTime() - new Date(a.logged_at).getTime())
        .slice(0, 3);

    return (
        <>
            <Head title="Student Dashboard" />

            <div className="w-full min-h-screen bg-gray-50 dark:bg-[#030712] text-gray-900 dark:text-white p-6 space-y-6 transition-colors duration-200">
                
                {/* WELCOME HEADER */}
                <div className="flex w-full items-center justify-between rounded-xl bg-white dark:bg-[#090d16] p-6 shadow-sm border border-gray-100 dark:border-slate-800/60">
                    <div>
                        <h1 className="text-xl font-bold text-gray-900 dark:text-white">
                            Welcome back, {student.firstname} {student.surname}
                        </h1>
                        <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">Student ID {student.student_number}</p>
                    </div>
                    <div className="flex items-center gap-1.5 rounded-full bg-emerald-50 dark:bg-emerald-950/30 px-3 py-1.5 text-xs font-semibold text-emerald-700 dark:text-emerald-400 border border-emerald-200 dark:border-emerald-800/40">
                        <ShieldCheck className="h-4 w-4" />
                        <span>Biometrics verified</span>
                    </div>
                </div>

                {/* STAT CARDS ROW */}
                <div className="grid w-full grid-cols-1 sm:grid-cols-3 gap-4">
                    <StatCard
                        icon={<TrendingUp className="h-5 w-5 text-[#1B1F5C] dark:text-amber-400" aria-hidden="true" />}
                        label="Attendance rate"
                        value={attendanceRate !== null ? `${attendanceRate}%` : '—'}
                        caption={
                            totalExpectedEvents
                                ? `${eventsAttended} of ${totalExpectedEvents} events`
                                : 'Not enough data yet'
                        }
                    />
                    <StatCard
                        icon={<ListChecks className="h-5 w-5 text-[#1B1F5C] dark:text-amber-400" aria-hidden="true" />}
                        label="Events attended"
                        value={String(eventsAttended)}
                        caption="This term"
                    />
                    <StatCard
                        icon={<CalendarClock className="h-5 w-5 text-[#1B1F5C] dark:text-amber-400" aria-hidden="true" />}
                        label="Events today"
                        value={String(activeEvents.length)}
                        caption={
                            activeEvents.length - checkedInEventIds.size > 0
                                ? `${activeEvents.length - checkedInEventIds.size} still to check in`
                                : 'All checked in'
                        }
                    />
                </div>

                {/* TODAY'S EVENTS LIST */}
                <div className="w-full rounded-xl bg-white dark:bg-[#090d16] shadow-sm border border-gray-100 dark:border-slate-800/60 overflow-hidden">
                    <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100 dark:border-slate-800/60">
                        <h2 className="text-base font-bold text-gray-900 dark:text-white">Today's events</h2>
                        <span className="text-xs text-gray-400 dark:text-gray-500">{activeEvents.length} scheduled</span>
                    </div>

                    {activeEvents.length === 0 ? (
                        <div className="flex flex-col items-center justify-center py-12 text-center">
                            <Calendar className="h-10 w-10 mb-2 stroke-1 text-gray-400 dark:text-gray-600" aria-hidden="true" />
                            <p className="text-sm font-medium text-gray-600 dark:text-gray-300">No events today</p>
                            <p className="text-xs text-gray-400 dark:text-gray-500">Check back when an event opens for check-in.</p>
                        </div>
                    ) : (
                        <ul className="divide-y divide-gray-100 dark:divide-slate-800/60">
                            {activeEvents.map((evt) => {
                                const isCheckedIn = checkedInEventIds.has(evt.event_id);
                                return (
                                    <li key={evt.event_id}>
                                        <div className="w-full flex items-center gap-4 px-6 py-4 text-left">
                                            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-indigo-50 dark:bg-slate-800/80 text-[#1B1F5C] dark:text-amber-400 text-xs font-semibold">
                                                <Clock className="h-4 w-4" aria-hidden="true" />
                                            </div>

                                            <div className="min-w-0 flex-1">
                                                <p className="text-sm font-semibold text-gray-900 dark:text-white truncate">{evt.title}</p>
                                                <p className="mt-0.5 text-xs text-gray-500 dark:text-gray-400 truncate">
                                                    {evt.start_time && (
                                                        <span>{formatEventTime(evt.start_time, evt.end_time)}</span>
                                                    )}
                                                    {evt.location ? ` · ${evt.location}` : ' · Location TBA'}
                                                </p>
                                            </div>

                                            {isCheckedIn ? (
                                                <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 dark:bg-emerald-950/30 px-3 py-1 text-xs font-medium text-emerald-700 dark:text-emerald-400 border border-emerald-200 dark:border-emerald-800/40 shrink-0">
                                                    <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" />
                                                    Checked in
                                                </span>
                                            ) : (
                                                <button
                                                    onClick={() => setSelectedEvent(evt)}
                                                    className="inline-flex items-center gap-1 rounded-full px-4 py-1.5 text-xs font-semibold text-white shrink-0 transition-colors"
                                                    style={{ backgroundColor: GOLD }}
                                                >
                                                    Check in
                                                    <ChevronRight className="h-3.5 w-3.5" aria-hidden="true" />
                                                </button>
                                            )}
                                        </div>
                                    </li>
                                );
                            })}
                        </ul>
                    )}
                </div>

                {/* COMING UP */}
                {upcomingEvents.length > 0 && (
                    <div className="w-full rounded-xl bg-white dark:bg-[#090d16] shadow-sm border border-gray-100 dark:border-slate-800/60 overflow-hidden">
                        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100 dark:border-slate-800/60">
                            <h2 className="text-base font-bold text-gray-900 dark:text-white">Coming up</h2>
                            <Link
                                href="/events"
                                className="inline-flex items-center gap-1 text-xs font-semibold"
                                style={{ color: GOLD }}
                            >
                                View all
                                <ChevronRight className="h-3.5 w-3.5" aria-hidden="true" />
                            </Link>
                        </div>
                        <ul className="divide-y divide-gray-100 dark:divide-slate-800/60">
                            {upcomingEvents.slice(0, 3).map((evt) => (
                                <li key={evt.event_id} className="flex items-center gap-4 px-6 py-3.5">
                                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-indigo-50 dark:bg-slate-800/80 text-[#1B1F5C] dark:text-amber-400 text-xs font-semibold">
                                        <Calendar className="h-4 w-4" aria-hidden="true" />
                                    </div>
                                    <div className="min-w-0 flex-1">
                                        <p className="text-sm font-semibold text-gray-900 dark:text-white truncate">{evt.title}</p>
                                        <p className="mt-0.5 text-xs text-gray-500 dark:text-gray-400 truncate">
                                            {evt.event_date}
                                            {evt.start_time ? ` (${formatEventTime(evt.start_time, evt.end_time)})` : ''}
                                            {evt.location ? ` · ${evt.location}` : ' · Location TBA'}
                                        </p>
                                    </div>
                                </li>
                            ))}
                        </ul>
                    </div>
                )}

                {/* RECENT ATTENDANCE */}
                <div className="w-full rounded-xl bg-white dark:bg-[#090d16] shadow-sm border border-gray-100 dark:border-slate-800/60 overflow-hidden">
                    <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100 dark:border-slate-800/60">
                        <h2 className="text-base font-bold text-gray-900 dark:text-white">Recent attendance</h2>
                        <Link
                            href="/attendance/history"
                            className="inline-flex items-center gap-1 text-xs font-semibold"
                            style={{ color: GOLD }}
                        >
                            View all
                            <ChevronRight className="h-3.5 w-3.5" aria-hidden="true" />
                        </Link>
                    </div>

                    {recentAttendances.length > 0 ? (
                        <ul className="divide-y divide-gray-100 dark:divide-slate-800/60">
                            {recentAttendances.map((log) => (
                                <li key={log.attendance_id} className="flex items-center justify-between px-6 py-3.5">
                                    <div className="min-w-0 flex-1">
                                        <p className="text-sm font-semibold text-gray-900 dark:text-white truncate">
                                            {log.event?.title || 'Event'}
                                        </p>
                                        <p className="mt-0.5 text-xs text-gray-500 dark:text-gray-400 truncate">
                                            {new Date(log.logged_at).toLocaleDateString()} {new Date(log.logged_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })} - {log.event?.location || 'N/A'}
                                        </p>
                                    </div>
                                    <div className="flex items-center gap-2 shrink-0">
                                        <ConfidenceBadge score={log.confidence_score} />
                                        <span className="inline-flex items-center rounded-full bg-emerald-50 dark:bg-emerald-950/30 px-2.5 py-0.5 text-xs font-medium text-emerald-700 dark:text-emerald-400 border border-emerald-200 dark:border-emerald-800/40">
                                            {log.status?.toLowerCase() || 'present'}
                                        </span>
                                    </div>
                                </li>
                            ))}
                        </ul>
                    ) : (
                        <div className="flex flex-col items-center justify-center py-12 text-center text-gray-400 dark:text-gray-500">
                            <p className="text-xs">No attendance records yet.</p>
                        </div>
                    )}
                </div>
            </div>

            {selectedEvent && (
                <CheckInModal event={selectedEvent} onClose={() => setSelectedEvent(null)} />
            )}
        </>
    );
}

function StatCard({ icon, label, value, caption }: { icon: React.ReactNode; label: string; value: string; caption: string }) {
    return (
        <div className="rounded-xl bg-white dark:bg-[#090d16] p-5 shadow-sm border border-gray-100 dark:border-slate-800/60">
            <div className="flex items-center gap-2 text-gray-500 dark:text-gray-400">
                <span>{icon}</span>
                <span className="text-xs font-medium">{label}</span>
            </div>
            <p className="mt-2 text-2xl font-bold text-gray-900 dark:text-white">{value}</p>
            <p className="text-xs text-gray-400 dark:text-gray-500">{caption}</p>
        </div>
    );
}

function ConfidenceBadge({ score }: { score: number }) {
    const pct = score <= 1 ? score * 100 : score;
    return (
        <span className="inline-flex items-center rounded-full bg-emerald-50 dark:bg-emerald-950/30 px-2 py-0.5 font-mono text-xs font-medium text-emerald-700 dark:text-emerald-400 border border-emerald-100 dark:border-emerald-800/40">
            {pct.toFixed(1)}%
        </span>
    );
}

function CheckInModal({ event, onClose }: { event: Event; onClose: () => void }) {
    const videoRef = useRef<HTMLVideoElement | null>(null);
    const landmarkerRef = useRef<FaceLandmarker | null>(null);
    const requestRef = useRef<number | null>(null);
    const mountedRef = useRef(true);

    const stepRef = useRef<LivenessStep>('DETECT');
    const frameCountRef = useRef(0);
    const lastVideoTimeRef = useRef(-1);
    const holdCountRef = useRef(0);
    const turnHoldRef = useRef(0);
    const challengeStartRef = useRef<number | null>(null);
    const hasSubmittedRef = useRef(false);

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
        challengeStartRef.current = null;
        frontalFrameRef.current = null;
        midFrameRef.current = null;
        peakFrameRef.current = null;
        setHoldProgress(0);
        goToStep('DETECT');
    };

    useEffect(() => {
        mountedRef.current = true;

        async function initialize() {
            const landmarkerPromise = createLandmarker();
            landmarkerPromise.catch(() => {});

            try {
                const stream = await navigator.mediaDevices.getUserMedia(VIDEO_CONSTRAINTS);
                if (!mountedRef.current || !videoRef.current) {
                    stream.getTracks().forEach((t) => t.stop());
                    return;
                }
                videoRef.current.srcObject = stream;
                await videoRef.current.play().catch(() => {});
                setStreamStarted(true);
            } catch (error) {
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
                if (mountedRef.current) {
                    setCameraError('Unable to load face detection model.');
                }
            }
        }

        initialize();

        return () => {
            mountedRef.current = false;
            if (requestRef.current !== null) cancelAnimationFrame(requestRef.current);
            if (videoRef.current?.srcObject) {
                (videoRef.current.srcObject as MediaStream).getTracks().forEach((t) => t.stop());
            }
            landmarkerRef.current?.close();
            landmarkerRef.current = null;
        };
    }, []);

    useEffect(() => {
        if (!streamStarted || !modelReady || modalError !== null) return;

        let stopped = false;

        const processFrame = () => {
            const video = videoRef.current;
            const landmarker = landmarkerRef.current;
            if (!video || !landmarker || video.readyState < 2) return;

            if (video.currentTime === lastVideoTimeRef.current) return;
            lastVideoTimeRef.current = video.currentTime;

            let faces: Landmark[][];
            try {
                faces = landmarker.detectForVideo(video, performance.now()).faceLandmarks ?? [];
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
                case 'DETECT':
                    goToStep('LOOK_CENTER');
                    break;

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

                    if (!midFrameRef.current && turned >= MID_TURN_YAW) {
                        midFrameRef.current = captureFrame(video);
                    }

                    if (turned >= TURN_YAW_MIN) {
                        turnHoldRef.current += 1;
                        if (turnHoldRef.current >= TURN_HOLD_FRAMES) {
                            peakFrameRef.current = captureFrame(video);
                            void submitAttendance(frontalFrameRef.current, midFrameRef.current, peakFrameRef.current);
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
            if (stepRef.current === 'VERIFYING' || stepRef.current === 'PASSED') return;

            frameCountRef.current += 1;
            if (frameCountRef.current % PROCESS_EVERY_N_FRAMES === 0) processFrame();

            if ((stepRef.current as string) === 'VERIFYING') return;
            requestRef.current = requestAnimationFrame(tick);
        };

        requestRef.current = requestAnimationFrame(tick);

        return () => {
            stopped = true;
            if (requestRef.current !== null) cancelAnimationFrame(requestRef.current);
        };
    }, [streamStarted, modelReady, modalError, direction]);

    const submitAttendance = async (
        frontalPromise: Promise<Blob | null> | null,
        midPromise: Promise<Blob | null> | null,
        peakPromise: Promise<Blob | null> | null
    ) => {
        if (hasSubmittedRef.current) return;
        hasSubmittedRef.current = true;
        goToStep('VERIFYING');
        setHint(null);

        try {
            const [frontal, mid, peak] = await Promise.all([frontalPromise, midPromise, peakPromise]);
            if (!frontal || !peak) throw new Error('Failed to capture camera frames.');

            setIsSubmitting(true);
            const formData = new FormData();
            formData.append('event_id', String(event.event_id));
            formData.append('live_camera_frame', frontal, 'frontal.jpg');
            if (mid) formData.append('turn_mid_frame', mid, 'turn-mid.jpg');
            formData.append('turn_peak_frame', peak, 'turn-peak.jpg');
            formData.append('direction', direction);

            router.post('/attendance/check-in', formData, {
                forceFormData: true,
                onSuccess: () => {
                    setIsSubmitting(false);
                    goToStep('PASSED');
                    setTimeout(() => onClose(), 1200);
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
            case 'DETECT':
            case 'LOOK_CENTER':
                return { text: 'Look straight and hold still', icon: Eye, spin: false };
            case 'TURN':
                return { text: `Turn your head to your ${direction}`, icon: direction === 'left' ? ArrowLeft : ArrowRight, spin: false };
            case 'VERIFYING':
                return { text: 'Verifying attendance...', icon: RefreshCw, spin: true };
            case 'PASSED':
                return { text: 'Checked in successfully!', icon: CheckCircle2, spin: false };
            default:
                return { text: 'Loading camera...', icon: Loader2, spin: true };
        }
    })();
    const ActiveIcon = instruction.icon;

    return (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
            <div className="w-full max-w-md rounded-2xl bg-white dark:bg-[#090d16] text-gray-900 dark:text-white shadow-2xl overflow-hidden border border-gray-100 dark:border-slate-800">
                <div className="relative px-6 pt-6 pb-4 border-b border-gray-100 dark:border-slate-800">
                    <button onClick={onClose} className="absolute right-4 top-4 rounded-full p-1 text-gray-400 hover:bg-gray-100 dark:hover:bg-slate-800">
                        <X className="h-5 w-5" />
                    </button>
                    <h2 className="text-lg font-bold pr-8">{event.title}</h2>
                    <p className="mt-1 text-xs text-gray-500">Active Liveness Attendance Check-in</p>
                </div>

                <div className="flex flex-col items-center px-6 py-6">
                    <div className="relative h-48 w-48 overflow-hidden rounded-full border-4 border-[#1B1F5C] dark:border-amber-400 bg-black mb-3">
                        <video ref={videoRef} autoPlay playsInline muted className="h-full w-full object-cover scale-x-[-1]" />
                        <div className="pointer-events-none absolute inset-2 rounded-full border-2 border-dashed border-[#F5A623] animate-pulse" />
                        
                        {step === 'TURN' && (
                            <div className={`absolute top-1/2 -translate-y-1/2 rounded-full bg-black/60 p-2 text-white ${direction === 'left' ? 'left-2' : 'right-2'}`}>
                                <ActiveIcon className="h-6 w-6 animate-pulse" />
                            </div>
                        )}
                    </div>

                    <div className="flex items-center gap-2 rounded-lg bg-amber-50 dark:bg-amber-950/30 px-3 py-2 text-xs font-semibold text-amber-800 dark:text-amber-400 border border-amber-200 dark:border-amber-800/40 mb-2">
                        <ActiveIcon className={`h-4 w-4 shrink-0 ${instruction.spin ? 'animate-spin' : ''}`} />
                        <span>{instruction.text}</span>
                    </div>

                    {hint && <p className="text-[11px] text-amber-600 dark:text-amber-400 text-center">{hint}</p>}
                    {modalError && <p className="text-[11px] text-red-600 text-center mt-2">{modalError}</p>}
                    {cameraError && <p className="text-[11px] text-red-600 text-center mt-2">{cameraError}</p>}
                </div>
            </div>
        </div>
    );
}