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

// ─── Constants & Formatting ───────────────────────────────────────────────────

const NAVY = '#1B1F5C';

const fmt = new Intl.NumberFormat('en-PH');
const confidenceFmt = new Intl.NumberFormat('en-PH', { style: 'percent', minimumFractionDigits: 1 });

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
        <div className="rounded-xl border border-gray-200 bg-white p-3 shadow-md text-xs space-y-1">
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
        <div className="flex h-56 w-full flex-col items-center justify-center space-y-2 rounded-xl border border-dashed border-gray-200 bg-gray-50/60 p-4 text-center">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-indigo-50 text-[#1B1F5C]">
                <CalendarX className="h-4 w-4" aria-hidden="true" />
            </div>
            <p className="text-xs font-bold text-gray-500">{message}</p>
        </div>
    );
}

function StatusBadge({ status }: { status: string }) {
    const s = status.toLowerCase();
    if (s === 'success' || s === 'present') {
        return (
            <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 border border-emerald-200 px-2.5 py-0.5 text-xs font-bold text-emerald-700">
                <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" /> Verified
            </span>
        );
    }
    return (
        <span className="inline-flex items-center gap-1 rounded-full bg-rose-50 border border-rose-200 px-2.5 py-0.5 text-xs font-bold text-rose-700">
            <XCircle className="h-3.5 w-3.5" aria-hidden="true" /> {status}
        </span>
    );
}

