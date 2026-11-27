import React, { useMemo, useState } from 'react';
import { Head, Link } from '@inertiajs/react';
import AdminLayout from '@/layouts/admin-layout';
import {
    ArrowLeft,
    Users,
    CheckCircle2,
    ShieldCheck,
    Clock,
    XCircle,
    AlertTriangle,
    Calendar,
    CalendarX,
    Search,
    X,
    RotateCcw,
} from 'lucide-react';
import {
    ResponsiveContainer,
    BarChart,
    Bar,
    AreaChart,
    Area,
    XAxis,
    YAxis,
    CartesianGrid,
    Tooltip,
    Legend,
} from 'recharts';

// ─── Types ─────────────────────────────────────────────────────────────────────

type DepartmentRow = {
    course: string;
    total: number;
    checkedIn: number;
    successful: number;
    noShow: number;
    avg_confidence: number;
};

type TimelineRow = {
    label: string;
    count: number;
    successful: number;
    cumulative: number;
};

type RosterRow = {
    student_id: string | number;
    name: string;
    course: string;
    status: string;
    confidence_score: number;
    logged_at: string;
};

type SlotItem = {
    time_in_start?: string;
    time_in_end?: string;
    time_out_start?: string;
    time_out_end?: string;
    has_afternoon?: boolean;
    morning_time_in_start?: string;
    morning_time_in_end?: string;
    morning_time_out_start?: string;
    morning_time_out_end?: string;
    afternoon_time_in_start?: string;
    afternoon_time_in_end?: string;
    afternoon_time_out_start?: string;
    afternoon_time_out_end?: string;
};

type ScheduleItem = {
    date: string;
    slots: SlotItem[];
};

type DailyBreakdownItem = {
    date: string;
    slots: SlotItem[];
    attendees: number;
    successful: number;
};

type EventModel = {
    id: number;
    title: string;
    name?: string;
    description?: string;
    created_at?: string;
    schedules?: ScheduleItem[];
    [key: string]: any;
};

type Analytics = {
    totalAttendees: number;
    successfulCheckins: number;
    eventSuccessRate: number;
    avgConfidence: number;
    dailyBreakdown?: DailyBreakdownItem[];
    departmentBreakdown: DepartmentRow[];
    checkinTimeline: TimelineRow[];
    roster: RosterRow[];
    flaggedRoster?: RosterRow[];
};

type Props = {
    event: EventModel;
    analytics: Analytics;
};

type RosterStatusFilter = 'all' | 'verified' | 'failed';

// ─── Constants & Formatting ───────────────────────────────────────────────────

const NAVY = '#1B1F5C';

const fmt = new Intl.NumberFormat('en-PH');
const confidenceFmt = new Intl.NumberFormat('en-PH', {
    style: 'percent',
    minimumFractionDigits: 1,
});

function formatTimestamp(value: string): string {
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return value;
    return d.toLocaleString('en-PH', {
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
    });
}

function formatSlotWindow(slot: SlotItem): string {
    const start = slot.morning_time_in_start || slot.time_in_start;
    const end =
        (slot.has_afternoon && (slot.afternoon_time_out_end || slot.afternoon_time_out_start)) ||
        slot.morning_time_out_end ||
        slot.morning_time_out_start ||
        slot.time_out_end ||
        slot.time_out_start ||
        'End';
    return start ? `${start} – ${end}` : `Until ${end}`;
}

function isVerifiedStatus(status: string): boolean {
    const s = status.toLowerCase();
    return s === 'success' || s === 'present' || s === 'verified';
}

function ChartTooltip({ active, payload, label }: any) {
    if (!active || !payload?.length) return null;
    return (
        <div className="space-y-1 rounded-xl border border-gray-200 bg-white p-3 text-xs shadow-sm">
            <p className="font-extrabold text-[#1B1F5C]">{label}</p>
            {payload.map((entry: any, i: number) => (
                <p key={i} style={{ color: entry.color }} className="flex justify-between gap-4">
                    <span className="font-semibold">{entry.name}</span>
                    <span className="font-black">{fmt.format(entry.value)}</span>
                </p>
            ))}
        </div>
    );
}

