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

function DeltaBadge({ value }: { value: number | null }) {
    if (value === null) return <span className="text-xs text-gray-400 font-mono">—</span>;
    const positive = value >= 0;
    return (
        <span
            className={[
                'inline-flex items-center gap-0.5 rounded-full px-2 py-0.5 text-[10px] font-bold border',
                positive ? 'bg-emerald-50 text-emerald-700 border-emerald-200' : 'bg-rose-50 text-rose-700 border-rose-200',
            ].join(' ')}
        >
            {positive ? <TrendingUp className="h-3 w-3" aria-hidden="true" /> : <TrendingDown className="h-3 w-3" aria-hidden="true" />}
            {positive ? '+' : ''}{value}%
        </span>
    );
}

function SectionHeader({ title, description }: { title: string; description?: string }) {
    return (
        <div className="mb-3 space-y-0.5">
            <h2 className="text-base font-extrabold text-[#1B1F5C]">{title}</h2>
            {description && <p className="text-xs text-gray-500 font-medium">{description}</p>}
        </div>
    );
}

function EmptyState({ message }: { message: string }) {
    return (
        <div className="flex flex-col items-center justify-center min-h-[160px] rounded-xl border border-dashed border-gray-200 bg-gray-50/50 text-gray-500 space-y-1.5 p-4">
            <CalendarX className="h-6 w-6 text-gray-400" aria-hidden="true" />
            <p className="text-xs font-bold">{message}</p>
        </div>
    );
}

