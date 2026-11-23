import React, { useState, useMemo } from 'react';
import { Head, Link, usePage } from '@inertiajs/react';
import {
    Calendar as CalendarIcon,
    Clock,
    ShieldCheck,
    ChevronRight,
    MapPin,
    History,
    CalendarX,
    ArrowUpRight,
    ChevronLeft,
    Sparkles,
    CheckCircle2,
    Lock,
    RotateCcw,
    Camera,
    Sun,
    Sunset,
} from 'lucide-react';
import CheckInModal from '@/components/CheckInModal';
import { formatTime } from '@/lib/slots';

export type CheckpointKey =
    | 'morning_time_in'
    | 'morning_time_out'
    | 'afternoon_time_in'
    | 'afternoon_time_out';

type CheckpointSlot = {
    slot_index?: number;
    morning_time_in_start?: string;
    morning_time_in_end?: string;
    morning_time_out_start?: string;
    morning_time_out_end?: string;
    afternoon_time_in_start?: string;
    afternoon_time_in_end?: string;
    afternoon_time_out_start?: string;
    afternoon_time_out_end?: string;
    // Legacy fallback fields
    time_in_start?: string;
    time_in_end?: string;
    time_out_start?: string;
    time_out_end?: string;
    // Status booleans injected by StudentDashboardController
    morning_time_in?: boolean;
    morning_time_out?: boolean;
    afternoon_time_in?: boolean;
    afternoon_time_out?: boolean;
};

type ScheduleItem = {
    date: string;
    slots: CheckpointSlot[];
};

type Event = {
    event_id: number;
    title: string;
    description?: string | null;
    location?: string | null;
    is_active?: boolean;
    is_geofenced?: boolean;
    latitude?: number | null;
    longitude?: number | null;
    radius_meters?: number | null;
    schedules?: ScheduleItem[] | null;
    event_date?: string;
    start_time?: string;
    end_time?: string | null;
};

type CalendarEvent = {
    event_id: number;
    title: string;
    location?: string | null;
    schedules: ScheduleItem[];
};

type UpcomingEvent = {
    event_id: number;
    title: string;
    location?: string | null;
    next_date: string;
    start_date: string;
    end_date: string;
    day_count: number;
};

type AttendanceLog = {
    attendance_id: number;
    event_id: number;
    event_date: string;
    slot_index: number;
    type: 'in' | 'out';
    checkpoint_key?: CheckpointKey;
    logged_at: string;
    attendance_time: string;
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
    calendarEvents?: CalendarEvent[];
    upcomingEvents?: UpcomingEvent[];
    totalExpectedEvents?: number;
    today?: string;
};

const CHECKPOINT_LABELS: Record<CheckpointKey, string> = {
    morning_time_in: 'Morning In',
    morning_time_out: 'Morning Out',
    afternoon_time_in: 'Afternoon In',
    afternoon_time_out: 'Afternoon Out',
};

const localToday = () => {
    const n = new Date();
    const mm = String(n.getMonth() + 1).padStart(2, '0');
    const dd = String(n.getDate()).padStart(2, '0');
    return `${n.getFullYear()}-${mm}-${dd}`;
};

const parseDateStr = (dateStr: string) => {
    const [y, m, d] = dateStr.split('-').map(Number);
    return new Date(y, m - 1, d);
};

const formatShortDate = (dateStr: string) =>
    parseDateStr(dateStr).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });

const formatLongDate = (dateStr: string) =>
    parseDateStr(dateStr).toLocaleDateString('en-US', {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        year: 'numeric',
    });

const formatDateRange = (start: string, end: string) =>
    start === end ? formatShortDate(start) : `${formatShortDate(start)} \u2013 ${formatShortDate(end)}`;

function checkpointWindowState(startStr?: string, endStr?: string, dateStr?: string): 'upcoming' | 'open' | 'closed' {
    if (!startStr || !dateStr) return 'closed';
    const now = new Date();
    const [y, m, d] = dateStr.split('-').map(Number);

    const [sh, sm] = startStr.split(':').map(Number);
    const start = new Date(y, m - 1, d, sh, sm, 0);

    if (now < start) return 'upcoming';

    if (endStr) {
        const [eh, em] = endStr.split(':').map(Number);
        const end = new Date(y, m - 1, d, eh, em, 59);
        if (end <= start) end.setDate(end.getDate() + 1);
        if (now > end) return 'closed';
    } else {
        const endOfDay = new Date(y, m - 1, d, 23, 59, 59);
        if (now > endOfDay) return 'closed';
    }

    return 'open';
}

