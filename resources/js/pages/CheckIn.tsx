import React, { useState } from 'react';
import { Head, Link } from '@inertiajs/react';
import {
    Clock,
    ShieldCheck,
    MapPin,
    CalendarX,
    CheckCircle2,
    Lock,
    Sun,
    Sunset,
    ArrowLeft,
} from 'lucide-react';
import CheckInModal from '@/components/CheckInModal';
import { type ScheduleItem, type TimeSlot } from '@/lib/eventValidation';
import { formatTime } from '@/lib/slots';

export type CheckpointKey =
    | 'morning_time_in'
    | 'morning_time_out'
    | 'afternoon_time_in'
    | 'afternoon_time_out';

type ExtendedTimeSlot = TimeSlot & {
    morning_time_in?: boolean;
    morning_time_out?: boolean;
    afternoon_time_in?: boolean;
    afternoon_time_out?: boolean;
};

type Event = {
    event_id: number;
    title: string;
    description?: string | null;
    event_date: string;
    start_time: string;
    end_time?: string | null;
    location?: string | null;
    is_active?: boolean;
    is_geofenced?: boolean;
    geofence_enabled?: boolean;
    latitude?: number | null;
    longitude?: number | null;
    radius_meters?: number | null;
    schedules?: {
        date: string;
        slots: ExtendedTimeSlot[];
    }[] | null;
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

type CheckInProps = {
    student: Student;
    activeEvents: Event[];
};

function checkpointWindowState(
    startStr?: string | null,
    endStr?: string | null,
    dateStr?: string
): 'upcoming' | 'open' | 'closed' {
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

export default function CheckIn({ student, activeEvents }: CheckInProps) {
    const [selectedSlotEvent, setSelectedSlotEvent] = useState<{
        event: Event;
        slot: ExtendedTimeSlot;
        slotIndex: number;
        dateStr: string;
        type: 'in' | 'out';
        checkpointKey: CheckpointKey;
    } | null>(null);

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

    return (
        <div className="w-full min-h-screen bg-[#F5F6FA] text-gray-900 font-sans antialiased p-3 sm:p-5 space-y-4">
            <Head title="Student Check-In Hub | 4ttnd Attendance System" />

            {/* COMPACT HUB HEADER */}
            <header className="flex flex-col sm:flex-row w-full sm:items-center justify-between gap-3 rounded-2xl bg-white p-4 sm:p-5 shadow-xs border border-gray-200/80">
                <div className="space-y-1">
                    <Link
                        href="/dashboard"
                        className="inline-flex items-center gap-1 text-xs font-bold text-[#1B1F5C] hover:underline mb-1 focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-xs"
                    >
                        <ArrowLeft className="h-3.5 w-3.5" aria-hidden="true" />
                        <span>Back to Dashboard</span>
                    </Link>
                    <h1 className="text-lg sm:text-xl font-black tracking-tight text-[#1B1F5C]">
                        Attendance Check-In Hub
                    </h1>
                    <p className="text-xs text-gray-500 font-medium">
                        Select an active event checkpoint window below to verify your identity and record attendance.
                    </p>
                </div>
                <div className="flex items-center gap-1.5 rounded-full bg-emerald-50 px-3 py-1.5 text-xs font-bold text-emerald-700 border border-emerald-200 shrink-0 self-start sm:self-center">
                    <ShieldCheck className="h-4 w-4" aria-hidden="true" />
                    <span>Biometrics Ready</span>
                </div>
            </header>

            {/* ACTIVE EVENTS & SLOTS LIST */}
            <main
                aria-label="Events Open For Check-In"
                className="w-full rounded-2xl bg-white shadow-xs border border-gray-200/80 overflow-hidden"
            >
                <div className="flex items-center justify-between px-4 sm:px-5 py-3.5 border-b border-gray-100 bg-gray-50/50">
                    <h2 className="text-sm font-extrabold text-[#1B1F5C]">
                        Events Open For Check-In
                    </h2>
                    <span className="text-xs font-bold text-gray-600 bg-gray-200/70 px-2.5 py-0.5 rounded-full">
                        {activeEvents.length} Active
                    </span>
                </div>

                {activeEvents.length === 0 ? (
                    <div className="flex flex-col items-center justify-center py-12 text-center p-4 space-y-2">
                        <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-indigo-50 text-[#1B1F5C]">
                            <CalendarX className="h-6 w-6" aria-hidden="true" />
                        </div>
                        <div>
                            <p className="text-sm font-bold text-gray-900">No active events right now</p>
                            <p className="text-xs text-gray-500 max-w-xs mx-auto mt-0.5">
                                Check back when your scheduled event window opens or view upcoming dates in your dashboard.
                            </p>
                        </div>
                    </div>
                ) : (
                    <ul className="divide-y divide-gray-100" aria-live="polite">
                        {activeEvents.map((evt) => (
                            <li key={evt.event_id} className="p-4 sm:p-5 space-y-4 hover:bg-gray-50/30 transition-colors">
                                <div className="flex items-center justify-between gap-3">
                                    <div className="flex items-center gap-3 min-w-0">
                                        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-indigo-50 text-[#1B1F5C]">
                                            <Clock className="h-5.5 w-5.5" aria-hidden="true" />
                                        </div>
                                        <div className="min-w-0 flex-1">
                                            <h3 className="text-sm sm:text-base font-bold text-gray-900 truncate">
                                                {evt.title}
                                            </h3>
                                            <p className="text-xs text-gray-500 truncate flex items-center gap-1 mt-0.5">
                                                <MapPin className="h-3 w-3 text-[#F5A623]" aria-hidden="true" />
                                                {evt.location ? evt.location : 'Location TBA'}
                                            </p>
                                        </div>
                                    </div>
                                    <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2.5 py-0.5 text-[10px] font-bold text-emerald-700 border border-emerald-200/80 shrink-0">
                                        <span className="h-1.5 w-1.5 rounded-full bg-emerald-500 animate-pulse" aria-hidden="true" />
                                        Live Window
                                    </span>
                                </div>

                                {evt.schedules && evt.schedules.length > 0 && (
                                    <div className="space-y-3 pt-2 border-t border-gray-100">
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

                                                    const checkpoints = [
                                                        {
                                                            key: 'morning_time_in' as CheckpointKey,
                                                            label: 'Morning Time-In',
                                                            session: 'morning' as const,
                                                            type: 'in' as const,
                                                            start: mInStart,
                                                            end: mInEnd,
                                                            done: hasLoggedCheckpoint(evt.event_id, slotIdx, sched.date, 'morning_time_in', slot.morning_time_in),
                                                        },
                                                        {
                                                            key: 'morning_time_out' as CheckpointKey,
                                                            label: 'Morning Time-Out',
                                                            session: 'morning' as const,
                                                            type: 'out' as const,
                                                            start: mOutStart,
                                                            end: mOutEnd,
                                                            done: hasLoggedCheckpoint(evt.event_id, slotIdx, sched.date, 'morning_time_out', slot.morning_time_out),
                                                        },
                                                        {
                                                            key: 'afternoon_time_in' as CheckpointKey,
                                                            label: 'Afternoon Time-In',
                                                            session: 'afternoon' as const,
                                                            type: 'in' as const,
                                                            start: aInStart,
                                                            end: aInEnd,
                                                            done: hasLoggedCheckpoint(evt.event_id, slotIdx, sched.date, 'afternoon_time_in', slot.afternoon_time_in),
                                                        },
                                                        {
                                                            key: 'afternoon_time_out' as CheckpointKey,
                                                            label: 'Afternoon Time-Out',
                                                            session: 'afternoon' as const,
                                                            type: 'out' as const,
                                                            start: aOutStart,
                                                            end: aOutEnd,
                                                            done: hasLoggedCheckpoint(evt.event_id, slotIdx, sched.date, 'afternoon_time_out', slot.afternoon_time_out),
                                                        },
                                                    ].filter((cp): cp is typeof cp & { start: string } => Boolean(cp.start));

                                                    const completedCount = checkpoints.filter((c) => c.done).length;

                                                    return (
                                                        <div
                                                            key={slotIdx}
                                                            className="bg-gray-50/80 p-3.5 sm:p-4 rounded-xl border border-gray-200/70 space-y-3"
                                                        >
                                                            <div className="flex items-center justify-between">
                                                                <span className="font-extrabold text-[#1B1F5C] uppercase tracking-wider text-[10px]">
                                                                    Schedule ({sched.date}) • Slot {slotIdx + 1} Checkpoints
                                                                </span>
                                                                <span className="text-[10px] font-bold px-2.5 py-0.5 rounded-full bg-indigo-50 text-[#1B1F5C] border border-indigo-100">
                                                                    {completedCount} / {checkpoints.length} Completed
                                                                </span>
                                                            </div>

                                                            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-2.5">
                                                                {checkpoints.map((cp) => {
                                                                    const state = checkpointWindowState(cp.start, cp.end, sched.date);
                                                                    const isMorning = cp.session === 'morning';

                                                                    return (
                                                                        <div
                                                                            key={cp.key}
                                                                            className={`p-3 rounded-xl border flex flex-col justify-between transition-all ${
                                                                                cp.done
                                                                                    ? 'bg-emerald-50/70 border-emerald-200 text-emerald-900'
                                                                                    : state === 'open'
                                                                                      ? 'bg-white border-indigo-200 shadow-xs'
                                                                                      : 'bg-gray-100/80 border-gray-200 text-gray-500'
                                                                            }`}
                                                                        >
                                                                            <div className="space-y-1 mb-2">
                                                                                <span className="inline-flex items-center gap-1 text-[10px] font-extrabold uppercase tracking-wider">
                                                                                    {isMorning ? (
                                                                                        <Sun className="h-3 w-3 text-blue-600" />
                                                                                    ) : (
                                                                                        <Sunset className="h-3 w-3 text-amber-600" />
                                                                                    )}
                                                                                    <span>{cp.label}</span>
                                                                                </span>
                                                                                <div className="text-[11px] font-mono font-bold text-gray-800">
                                                                                    {formatTime(cp.start)}
                                                                                    {cp.end ? ` - ${formatTime(cp.end)}` : ''}
                                                                                </div>
                                                                            </div>

                                                                            {cp.done ? (
                                                                                <div className="flex items-center gap-1 text-[11px] font-bold text-emerald-700 py-1">
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
                                                                                    className="w-full mt-1 min-h-[38px] py-1.5 px-3 rounded-lg bg-[#1B1F5C] text-white text-xs font-bold hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] shadow-xs transition-all active:scale-98"
                                                                                >
                                                                                    Log {cp.label} →
                                                                                </button>
                                                                            ) : (
                                                                                <div className="flex items-center gap-1 text-[11px] font-medium text-gray-400 py-1">
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
                            </li>
                        ))}
                    </ul>
                )}
            </main>

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