function ChartTooltip({ active, payload, label }: any) {
    if (!active || !payload?.length) return null;
    return (
        <div className="rounded-xl border border-gray-200 bg-white p-3 shadow-md text-xs space-y-1">
            <p className="font-extrabold text-[#1B1F5C]">{label}</p>
            {payload.map((entry: any, i: number) => (
                <p key={i} style={{ color: entry.color }} className="flex justify-between gap-4">
                    <span className="flex items-center gap-1.5 font-semibold">
                        <span className="h-2 w-2 rounded-full" style={{ backgroundColor: entry.color }} />
                        {entry.name}
                    </span>
                    <span className="font-black">{fmt.format(entry.value)}</span>
                </p>
            ))}
        </div>
    );
}

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
            <Head title="System Analytics & Reports | 4ttnd Attendance System" />

            <div className="p-3 sm:p-5 space-y-4 font-sans text-gray-900 antialiased bg-[#F5F6FA] min-h-screen">

                {/* EXECUTIVE HEADER & TOOLBAR */}
                <header className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 bg-white p-4 sm:p-5 rounded-2xl border border-gray-200/80 shadow-xs">
                    <div className="space-y-0.5">
                        <h1 className="text-xl sm:text-2xl font-black tracking-tight text-[#1B1F5C]">System Analytics</h1>
                        <p className="text-xs text-gray-500 font-medium">Institutional biometric data and event attendance reporting</p>
                    </div>

                    <div className="flex flex-wrap items-center gap-2">
                        {/* Range Switcher */}
                        <div className="flex rounded-xl border border-gray-200 bg-gray-50/80 p-1 shadow-2xs">
                            {[
                                { key: '12m', label: 'Last 12 Months' },
                                { key: 'semester', label: 'This Semester' },
                                { key: 'month', label: 'This Month' },
                            ].map((item) => (
                                <button
                                    key={item.key}
                                    onClick={() => handleRangeChange(item.key)}
                                    className={[
                                        'rounded-lg px-3 py-1.5 text-xs font-bold transition-all min-h-[38px] focus-visible:ring-2 focus-visible:ring-[#F5A623]',
                                        dateRange === item.key
                                            ? 'bg-[#1B1F5C] text-white shadow-xs'
                                            : 'text-gray-600 hover:text-gray-900',
                                    ].join(' ')}
                                >
                                    {item.label}
                                </button>
                            ))}
                        </div>

                        <button
                            onClick={handleExportReport}
                            className="inline-flex items-center justify-center gap-1.5 rounded-xl border border-gray-300 bg-white px-3.5 py-2 min-h-[38px] text-xs font-bold text-gray-700 shadow-xs hover:bg-gray-100 transition focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                        >
                            <Download className="h-3.5 w-3.5 text-[#1B1F5C]" aria-hidden="true" />
                            <span>Export Report</span>
                        </button>

                        <Link
                            href="/admin/events"
                            className="inline-flex items-center justify-center gap-1.5 rounded-xl bg-[#1B1F5C] px-4 py-2 min-h-[38px] text-xs font-bold text-white shadow-md hover:bg-[#131644] transition-all focus-visible:ring-2 focus-visible:ring-[#F5A623] active:scale-98"
                        >
                            <span>Manage Events</span>
                            <ArrowUpRight className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                        </Link>
                    </div>
                </header>

                {/* KPI RIBBON CARDS */}
                <section aria-label="System Performance Indicators" className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
                    <KpiCard
                        label="Enrolled Students"
                        value={fmt.format(metrics.totalStudents)}
                        sub="Active biometric vectors"
                        subColor="text-[#1B1F5C]"
                        icon={<Users className="h-4.5 w-4.5" aria-hidden="true" />}
                        iconBg="bg-indigo-50 text-[#1B1F5C] border border-indigo-100"
                    />
                    <KpiCard
                        label="Attendance Rate"
                        value={`${metrics.globalAttendanceRate}%`}
                        sub="System-wide turnout"
                        icon={<CheckCircle2 className="h-4.5 w-4.5" aria-hidden="true" />}
                        iconBg="bg-emerald-50 text-emerald-700 border border-emerald-100"
                        delta={<DeltaBadge value={deltas.attendances} />}
                    />
                    <KpiCard
                        label="Biometric Success"
                        value={`${metrics.biometricSuccessRate}%`}
                        sub="Verified check-ins"
                        subColor="text-indigo-900"
                        icon={<ShieldCheck className="h-4.5 w-4.5" aria-hidden="true" />}
                        iconBg="bg-purple-50 text-purple-700 border border-purple-100"
                        delta={<DeltaBadge value={deltas.biometricSuccessRate} />}
                    />
                    <KpiCard
                        label="Total Events"
                        value={fmt.format(metrics.totalEvents)}
                        sub="Recorded sessions"
                        icon={<Calendar className="h-4.5 w-4.5" aria-hidden="true" />}
                        iconBg="bg-amber-50 text-amber-700 border border-amber-100"
                    />
                </section>

                {/* MONTHLY ATTENDANCE TREND */}
                <section aria-label="Monthly Attendance Trend" className="rounded-2xl border border-gray-200/80 bg-white p-4 sm:p-5 shadow-xs space-y-3">
                    <SectionHeader
                        title="Monthly Attendance Trend"
                        description="Check-ins and biometric verifications over the selected period"
                    />
                    {monthlyTrend.length > 0 ? (
                        <div className="h-60 w-full">
                            <ResponsiveContainer width="100%" height="100%">
                                <LineChart data={monthlyTrend} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
                                    <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#f1f5f9" />
                                    <XAxis dataKey="month" tick={{ fontSize: 10, fill: '#64748b' }} tickLine={false} axisLine={false} />
                                    <YAxis allowDecimals={false} tick={{ fontSize: 10, fill: '#64748b' }} tickLine={false} axisLine={false} />
                                    <Tooltip content={<ChartTooltip />} />
                                    <Legend wrapperStyle={{ fontSize: 11, fontWeight: 600, paddingTop: '6px' }} />
                                    <Line
                                        type="monotone"
                                        dataKey="total"
                                        name="Total Check-ins"
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
                </section>

                {/* EVENT SUMMARY & HOURLY DISTRIBUTION */}
                <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
                    {/* Event Bar Chart */}
                    <section aria-label="Attendance by event" className="rounded-2xl border border-gray-200/80 bg-white p-4 sm:p-5 shadow-xs space-y-3">
                        <SectionHeader
                            title="Attendance by Event"
                            description="20 most recent events — total check-ins vs. verified"
                        />
                        {filteredEventSummary.length > 0 ? (
                            <div className="h-64 w-full">
                                <ResponsiveContainer width="100%" height="100%">
                                    <BarChart
                                        data={filteredEventSummary}
                                        layout="vertical"
                                        margin={{ top: 5, right: 10, left: 10, bottom: 0 }}
                                    >
                                        <CartesianGrid strokeDasharray="3 3" horizontal={false} stroke="#f1f5f9" />
                                        <XAxis type="number" allowDecimals={false} tick={{ fontSize: 10, fill: '#64748b' }} tickLine={false} axisLine={false} />
                                        <YAxis
                                            dataKey="event"
                                            type="category"
                                            width={100}
                                            tick={{ fontSize: 10, fill: '#1B1F5C', fontWeight: 600 }}
                                            tickLine={false}
                                            axisLine={false}
                                        />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Legend wrapperStyle={{ fontSize: 11, fontWeight: 600, paddingTop: '6px' }} />
                                        <Bar dataKey="attended" name="Attended" fill={NAVY} radius={[0, 4, 4, 0]} barSize={9} />
                                        <Bar dataKey="successful" name="Verified" fill="#10B981" radius={[0, 4, 4, 0]} barSize={9} />
                                    </BarChart>
                                </ResponsiveContainer>
                            </div>
                        ) : (
                            <EmptyState message="No event data recorded." />
                        )}
                    </section>

                    {/* Hourly Histogram */}
                    <section aria-label="Check-in time distribution" className="rounded-2xl border border-gray-200/80 bg-white p-4 sm:p-5 shadow-xs space-y-3">
                        <SectionHeader
                            title="Check-in Time Distribution"
                            description="Hourly breakdown of successful biometric verifications"
                        />
                        {hourlyDistribution.length > 0 ? (
                            <div className="h-64 w-full">
                                <ResponsiveContainer width="100%" height="100%">
                                    <BarChart data={hourlyDistribution} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
                                        <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#f1f5f9" />
                                        <XAxis dataKey="label" tick={{ fontSize: 10, fill: '#64748b' }} tickLine={false} axisLine={false} />
                                        <YAxis allowDecimals={false} tick={{ fontSize: 10, fill: '#64748b' }} tickLine={false} axisLine={false} />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Bar dataKey="count" name="Check-ins" radius={[4, 4, 0, 0]} barSize={14}>
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
                    </section>
                </div>

                {/* COURSE / DEGREE BREAKDOWN */}
                <main className="rounded-2xl border border-gray-200/80 bg-white p-4 sm:p-5 shadow-xs space-y-4">
                    <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-gray-100 pb-3">
                        <SectionHeader
                            title="Student Distribution by Course"
                            description="Enrolled biometric students grouped by academic program. Click to filter."
                        />
                        {selectedCourse && (
                            <button
                                onClick={() => setSelectedCourse(null)}
                                className="inline-flex items-center gap-1 text-xs font-bold text-[#1B1F5C] hover:underline focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-xs"
                            >
                                <Filter className="h-3 w-3 text-[#F5A623]" aria-hidden="true" />
                                <span>Clear filter ({selectedCourse})</span>
                            </button>
                        )}
                    </div>

                    {courseBreakdown.length > 0 ? (
                        <div className="space-y-4">
                            {/* Horizontal Bar Chart */}
                            <div className="h-52 w-full">
                                <ResponsiveContainer width="100%" height="100%">
                                    <BarChart
                                        data={courseBreakdown}
                                        layout="vertical"
                                        margin={{ top: 5, right: 10, left: 10, bottom: 0 }}
                                    >
                                        <CartesianGrid strokeDasharray="3 3" horizontal={false} stroke="#f1f5f9" />
                                        <XAxis type="number" allowDecimals={false} tick={{ fontSize: 10, fill: '#64748b' }} tickLine={false} axisLine={false} />
                                        <YAxis
                                            dataKey="course"
                                            type="category"
                                            width={85}
                                            tick={{ fontSize: 10, fill: '#1B1F5C', fontWeight: 600 }}
                                            tickLine={false}
                                            axisLine={false}
                                        />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Bar dataKey="total" name="Students" radius={[0, 4, 4, 0]} barSize={12}>
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
                            <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2 lg:grid-cols-3">
                                {courseBreakdown.map((item, i) => {
                                    const pct = totalStudents > 0 ? Math.round((item.total / totalStudents) * 100) : 0;
                                    const isSelected = selectedCourse === item.course;
                                    return (
                                        <div
                                            key={i}
                                            onClick={() => setSelectedCourse(isSelected ? null : item.course)}
                                            className={[
                                                'flex items-center justify-between rounded-xl border p-3 cursor-pointer transition-all focus-visible:ring-2 focus-visible:ring-[#F5A623]',
                                                isSelected
                                                    ? 'border-[#1B1F5C] bg-indigo-50/50 shadow-xs'
                                                    : 'border-gray-200/70 bg-gray-50/50 hover:border-gray-300 hover:bg-gray-100/50',
                                            ].join(' ')}
                                        >
                                            <div className="flex items-center gap-2">
                                                <span
                                                    className="h-2.5 w-2.5 shrink-0 rounded-full"
                                                    style={{ backgroundColor: COLORS[i % COLORS.length] }}
                                                    aria-hidden="true"
                                                />
                                                <span className="text-xs font-bold text-gray-900 truncate max-w-[130px]" title={item.course}>
                                                    {item.course}
                                                </span>
                                            </div>
                                            <div className="flex items-center gap-2">
                                                <span className="text-[10px] font-mono font-bold text-gray-500">{pct}%</span>
                                                <span className="rounded-lg bg-white px-2 py-0.5 text-xs font-black text-[#1B1F5C] border border-gray-200 shadow-2xs">
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
                </main>

            </div>
        </>
    );
}

function KpiCard({
    label,
    value,
    sub,
    subColor = 'text-gray-500',
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
        <div className="rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs flex flex-col justify-between">
            <div className="flex items-center justify-between">
                <span className="text-[10px] font-extrabold uppercase tracking-wider text-gray-500">{label}</span>
                <div className={`rounded-xl p-2 ${iconBg}`}>{icon}</div>
            </div>
            <div className="mt-3">
                <p className="text-2xl font-black text-gray-900 tracking-tight">{value}</p>
                <div className="mt-0.5 flex items-center justify-between gap-2">
                    <span className={`text-[11px] font-bold ${subColor}`}>{sub}</span>
                    {delta}
                </div>
            </div>
        </div>
    );
}

AnalyticsIndex.layout = (page: React.ReactNode) => <AdminLayout title="System Analytics">{page}</AdminLayout>;