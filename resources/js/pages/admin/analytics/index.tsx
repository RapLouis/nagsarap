import React, { useState, useMemo } from 'react';
import { Head, Link, router } from '@inertiajs/react';
import AdminLayout from '@/layouts/admin-layout';
import {
    Users,
    Calendar,
    CheckCircle2,
    ShieldCheck,
    TrendingUp,
    TrendingDown,
    ArrowUpRight,
    Download,
    Filter,
    CalendarX,
} from 'lucide-react';
import {
    ResponsiveContainer,
    BarChart,
    Bar,
    LineChart,
    Line,
    XAxis,
    YAxis,
    CartesianGrid,
    Tooltip,
    Cell,
    Legend,
} from 'recharts';

// ─── Types ─────────────────────────────────────────────────────────────────────

type Metrics = {
    totalStudents: number;
    totalEvents: number;
    globalAttendanceRate: number;
    biometricSuccessRate: number;
};

type Deltas = {
    attendances: number | null;
    biometricSuccessRate: number | null;
};

type CourseStat = {
    course: string;
    total: number;
};

type MonthlyTrendRow = {
    month: string;
    total: number;
    successful: number;
    avg_confidence: number;
};

type EventSummaryRow = {
    id: number;
    event: string;
    date: string;
    attended: number;
    successful: number;
    avg_confidence: number;
};

type HourlyRow = {
    hour: number;
    label: string;
    count: number;
};

type Props = {
    metrics: Metrics;
    deltas: Deltas;
    courseBreakdown: CourseStat[];
    monthlyTrend: MonthlyTrendRow[];
    eventSummary: EventSummaryRow[];
    hourlyDistribution: HourlyRow[];
    filters: { range: string };
};

// ─── Constants ─────────────────────────────────────────────────────────────────

const NAVY = '#1B1F5C';
const COLORS = ['#1B1F5C', '#3B82F6', '#10B981', '#F59E0B', '#8B5CF6', '#EF4444', '#06B6D4', '#F97316'];

const fmt = new Intl.NumberFormat('en-PH');

// ─── Small helpers ─────────────────────────────────────────────────────────────

function DeltaBadge({ value }: { value: number | null }) {
    if (value === null) return <span className="text-xs text-gray-400">—</span>;
    const positive = value >= 0;
    return (
        <span
            className={[
                'inline-flex items-center gap-0.5 rounded-full px-2 py-0.5 text-[10px] font-semibold',
                positive ? 'bg-emerald-50 text-emerald-700' : 'bg-rose-50 text-rose-600',
            ].join(' ')}
        >
            {positive ? <TrendingUp className="h-3 w-3" /> : <TrendingDown className="h-3 w-3" />}
            {positive ? '+' : ''}{value}%
        </span>
    );
}

function SectionHeader({ title, description }: { title: string; description?: string }) {
    return (
        <div className="mb-5">
            <h2 className="text-base font-bold text-gray-800">{title}</h2>
            {description && <p className="mt-0.5 text-xs text-gray-400">{description}</p>}
        </div>
    );
}

function EmptyState({ message }: { message: string }) {
    return (
        <div className="flex flex-col items-center justify-center min-h-[165px] rounded-2xl border border-dashed border-gray-200 bg-gray-50/50 text-gray-400 space-y-2">
            <CalendarX className="h-6 w-6 text-gray-300" />
            <p className="text-xs font-semibold">{message}</p>
        </div>
    );
}

// ─── Custom tooltip ────────────────────────────────────────────────────────────

function ChartTooltip({ active, payload, label }: any) {
    if (!active || !payload?.length) return null;
    return (
        <div className="rounded-xl border border-gray-100 bg-white p-3 shadow-lg text-xs space-y-1">
            <p className="font-bold text-gray-700">{label}</p>
            {payload.map((entry: any, i: number) => (
                <p key={i} style={{ color: entry.color }} className="flex justify-between gap-4">
                    <span className="flex items-center gap-1.5 font-medium">
                        <span className="h-2 w-2 rounded-full" style={{ backgroundColor: entry.color }} />
                        {entry.name}
                    </span>
                    <span className="font-bold">{fmt.format(entry.value)}</span>
                </p>
            ))}
        </div>
    );
}

// ─── Main page ─────────────────────────────────────────────────────────────────