function ConfidenceBar({ score }: { score: number }) {
    const pct = Math.round(score * 100);
    const color = pct >= 70 ? 'bg-emerald-500' : pct >= 60 ? 'bg-amber-500' : 'bg-red-500';
    return (
        <div className="flex items-center gap-2">
            <div className="h-1.5 w-20 overflow-hidden rounded-full bg-gray-200">
                <div className={`h-full rounded-full ${color}`} style={{ width: `${pct}%` }} />
            </div>
            <span className="text-xs font-mono font-bold text-gray-700">{pct}%</span>
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

    const failed = totalAttendees - successfulCheckins;

    return (
        <>
            <Head title={`Analytics — ${eventTitle} | 4ttnd Attendance System`} />

            <div className="p-3 sm:p-5 font-sans text-gray-900 antialiased bg-[#F5F6FA] min-h-screen space-y-4">
                {/* BACK NAVIGATION */}
                <nav aria-label="Breadcrumb navigation">
                    <Link
                        href="/admin/analytics"
                        className="inline-flex items-center gap-1.5 text-xs font-bold text-gray-500 hover:text-[#1B1F5C] transition-colors focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-xs"
                    >
                        <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Back to Analytics Overview
                    </Link>
                </nav>

                {/* EVENT HEADER */}
                <header className="rounded-2xl border border-gray-200/80 bg-white p-4 sm:p-5 shadow-xs">
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                        <div className="space-y-1">
                            <span className="rounded-md bg-indigo-50 border border-indigo-100 px-2.5 py-0.5 text-[10px] font-extrabold text-[#1B1F5C] uppercase tracking-wider">
                                Event Attendance Data
                            </span>
                            <h1 className="text-xl sm:text-2xl font-black text-[#1B1F5C] tracking-tight">{eventTitle}</h1>
                            {event.description && (
                                <p className="max-w-2xl text-xs sm:text-sm text-gray-500 font-medium">{event.description}</p>
                            )}
                        </div>
                        {event.created_at && (
                            <div className="flex shrink-0 items-center gap-1.5 text-xs font-bold text-gray-500 bg-gray-50 px-3 py-1.5 rounded-xl border border-gray-200/70">
                                <Clock className="h-4 w-4 text-[#F5A623]" aria-hidden="true" />
                                <span>{new Date(event.created_at).toLocaleDateString('en-PH', {
                                    year: 'numeric', month: 'long', day: 'numeric',
                                })}</span>
                            </div>
                        )}
                    </div>
                </header>

                {/* MULTI-DAY & TIME SLOTS BREAKDOWN */}
                {dailyBreakdown.length > 0 && (
                    <section aria-label="Schedule & Daily Breakdown" className="rounded-2xl border border-gray-200/80 bg-white p-4 sm:p-5 shadow-xs space-y-3">
                        <div className="flex items-center gap-2 pb-2 border-b border-gray-100">
                            <Calendar className="h-4.5 w-4.5 text-[#1B1F5C]" aria-hidden="true" />
                            <h2 className="text-base font-extrabold text-[#1B1F5C]">Schedule & Daily Breakdown</h2>
                        </div>
                        <div className="grid grid-cols-1 gap-3 md:grid-cols-2 lg:grid-cols-3">
                            {dailyBreakdown.map((day, idx) => (
                                <div key={idx} className="rounded-xl border border-gray-200/70 bg-gray-50/80 p-3.5 space-y-2">
                                    <div className="flex justify-between items-center">
                                        <span className="font-extrabold text-[#1B1F5C] text-xs sm:text-sm">
                                            Day {idx + 1}: {day.date}
                                        </span>
                                        <span className="text-[10px] font-bold bg-white border border-gray-200 px-2 py-0.5 rounded-full text-gray-700 shadow-2xs">
                                            {day.attendees} Check-ins
                                        </span>
                                    </div>
                                    
                                    <div className="space-y-1 pt-1 border-t border-gray-200/60">
                                        <p className="text-[10px] font-extrabold tracking-wider text-gray-500 uppercase">Time Windows:</p>
                                        <div className="flex flex-wrap gap-1">
                                            {day.slots?.map((slot, sIdx) => (
                                                <span key={sIdx} className="rounded-md bg-white border border-gray-200 px-2 py-0.5 text-xs font-mono font-bold text-gray-700">
                                                    {slot.time_in_start} - {slot.time_out_end || slot.time_out_start || 'End'}
                                                </span>
                                            ))}
                                        </div>
                                    </div>
                                </div>
                            ))}
                        </div>
                    </section>
                )}

                {/* KPI CARDS RIBBON */}
                <section aria-label="Event Key Performance Metrics" className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                    <EventKpiCard
                        label="Total Check-ins"
                        value={fmt.format(totalAttendees)}
                        icon={<Users className="h-4.5 w-4.5" aria-hidden="true" />}
                        iconBg="bg-indigo-50 text-[#1B1F5C] border border-indigo-100"
                    />
                    <EventKpiCard
                        label="Verified"
                        value={fmt.format(successfulCheckins)}
                        sub={`${eventSuccessRate}% success rate`}
                        subColor="text-emerald-700"
                        icon={<CheckCircle2 className="h-4.5 w-4.5" aria-hidden="true" />}
                        iconBg="bg-emerald-50 text-emerald-700 border border-emerald-100"
                    />
                    <EventKpiCard
                        label="Failed Verification"
                        value={fmt.format(failed)}
                        icon={<XCircle className="h-4.5 w-4.5" aria-hidden="true" />}
                        iconBg="bg-rose-50 text-rose-700 border border-rose-100"
                    />
                    <EventKpiCard
                        label="Avg. Confidence"
                        value={confidenceFmt.format(avgConfidence)}
                        sub="Facial recognition score"
                        icon={<ShieldCheck className="h-4.5 w-4.5" aria-hidden="true" />}
                        iconBg="bg-amber-50 text-amber-700 border border-amber-100"
                    />
                </section>

                {/* DEPARTMENT BREAKDOWN & CUMULATIVE TIMELINE */}
                <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                    {/* Stacked Bar Chart */}
                    <section aria-label="Attendance by course" className="rounded-2xl border border-gray-200/80 bg-white p-4 sm:p-5 shadow-xs space-y-3">
                        <div>
                            <h2 className="text-base font-extrabold text-[#1B1F5C]">Attendance by Course</h2>
                            <p className="text-xs text-gray-500 font-medium">Sorted by academic program volume and check-in share</p>
                        </div>
                        {departmentBreakdown.length > 0 ? (
                            <div className="h-56">
                                <ResponsiveContainer width="100%" height="100%">
                                    <BarChart
                                        data={departmentBreakdown}
                                        layout="vertical"
                                        margin={{ top: 8, right: 12, left: 12, bottom: 8 }}
                                    >
                                        <CartesianGrid strokeDasharray="3 3" horizontal={false} stroke="#f1f5f9" />
                                        <XAxis type="number" allowDecimals={false} tick={{ fontSize: 10, fill: '#64748b' }} tickLine={false} axisLine={false} />
                                        <YAxis
                                            dataKey="course"
                                            type="category"
                                            width={110}
                                            tick={{ fontSize: 10, fill: '#1B1F5C', fontWeight: 600 }}
                                            tickLine={false}
                                            axisLine={false}
                                        />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Legend wrapperStyle={{ fontSize: 11, fontWeight: 600, paddingTop: '12px' }} verticalAlign="bottom" />
                                        <Bar dataKey="checkedIn" name="Checked in" stackId="a" fill={NAVY} barSize={16} radius={[0, 0, 0, 0]} />
                                        <Bar dataKey="noShow" name="No-show" stackId="a" fill="#E2E8F0" barSize={16} radius={[0, 4, 4, 0]} />
                                    </BarChart>
                                </ResponsiveContainer>
                            </div>
                        ) : (
                            <EmptyState message="No department breakdown data for this event." />
                        )}
                    </section>

                    {/* Arrival Pattern Area Chart */}
                    <section aria-label="Arrival pattern timeline" className="rounded-2xl border border-gray-200/80 bg-white p-4 sm:p-5 shadow-xs space-y-3">
                        <div>
                            <h2 className="text-base font-extrabold text-[#1B1F5C]">Arrival Pattern Timeline</h2>
                            <p className="text-xs text-gray-500 font-medium">Cumulative student arrivals across the active window</p>
                        </div>
                        {checkinTimeline.length > 0 ? (
                            <div className="h-56">
                                <ResponsiveContainer width="100%" height="100%">
                                    <AreaChart data={checkinTimeline} margin={{ top: 4, right: 8, left: 0, bottom: 4 }}>
                                        <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#f1f5f9" />
                                        <XAxis dataKey="label" tick={{ fontSize: 10, fill: '#64748b' }} tickLine={false} axisLine={false} />
                                        <YAxis allowDecimals={false} tick={{ fontSize: 10, fill: '#64748b' }} tickLine={false} axisLine={false} />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Area type="monotone" dataKey="cumulative" name="Total Check-ins" stroke={NAVY} fill="#EEF2FF" strokeWidth={2.5} />
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
                    <section aria-label="Flagged Check-ins" className="rounded-2xl border border-amber-200/80 bg-white p-4 sm:p-5 shadow-xs space-y-3">
                        <div className="flex items-center gap-2 pb-2 border-b border-amber-100">
                            <AlertTriangle className="h-4.5 w-4.5 text-amber-600" aria-hidden="true" />
                            <div>
                                <h2 className="text-base font-extrabold text-[#1B1F5C]">Flagged Verification Exception Queue</h2>
                                <p className="text-xs text-gray-500 font-medium">Biometric scores falling below confidence threshold</p>
                            </div>
                        </div>

                        <div className="overflow-x-auto">
                            <table className="w-full text-left text-xs sm:text-sm text-gray-700">
                                <thead>
                                    <tr className="border-b border-gray-100 text-[10px] font-extrabold uppercase text-gray-500">
                                        <th className="pb-3 pr-4">Student</th>
                                        <th className="pb-3 pr-4">Course</th>
                                        <th className="pb-3 pr-4">Reason Flagged</th>
                                        <th className="pb-3 pr-4">Confidence Score</th>
                                        <th className="pb-3">Checked In</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-gray-100">
                                    {flaggedRoster.map((row: any, i: number) => (
                                        <tr key={i} className="hover:bg-amber-50/30 transition-colors">
                                            <td className="py-3 pr-4">
                                                <p className="font-extrabold text-gray-900">{row.name}</p>
                                                <p className="font-mono text-xs text-gray-500">{row.student_id}</p>
                                            </td>
                                            <td className="py-3 pr-4 text-gray-700 font-medium">{row.course}</td>
                                            <td className="py-3 pr-4 text-amber-700 font-bold text-xs">Low facial match confidence</td>
                                            <td className="py-3 pr-4"><ConfidenceBar score={row.confidence_score} /></td>
                                            <td className="py-3 text-xs text-gray-500 font-mono">{formatTimestamp(row.logged_at)}</td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    </section>
                )}

                {/* COMPLETE ATTENDEE ROSTER TABLE */}
                <main className="rounded-2xl border border-gray-200/80 bg-white p-4 sm:p-5 shadow-xs space-y-3">
                    <div className="flex items-center justify-between pb-2 border-b border-gray-100">
                        <div>
                            <h2 className="text-base font-extrabold text-[#1B1F5C]">Attendee Roster Log</h2>
                            <p className="text-xs text-gray-500 font-medium">
                                {roster.length > 0
                                    ? `${roster.length} record${roster.length !== 1 ? 's' : ''} — ordered chronologically by check-in timestamp`
                                    : 'No attendance records logged yet.'}
                            </p>
                        </div>
                    </div>

                    {roster.length > 0 ? (
                        <div className="overflow-x-auto">
                            <table className="w-full text-left text-xs sm:text-sm text-gray-700">
                                <thead>
                                    <tr className="border-b border-gray-100 text-[10px] font-extrabold uppercase tracking-wider text-gray-500">
                                        <th className="pb-3 pr-4">Student ID</th>
                                        <th className="pb-3 pr-4">Name</th>
                                        <th className="pb-3 pr-4">Course</th>
                                        <th className="pb-3 pr-4">Status</th>
                                        <th className="pb-3 pr-4">Confidence</th>
                                        <th className="pb-3">Checked In</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-gray-100" aria-live="polite">
                                    {roster.map((row, i) => (
                                        <tr key={i} className="hover:bg-gray-50/60 transition-colors">
                                            <td className="py-3 pr-4 font-mono text-xs font-bold text-[#1B1F5C]">
                                                {row.student_id}
                                            </td>
                                            <td className="py-3 pr-4 font-extrabold text-gray-900">
                                                {row.name}
                                            </td>
                                            <td className="py-3 pr-4 text-gray-700 font-medium">
                                                {row.course}
                                            </td>
                                            <td className="py-3 pr-4">
                                                <StatusBadge status={row.status} />
                                            </td>
                                            <td className="py-3 pr-4">
                                                <ConfidenceBar score={row.confidence_score} />
                                            </td>
                                            <td className="py-3 text-xs text-gray-500 font-mono">
                                                {formatTimestamp(row.logged_at)}
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    ) : (
                        <EmptyState message="No attendance records logged for this event yet." />
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
    subColor = 'text-gray-500',
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
        <div className="rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs flex flex-col justify-between">
            <div className="flex items-center justify-between">
                <span className="text-[10px] font-extrabold uppercase tracking-wider text-gray-500">{label}</span>
                <div className={`rounded-xl p-2 ${iconBg}`}>{icon}</div>
            </div>
            <div className="mt-3">
                <p className="text-2xl font-black text-gray-900 tracking-tight">{value}</p>
                {sub && <p className={`mt-0.5 text-[11px] font-bold ${subColor}`}>{sub}</p>}
            </div>
        </div>
    );
}

EventAnalyticsShow.layout = (page: React.ReactNode) => <AdminLayout title="Event Analytics">{page}</AdminLayout>;