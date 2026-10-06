import React, { useState, useMemo } from 'react';
import { Head, Link } from '@inertiajs/react';
import {
    Calendar as CalendarIcon,
    Clock,
    ShieldCheck,
    ChevronRight,
    TrendingUp,
    ListChecks,
    CalendarClock,
    MapPin,
    History,
    CalendarX,
    ArrowUpRight,
    ChevronLeft,
    Sparkles,
} from 'lucide-react';
import CheckInModal from '@/components/CheckInModal';
import { type ScheduleItem, type TimeSlot } from '@/lib/eventValidation';
import { findSlotRecord, formatTime, windowState, type SlotType } from '@/lib/slots';
import { SlotStatusBadge, SlotWindowRow, slotBadge } from '@/components/slot-rows';

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

// Lightweight event used by the calendar grid and date inspector (built from event_days).
type CalendarEvent = {
    event_id: number;
    title: string;
    location?: string | null;
    schedules: ScheduleItem[];
};

// One entry per event in the "Coming Up" widget.
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
    today?: string; // YYYY-MM-DD, from the server (falls back to the browser's date)
};

// Browser-local YYYY-MM-DD, used only if the server doesn't send `today`.
const localToday = () => {
    const n = new Date();
    const mm = String(n.getMonth() + 1).padStart(2, '0');
    const dd = String(n.getDate()).padStart(2, '0');
    return `${n.getFullYear()}-${mm}-${dd}`;
};

// Parse a YYYY-MM-DD string as a local date (avoids UTC off-by-one shifts).
const parseDateStr = (dateStr: string) => {
    const [y, m, d] = dateStr.split('-').map(Number);
    return new Date(y, m - 1, d);
};

const formatShortDate = (dateStr: string) =>
    parseDateStr(dateStr).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });

const formatLongDate = (dateStr: string) =>
    parseDateStr(dateStr).toLocaleDateString('en-US', {
        weekday: 'long',
        month: 'long',
        day: 'numeric',
        year: 'numeric',
    });

const formatDateRange = (start: string, end: string) =>
    start === end ? formatShortDate(start) : `${formatShortDate(start)} \u2013 ${formatShortDate(end)}`;

