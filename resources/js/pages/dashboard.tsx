import React, { useState, useRef, useEffect } from 'react';
import { Head, Link, router } from '@inertiajs/react';
import type { FaceLandmarker } from '@mediapipe/tasks-vision';
import {
    CheckCircle2,
    Calendar,
    Clock,
    ShieldCheck,
    RefreshCw,
    X,
    ChevronRight,
    TrendingUp,
    ListChecks,
    CalendarClock,
    Eye,
    ArrowLeft,
    ArrowRight,
    Loader2,
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
} from '../lib/liveness';
import { isEventWindowOpen, type ScheduleItem } from '../lib/eventValidation';

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
    schedules?: ScheduleItem[] | null;
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

type LivenessStep = 'LOOK_CENTER' | 'TURN' | 'VERIFYING' | 'PASSED';

const GOLD = '#C9973E';

// Liveness tuning
const PROCESS_EVERY_N_FRAMES = 3;
const FRONTAL_YAW_MAX = 0.12;
const FRONTAL_HOLD_FRAMES = 8;
const TURN_YAW_MIN = 0.25;
const TURN_HOLD_FRAMES = 3;
const WRONG_WAY_YAW = 0.15;
const CHALLENGE_TIMEOUT_MS = 20_000;
const LOW_ACCURACY_WARNING_METERS = 100;

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
                                const windowIsOpen = isEventWindowOpen(evt.schedules);

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
                                                {!isCheckedIn && !windowIsOpen && (
                                                    <p className="mt-1 text-[11px] font-medium text-amber-600 dark:text-amber-400">
                                                        Check-in window is currently closed
                                                    </p>
                                                )}
                                            </div>

                                            {isCheckedIn ? (
                                                <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 dark:bg-emerald-950/30 px-3 py-1 text-xs font-medium text-emerald-700 dark:text-emerald-400 border border-emerald-200 dark:border-emerald-800/40 shrink-0">
                                                    <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" />
                                                    Checked in
                                                </span>
                                            ) : !windowIsOpen ? (
                                                <span className="inline-flex items-center gap-1 rounded-full bg-gray-100 dark:bg-slate-800 px-3 py-1 text-xs font-medium text-gray-400 dark:text-gray-500 shrink-0 cursor-not-allowed">
                                                    Window closed
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

type SetupStage = 'LOCATING' | 'STARTING_CAMERA' | 'READY';

function CheckInModal({ event, onClose }: { event: Event; onClose: () => void }) {
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
    const [isSubmitting, setIsSubmitting] = useState(false);
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
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [event, retryToken]);

    useEffect(() => {
        if (!isReady || blockingError) return;

        let stopped = false;

        const processFrame = () => {
            const video = videoRef.current;
            const landmarker = landmarkerRef.current;

            if (!video || !landmarker || video.readyState < 2) {
                return;
            }

            if (video.currentTime === lastVideoTimeRef.current) {
                return;
            }

            lastVideoTimeRef.current = video.currentTime;

            let faces: Landmark[][] = [];

            try {
                const result = landmarker.detectForVideo(
                    video,
                    performance.now()
                );

                faces = result.faceLandmarks ?? [];
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

            const currentStep = stepRef.current;
            if (currentStep === 'VERIFYING' || currentStep === 'PASSED') {
                return;
            }

            frameCountRef.current += 1;
            if (frameCountRef.current % PROCESS_EVERY_N_FRAMES === 0) {
                processFrame();
            }

            if (stepRef.current === 'VERIFYING' || stepRef.current === 'PASSED') {
                return;
            }

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
            setIsSubmitting(true);

            const formData = new FormData();
            formData.append('event_id', String(event.event_id));
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
                    setIsSubmitting(false);
                    goToStep('PASSED');
                    setTimeout(() => onClose(), 1200);
                },
                onError: (errors: Record<string, string>) => {
                    setIsSubmitting(false);
                    setModalError(errors.attendance || errors.live_camera_frame || 'Verification failed.');
                },
            });
        } catch {
            setIsSubmitting(false);
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
                return { text: 'Verifying attendance...', icon: RefreshCw, spin: true };
            case 'PASSED':
                return { text: 'Checked in successfully!', icon: CheckCircle2, spin: false };
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
                if (e.target === e.currentTarget) onClose();
            }}
        >
            <div className="w-full max-w-md rounded-2xl bg-white dark:bg-[#090d16] text-gray-900 dark:text-white shadow-2xl overflow-hidden border border-gray-100 dark:border-slate-800">
                <div className="relative px-6 pt-6 pb-4 border-b border-gray-100 dark:border-slate-800">
                    <button onClick={onClose} className="absolute right-4 top-4 rounded-full p-1 text-gray-400 hover:bg-gray-100 dark:hover:bg-slate-800">
                        <X className="h-5 w-5" />
                    </button>
                    <h2 id="checkin-title" className="text-lg font-bold pr-8">{event.title}</h2>
                    <p className="mt-1 text-xs text-gray-500">Active Liveness & Geofence Check-in</p>
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