export default function AnalyticsIndex({
    metrics,
    deltas,
    courseBreakdown,
    monthlyTrend,
    eventSummary,
    hourlyDistribution,
    filters,
}: Props) {
    const [selectedCourse, setSelectedCourse] = useState<string | null>(null);
    const [dateRange, setDateRange] = useState<string>(filters?.range || '12m');

    const totalStudents = courseBreakdown.reduce((s, r) => s + r.total, 0);

    const filteredEventSummary = useMemo(() => {
        if (!selectedCourse) return eventSummary;
        return eventSummary;
    }, [eventSummary, selectedCourse]);

    const handleRangeChange = (range: string) => {
        setDateRange(range);
        router.get(
            '/admin/analytics',
            { range: range },
            { preserveState: true, preserveScroll: true, replace: true }
        );
    };

    const handleExportReport = () => {
        window.print();
    };

    return (
        <>
            <Head title="System Analytics & Reports" />

            <div className="p-6 space-y-6">

                {/* ── HEADER ── */}
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                    <div>
                        <h2 className="text-xl font-bold text-gray-800">System Analytics</h2>
                        <p className="text-xs text-gray-500">Global overview of biometric attendance across all academic events</p>
                    </div>

                    <div className="flex flex-wrap items-center gap-2.5">
                        {/* Range Switcher */}
                        <div className="flex rounded-xl border border-gray-200 bg-white p-1 shadow-xs">
                            {[
                                { key: '12m', label: 'Last 12 Months' },
                                { key: 'semester', label: 'This Semester' },
                                { key: 'month', label: 'This Month' },
                            ].map((item) => (
                                <button
                                    key={item.key}
                                    onClick={() => handleRangeChange(item.key)}
                                    className={[
                                        'rounded-lg px-3 py-1.5 text-xs font-bold transition-all',
                                        dateRange === item.key
                                            ? 'bg-[#1B1F5C] text-white shadow-xs'
                                            : 'text-gray-500 hover:text-gray-800',
                                    ].join(' ')}
                                >
                                    {item.label}
                                </button>
                            ))}
                        </div>

                        <button
                            onClick={handleExportReport}
                            className="inline-flex items-center gap-1.5 rounded-xl border border-gray-200 bg-white px-3.5 py-2 text-xs font-bold text-gray-700 shadow-xs hover:bg-gray-50 transition"
                        >
                            <Download className="h-3.5 w-3.5" />
                            <span>Export</span>
                        </button>

                        <Link
                            href="/admin/events"
                            className="inline-flex items-center gap-1.5 rounded-xl bg-[#1B1F5C] px-4 py-2 text-xs font-bold text-white shadow-xs hover:bg-[#151848] transition active:scale-[0.98]"
                        >
                            <span>Manage Events</span>
                            <ArrowUpRight className="h-3.5 w-3.5" />
                        </Link>
                    </div>
                </div>

                {/* ── KPI CARDS ── */}
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
                    <KpiCard
                        label="Enrolled Students"
                        value={fmt.format(metrics.totalStudents)}
                        sub="Active biometric vectors"
                        subColor="text-blue-600"
                        icon={<Users className="h-4 w-4" />}
                        iconBg="bg-blue-50 text-blue-600"
                    />
                    <KpiCard
                        label="Attendance Rate"
                        value={`${metrics.globalAttendanceRate}%`}
                        sub="System-wide turnout"
                        icon={<CheckCircle2 className="h-4 w-4" />}
                        iconBg="bg-emerald-50 text-emerald-600"
                        delta={<DeltaBadge value={deltas.attendances} />}
                    />
                    <KpiCard
                        label="Biometric Success"
                        value={`${metrics.biometricSuccessRate}%`}
                        sub="Verified check-ins"
                        subColor="text-purple-600"
                        icon={<ShieldCheck className="h-4 w-4" />}
                        iconBg="bg-purple-50 text-purple-600"
                        delta={<DeltaBadge value={deltas.biometricSuccessRate} />}
                    />
                    <KpiCard
                        label="Total Events"
                        value={fmt.format(metrics.totalEvents)}
                        sub="Recorded activities"
                        icon={<Calendar className="h-4 w-4" />}
                        iconBg="bg-amber-50 text-amber-600"
                    />
                </div>

                {/* ── MONTHLY ATTENDANCE TREND ── */}
                <div className="rounded-2xl border border-gray-100 bg-white p-6 shadow-xs transition hover:shadow-sm">
                    <SectionHeader
                        title="Monthly Attendance Trend"
                        description="Check-ins and successful verifications over the selected period"
                    />
                    {monthlyTrend.length > 0 ? (
                        <div className="h-64 w-full">
                            <ResponsiveContainer width="100%" height="100%">
                                <LineChart data={monthlyTrend} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
                                    <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#f1f5f9" />
                                    <XAxis dataKey="month" tick={{ fontSize: 11, fill: '#94a3b8' }} tickLine={false} axisLine={false} />
                                    <YAxis allowDecimals={false} tick={{ fontSize: 11, fill: '#94a3b8' }} tickLine={false} axisLine={false} />
                                    <Tooltip content={<ChartTooltip />} />
                                    <Legend wrapperStyle={{ fontSize: 12, paddingTop: '10px' }} />
                                    <Line
                                        type="monotone"
                                        dataKey="total"
                                        name="Total check-ins"
                                        stroke={NAVY}
                                        strokeWidth={2.5}
                                        dot={{ r: 3, fill: NAVY }}
                                        activeDot={{ r: 5 }}
                                    />
                                    <Line
                                        type="monotone"
                                        dataKey="successful"
                                        name="Verified"
                                        stroke="#10B981"
                                        strokeWidth={2.5}
                                        dot={{ r: 3, fill: '#10B981' }}
                                        activeDot={{ r: 5 }}
                                    />
                                </LineChart>
                            </ResponsiveContainer>
                        </div>
                    ) : (
                        <EmptyState message="No attendance records found for this period." />
                    )}
                </div>

                {/* ── EVENT SUMMARY + HOURLY DISTRIBUTION ── */}
                <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
                    {/* Event Bar Chart */}
                    <div className="rounded-2xl border border-gray-100 bg-white p-6 shadow-xs transition hover:shadow-sm">
                        <SectionHeader
                            title="Attendance by Event"
                            description="20 most recent events — total check-ins vs. verified"
                        />
                        {filteredEventSummary.length > 0 ? (
                            <div className="h-72 w-full">
                                <ResponsiveContainer width="100%" height="100%">
                                    <BarChart
                                        data={filteredEventSummary}
                                        layout="vertical"
                                        margin={{ top: 5, right: 10, left: 10, bottom: 0 }}
                                    >
                                        <CartesianGrid strokeDasharray="3 3" horizontal={false} stroke="#f1f5f9" />
                                        <XAxis type="number" allowDecimals={false} tick={{ fontSize: 11, fill: '#94a3b8' }} tickLine={false} axisLine={false} />
                                        <YAxis
                                            dataKey="event"
                                            type="category"
                                            width={110}
                                            tick={{ fontSize: 10, fill: '#64748b' }}
                                            tickLine={false}
                                            axisLine={false}
                                        />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Legend wrapperStyle={{ fontSize: 12, paddingTop: '10px' }} />
                                        <Bar dataKey="attended" name="Attended" fill={NAVY} radius={[0, 4, 4, 0]} barSize={10} />
                                        <Bar dataKey="successful" name="Verified" fill="#10B981" radius={[0, 4, 4, 0]} barSize={10} />
                                    </BarChart>
                                </ResponsiveContainer>
                            </div>
                        ) : (
                            <EmptyState message="No event data recorded." />
                        )}
                    </div>

                    {/* Hourly Histogram */}
                    <div className="rounded-2xl border border-gray-100 bg-white p-6 shadow-xs transition hover:shadow-sm">
                        <SectionHeader
                            title="Check-in Time Distribution"
                            description="When successful verifications happen throughout the day"
                        />
                        {hourlyDistribution.length > 0 ? (
                            <div className="h-72 w-full">
                                <ResponsiveContainer width="100%" height="100%">
                                    <BarChart data={hourlyDistribution} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
                                        <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#f1f5f9" />
                                        <XAxis dataKey="label" tick={{ fontSize: 10, fill: '#94a3b8' }} tickLine={false} axisLine={false} />
                                        <YAxis allowDecimals={false} tick={{ fontSize: 11, fill: '#94a3b8' }} tickLine={false} axisLine={false} />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Bar dataKey="count" name="Check-ins" radius={[4, 4, 0, 0]} barSize={16}>
                                            {hourlyDistribution.map((_, i) => (
                                                <Cell key={i} fill={COLORS[i % COLORS.length]} />
                                            ))}
                                        </Bar>
                                    </BarChart>
                                </ResponsiveContainer>
                            </div>
                        ) : (
                            <EmptyState message="No check-in logs available." />
                        )}
                    </div>
                </div>

                {/* ── COURSE / DEGREE BREAKDOWN ── */}
                <div className="rounded-2xl border border-gray-100 bg-white p-6 shadow-xs transition hover:shadow-sm">
                    <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 mb-5">
                        <SectionHeader
                            title="Student Distribution by Course"
                            description="Enrolled biometric students grouped by academic programme. Click a bar or card to filter."
                        />
                        {selectedCourse && (
                            <button
                                onClick={() => setSelectedCourse(null)}
                                className="inline-flex items-center gap-1 text-xs font-bold text-blue-600 hover:text-blue-800 transition"
                            >
                                <Filter className="h-3 w-3" />
                                <span>Clear filter ({selectedCourse})</span>
                            </button>
                        )}
                    </div>

                    {courseBreakdown.length > 0 ? (
                        <div className="space-y-6">
                            {/* Horizontal Bar Chart */}
                            <div className="h-56 w-full">
                                <ResponsiveContainer width="100%" height="100%">
                                    <BarChart
                                        data={courseBreakdown}
                                        layout="vertical"
                                        margin={{ top: 5, right: 10, left: 10, bottom: 0 }}
                                    >
                                        <CartesianGrid strokeDasharray="3 3" horizontal={false} stroke="#f1f5f9" />
                                        <XAxis type="number" allowDecimals={false} tick={{ fontSize: 11, fill: '#94a3b8' }} tickLine={false} axisLine={false} />
                                        <YAxis
                                            dataKey="course"
                                            type="category"
                                            width={90}
                                            tick={{ fontSize: 11, fill: '#64748b' }}
                                            tickLine={false}
                                            axisLine={false}
                                        />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Bar dataKey="total" name="Students" radius={[0, 4, 4, 0]} barSize={14}>
                                            {courseBreakdown.map((item, i) => (
                                                <Cell
                                                    key={i}
                                                    fill={COLORS[i % COLORS.length]}
                                                    opacity={selectedCourse && selectedCourse !== item.course ? 0.3 : 1}
                                                    className="cursor-pointer transition-opacity"
                                                    onClick={() => setSelectedCourse(selectedCourse === item.course ? null : item.course)}
                                                />
                                            ))}
                                        </Bar>
                                    </BarChart>
                                </ResponsiveContainer>
                            </div>

                            {/* Program Breakdown Cards */}
                            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
                                {courseBreakdown.map((item, i) => {
                                    const pct = totalStudents > 0 ? Math.round((item.total / totalStudents) * 100) : 0;
                                    const isSelected = selectedCourse === item.course;
                                    return (
                                        <div
                                            key={i}
                                            onClick={() => setSelectedCourse(isSelected ? null : item.course)}
                                            className={[
                                                'flex items-center justify-between rounded-xl border p-3.5 cursor-pointer transition-all',
                                                isSelected
                                                    ? 'border-blue-500 bg-blue-50/40 shadow-xs'
                                                    : 'border-gray-100 bg-gray-50/50 hover:border-gray-200 hover:bg-gray-100/50',
                                            ].join(' ')}
                                        >
                                            <div className="flex items-center gap-2.5">
                                                <span
                                                    className="h-2.5 w-2.5 shrink-0 rounded-full"
                                                    style={{ backgroundColor: COLORS[i % COLORS.length] }}
                                                />
                                                <span className="text-xs font-bold text-gray-700 truncate max-w-[130px]" title={item.course}>
                                                    {item.course}
                                                </span>
                                            </div>
                                            <div className="flex items-center gap-2">
                                                <span className="text-[10px] font-semibold text-gray-400">{pct}%</span>
                                                <span className="rounded-lg bg-white px-2.5 py-1 text-xs font-bold text-[#1B1F5C] shadow-xs">
                                                    {fmt.format(item.total)}
                                                </span>
                                            </div>
                                        </div>
                                    );
                                })}
                            </div>
                        </div>
                    ) : (
                        <EmptyState message="No course/degree breakdown records found." />
                    )}
                </div>

            </div>
        </>
    );
}

// ─── KPI Card ──────────────────────────────────────────────────────────────────

function KpiCard({
    label,
    value,
    sub,
    subColor = 'text-gray-400',
    icon,
    iconBg,
    delta,
}: {
    label: string;
    value: string;
    sub: string;
    subColor?: string;
    icon: React.ReactNode;
    iconBg: string;
    delta?: React.ReactNode;
}) {
    return (
        <div className="rounded-2xl border border-gray-100 bg-white p-5 shadow-xs transition hover:shadow-sm">
            <div className="flex items-center justify-between">
                <span className="text-xs font-semibold uppercase tracking-wider text-gray-400">{label}</span>
                <div className={`rounded-xl p-2 ${iconBg}`}>{icon}</div>
            </div>
            <p className="mt-3 text-xl font-bold text-gray-800">{value}</p>
            <div className="mt-1 flex items-center justify-between gap-2">
                <span className={`text-[11px] font-semibold ${subColor}`}>{sub}</span>
                {delta}
            </div>
        </div>
    );
}

AnalyticsIndex.layout = (page: React.ReactNode) => <AdminLayout title="System Analytics">{page}</AdminLayout>;