export default function Dashboard({
    student,
    activeEvents,
    calendarEvents = [],
    upcomingEvents = [],
    totalExpectedEvents,
    today: todayProp,
}: DashboardProps) {
    const { auth } = usePage<any>().props;
    const isApprovedOrganizer = auth?.user?.role === 'organizer';

    const today = todayProp || localToday();

    const [selectedSlotEvent, setSelectedSlotEvent] = useState<{
        event: Event;
        slot: CheckpointSlot;
        slotIndex: number;
        dateStr: string;
        type: 'in' | 'out';
        checkpointKey: CheckpointKey;
    } | null>(null);

    const [currentDate, setCurrentDate] = useState(() => {
        const t = parseDateStr(today);
        return new Date(t.getFullYear(), t.getMonth(), 1);
    });
    const [selectedDateStr, setSelectedDateStr] = useState<string>(today);

    const hasLoggedCheckpoint = (
        eventId: number,
        slotIndex: number,
        dateStr: string,
        checkpointKey: CheckpointKey,
        slotFlag?: boolean
    ) => {
        if (typeof slotFlag === 'boolean') return slotFlag;
        return student.attendances.some(
            (att) =>
                att.event_id === eventId &&
                att.slot_index === slotIndex &&
                att.event_date?.startsWith(dateStr) &&
                (att.checkpoint_key === checkpointKey ||
                    (!att.checkpoint_key &&
                        ((checkpointKey === 'morning_time_in' && att.type === 'in') ||
                            (checkpointKey === 'morning_time_out' && att.type === 'out'))))
        );
    };

    const eventsAttended = student.attendances.length;
    const attendanceRate =
        totalExpectedEvents && totalExpectedEvents > 0
            ? Math.round((eventsAttended / totalExpectedEvents) * 100)
            : null;

    const recentAttendances = useMemo(
        () =>
            [...student.attendances]
                .sort((a, b) => new Date(b.logged_at).getTime() - new Date(a.logged_at).getTime())
                .slice(0, 4),
        [student.attendances]
    );

    const eventsByDate = useMemo(() => {
        const map: Record<string, { event: CalendarEvent; schedule: ScheduleItem }[]> = {};
        for (const evt of calendarEvents) {
            for (const sched of evt.schedules ?? []) {
                (map[sched.date] ??= []).push({ event: evt, schedule: sched });
            }
        }
        return map;
    }, [calendarEvents]);

    const hasEventOnDate = (dateStr: string) => (eventsByDate[dateStr]?.length ?? 0) > 0;
    const selectedDateEntries = eventsByDate[selectedDateStr] ?? [];

    const filteredUpcomingEvents = useMemo(() => {
        const inspectedEventIds = new Set(selectedDateEntries.map((entry) => entry.event.event_id));

        return upcomingEvents.filter((evt) => {
            if (inspectedEventIds.has(evt.event_id)) return false;
            if (evt.next_date <= selectedDateStr) return false;
            return true;
        });
    }, [upcomingEvents, selectedDateEntries, selectedDateStr]);

    const jumpToDate = (dateStr: string) => {
        const d = parseDateStr(dateStr);
        setCurrentDate(new Date(d.getFullYear(), d.getMonth(), 1));
        setSelectedDateStr(dateStr);
    };

    const year = currentDate.getFullYear();
    const month = currentDate.getMonth();
    const monthName = currentDate.toLocaleString('default', { month: 'long' });

    const firstDayIndex = new Date(year, month, 1).getDay();
    const startingDay = (firstDayIndex + 6) % 7;
    const totalDaysInMonth = new Date(year, month + 1, 0).getDate();

    const handlePrevMonth = () => setCurrentDate(new Date(year, month - 1, 1));
    const handleNextMonth = () => setCurrentDate(new Date(year, month + 1, 1));
    const handleJumpToToday = () => jumpToDate(today);

    return (
        <div className="min-h-screen bg-[#F5F6FA] p-3 sm:p-5 font-sans text-gray-900 antialiased">
            <Head title="Student Dashboard | 4ttnd Attendance System" />

            <div className="w-full space-y-4">
                {/* COMPACT HERO BANNER WITH UNIFIED DATA STRIP */}
                <header className="rounded-2xl bg-[#1B1F5C] p-4 sm:p-5 text-white shadow-xs border border-[#1B1F5C]">
                    <div className="flex flex-col lg:flex-row lg:items-center lg:justify-between gap-4">
                        {/* Student Identity */}
                        <div className="flex items-center gap-3.5">
                            <div className="h-12 w-12 overflow-hidden rounded-xl border-2 border-[#F5A623] bg-indigo-950 shrink-0">
                                {student.face_photo_url ? (
                                    <img
                                        src={student.face_photo_url}
                                        alt={`${student.firstname} ${student.surname}`}
                                        className="h-full w-full object-cover"
                                    />
                                ) : (
                                    <div className="flex h-full w-full items-center justify-center font-black text-[#F5A623] text-lg">
                                        {student.firstname[0]}
                                    </div>
                                )}
                            </div>
                            <div className="space-y-0.5">
                                <span className="inline-flex items-center gap-1 rounded-full bg-emerald-500/20 border border-emerald-400/30 px-2.5 py-0.5 text-[10px] font-bold text-emerald-300">
                                    <ShieldCheck className="h-3 w-3" aria-hidden="true" /> Biometrics Verified
                                </span>
                                <h1 className="text-lg sm:text-xl font-black tracking-tight text-white">
                                    Welcome, {student.firstname} {student.surname}
                                </h1>
                                <p className="text-[11px] text-indigo-200 font-mono">
                                    Student ID: <span className="font-bold text-white">{student.student_number}</span>
                                </p>
                            </div>
                        </div>

                        {/* Consolidated KPI Strip & Organizer Action */}
                        <div className="flex flex-wrap items-center gap-2.5 sm:gap-3 shrink-0">
                            <div className="flex items-center divide-x divide-white/15 bg-white/10 px-3.5 py-2 rounded-xl border border-white/15 text-xs">
                                <div className="pr-3.5">
                                    <span className="text-[9px] uppercase tracking-wider text-indigo-200 font-bold block">
                                        Attendance Rate
                                    </span>
                                    <span className="text-base font-black text-[#F5A623]">
                                        {attendanceRate !== null ? `${attendanceRate}%` : '—'}
                                    </span>
                                </div>
                                <div className="px-3.5">
                                    <span className="text-[9px] uppercase tracking-wider text-indigo-200 font-bold block">
                                        Checkpoints
                                    </span>
                                    <span className="text-base font-black text-white">{eventsAttended}</span>
                                </div>
                                <div className="pl-3.5">
                                    <span className="text-[9px] uppercase tracking-wider text-indigo-200 font-bold block">
                                        Active Today
                                    </span>
                                    <span className="text-base font-black text-emerald-300">{activeEvents.length}</span>
                                </div>
                            </div>

                            {isApprovedOrganizer && (
                                <Link
                                    href="/organizer/dashboard"
                                    className="inline-flex items-center justify-center gap-1.5 min-h-[44px] px-4 py-2 bg-[#F5A623] hover:bg-[#d98e19] text-[#1B1F5C] font-extrabold text-xs rounded-xl shadow-xs transition-all focus-visible:ring-2 focus-visible:ring-white active:scale-98"
                                >
                                    <Camera className="w-4 h-4 text-[#1B1F5C]" aria-hidden="true" />
                                    <span>Organizer Portal →</span>
                                </Link>
                            )}
                        </div>
                    </div>
                </header>

                {/* 12-COLUMN ASYMMETRIC BENTO GRID */}
                <div className="grid grid-cols-1 lg:grid-cols-12 gap-4 items-start">
                    {/* LEFT PRIMARY COLUMN (8 Cols): ACTIVE EVENTS & FLATTENED CHECKPOINTS */}
                    <main className="lg:col-span-8 space-y-4">
                        <div className="flex items-center justify-between px-0.5">
                            <h2 className="font-black text-[#1B1F5C] text-xs sm:text-sm uppercase tracking-wider">
                                Today's Active Check-In Sessions
                            </h2>
                            {activeEvents.length > 3 && (
                                <Link
                                    href="/check-in"
                                    className="inline-flex items-center gap-1 text-xs font-bold text-[#1B1F5C] hover:underline focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-xs"
                                >
                                    <span>View All ({activeEvents.length})</span>
                                    <ArrowUpRight className="h-3.5 w-3.5" aria-hidden="true" />
                                </Link>
                            )}
                        </div>

                        {activeEvents.length === 0 ? (
                            <div className="bg-white p-8 rounded-2xl shadow-xs border border-gray-200/80 text-center space-y-2">
                                <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-xl bg-indigo-50 text-[#1B1F5C]">
                                    <CalendarX className="h-5 w-5" aria-hidden="true" />
                                </div>
                                <h3 className="font-bold text-gray-900 text-sm">No active events scheduled today</h3>
                                <p className="text-xs text-gray-500 max-w-xs mx-auto">
                                    Check the calendar sidebar to preview upcoming academic sessions and events.
                                </p>
                            </div>
                        ) : (
                            <div className="space-y-4">
                                {activeEvents.slice(0, 3).map((evt) => (
                                    <article
                                        key={evt.event_id}
                                        className="bg-white p-4 sm:p-5 rounded-2xl shadow-xs border border-gray-200/80 space-y-4 hover:border-[#1B1F5C]/30 transition-all"
                                    >
                                        {/* Event Header */}
                                        <div className="flex items-center justify-between gap-3 border-b border-gray-100 pb-3">
                                            <div className="flex items-center gap-3">
                                                <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-indigo-50 text-[#1B1F5C] border border-indigo-100">
                                                    <Clock className="h-5 w-5" aria-hidden="true" />
                                                </div>
                                                <div>
                                                    <h3 className="font-black text-[#1B1F5C] text-base leading-tight">
                                                        {evt.title}
                                                    </h3>
                                                    <p className="text-xs text-gray-500 font-medium flex items-center gap-1 mt-0.5">
                                                        <MapPin className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                                                        <span>{evt.location || 'Location TBA'}</span>
                                                    </p>
                                                </div>
                                            </div>
                                            <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-2.5 py-0.5 text-[10px] font-extrabold text-emerald-700 border border-emerald-200 shrink-0">
                                                <span className="h-1.5 w-1.5 rounded-full bg-emerald-500 animate-pulse" aria-hidden="true" />
                                                Live Window
                                            </span>
                                        </div>

                                        {/* Flattened Checkpoint Grid (No outer nested wrapper box) */}
                                        {evt.schedules && evt.schedules.length > 0 && (
                                            <div className="space-y-4">
                                                {evt.schedules.map((sched, sIdx) => (
                                                    <div key={sIdx} className="space-y-3">
                                                        {sched.slots?.map((slot, slotIdx) => {
                                                            const mInStart = slot.morning_time_in_start || slot.time_in_start;
                                                            const mInEnd = slot.morning_time_in_end || slot.time_in_end;
                                                            const mOutStart = slot.morning_time_out_start || slot.time_out_start;
                                                            const mOutEnd = slot.morning_time_out_end || slot.time_out_end;
                                                            const aInStart = slot.afternoon_time_in_start;
                                                            const aInEnd = slot.afternoon_time_in_end;
                                                            const aOutStart = slot.afternoon_time_out_start;
                                                            const aOutEnd = slot.afternoon_time_out_end;

                                                            const checkpoints: {
                                                                key: CheckpointKey;
                                                                label: string;
                                                                session: 'morning' | 'afternoon';
                                                                type: 'in' | 'out';
                                                                start?: string;
                                                                end?: string;
                                                                done: boolean;
                                                            }[] = [
                                                                {
                                                                    key: 'morning_time_in' as CheckpointKey,
                                                                    label: 'Morning Time-In',
                                                                    session: 'morning',
                                                                    type: 'in',
                                                                    start: mInStart,
                                                                    end: mInEnd,
                                                                    done: hasLoggedCheckpoint(evt.event_id, slotIdx, sched.date, 'morning_time_in', slot.morning_time_in),
                                                                },
                                                                {
                                                                    key: 'morning_time_out' as CheckpointKey,
                                                                    label: 'Morning Time-Out',
                                                                    session: 'morning',
                                                                    type: 'out',
                                                                    start: mOutStart,
                                                                    end: mOutEnd,
                                                                    done: hasLoggedCheckpoint(evt.event_id, slotIdx, sched.date, 'morning_time_out', slot.morning_time_out),
                                                                },
                                                                {
                                                                    key: 'afternoon_time_in' as CheckpointKey,
                                                                    label: 'Afternoon Time-In',
                                                                    session: 'afternoon',
                                                                    type: 'in',
                                                                    start: aInStart,
                                                                    end: aInEnd,
                                                                    done: hasLoggedCheckpoint(evt.event_id, slotIdx, sched.date, 'afternoon_time_in', slot.afternoon_time_in),
                                                                },
                                                                {
                                                                    key: 'afternoon_time_out' as CheckpointKey,
                                                                    label: 'Afternoon Time-Out',
                                                                    session: 'afternoon',
                                                                    type: 'out',
                                                                    start: aOutStart,
                                                                    end: aOutEnd,
                                                                    done: hasLoggedCheckpoint(evt.event_id, slotIdx, sched.date, 'afternoon_time_out', slot.afternoon_time_out),
                                                                },
                                                            ].filter((cp) => Boolean(cp.start)) as {
                                                                key: CheckpointKey;
                                                                label: string;
                                                                session: 'morning' | 'afternoon';
                                                                type: 'in' | 'out';
                                                                start: string;
                                                                end?: string;
                                                                done: boolean;
                                                            }[];

                                                            const completedCount = checkpoints.filter((c) => c.done).length;

                                                            return (
                                                                <div key={slotIdx} className="space-y-2.5">
                                                                    <div className="flex items-center justify-between">
                                                                        <span className="font-extrabold text-[#1B1F5C] uppercase tracking-wider text-[10px]">
                                                                            Slot {slotIdx + 1} Checkpoints
                                                                        </span>
                                                                        <span className="text-[10px] font-bold px-2.5 py-0.5 rounded-full bg-indigo-50 text-[#1B1F5C] border border-indigo-100">
                                                                            {completedCount} / {checkpoints.length} Completed
                                                                        </span>
                                                                    </div>

                                                                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
                                                                        {checkpoints.map((cp) => {
                                                                            const state = checkpointWindowState(cp.start, cp.end, sched.date);
                                                                            const isMorning = cp.session === 'morning';

                                                                            return (
                                                                                <div
                                                                                    key={cp.key}
                                                                                    className={`p-3 rounded-xl border flex flex-col justify-between transition-all ${
                                                                                        cp.done
                                                                                            ? 'bg-emerald-50/60 border-emerald-200 text-emerald-900'
                                                                                            : state === 'open'
                                                                                              ? 'bg-amber-50/40 border-[#F5A623] shadow-2xs'
                                                                                              : 'bg-gray-50/80 border-gray-200/80 text-gray-500'
                                                                                    }`}
                                                                                >
                                                                                    <div className="flex items-center justify-between mb-1.5">
                                                                                        <span className="inline-flex items-center gap-1.5 text-[10px] font-extrabold uppercase tracking-wider text-[#1B1F5C]">
                                                                                            {isMorning ? (
                                                                                                <Sun className="h-3.5 w-3.5 text-sky-500" aria-hidden="true" />
                                                                                            ) : (
                                                                                                <Sunset className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                                                                                            )}
                                                                                            <span>{cp.label}</span>
                                                                                        </span>
                                                                                        <span className="text-[11px] font-mono font-bold text-gray-700">
                                                                                            {formatTime(cp.start)}
                                                                                            {cp.end ? ` - ${formatTime(cp.end)}` : ''}
                                                                                        </span>
                                                                                    </div>

                                                                                    {cp.done ? (
                                                                                        <div className="flex items-center gap-1 text-[11px] font-bold text-emerald-700 pt-1">
                                                                                            <CheckCircle2 className="h-3.5 w-3.5 text-emerald-600" aria-hidden="true" />
                                                                                            <span>Logged</span>
                                                                                        </div>
                                                                                    ) : state === 'open' ? (
                                                                                        <button
                                                                                            type="button"
                                                                                            onClick={() =>
                                                                                                setSelectedSlotEvent({
                                                                                                    event: evt,
                                                                                                    slot,
                                                                                                    slotIndex: slotIdx,
                                                                                                    dateStr: sched.date,
                                                                                                    type: cp.type,
                                                                                                    checkpointKey: cp.key,
                                                                                                })
                                                                                            }
                                                                                            className="w-full mt-1.5 min-h-[38px] py-1.5 px-3 rounded-lg bg-[#1B1F5C] text-white text-xs font-bold hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] shadow-xs transition-all active:scale-98"
                                                                                        >
                                                                                            Log {cp.label} →
                                                                                        </button>
                                                                                    ) : (
                                                                                        <div className="flex items-center gap-1 text-[11px] font-medium text-gray-400 pt-1">
                                                                                            <Lock className="h-3 w-3" aria-hidden="true" />
                                                                                            <span>{state === 'upcoming' ? 'Not Open Yet' : 'Window Closed'}</span>
                                                                                        </div>
                                                                                    )}
                                                                                </div>
                                                                            );
                                                                        })}
                                                                    </div>
                                                                </div>
                                                            );
                                                        })}
                                                    </div>
                                                ))}
                                            </div>
                                        )}
                                    </article>
                                ))}
                            </div>
                        )}

                        {/* RECENT ATTENDANCE LOGS (Moved to Left Column for balanced Bento height) */}
                        <section
                            aria-label="Recent Attendance History"
                            className="bg-white p-4 sm:p-5 rounded-2xl shadow-xs border border-gray-200/80 space-y-3"
                        >
                            <div className="flex items-center justify-between border-b border-gray-100 pb-2.5">
                                <h3 className="font-black text-[#1B1F5C] text-sm flex items-center gap-1.5">
                                    <History className="h-4 w-4 text-[#F5A623]" aria-hidden="true" />
                                    <span>Recent Biometric Logs</span>
                                </h3>
                                <Link
                                    href="/attendance/history"
                                    className="text-xs font-bold text-[#1B1F5C] hover:underline flex items-center gap-0.5 focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-xs"
                                >
                                    <span>Full History</span>
                                    <ChevronRight className="h-3.5 w-3.5" aria-hidden="true" />
                                </Link>
                            </div>

                            {recentAttendances.length > 0 ? (
                                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
                                    {recentAttendances.map((log) => {
                                        const logDate = new Date(log.logged_at || log.attendance_time);
                                        const checkpointLabel = log.checkpoint_key
                                            ? CHECKPOINT_LABELS[log.checkpoint_key]
                                            : log.type === 'out'
                                              ? 'Time-Out'
                                              : 'Time-In';

                                        return (
                                            <div
                                                key={log.attendance_id}
                                                className="flex items-center justify-between p-2.5 rounded-xl bg-gray-50/80 border border-gray-200/70 text-xs"
                                            >
                                                <div className="min-w-0 pr-2">
                                                    <p className="font-extrabold text-gray-900 truncate">
                                                        {log.event?.title || 'Academic Event'}
                                                    </p>
                                                    <p className="text-[11px] text-gray-500 mt-0.5">
                                                        <span className="font-bold text-[#1B1F5C]">{checkpointLabel}</span> •{' '}
                                                        {logDate.toLocaleDateString()} {logDate.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                                                    </p>
                                                </div>
                                                <span className="inline-flex items-center rounded-full bg-emerald-50 px-2.5 py-0.5 text-[10px] font-extrabold text-emerald-700 border border-emerald-200 shrink-0">
                                                    {log.status || 'Present'}
                                                </span>
                                            </div>
                                        );
                                    })}
                                </div>
                            ) : (
                                <p className="text-xs text-gray-400 text-center py-4 font-medium">
                                    No biometric attendance logs recorded yet.
                                </p>
                            )}
                        </section>
                    </main>

                    {/* RIGHT SECONDARY COLUMN (4 Cols): COMPACT CALENDAR & UPCOMING */}
                    <aside className="lg:col-span-4 space-y-4">
                        {/* COMPACT CALENDAR */}
                        <section
                            aria-label="Event Calendar"
                            className="bg-white p-4 rounded-2xl shadow-xs border border-gray-200/80 space-y-3"
                        >
                            <div className="flex items-center justify-between">
                                <div className="flex items-center gap-1.5">
                                    <h3 className="font-black text-[#1B1F5C] text-sm flex items-center gap-1.5">
                                        <CalendarIcon className="h-4 w-4 text-[#F5A623]" aria-hidden="true" />
                                        <span>Calendar</span>
                                    </h3>
                                    {selectedDateStr !== today && (
                                        <button
                                            onClick={handleJumpToToday}
                                            className="text-[10px] font-bold text-[#1B1F5C] bg-indigo-50 px-2 py-0.5 rounded-md hover:bg-indigo-100 transition-colors flex items-center gap-0.5 focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                            title="Jump back to today"
                                        >
                                            <RotateCcw className="h-2.5 w-2.5" aria-hidden="true" /> Today
                                        </button>
                                    )}
                                </div>
                                <div className="flex items-center gap-0.5">
                                    <button
                                        onClick={handlePrevMonth}
                                        aria-label="Previous Month"
                                        className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-600 transition-colors focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    >
                                        <ChevronLeft className="h-3.5 w-3.5" />
                                    </button>
                                    <span className="text-xs font-extrabold text-gray-800 min-w-[85px] text-center">
                                        {monthName} {year}
                                    </span>
                                    <button
                                        onClick={handleNextMonth}
                                        aria-label="Next Month"
                                        className="p-1.5 rounded-lg hover:bg-gray-100 text-gray-600 transition-colors focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    >
                                        <ChevronRight className="h-3.5 w-3.5" />
                                    </button>
                                </div>
                            </div>

                            {/* COMPACT DAYS GRID */}
                            <div className="grid grid-cols-7 gap-1 text-center">
                                {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d, i) => (
                                    <span key={i} className="text-[10px] font-extrabold text-gray-400 py-0.5">
                                        {d}
                                    </span>
                                ))}
                                {Array.from({ length: startingDay }).map((_, index) => (
                                    <div key={`empty-${index}`} />
                                ))}
                                {Array.from({ length: totalDaysInMonth }).map((_, index) => {
                                    const dayNum = index + 1;
                                    const formattedDay = dayNum < 10 ? `0${dayNum}` : `${dayNum}`;
                                    const formattedMonth = month + 1 < 10 ? `0${month + 1}` : `${month + 1}`;
                                    const dateString = `${year}-${formattedMonth}-${formattedDay}`;

                                    const isSelected = selectedDateStr === dateString;
                                    const isToday = dateString === today;
                                    const hasEvent = hasEventOnDate(dateString);

                                    return (
                                        <button
                                            key={dayNum}
                                            onClick={() => setSelectedDateStr(dateString)}
                                            className={`relative h-7 w-7 mx-auto rounded-lg flex flex-col items-center justify-center text-[11px] font-bold transition-all focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                isSelected
                                                    ? 'bg-[#1B1F5C] text-white shadow-2xs'
                                                    : isToday
                                                      ? 'bg-[#F5A623] text-[#1B1F5C] font-black'
                                                      : 'text-gray-700 hover:bg-gray-100'
                                            }`}
                                        >
                                            <span>{dayNum}</span>
                                            {hasEvent && (
                                                <span
                                                    className={`absolute bottom-0.5 h-1 w-1 rounded-full ${
                                                        isSelected ? 'bg-[#F5A623]' : 'bg-[#1B1F5C]'
                                                    }`}
                                                />
                                            )}
                                        </button>
                                    );
                                })}
                            </div>

                            {/* SELECTED DATE SUMMARY */}
                            <div className="pt-2.5 border-t border-gray-100 space-y-2" aria-live="polite">
                                <div className="flex items-center justify-between text-[11px] gap-2">
                                    <span className="text-gray-600 font-bold truncate">
                                        {formatLongDate(selectedDateStr)}
                                    </span>
                                    <span className="px-2 py-0.5 rounded-md font-extrabold text-[10px] bg-indigo-50 text-[#1B1F5C]">
                                        {selectedDateEntries.length} Event{selectedDateEntries.length === 1 ? '' : 's'}
                                    </span>
                                </div>

                                {selectedDateEntries.length > 0 ? (
                                    <div className="space-y-1.5 max-h-48 overflow-y-auto pr-0.5">
                                        {selectedDateEntries.map(({ event }) => (
                                            <div
                                                key={event.event_id}
                                                className="p-2.5 rounded-xl bg-indigo-50/50 border border-indigo-100 text-xs space-y-0.5"
                                            >
                                                <p className="font-extrabold text-[#1B1F5C] truncate">{event.title}</p>
                                                <p className="text-[11px] text-gray-500 flex items-center gap-1">
                                                    <MapPin className="h-3 w-3 text-[#F5A623]" /> {event.location || 'Location TBA'}
                                                </p>
                                            </div>
                                        ))}
                                    </div>
                                ) : (
                                    <p className="text-xs text-gray-400 italic text-center py-2">No events scheduled.</p>
                                )}
                            </div>
                        </section>

                        {/* UPCOMING EVENTS */}
                        <section
                            aria-label="Upcoming Events"
                            className="bg-white p-4 rounded-2xl shadow-xs border border-gray-200/80 space-y-3"
                        >
                            <div className="flex items-center justify-between">
                                <h3 className="font-black text-[#1B1F5C] text-sm flex items-center gap-1.5">
                                    <Sparkles className="h-4 w-4 text-[#F5A623]" aria-hidden="true" />
                                    <span>Coming Up</span>
                                </h3>
                                <Link
                                    href="/events"
                                    className="text-xs font-bold text-[#1B1F5C] hover:underline flex items-center gap-0.5 focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-xs"
                                >
                                    <span>View all</span>
                                    <ArrowUpRight className="h-3.5 w-3.5" aria-hidden="true" />
                                </Link>
                            </div>

                            {filteredUpcomingEvents.length > 0 ? (
                                <div className="space-y-2">
                                    {filteredUpcomingEvents.slice(0, 3).map((evt) => (
                                        <button
                                            key={evt.event_id}
                                            type="button"
                                            onClick={() => jumpToDate(evt.next_date)}
                                            className="w-full text-left flex items-center gap-2.5 p-2.5 rounded-xl bg-gray-50/80 border border-gray-200/70 hover:bg-amber-50/50 hover:border-amber-200 transition-all focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                        >
                                            <div className="h-8 w-8 rounded-lg bg-amber-50 text-[#1B1F5C] flex items-center justify-center shrink-0 font-black text-xs border border-amber-200/70">
                                                {evt.next_date.split('-')[2]}
                                            </div>
                                            <div className="min-w-0 flex-1">
                                                <p className="text-xs font-extrabold text-gray-900 truncate">{evt.title}</p>
                                                <p className="text-[11px] text-gray-500 truncate">
                                                    {formatDateRange(evt.start_date, evt.end_date)}
                                                </p>
                                            </div>
                                        </button>
                                    ))}
                                </div>
                            ) : (
                                <p className="text-xs text-gray-400 text-center py-3 font-medium">
                                    No further upcoming events.
                                </p>
                            )}
                        </section>
                    </aside>
                </div>
            </div>

            {/* SHARED LIVENESS CHECK-IN MODAL */}
            {selectedSlotEvent && (
                <CheckInModal
                    event={selectedSlotEvent.event as any}
                    slot={selectedSlotEvent.slot as any}
                    slotIndex={selectedSlotEvent.slotIndex}
                    dateStr={selectedSlotEvent.dateStr}
                    type={selectedSlotEvent.type}
                    checkpointKey={selectedSlotEvent.checkpointKey}
                    onClose={() => setSelectedSlotEvent(null)}
                />
            )}
        </div>
    );
}