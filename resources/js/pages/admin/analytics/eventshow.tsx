import { Head, Link } from '@inertiajs/react';
import {
    ArrowLeft,
    Users,
    CheckCircle2,
    ShieldCheck,
    Clock,
    XCircle,
    AlertTriangle,
    Calendar,
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
    time_in_start: string;
    time_in_end?: string;
    time_out_start?: string;
    time_out_end?: string;
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
    name?: string; // fallback
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

// ─── Constants ─────────────────────────────────────────────────────────────────

const NAVY = '#1B1F5C';

const fmt = new Intl.NumberFormat('en-PH');
const confidenceFmt = new Intl.NumberFormat('en-PH', { style: 'percent', minimumFractionDigits: 1 });

// ─── Helpers ───────────────────────────────────────────────────────────────────

function formatTimestamp(value: string): string {
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return value;
    return d.toLocaleString('en-PH', {
        month: 'short', day: 'numeric',
        hour: '2-digit', minute: '2-digit',
    });
}

function ChartTooltip({ active, payload, label }: any) {
    if (!active || !payload?.length) return null;
    return (
        <div className="rounded-xl border border-gray-100 bg-white p-3 shadow-lg text-xs">
            <p className="mb-1.5 font-semibold text-gray-700">{label}</p>
            {payload.map((entry: any, i: number) => (
                <p key={i} style={{ color: entry.color }} className="flex justify-between gap-4">
                    <span>{entry.name}</span>
                    <span className="font-bold">{fmt.format(entry.value)}</span>
                </p>
            ))}
        </div>
    );
}

function EmptyState({ message }: { message: string }) {
    return (
        <div className="flex min-h-[140px] items-center justify-center rounded-xl border border-dashed border-gray-200 bg-gray-50 text-sm text-gray-400">
            {message}
        </div>
    );
}

// ─── Status badge ──────────────────────────────────────────────────────────────

function StatusBadge({ status }: { status: string }) {
    const s = status.toLowerCase();
    if (s === 'success' || s === 'present') {
        return (
            <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-semibold text-emerald-700">
                <CheckCircle2 className="h-3 w-3" /> Verified
            </span>
        );
    }
    return (
        <span className="inline-flex items-center gap-1 rounded-full bg-red-50 px-2 py-0.5 text-xs font-semibold text-red-600">
            <XCircle className="h-3 w-3" /> {status}
        </span>
    );
}

// ─── Confidence bar ────────────────────────────────────────────────────────────

function ConfidenceBar({ score }: { score: number }) {
    const pct = Math.round(score * 100);
    const color = pct >= 70 ? 'bg-emerald-500' : pct >= 60 ? 'bg-amber-400' : 'bg-red-400';
    return (
        <div className="flex items-center gap-2">
            <div className="h-1.5 w-20 overflow-hidden rounded-full bg-gray-100">
                <div className={`h-full rounded-full ${color}`} style={{ width: `${pct}%` }} />
            </div>
            <span className="text-xs text-gray-500">{pct}%</span>
        </div>
    );
}

// ─── Main page ─────────────────────────────────────────────────────────────────

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

    const failed = totalAttendees - successfulCheckins;

    return (
        <div className="min-h-screen bg-[#F5F6FA] p-6 font-sans text-black">
            <Head title={`Analytics — ${eventTitle}`} />

            <div className="mx-auto max-w-7xl space-y-6">

                {/* ── Back Navigation ── */}
                <Link
                    href="/admin/analytics"
                    className="inline-flex items-center gap-2 text-sm font-semibold text-gray-500 hover:text-[#1B1F5C]"
                >
                    <ArrowLeft className="h-4 w-4" /> Back to Analytics
                </Link>

                {/* ── Event Header ── */}
                <div className="rounded-2xl border border-gray-100 bg-white p-6 shadow-sm">
                    <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                        <div>
                            <span className="rounded-md bg-blue-50 px-2.5 py-1 text-xs font-semibold text-blue-700">
                                Event attendance report
                            </span>
                            <h1 className="mt-2 text-2xl font-bold text-[#1B1F5C]">{eventTitle}</h1>
                            {event.description && (
                                <p className="mt-1 max-w-xl text-sm text-gray-500">{event.description}</p>
                            )}
                        </div>
                        {event.created_at && (
                            <div className="flex shrink-0 items-center gap-2 text-sm text-gray-500">
                                <Clock className="h-4 w-4 text-gray-400" />
                                {new Date(event.created_at).toLocaleDateString('en-PH', {
                                    year: 'numeric', month: 'long', day: 'numeric',
                                })}
                            </div>
                        )}
                    </div>
                </div>

                {/* ── Multi-Day & Time Slots Breakdown Section ── */}
                {dailyBreakdown.length > 0 && (
                    <div className="rounded-2xl border border-gray-100 bg-white p-6 shadow-sm">
                        <div className="mb-4 flex items-center gap-2">
                            <Calendar className="h-5 w-5 text-blue-600" />
                            <h2 className="text-base font-bold text-gray-900">Schedule & Daily Breakdown</h2>
                        </div>
                        <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
                            {dailyBreakdown.map((day, idx) => (
                                <div key={idx} className="rounded-xl border border-gray-100 bg-gray-50 p-4">
                                    <div className="flex justify-between items-center mb-2">
                                        <span className="font-semibold text-blue-900 text-sm">
                                            Day {idx + 1}: {day.date}
                                        </span>
                                        <span className="text-xs bg-white border px-2 py-0.5 rounded-full font-medium text-gray-600">
                                            {day.attendees} Check-ins
                                        </span>
                                    </div>
                                    
                                    {/* Configured Slots for this Day */}
                                    <div className="mt-2 space-y-1">
                                        <p className="text-[11px] font-semibold tracking-wider text-gray-400 uppercase">Time Slots:</p>
                                        <div className="flex flex-wrap gap-1.5">
                                            {day.slots?.map((slot, sIdx) => (
                                                <span key={sIdx} className="rounded bg-white border border-gray-200 px-2 py-0.5 text-xs text-gray-700">
                                                    {slot.time_in_start} - {slot.time_out_end || slot.time_out_start || 'End'}
                                                </span>
                                            ))}
                                        </div>
                                    </div>
                                </div>
                            ))}
                        </div>
                    </div>
                )}

                {/* ── KPI Cards ── */}
                <div className="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
                    <EventKpiCard
                        label="Total check-ins"
                        value={fmt.format(totalAttendees)}
                        icon={<Users className="h-5 w-5" />}
                        iconBg="bg-blue-50 text-blue-600"
                    />
                    <EventKpiCard
                        label="Verified"
                        value={fmt.format(successfulCheckins)}
                        sub={`${eventSuccessRate}% success rate`}
                        subColor="text-emerald-600"
                        icon={<CheckCircle2 className="h-5 w-5" />}
                        iconBg="bg-emerald-50 text-emerald-600"
                    />
                    <EventKpiCard
                        label="Failed verification"
                        value={fmt.format(failed)}
                        icon={<XCircle className="h-5 w-5" />}
                        iconBg="bg-red-50 text-red-500"
                    />
                    <EventKpiCard
                        label="Avg. confidence"
                        value={confidenceFmt.format(avgConfidence)}
                        sub="Face recognition score"
                        icon={<ShieldCheck className="h-5 w-5" />}
                        iconBg="bg-purple-50 text-purple-600"
                    />
                </div>

                {/* ── Department Breakdown & Cumulative Timeline ── */}
                <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">

                    {/* Stacked Bar Chart: Checked-in vs No-show */}
                    <div className="rounded-2xl border border-gray-100 bg-white p-6 shadow-sm">
                        <div className="mb-5">
                            <h2 className="text-base font-bold text-gray-900">Attendance by course</h2>
                            <p className="mt-0.5 text-sm text-gray-500">Sorted by program volume and activity share.</p>
                        </div>
                        {departmentBreakdown.length > 0 ? (
                            <div className="h-64">
                                <ResponsiveContainer width="100%" height="100%">
                                    <BarChart
                                        data={departmentBreakdown}
                                        layout="vertical"
                                        margin={{ top: 4, right: 8, left: 4, bottom: 4 }}
                                    >
                                        <CartesianGrid strokeDasharray="3 3" horizontal={false} stroke="#f1f5f9" />
                                        <XAxis type="number" allowDecimals={false} tick={{ fontSize: 11, fill: '#94a3b8' }} tickLine={false} axisLine={false} />
                                        <YAxis
                                            dataKey="course"
                                            type="category"
                                            width={100}
                                            tick={{ fontSize: 11, fill: '#64748b' }}
                                            tickLine={false}
                                            axisLine={false}
                                        />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Legend wrapperStyle={{ fontSize: 12 }} />
                                        <Bar dataKey="checkedIn" name="Checked in" stackId="a" fill={NAVY} radius={[0, 0, 0, 0]} />
                                        <Bar dataKey="noShow" name="No-show" stackId="a" fill="#E2E8F0" radius={[0, 3, 3, 0]} />
                                    </BarChart>
                                </ResponsiveContainer>
                            </div>
                        ) : (
                            <EmptyState message="No department breakdown data for this event." />
                        )}
                    </div>

                    {/* Cumulative Arrival Pattern Area Chart */}
                    <div className="rounded-2xl border border-gray-100 bg-white p-6 shadow-sm">
                        <div className="mb-5">
                            <h2 className="text-base font-bold text-gray-900">Arrival pattern</h2>
                            <p className="mt-0.5 text-sm text-gray-500">Cumulative check-ins across the event timeline.</p>
                        </div>
                        {checkinTimeline.length > 0 ? (
                            <div className="h-64">
                                <ResponsiveContainer width="100%" height="100%">
                                    <AreaChart data={checkinTimeline} margin={{ top: 4, right: 8, left: 0, bottom: 4 }}>
                                        <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#f1f5f9" />
                                        <XAxis dataKey="label" tick={{ fontSize: 10, fill: '#94a3b8' }} tickLine={false} axisLine={false} />
                                        <YAxis allowDecimals={false} tick={{ fontSize: 11, fill: '#94a3b8' }} tickLine={false} axisLine={false} />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Area type="monotone" dataKey="cumulative" name="Total Check-ins" stroke={NAVY} fill="#EEF2FF" strokeWidth={2} />
                                    </AreaChart>
                                </ResponsiveContainer>
                            </div>
                        ) : (
                            <EmptyState message="No timeline data for this event." />
                        )}
                    </div>
                </div>

                {/* ── Flagged Low-Confidence Review Section ── */}
                {flaggedRoster.length > 0 && (
                    <div className="rounded-2xl border border-amber-100 bg-white p-6 shadow-sm">
                        <div className="mb-5 flex items-center justify-between">
                            <div>
                                <div className="flex items-center gap-2">
                                    <AlertTriangle className="h-5 w-5 text-amber-500" />
                                    <h2 className="text-base font-bold text-gray-900">Flagged check-ins</h2>
                                </div>
                                <p className="mt-0.5 text-sm text-gray-500">
                                    Records falling below confidence thresholds requiring manual review.
                                </p>
                            </div>
                        </div>

                        <div className="overflow-x-auto">
                            <table className="w-full text-left text-sm">
                                <thead>
                                    <tr className="border-b border-gray-100 text-xs font-medium text-gray-500">
                                        <th className="pb-3 pr-4">Student</th>
                                        <th className="pb-3 pr-4">Course</th>
                                        <th className="pb-3 pr-4">Reason flagged</th>
                                        <th className="pb-3 pr-4">Confidence</th>
                                        <th className="pb-3">Checked in</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-gray-50">
                                    {flaggedRoster.map((row: any, i: number) => (
                                        <tr key={i} className="hover:bg-gray-50/60">
                                            <td className="py-3 pr-4">
                                                <p className="font-semibold text-gray-900">{row.name}</p>
                                                <p className="font-mono text-xs text-gray-400">{row.student_id}</p>
                                            </td>
                                            <td className="py-3 pr-4 text-gray-500">{row.course}</td>
                                            <td className="py-3 pr-4 text-amber-600 font-medium text-xs">Low match confidence</td>
                                            <td className="py-3 pr-4"><ConfidenceBar score={row.confidence_score} /></td>
                                            <td className="py-3 text-xs text-gray-400">{formatTimestamp(row.logged_at)}</td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    </div>
                )}

                {/* ── Complete Attendee Roster Table ── */}
                <div className="rounded-2xl border border-gray-100 bg-white p-6 shadow-sm">
                    <div className="mb-5 flex items-center justify-between">
                        <div>
                            <h2 className="text-base font-bold text-gray-900">Attendee roster</h2>
                            <p className="mt-0.5 text-sm text-gray-500">
                                {roster.length > 0
                                    ? `${roster.length} record${roster.length !== 1 ? 's' : ''} — sorted by check-in time.`
                                    : 'No records yet.'}
                            </p>
                        </div>
                    </div>

                    {roster.length > 0 ? (
                        <div className="overflow-x-auto">
                            <table className="w-full text-left text-sm">
                                <thead>
                                    <tr className="border-b border-gray-100 text-xs font-medium text-gray-500">
                                        <th className="pb-3 pr-4">Student ID</th>
                                        <th className="pb-3 pr-4">Name</th>
                                        <th className="pb-3 pr-4">Course</th>
                                        <th className="pb-3 pr-4">Status</th>
                                        <th className="pb-3 pr-4">Confidence</th>
                                        <th className="pb-3">Checked in</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-gray-50">
                                    {roster.map((row, i) => (
                                        <tr key={i} className="hover:bg-gray-50/60">
                                            <td className="py-3 pr-4 font-mono text-xs text-gray-500">
                                                {row.student_id}
                                            </td>
                                            <td className="py-3 pr-4 font-semibold text-gray-900">
                                                {row.name}
                                            </td>
                                            <td className="py-3 pr-4 text-gray-500">
                                                {row.course}
                                            </td>
                                            <td className="py-3 pr-4">
                                                <StatusBadge status={row.status} />
                                            </td>
                                            <td className="py-3 pr-4">
                                                <ConfidenceBar score={row.confidence_score} />
                                            </td>
                                            <td className="py-3 text-xs text-gray-400">
                                                {formatTimestamp(row.logged_at)}
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    ) : (
                        <EmptyState message="No attendance records for this event yet." />
                    )}
                </div>

            </div>
        </div>
    );
}

// ─── Event KPI Card ─────────────────────────────────────────────────────────────

function EventKpiCard({
    label,
    value,
    sub,
    subColor = 'text-gray-400',
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
        <div className="rounded-2xl border border-gray-100 bg-white p-6 shadow-sm">
            <div className="flex items-center justify-between">
                <span className="text-sm font-medium text-gray-500">{label}</span>
                <div className={`rounded-full p-2 ${iconBg}`}>{icon}</div>
            </div>
            <p className="mt-4 text-2xl font-bold text-gray-900">{value}</p>
            {sub && <p className={`mt-1 text-xs font-medium ${subColor}`}>{sub}</p>}
        </div>
    );
}