function EmptyState({ message }: { message: string }) {
    return (
        <div className="flex h-56 w-full flex-col items-center justify-center space-y-2 rounded-xl border border-dashed border-gray-200 bg-[#F5F6FA]/70 p-4 text-center">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 text-[#1B1F5C]">
                <CalendarX className="h-4 w-4" aria-hidden="true" />
            </div>
            <p className="text-xs font-bold text-gray-600">{message}</p>
        </div>
    );
}

function StatusBadge({ status }: { status: string }) {
    if (isVerifiedStatus(status)) {
        return (
            <span className="inline-flex items-center gap-1 rounded-full border border-emerald-200 bg-emerald-50 px-2.5 py-0.5 text-xs font-bold text-emerald-800">
                <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" />
                <span>Verified</span>
            </span>
        );
    }
    return (
        <span className="inline-flex items-center gap-1 rounded-full border border-rose-200 bg-rose-50 px-2.5 py-0.5 text-xs font-bold text-rose-800">
            <XCircle className="h-3.5 w-3.5" aria-hidden="true" />
            <span>{status}</span>
        </span>
    );
}

function ConfidenceBar({ score }: { score: number }) {
    const pct = Math.min(100, Math.max(0, Math.round(score * 100)));
    const color = pct >= 70 ? 'bg-emerald-600' : pct >= 60 ? 'bg-amber-500' : 'bg-rose-600';
    return (
        <div className="flex items-center gap-2">
            <div
                role="progressbar"
                aria-label="Biometric confidence score"
                aria-valuenow={pct}
                aria-valuemin={0}
                aria-valuemax={100}
                className="h-1.5 w-20 overflow-hidden rounded-full bg-gray-200"
            >
                <div className={`h-full rounded-full ${color}`} style={{ width: `${pct}%` }} />
            </div>
            <span className="font-mono text-xs font-bold text-gray-700">{pct}%</span>
        </div>
    );
}

// ─── Main Component ─────────────────────────────────────────────────────────────

export default function EventAnalyticsShow({ event, analytics }: Props) {
    const eventTitle = event.title || event.name || 'Event Analytics';

    const {
        totalAttendees,
        successfulCheckins,
        eventSuccessRate,
        avgConfidence,
        dailyBreakdown = [],
        departmentBreakdown,
        checkinTimeline,
        roster,
        flaggedRoster = [],
    } = analytics;

    const failed = Math.max(0, totalAttendees - successfulCheckins);

    // Client-side Roster Filtering & Search
    const [rosterSearch, setRosterSearch] = useState('');
    const [statusFilter, setStatusFilter] = useState<RosterStatusFilter>('all');

    const filteredRoster = useMemo(() => {
        const query = rosterSearch.trim().toLowerCase();
        return roster.filter((row) => {
            const matchesStatus =
                statusFilter === 'all'
                    ? true
                    : statusFilter === 'verified'
                      ? isVerifiedStatus(row.status)
                      : !isVerifiedStatus(row.status);

            if (!matchesStatus) return false;
            if (!query) return true;

            return (
                String(row.student_id).toLowerCase().includes(query) ||
                row.name.toLowerCase().includes(query) ||
                row.course.toLowerCase().includes(query)
            );
        });
    }, [roster, rosterSearch, statusFilter]);

    const hasActiveRosterFilters = rosterSearch.trim() !== '' || statusFilter !== 'all';

    return (
        <>
            <Head title={`Analytics — ${eventTitle} | 4ttnd Attendance System`} />

            <div className="min-h-screen space-y-4 bg-[#F5F6FA] p-3 font-sans text-gray-900 antialiased sm:p-5">
                {/* BACK NAVIGATION */}
                <nav aria-label="Breadcrumb navigation">
                    <Link
                        href="/admin/analytics"
                        className="inline-flex min-h-[38px] items-center gap-1.5 rounded-lg px-1.5 text-xs font-bold text-gray-600 transition-colors hover:text-[#1B1F5C] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                    >
                        <ArrowLeft className="h-4 w-4" aria-hidden="true" />
                        <span>Back to Analytics Overview</span>
                    </Link>
                </nav>

                {/* EVENT HEADER */}
                <header className="rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs sm:p-5">
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                        <div className="space-y-1">
                            <span className="inline-block rounded-md border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 px-2.5 py-0.5 text-[10px] font-extrabold uppercase tracking-wider text-[#1B1F5C]">
                                Event Attendance Data
                            </span>
                            <h1 className="text-xl font-black tracking-tight text-[#1B1F5C] sm:text-2xl">
                                {eventTitle}
                            </h1>
                            {event.description && (
                                <p className="max-w-2xl text-xs font-medium text-gray-600 sm:text-sm">
                                    {event.description}
                                </p>
                            )}
                        </div>
                        {event.created_at && (
                            <div className="flex shrink-0 items-center gap-1.5 rounded-xl border border-gray-200/80 bg-[#F5F6FA] px-3 py-1.5 text-xs font-bold text-gray-600">
                                <Clock className="h-4 w-4 text-[#F5A623]" aria-hidden="true" />
                                <span>
                                    {new Date(event.created_at).toLocaleDateString('en-PH', {
                                        year: 'numeric',
                                        month: 'long',
                                        day: 'numeric',
                                    })}
                                </span>
                            </div>
                        )}
                    </div>
                </header>

                {/* KPI CARDS RIBBON */}
                <section
                    aria-label="Event Key Performance Metrics"
                    className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4"
                >
                    <EventKpiCard
                        label="Total Check-ins"
                        value={fmt.format(totalAttendees)}
                        icon={<Users className="h-4 w-4" aria-hidden="true" />}
                        iconBg="border-[#1B1F5C]/15 bg-[#1B1F5C]/5 text-[#1B1F5C]"
                    />
                    <EventKpiCard
                        label="Verified"
                        value={fmt.format(successfulCheckins)}
                        sub={`${eventSuccessRate}% success rate`}
                        subColor="text-emerald-800"
                        icon={<CheckCircle2 className="h-4 w-4" aria-hidden="true" />}
                        iconBg="border-emerald-200 bg-emerald-50 text-emerald-700"
                    />
                    <EventKpiCard
                        label="Failed Verification"
                        value={fmt.format(failed)}
                        sub={totalAttendees > 0 ? `${Math.round((failed / totalAttendees) * 100)}% of attempts` : undefined}
                        icon={<XCircle className="h-4 w-4" aria-hidden="true" />}
                        iconBg="border-rose-200 bg-rose-50 text-rose-700"
                    />
                    <EventKpiCard
                        label="Avg. Confidence"
                        value={confidenceFmt.format(avgConfidence)}
                        sub="Facial recognition score"
                        icon={<ShieldCheck className="h-4 w-4" aria-hidden="true" />}
                        iconBg="border-amber-200 bg-amber-50 text-amber-800"
                    />
                </section>

                {/* MULTI-DAY & TIME SLOTS BREAKDOWN */}
                {dailyBreakdown.length > 0 && (
                    <section
                        aria-labelledby="daily-breakdown-heading"
                        className="space-y-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs sm:p-5"
                    >
                        <div className="flex items-center gap-2 border-b border-gray-100 pb-2">
                            <Calendar className="h-4 w-4 text-[#1B1F5C]" aria-hidden="true" />
                            <h2
                                id="daily-breakdown-heading"
                                className="text-base font-extrabold text-[#1B1F5C]"
                            >
                                Schedule &amp; Daily Breakdown
                            </h2>
                        </div>
                        <div className="grid grid-cols-1 gap-3 md:grid-cols-2 lg:grid-cols-3">
                            {dailyBreakdown.map((day, idx) => (
                                <div
                                    key={idx}
                                    className="space-y-2 rounded-xl border border-gray-200/80 bg-[#F5F6FA]/70 p-3.5"
                                >
                                    <div className="flex items-center justify-between gap-2">
                                        <span className="text-xs font-extrabold text-[#1B1F5C] sm:text-sm">
                                            Day {idx + 1}: {day.date}
                                        </span>
                                        <span className="rounded-full border border-gray-200 bg-white px-2.5 py-0.5 text-[11px] font-bold text-gray-700 shadow-2xs">
                                            {fmt.format(day.attendees)} Check-ins
                                        </span>
                                    </div>

                                    <div className="space-y-1 border-t border-gray-200/70 pt-1.5">
                                        <p className="text-[10px] font-extrabold uppercase tracking-wider text-gray-500">
                                            Time Windows:
                                        </p>
                                        <div className="flex flex-wrap gap-1.5">
                                            {day.slots?.map((slot, sIdx) => (
                                                <span
                                                    key={sIdx}
                                                    className="rounded-md border border-gray-200 bg-white px-2 py-0.5 font-mono text-xs font-bold text-gray-700"
                                                >
                                                    {formatSlotWindow(slot)}
                                                </span>
                                            ))}
                                        </div>
                                    </div>
                                </div>
                            ))}
                        </div>
                    </section>
                )}

                {/* DEPARTMENT BREAKDOWN & CUMULATIVE TIMELINE */}
                <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                    {/* Stacked Bar Chart */}
                    <section
                        aria-labelledby="course-chart-heading"
                        className="space-y-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs sm:p-5"
                    >
                        <div>
                            <h2
                                id="course-chart-heading"
                                className="text-base font-extrabold text-[#1B1F5C]"
                            >
                                Attendance by Course
                            </h2>
                            <p className="text-xs font-medium text-gray-600">
                                Sorted by academic program volume and check-in share
                            </p>
                        </div>
                        {departmentBreakdown.length > 0 ? (
                            <div className="h-56">
                                <ResponsiveContainer width="100%" height="100%">
                                    <BarChart
                                        data={departmentBreakdown}
                                        layout="vertical"
                                        margin={{ top: 8, right: 12, left: 12, bottom: 8 }}
                                    >
                                        <CartesianGrid
                                            strokeDasharray="3 3"
                                            horizontal={false}
                                            stroke="#f1f5f9"
                                        />
                                        <XAxis
                                            type="number"
                                            allowDecimals={false}
                                            tick={{ fontSize: 10, fill: '#64748b' }}
                                            tickLine={false}
                                            axisLine={false}
                                        />
                                        <YAxis
                                            dataKey="course"
                                            type="category"
                                            width={110}
                                            tick={{ fontSize: 10, fill: '#1B1F5C', fontWeight: 600 }}
                                            tickLine={false}
                                            axisLine={false}
                                        />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Legend
                                            wrapperStyle={{
                                                fontSize: 11,
                                                fontWeight: 600,
                                                paddingTop: '12px',
                                            }}
                                            verticalAlign="bottom"
                                        />
                                        <Bar
                                            dataKey="checkedIn"
                                            name="Checked in"
                                            stackId="a"
                                            fill={NAVY}
                                            barSize={16}
                                            radius={[0, 0, 0, 0]}
                                        />
                                        <Bar
                                            dataKey="noShow"
                                            name="No-show"
                                            stackId="a"
                                            fill="#E2E8F0"
                                            barSize={16}
                                            radius={[0, 4, 4, 0]}
                                        />
                                    </BarChart>
                                </ResponsiveContainer>
                            </div>
                        ) : (
                            <EmptyState message="No department breakdown data for this event." />
                        )}
                    </section>

                    {/* Arrival Pattern Area Chart */}
                    <section
                        aria-labelledby="timeline-chart-heading"
                        className="space-y-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs sm:p-5"
                    >
                        <div>
                            <h2
                                id="timeline-chart-heading"
                                className="text-base font-extrabold text-[#1B1F5C]"
                            >
                                Arrival Pattern Timeline
                            </h2>
                            <p className="text-xs font-medium text-gray-600">
                                Cumulative student arrivals across the active window
                            </p>
                        </div>
                        {checkinTimeline.length > 0 ? (
                            <div className="h-56">
                                <ResponsiveContainer width="100%" height="100%">
                                    <AreaChart
                                        data={checkinTimeline}
                                        margin={{ top: 4, right: 8, left: 0, bottom: 4 }}
                                    >
                                        <CartesianGrid
                                            strokeDasharray="3 3"
                                            vertical={false}
                                            stroke="#f1f5f9"
                                        />
                                        <XAxis
                                            dataKey="label"
                                            tick={{ fontSize: 10, fill: '#64748b' }}
                                            tickLine={false}
                                            axisLine={false}
                                        />
                                        <YAxis
                                            allowDecimals={false}
                                            tick={{ fontSize: 10, fill: '#64748b' }}
                                            tickLine={false}
                                            axisLine={false}
                                        />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Area
                                            type="monotone"
                                            dataKey="cumulative"
                                            name="Total Check-ins"
                                            stroke={NAVY}
                                            fill="#EEF2FF"
                                            strokeWidth={2.5}
                                        />
                                    </AreaChart>
                                </ResponsiveContainer>
                            </div>
                        ) : (
                            <EmptyState message="No timeline data for this event." />
                        )}
                    </section>
                </div>

                {/* FLAGGED LOW-CONFIDENCE REVIEW SECTION */}
                {flaggedRoster.length > 0 && (
                    <section
                        aria-labelledby="flagged-queue-heading"
                        className="space-y-3 rounded-2xl border border-amber-300/80 bg-white p-4 shadow-xs sm:p-5"
                    >
                        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-amber-100 pb-2.5">
                            <div className="flex items-center gap-2.5">
                                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-amber-200 bg-amber-50 text-amber-700">
                                    <AlertTriangle className="h-4 w-4" aria-hidden="true" />
                                </div>
                                <div>
                                    <h2
                                        id="flagged-queue-heading"
                                        className="text-base font-extrabold text-[#1B1F5C]"
                                    >
                                        Flagged Verification Exception Queue
                                    </h2>
                                    <p className="text-xs font-medium text-gray-600">
                                        Biometric scores falling below confidence threshold
                                    </p>
                                </div>
                            </div>
                            <span className="rounded-full border border-amber-200 bg-amber-50 px-2.5 py-0.5 text-xs font-bold text-amber-800">
                                {flaggedRoster.length} Flagged
                            </span>
                        </div>

                        {/* Mobile Cards (< md) */}
                        <div className="divide-y divide-gray-100 md:hidden">
                            {flaggedRoster.map((row, i) => (
                                <div key={i} className="space-y-1.5 py-3 first:pt-1 last:pb-1">
                                    <div className="flex items-start justify-between gap-2">
                                        <div>
                                            <p className="text-xs font-extrabold text-gray-900">
                                                {row.name}
                                            </p>
                                            <p className="font-mono text-[11px] text-gray-500">
                                                {row.student_id} • {row.course}
                                            </p>
                                        </div>
                                        <span className="font-mono text-[11px] text-gray-500">
                                            {formatTimestamp(row.logged_at)}
                                        </span>
                                    </div>
                                    <div className="flex flex-wrap items-center justify-between gap-2 pt-1">
                                        <span className="text-[11px] font-bold text-amber-800">
                                            Low facial match confidence
                                        </span>
                                        <ConfidenceBar score={row.confidence_score} />
                                    </div>
                                </div>
                            ))}
                        </div>

                        {/* Desktop Table (>= md) */}
                        <div className="hidden overflow-x-auto md:block">
                            <table className="w-full text-left text-xs text-gray-700 sm:text-sm">
                                <thead>
                                    <tr className="border-b border-gray-100 text-[10px] font-extrabold uppercase tracking-wider text-gray-500">
                                        <th scope="col" className="pb-3 pr-4">
                                            Student
                                        </th>
                                        <th scope="col" className="pb-3 pr-4">
                                            Course
                                        </th>
                                        <th scope="col" className="pb-3 pr-4">
                                            Reason Flagged
                                        </th>
                                        <th scope="col" className="pb-3 pr-4">
                                            Confidence Score
                                        </th>
                                        <th scope="col" className="pb-3">
                                            Checked In
                                        </th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-gray-100">
                                    {flaggedRoster.map((row, i) => (
                                        <tr
                                            key={i}
                                            className="transition-colors hover:bg-amber-50/40"
                                        >
                                            <td className="py-3 pr-4">
                                                <p className="font-extrabold text-gray-900">
                                                    {row.name}
                                                </p>
                                                <p className="font-mono text-xs text-gray-500">
                                                    {row.student_id}
                                                </p>
                                            </td>
                                            <td className="py-3 pr-4 font-medium text-gray-700">
                                                {row.course}
                                            </td>
                                            <td className="py-3 pr-4 text-xs font-bold text-amber-800">
                                                Low facial match confidence
                                            </td>
                                            <td className="py-3 pr-4">
                                                <ConfidenceBar score={row.confidence_score} />
                                            </td>
                                            <td className="py-3 font-mono text-xs text-gray-600">
                                                {formatTimestamp(row.logged_at)}
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    </section>
                )}

                {/* COMPLETE ATTENDEE ROSTER TABLE */}
                <main
                    aria-labelledby="roster-log-heading"
                    className="space-y-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs sm:p-5"
                >
                    <div className="flex flex-col gap-3 border-b border-gray-100 pb-3 lg:flex-row lg:items-center lg:justify-between">
                        <div>
                            <h2
                                id="roster-log-heading"
                                className="text-base font-extrabold text-[#1B1F5C]"
                            >
                                Attendee Roster Log
                            </h2>
                            <p className="text-xs font-medium text-gray-600">
                                {roster.length > 0
                                    ? `Showing ${filteredRoster.length} of ${roster.length} record${roster.length !== 1 ? 's' : ''} — ordered chronologically by check-in timestamp`
                                    : 'No attendance records logged yet.'}
                            </p>
                        </div>

                        {roster.length > 0 && (
                            <div className="flex flex-wrap items-center gap-2">
                                {/* Status Filter Pills */}
                                <div
                                    role="group"
                                    aria-label="Filter roster by verification status"
                                    className="inline-flex rounded-xl border border-gray-200 bg-[#F5F6FA] p-1"
                                >
                                    {(
                                        [
                                            { key: 'all', label: 'All' },
                                            { key: 'verified', label: 'Verified' },
                                            { key: 'failed', label: 'Failed' },
                                        ] as const
                                    ).map((opt) => (
                                        <button
                                            key={opt.key}
                                            type="button"
                                            aria-pressed={statusFilter === opt.key}
                                            onClick={() => setStatusFilter(opt.key)}
                                            className={`min-h-[32px] rounded-lg px-2.5 py-1 text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                statusFilter === opt.key
                                                    ? 'bg-[#1B1F5C] text-white'
                                                    : 'text-gray-600 hover:text-gray-900'
                                            }`}
                                        >
                                            {opt.label}
                                        </button>
                                    ))}
                                </div>

                                {/* Instant Search Input */}
                                <div className="relative w-full sm:w-64">
                                    <Search
                                        className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-gray-400"
                                        aria-hidden="true"
                                    />
                                    <input
                                        type="text"
                                        value={rosterSearch}
                                        onChange={(e) => setRosterSearch(e.target.value)}
                                        placeholder="Search ID, student, or course..."
                                        aria-label="Search attendee roster"
                                        className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white py-1.5 pl-8 pr-8 text-xs font-medium text-gray-900 placeholder:text-gray-400 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    />
                                    {rosterSearch && (
                                        <button
                                            type="button"
                                            onClick={() => setRosterSearch('')}
                                            aria-label="Clear roster search"
                                            className="absolute right-2 top-1/2 -translate-y-1/2 rounded-md p-1 text-gray-400 hover:bg-gray-100 hover:text-gray-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                        >
                                            <X className="h-3.5 w-3.5" aria-hidden="true" />
                                        </button>
                                    )}
                                </div>
                            </div>
                        )}
                    </div>

                    {roster.length === 0 ? (
                        <EmptyState message="No attendance records logged for this event yet." />
                    ) : filteredRoster.length === 0 ? (
                        <div className="flex flex-col items-center justify-center space-y-2.5 rounded-xl border border-dashed border-gray-200 bg-[#F5F6FA]/70 px-4 py-10 text-center">
                            <p className="text-xs font-bold text-gray-800">
                                No matching roster records
                            </p>
                            <p className="max-w-xs text-xs text-gray-500">
                                Adjust your search term or reset the verification status filter.
                            </p>
                            {hasActiveRosterFilters && (
                                <button
                                    type="button"
                                    onClick={() => {
                                        setRosterSearch('');
                                        setStatusFilter('all');
                                    }}
                                    className="inline-flex min-h-[38px] items-center gap-1.5 rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-bold text-[#1B1F5C] transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                >
                                    <RotateCcw
                                        className="h-3.5 w-3.5 text-[#F5A623]"
                                        aria-hidden="true"
                                    />
                                    <span>Clear Filters</span>
                                </button>
                            )}
                        </div>
                    ) : (
                        <>
                            {/* Mobile Roster Cards (< md) */}
                            <div className="divide-y divide-gray-100 md:hidden" aria-live="polite">
                                {filteredRoster.map((row, i) => (
                                    <article
                                        key={`${row.student_id}-${i}`}
                                        className="space-y-2 py-3 first:pt-1 last:pb-1"
                                    >
                                        <div className="flex items-start justify-between gap-2">
                                            <div>
                                                <p className="text-xs font-extrabold text-gray-900">
                                                    {row.name}
                                                </p>
                                                <p className="font-mono text-[11px] font-bold text-[#1B1F5C]">
                                                    {row.student_id}{' '}
                                                    <span className="font-sans font-medium text-gray-600">
                                                        • {row.course}
                                                    </span>
                                                </p>
                                            </div>
                                            <StatusBadge status={row.status} />
                                        </div>
                                        <div className="flex items-center justify-between gap-2 pt-0.5">
                                            <ConfidenceBar score={row.confidence_score} />
                                            <span className="font-mono text-[11px] text-gray-500">
                                                {formatTimestamp(row.logged_at)}
                                            </span>
                                        </div>
                                    </article>
                                ))}
                            </div>

                            {/* Desktop Roster Table (>= md) */}
                            <div className="hidden overflow-x-auto md:block">
                                <table className="w-full text-left text-xs text-gray-700 sm:text-sm">
                                    <thead>
                                        <tr className="border-b border-gray-100 text-[10px] font-extrabold uppercase tracking-wider text-gray-500">
                                            <th scope="col" className="pb-3 pr-4">
                                                Student ID
                                            </th>
                                            <th scope="col" className="pb-3 pr-4">
                                                Name
                                            </th>
                                            <th scope="col" className="pb-3 pr-4">
                                                Course
                                            </th>
                                            <th scope="col" className="pb-3 pr-4">
                                                Status
                                            </th>
                                            <th scope="col" className="pb-3 pr-4">
                                                Confidence
                                            </th>
                                            <th scope="col" className="pb-3">
                                                Checked In
                                            </th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-gray-100" aria-live="polite">
                                        {filteredRoster.map((row, i) => (
                                            <tr
                                                key={`${row.student_id}-${i}`}
                                                className="transition-colors hover:bg-[#F5F6FA]/70"
                                            >
                                                <td className="py-3 pr-4 font-mono text-xs font-bold text-[#1B1F5C]">
                                                    {row.student_id}
                                                </td>
                                                <td className="py-3 pr-4 font-extrabold text-gray-900">
                                                    {row.name}
                                                </td>
                                                <td className="py-3 pr-4 font-medium text-gray-700">
                                                    {row.course}
                                                </td>
                                                <td className="py-3 pr-4">
                                                    <StatusBadge status={row.status} />
                                                </td>
                                                <td className="py-3 pr-4">
                                                    <ConfidenceBar score={row.confidence_score} />
                                                </td>
                                                <td className="py-3 font-mono text-xs text-gray-600">
                                                    {formatTimestamp(row.logged_at)}
                                                </td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        </>
                    )}
                </main>
            </div>
        </>
    );
}

function EventKpiCard({
    label,
    value,
    sub,
    subColor = 'text-gray-600',
    icon,
    iconBg,
}: {
    label: string;
    value: string;
    sub?: string;
    subColor?: string;
    icon: React.ReactNode;
    iconBg: string;
}) {
    return (
        <div className="flex flex-col justify-between rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs">
            <div className="flex items-center justify-between gap-2">
                <span className="text-[10px] font-extrabold uppercase tracking-wider text-gray-500">
                    {label}
                </span>
                <div className={`rounded-xl border p-2 ${iconBg}`}>{icon}</div>
            </div>
            <div className="mt-3">
                <p className="text-2xl font-black tracking-tight text-gray-900">{value}</p>
                {sub && <p className={`mt-0.5 text-[11px] font-bold ${subColor}`}>{sub}</p>}
            </div>
        </div>
    );
}

EventAnalyticsShow.layout = (page: React.ReactNode) => (
    <AdminLayout title="Event Analytics">{page}</AdminLayout>
);