export default function Dashboard({
    student,
    activeEvents,
    calendarEvents = [],
    upcomingEvents = [],
    totalExpectedEvents,
    today: todayProp,
}: DashboardProps) {
    const today = todayProp || localToday();

    const [selectedSlotEvent, setSelectedSlotEvent] = useState<{
        event: Event;
        slot: TimeSlot;
        slotIndex: number;
        dateStr: string;
        type: 'in' | 'out';
    } | null>(null);

    // Calendar navigation state (starts on the server's "today")
    const [currentDate, setCurrentDate] = useState(() => {
        const t = parseDateStr(today);
        return new Date(t.getFullYear(), t.getMonth(), 1);
    });
    const [selectedDateStr, setSelectedDateStr] = useState<string>(today);

    const hasCheckedInSlot = (eventId: number, slotIndex: number, dateStr: string, type: SlotType) =>
        Boolean(findSlotRecord(student.attendances, eventId, dateStr, slotIndex, type));

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

    // Index calendar data by date: { '2026-10-12': [{ event, schedule }, ...] }
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

    // Jump the calendar to a date (used by the Coming Up cards)
    const jumpToDate = (dateStr: string) => {
        const d = parseDateStr(dateStr);
        setCurrentDate(new Date(d.getFullYear(), d.getMonth(), 1));
        setSelectedDateStr(dateStr);
    };

    // Calendar calculation logic
    const year = currentDate.getFullYear();
    const month = currentDate.getMonth();
    const monthName = currentDate.toLocaleString('default', { month: 'long' });

    const firstDayIndex = new Date(year, month, 1).getDay();
    const startingDay = (firstDayIndex + 6) % 7; // Monday start
    const totalDaysInMonth = new Date(year, month + 1, 0).getDate();

    const handlePrevMonth = () => setCurrentDate(new Date(year, month - 1, 1));
    const handleNextMonth = () => setCurrentDate(new Date(year, month + 1, 1));

    return (
        <>
            <Head title="Student Dashboard" />

            <div className="min-h-screen bg-gray-50/50 p-6 lg:p-8 space-y-8 text-gray-900">

                {/* HERO WELCOME BANNER */}
                <div className="relative overflow-hidden rounded-3xl bg-gradient-to-r from-[#0b1354] to-[#1B1F5C] p-6 lg:p-8 text-white shadow-md">
                    <div className="relative z-10 flex flex-col md:flex-row md:items-center md:justify-between gap-6">
                        <div className="flex items-center gap-5">
                            <div className="h-16 w-16 overflow-hidden rounded-2xl border-2 border-amber-400 bg-indigo-950 shadow-inner shrink-0">
                                {student.face_photo_url ? (
                                    <img src={student.face_photo_url} alt="Profile" className="h-full w-full object-cover" />
                                ) : (
                                    <div className="flex h-full w-full items-center justify-center font-bold text-amber-400 text-xl">
                                        {student.firstname[0]}
                                    </div>
                                )}
                            </div>
                            <div>
                                <div className="flex items-center gap-2">
                                    <span className="rounded-full bg-emerald-500/20 border border-emerald-400/30 px-3 py-0.5 text-xs font-semibold text-emerald-300 flex items-center gap-1">
                                        <ShieldCheck className="h-3.5 w-3.5" /> Biometrics verified
                                    </span>
                                </div>
                                <h1 className="text-2xl lg:text-3xl font-black tracking-tight mt-1">
                                    Welcome back, {student.firstname} {student.surname}
                                </h1>
                                <p className="text-xs lg:text-sm text-indigo-200 mt-0.5 font-mono">
                                    Student ID: {student.student_number}
                                </p>
                            </div>
                        </div>

                        <div className="flex items-center gap-3 bg-white/10 backdrop-blur-md p-4 rounded-2xl border border-white/10 shrink-0">
                            <div>
                                <span className="text-[11px] uppercase tracking-wider text-indigo-300 font-semibold block">Attendance Rate</span>
                                <span className="text-2xl font-black text-amber-400">
                                    {attendanceRate !== null ? `${attendanceRate}%` : '—'}
                                </span>
                            </div>
                            <div className="h-8 w-px bg-white/20 mx-2" />
                            <div>
                                <span className="text-[11px] uppercase tracking-wider text-indigo-300 font-semibold block">Sessions</span>
                                <span className="text-2xl font-black text-white">{eventsAttended}</span>
                            </div>
                        </div>
                    </div>
                </div>

                {/* STAT CARDS ROW */}
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-5">
                    <StatCard
                        icon={<TrendingUp className="h-5 w-5 text-[#0b1354]" />}
                        label="Attendance Rate"
                        value={attendanceRate !== null ? `${attendanceRate}%` : '—'}
                        caption={totalExpectedEvents ? `${eventsAttended} of ${totalExpectedEvents} sessions completed` : 'Term progress'}
                    />
                    <StatCard
                        icon={<ListChecks className="h-5 w-5 text-[#0b1354]" />}
                        label="Sessions Attended"
                        value={String(eventsAttended)}
                        caption="Total recorded logs"
                    />
                    <StatCard
                        icon={<CalendarClock className="h-5 w-5 text-[#0b1354]" />}
                        label="Events Today"
                        value={String(activeEvents.length)}
                        caption="Scheduled for today"
                    />
                </div>

                {/* MAIN DESKTOP GRID LAYOUT (2 Columns) */}
                <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">

                    {/* LEFT COLUMN: TODAY'S ACTIVE EVENTS & SLOTS (Takes up 2 columns) */}
                    <div className="lg:col-span-2 space-y-6">
                        <div className="flex items-center justify-between">
                            <h2 className="text-lg font-bold text-gray-900">Today's Events & Check-In Slots</h2>
                            <span className="text-xs font-semibold text-gray-400 bg-gray-200/60 px-2.5 py-1 rounded-full">
                                {activeEvents.length} active
                            </span>
                        </div>

                        {activeEvents.length === 0 ? (
                            <div className="bg-white p-12 rounded-3xl shadow-xs border border-gray-100 text-center space-y-3">
                                <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-indigo-50 text-[#0b1354]">
                                    <CalendarX className="h-7 w-7 stroke-[1.5]" />
                                </div>
                                <div>
                                    <h3 className="font-bold text-gray-900 text-base">No activity today</h3>
                                    <p className="text-xs text-gray-400 mt-1">There are no events scheduled or open for check-in today.</p>
                                </div>
                            </div>
                        ) : (
                            <div className="space-y-4">
                                {activeEvents.map((evt) => (
                                    <div key={evt.event_id} className="bg-white p-6 rounded-3xl shadow-xs border border-gray-100 space-y-4 hover:shadow-md transition">
                                        <div className="flex items-start justify-between gap-4">
                                            <div className="flex items-center gap-3.5">
                                                <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-indigo-50 text-[#0b1354]">
                                                    <Clock className="h-6 w-6" />
                                                </div>
                                                <div>
                                                    <h3 className="font-bold text-gray-900 text-base">{evt.title}</h3>
                                                    <p className="text-xs text-gray-400 flex items-center gap-1 mt-0.5">
                                                        <MapPin className="h-3.5 w-3.5 text-amber-500" />
                                                        {evt.location || 'Location TBA'}
                                                    </p>
                                                </div>
                                            </div>
                                            <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-3 py-1 text-xs font-bold text-emerald-700 border border-emerald-200/50">
                                                <span className="h-2 w-2 rounded-full bg-emerald-500 animate-pulse" />
                                                Live Window
                                            </span>
                                        </div>

                                        {evt.schedules && evt.schedules.length > 0 && (
                                            <div className="grid grid-cols-1 md:grid-cols-2 gap-3 pt-2 border-t border-gray-100">
                                                {evt.schedules.map((sched, sIdx) => (
                                                    <div key={sIdx} className="bg-gray-50/70 p-4 rounded-2xl space-y-3 border border-gray-100">
                                                        <p className="text-xs font-bold text-gray-700">{sched.date}</p>
                                                        {sched.slots?.map((slot, slotIdx) => {
                                                            const inState = windowState(slot, 'in', sched.date);
                                                            const outState = windowState(slot, 'out', sched.date);
                                                            const inDone = hasCheckedInSlot(evt.event_id, slotIdx, sched.date, 'in');
                                                            const outDone = hasCheckedInSlot(evt.event_id, slotIdx, sched.date, 'out');
                                                            const badge = slotBadge({
                                                                hasIn: Boolean(slot.time_in_start),
                                                                hasOut: Boolean(slot.time_out_start),
                                                                inState,
                                                                outState,
                                                                inDone,
                                                                outDone,
                                                            });

                                                            return (
                                                                <div key={slotIdx} className="space-y-2 pt-2 first:pt-0 border-t first:border-t-0 border-gray-200/50">
                                                                    <div className="flex items-center justify-between">
                                                                        <span className="font-bold text-gray-400 uppercase text-[10px]">Slot {slotIdx + 1}</span>
                                                                        <SlotStatusBadge status={badge} />
                                                                    </div>

                                                                    {slot.time_in_start && (
                                                                        <SlotWindowRow
                                                                            label="In"
                                                                            time={formatTime(slot.time_in_start)}
                                                                            state={inState}
                                                                            done={inDone}
                                                                            doneLabel="Checked in"
                                                                            actionLabel="Check-In"
                                                                            onAction={() => setSelectedSlotEvent({ event: evt, slot, slotIndex: slotIdx, dateStr: sched.date, type: 'in' })}
                                                                        />
                                                                    )}

                                                                    {slot.time_out_start && (
                                                                        <SlotWindowRow
                                                                            label="Out"
                                                                            time={formatTime(slot.time_out_start)}
                                                                            state={outState}
                                                                            done={outDone}
                                                                            doneLabel="Checked out"
                                                                            actionLabel="Check-Out"
                                                                            blockedReason={slot.time_in_start && !inDone ? 'Check in first' : null}
                                                                            onAction={() => setSelectedSlotEvent({ event: evt, slot, slotIndex: slotIdx, dateStr: sched.date, type: 'out' })}
                                                                        />
                                                                    )}
                                                                </div>
                                                            );
                                                        })}
                                                    </div>
                                                ))}
                                            </div>
                                        )}
                                    </div>
                                ))}
                            </div>
                        )}
                    </div>

                    {/* RIGHT COLUMN: SIDEBAR (Interactive Calendar & Event Inspector) */}
                    <div className="space-y-6">

                        {/* INTERACTIVE MONTHLY CALENDAR WIDGET */}
                        <div className="bg-white p-6 rounded-3xl shadow-xs border border-gray-100 space-y-4">
                            <div className="flex items-center justify-between">
                                <h3 className="font-bold text-gray-900 text-base flex items-center gap-2">
                                    <CalendarIcon className="h-5 w-5 text-[#0b1354]" /> Calendar
                                </h3>
                                <div className="flex items-center gap-1">
                                    <button
                                        onClick={handlePrevMonth}
                                        className="p-1.5 rounded-xl hover:bg-gray-100 text-gray-600 transition"
                                        title="Previous Month"
                                    >
                                        <ChevronLeft className="h-4 w-4" />
                                    </button>
                                    <span className="text-xs font-bold text-gray-800 min-w-[90px] text-center">
                                        {monthName} {year}
                                    </span>
                                    <button
                                        onClick={handleNextMonth}
                                        className="p-1.5 rounded-xl hover:bg-gray-100 text-gray-600 transition"
                                        title="Next Month"
                                    >
                                        <ChevronRight className="h-4 w-4" />
                                    </button>
                                </div>
                            </div>

                            {/* Calendar Grid */}
                            <div className="grid grid-cols-7 gap-1 text-center">
                                {['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) => (
                                    <span key={d} className="text-[11px] font-bold uppercase text-gray-400 py-1">
                                        {d}
                                    </span>
                                ))}

                                {/* Blank cells for offset */}
                                {Array.from({ length: startingDay }).map((_, index) => (
                                    <div key={`empty-${index}`} />
                                ))}

                                {/* Day cells */}
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
                                            className={`relative h-9 w-9 mx-auto rounded-xl flex flex-col items-center justify-center text-xs font-bold transition ${
                                                isSelected
                                                    ? 'bg-[#0b1354] text-white shadow-sm'
                                                    : isToday
                                                    ? 'bg-amber-400 text-gray-900 font-black'
                                                    : 'text-gray-700 hover:bg-gray-100'
                                            }`}
                                        >
                                            <span>{dayNum}</span>
                                            {hasEvent && !isSelected && (
                                                <span className="absolute bottom-1 h-1 w-1 rounded-full bg-amber-500" />
                                            )}
                                            {hasEvent && isSelected && (
                                                <span className="absolute bottom-1 h-1 w-1 rounded-full bg-amber-300" />
                                            )}
                                        </button>
                                    );
                                })}
                            </div>

                            {/* SELECTED DATE EVENT INSPECTOR */}
                            <div className="pt-3 border-t border-gray-100 space-y-2">
                                <div className="flex items-center justify-between text-xs gap-2">
                                    <span className="text-gray-400 truncate">{formatLongDate(selectedDateStr)}</span>
                                    <span className="font-bold text-[#0b1354] shrink-0">{selectedDateEntries.length} found</span>
                                </div>

                                {selectedDateEntries.length > 0 ? (
                                    <div className="space-y-2 max-h-72 overflow-y-auto pr-1">
                                        {selectedDateEntries.map(({ event, schedule }) => (
                                            <div key={event.event_id} className="p-2.5 rounded-xl bg-indigo-50/50 border border-indigo-100/60 text-xs space-y-2">
                                                <div>
                                                    <p className="font-bold text-[#0b1354] truncate">{event.title}</p>
                                                    <p className="text-[11px] text-gray-500 mt-0.5 flex items-center gap-1">
                                                        <MapPin className="h-3 w-3 text-amber-500" /> {event.location || 'Location TBA'}
                                                    </p>
                                                </div>

                                                {schedule.slots?.map((slot, slotIdx) => {
                                                    const inState = windowState(slot, 'in', schedule.date);
                                                    const outState = windowState(slot, 'out', schedule.date);
                                                    const inDone = hasCheckedInSlot(event.event_id, slotIdx, schedule.date, 'in');
                                                    const outDone = hasCheckedInSlot(event.event_id, slotIdx, schedule.date, 'out');
                                                    const badge = slotBadge({
                                                        hasIn: Boolean(slot.time_in_start),
                                                        hasOut: Boolean(slot.time_out_start),
                                                        inState,
                                                        outState,
                                                        inDone,
                                                        outDone,
                                                    });

                                                    return (
                                                        <div key={slotIdx} className="rounded-lg bg-white/80 border border-indigo-100/60 p-2 space-y-1">
                                                            <div className="flex items-center justify-between">
                                                                <span className="font-bold text-gray-400 uppercase text-[10px]">Slot {slotIdx + 1}</span>
                                                                <SlotStatusBadge status={badge} />
                                                            </div>
                                                            {slot.time_in_start && (
                                                                <p className="text-[11px] text-gray-600 flex items-center gap-1">
                                                                    <Clock className="h-3 w-3 text-gray-400" /> Check-in opens {formatTime(slot.time_in_start)}
                                                                </p>
                                                            )}
                                                            {slot.time_out_start && (
                                                                <p className="text-[11px] text-gray-600 flex items-center gap-1">
                                                                    <Clock className="h-3 w-3 text-gray-400" /> Check-out opens {formatTime(slot.time_out_start)}
                                                                </p>
                                                            )}
                                                        </div>
                                                    );
                                                })}
                                            </div>
                                        ))}
                                    </div>
                                ) : (
                                    <p className="text-[11px] text-gray-400 italic text-center py-2">No events scheduled for this date.</p>
                                )}
                            </div>
                        </div>

                        {/* COMING UP EVENTS (Dynamic from Admin) */}
                        <div className="bg-white p-6 rounded-3xl shadow-xs border border-gray-100 space-y-4">
                            <div className="flex items-center justify-between">
                                <h3 className="font-bold text-gray-900 text-base flex items-center gap-2">
                                    <Sparkles className="h-5 w-5 text-amber-500" /> Coming Up
                                </h3>
                                <Link href="/events" className="text-xs font-bold text-[#0b1354] hover:underline flex items-center gap-0.5">
                                    View all <ArrowUpRight className="h-3.5 w-3.5" />
                                </Link>
                            </div>

                            {upcomingEvents.length > 0 ? (
                                <div className="space-y-3">
                                    {upcomingEvents.slice(0, 3).map((evt) => (
                                        <button
                                            key={evt.event_id}
                                            type="button"
                                            onClick={() => jumpToDate(evt.next_date)}
                                            className="w-full text-left flex items-start gap-3 p-3 rounded-2xl bg-gray-50 border border-gray-100 hover:bg-amber-50/50 transition"
                                        >
                                            <div className="h-9 w-9 rounded-xl bg-amber-50 text-amber-600 flex items-center justify-center shrink-0 font-bold text-xs">
                                                {evt.next_date.split('-')[2]}
                                            </div>
                                            <div className="min-w-0 flex-1">
                                                <p className="text-xs font-bold text-gray-900 truncate">{evt.title}</p>
                                                <p className="text-[11px] text-gray-400 mt-0.5 truncate">
                                                    {formatDateRange(evt.start_date, evt.end_date)}
                                                    {evt.day_count > 1 ? ` \u2022 ${evt.day_count} days` : ''}
                                                    {evt.location ? ` \u2022 ${evt.location}` : ''}
                                                </p>
                                            </div>
                                        </button>
                                    ))}
                                </div>
                            ) : (
                                <p className="text-xs text-gray-400 text-center py-6">No upcoming events scheduled.</p>
                            )}
                        </div>

                        {/* ATTENDANCE HISTORY QUICK CARD */}
                        <div className="bg-white p-6 rounded-3xl shadow-xs border border-gray-100 space-y-4">
                            <div className="flex items-center justify-between">
                                <h3 className="font-bold text-gray-900 text-base flex items-center gap-2">
                                    <History className="h-5 w-5 text-[#0b1354]" /> Attendance History
                                </h3>
                                <Link href="/attendance/history" className="text-xs font-bold text-[#0b1354] hover:underline flex items-center gap-0.5">
                                    View all <ChevronRight className="h-3.5 w-3.5" />
                                </Link>
                            </div>

                            {recentAttendances.length > 0 ? (
                                <div className="space-y-3">
                                    {recentAttendances.map((log) => {
                                        const logDate = new Date(log.logged_at || log.attendance_time);
                                        return (
                                            <div key={log.attendance_id} className="flex items-center justify-between p-3 rounded-2xl bg-gray-50 border border-gray-100">
                                                <div className="min-w-0 pr-2">
                                                    <p className="text-xs font-bold text-gray-900 truncate">{log.event?.title || 'Event'}</p>
                                                    <p className="text-[11px] text-gray-400 mt-0.5">
                                                        {logDate.toLocaleDateString()} &bull; {logDate.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                                                    </p>
                                                </div>
                                                <span className="inline-flex items-center rounded-full bg-emerald-50 px-2.5 py-0.5 text-[11px] font-bold text-emerald-700 border border-emerald-200">
                                                    {log.status || 'Present'}
                                                </span>
                                            </div>
                                        );
                                    })}
                                </div>
                            ) : (
                                <p className="text-xs text-gray-400 text-center py-6">No attendance records found yet.</p>
                            )}
                        </div>

                    </div>
                </div>
            </div>

            {/* SHARED LIVENESS CHECK-IN MODAL */}
            {selectedSlotEvent && (
                <CheckInModal 
                    event={selectedSlotEvent.event as any} 
                    slot={selectedSlotEvent.slot}
                    slotIndex={selectedSlotEvent.slotIndex}
                    dateStr={selectedSlotEvent.dateStr}
                    type={selectedSlotEvent.type}
                    onClose={() => setSelectedSlotEvent(null)} 
                />
            )}
        </>
    );
}

function StatCard({ icon, label, value, caption }: { icon: React.ReactNode; label: string; value: string; caption: string }) {
    return (
        <div className="rounded-3xl bg-white p-6 shadow-xs border border-gray-100 flex flex-col justify-between">
            <div className="flex items-center justify-between">
                <span className="text-xs font-bold uppercase tracking-wider text-gray-400">{label}</span>
                <div className="h-10 w-10 rounded-2xl bg-indigo-50 flex items-center justify-center">
                    {icon}
                </div>
            </div>
            <div className="mt-4">
                <p className="text-3xl font-black text-gray-900 tracking-tight">{value}</p>
                <p className="text-xs text-gray-400 mt-1">{caption}</p>
            </div>
        </div>
    );
}