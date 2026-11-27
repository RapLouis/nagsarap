import React, { useEffect, useMemo, useRef, useState } from 'react';
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
    ArrowUp,
    Download,
    X,
    CalendarX,
    Loader2,
    ChevronRight,
    ChevronLeft,
    Search,
    AlertCircle,
    RotateCcw,
    MapPin,
    FilterX,
} from 'lucide-react';
import {
    ResponsiveContainer,
    BarChart,
    Bar,
    ComposedChart,
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
    heldEvents?: number;
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
    enrolled_biometric?: number;
};

type MonthlyTrendRow = {
    month: string;
    total: number;
    successful: number;
    pass_rate?: number;
    avg_confidence: number;
};

type EventSummaryRow = {
    id: number;
    event: string;
    location?: string | null;
    date: string;
    start_date?: string;
    end_date?: string;
    total_days?: number;
    is_upcoming?: boolean;
    attended: number;
    successful: number;
    pass_rate?: number;
    avg_confidence: number;
};

type PageLink = {
    url: string | null;
    label: string;
    active: boolean;
};

type PaginatedEventDirectory = {
    data: EventSummaryRow[];
    links: PageLink[];
    current_page?: number;
    last_page?: number;
    total?: number;
    from?: number | null;
    to?: number | null;
};

type HourlyRow = {
    hour: number;
    label: string;
    count: number;
};

type Filters = {
    range?: string;
    search?: string;
    status?: string;
    sort?: string;
};

type Props = {
    metrics: Metrics;
    deltas: Deltas;
    courseBreakdown: CourseStat[];
    monthlyTrend: MonthlyTrendRow[];
    topEvents?: {
        highestTurnout: EventSummaryRow[];
        lowestTurnout: EventSummaryRow[];
    };
    eventDirectory?: PaginatedEventDirectory;
    eventSummary?: EventSummaryRow[];
    hourlyDistribution: HourlyRow[];
    filters: Filters;
};

type LeaderboardMode = 'highestTurnout' | 'lowestTurnout';
type DirectoryStatus = 'all' | 'held' | 'upcoming';
type DirectorySort = 'recent' | 'highest_turnout' | 'lowest_turnout' | 'lowest_confidence';

// ─── Constants & Helpers ───────────────────────────────────────────────────────

const NAVY = '#1B1F5C';
const EMERALD = '#059669';
const GOLD = '#F5A623';

const COLORS = [
    '#1B1F5C',
    '#2563EB',
    '#059669',
    '#D97706',
    '#7C3AED',
    '#DC2626',
    '#0891B2',
    '#EA580C',
];

const RANGE_OPTIONS = [
    { key: '12m', label: 'Last 12 Months', shortLabel: '12M' },
    { key: 'semester', label: 'This Semester', shortLabel: 'Semester' },
    { key: 'month', label: 'This Month', shortLabel: 'Month' },
] as const;

const fmt = new Intl.NumberFormat('en-PH');
const confidenceFmt = new Intl.NumberFormat('en-PH', {
    style: 'percent',
    minimumFractionDigits: 1,
});

function truncateLabel(value: string, maxLen = 22): string {
    if (!value) return 'Untitled';
    return value.length > maxLen ? `${value.slice(0, maxLen - 1)}…` : value;
}

function safeNumber(value: unknown): number {
    const n = Number(value);
    return Number.isFinite(n) ? n : 0;
}

function extractPageNumber(url: string | null): number | null {
    if (!url) return null;
    try {
        const parsed = new URL(url, 'http://localhost');
        const page = parsed.searchParams.get('page');
        return page ? Number(page) : 1;
    } catch {
        const match = url.match(/[?&]page=(\d+)/);
        return match ? Number(match[1]) : null;
    }
}

function formatPaginationLabel(rawLabel: string): {
    text: string;
    ariaLabel: string;
    type: 'prev' | 'next' | 'page';
} {
    const cleaned = rawLabel
        .replace(/«|»/g, '')
        .replace(/<[^>]*>/g, '')
        .trim();

    if (/previous/i.test(cleaned)) {
        return { text: 'Previous', ariaLabel: 'Go to previous page', type: 'prev' };
    }
    if (/next/i.test(cleaned)) {
        return { text: 'Next', ariaLabel: 'Go to next page', type: 'next' };
    }
    return {
        text: cleaned,
        ariaLabel: `Go to page ${cleaned}`,
        type: 'page',
    };
}

// ─── Reusable UI Primitives ────────────────────────────────────────────────────

function DeltaBadge({ value }: { value: number | null }) {
    if (value === null || value === undefined || Number.isNaN(value)) {
        return (
            <span className="font-mono text-[11px] font-medium text-gray-500">
                No prior baseline
            </span>
        );
    }
    const positive = value >= 0;
    return (
        <span
            className={[
                'inline-flex items-center gap-0.5 rounded-full border px-2 py-0.5 text-[11px] font-bold',
                positive
                    ? 'border-emerald-200 bg-emerald-50 text-emerald-800'
                    : 'border-rose-200 bg-rose-50 text-rose-800',
            ].join(' ')}
        >
            {positive ? (
                <TrendingUp className="h-3 w-3" aria-hidden="true" />
            ) : (
                <TrendingDown className="h-3 w-3" aria-hidden="true" />
            )}
            <span>
                {positive ? '+' : ''}
                {value}%
            </span>
        </span>
    );
}

function SectionHeader({
    id,
    title,
    description,
    badge,
}: {
    id?: string;
    title: string;
    description?: string;
    badge?: React.ReactNode;
}) {
    return (
        <div className="space-y-0.5">
            <div className="flex flex-wrap items-center gap-2">
                <h2 id={id} className="text-sm font-extrabold tracking-tight text-[#1B1F5C] sm:text-base">
                    {title}
                </h2>
                {badge}
            </div>
            {description && (
                <p className="text-xs font-medium text-gray-600">{description}</p>
            )}
        </div>
    );
}

function EmptyState({
    title,
    message,
    actionLabel,
    onAction,
    icon = 'calendar',
}: {
    title?: string;
    message: string;
    actionLabel?: string;
    onAction?: () => void;
    icon?: 'calendar' | 'filter';
}) {
    return (
        <div className="flex min-h-[160px] flex-col items-center justify-center space-y-2 rounded-xl border border-dashed border-gray-200 bg-[#F5F6FA]/80 p-4 text-center">
            <div className="flex h-9 w-9 items-center justify-center rounded-xl border border-[#1B1F5C]/15 bg-white text-[#1B1F5C] shadow-2xs">
                {icon === 'filter' ? (
                    <FilterX className="h-4 w-4 text-[#F5A623]" aria-hidden="true" />
                ) : (
                    <CalendarX className="h-4 w-4 text-[#1B1F5C]" aria-hidden="true" />
                )}
            </div>
            {title && <p className="text-xs font-extrabold text-[#1B1F5C]">{title}</p>}
            <p className="max-w-sm text-xs font-medium text-gray-600">{message}</p>
            {actionLabel && onAction && (
                <button
                    type="button"
                    onClick={onAction}
                    className="mt-1 inline-flex min-h-[38px] items-center gap-1.5 rounded-xl border border-gray-300 bg-white px-3.5 py-1.5 text-xs font-bold text-[#1B1F5C] transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                >
                    <RotateCcw className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                    <span>{actionLabel}</span>
                </button>
            )}
        </div>
    );
}

function ChartTooltip({ active, payload, label }: any) {
    if (!active || !payload?.length) return null;
    const fullTitle = payload[0]?.payload?.fullTitle || label;
    return (
        <div className="max-w-xs space-y-1.5 rounded-xl border border-gray-200 bg-white p-3 text-xs shadow-xs">
            <p className="break-words font-extrabold text-[#1B1F5C]">{fullTitle}</p>
            <div className="space-y-1">
                {payload.map((entry: any, i: number) => {
                    const isPercent =
                        entry.dataKey === 'pass_rate' || String(entry.name).includes('%');
                    return (
                        <p
                            key={i}
                            style={{ color: entry.color }}
                            className="flex items-center justify-between gap-4"
                        >
                            <span className="flex items-center gap-1.5 font-semibold">
                                <span
                                    className="h-2 w-2 shrink-0 rounded-full"
                                    style={{ backgroundColor: entry.color }}
                                />
                                {entry.name}
                            </span>
                            <span className="font-mono font-black">
                                {isPercent
                                    ? `${safeNumber(entry.value).toFixed(1)}%`
                                    : fmt.format(safeNumber(entry.value))}
                            </span>
                        </p>
                    );
                })}
            </div>
        </div>
    );
}

function ConfidencePill({ score, hasLogs }: { score: number; hasLogs: boolean }) {
    if (!hasLogs) {
        return (
            <span className="inline-flex items-center rounded-md border border-gray-200 bg-gray-50 px-2 py-0.5 font-mono text-xs font-medium text-gray-500">
                N/A
            </span>
        );
    }
    const pct = Math.min(100, Math.max(0, score * 100));
    const style =
        pct >= 80
            ? 'border-emerald-200 bg-emerald-50 text-emerald-800'
            : pct >= 60
              ? 'border-amber-200 bg-amber-50 text-amber-800'
              : 'border-rose-200 bg-rose-50 text-rose-800';
    return (
        <span
            className={`inline-flex items-center rounded-md border px-2 py-0.5 font-mono text-xs font-bold ${style}`}
        >
            {confidenceFmt.format(score)}
        </span>
    );
}

// ─── Main Component ─────────────────────────────────────────────────────────────

export default function AnalyticsIndex({
    metrics,
    deltas,
    courseBreakdown = [],
    monthlyTrend = [],
    topEvents,
    eventDirectory,
    eventSummary = [],
    hourlyDistribution = [],
    filters,
}: Props) {
    const [dateRange, setDateRange] = useState<string>(filters?.range || '12m');
    const [search, setSearch] = useState<string>(filters?.search || '');
    const [statusFilter, setStatusFilter] = useState<DirectoryStatus>(
        (filters?.status as DirectoryStatus) || 'all'
    );
    const [sortBy, setSortBy] = useState<DirectorySort>(
        (filters?.sort as DirectorySort) || 'recent'
    );
    const [leaderboardMode, setLeaderboardMode] = useState<LeaderboardMode>('highestTurnout');
    const [selectedCourse, setSelectedCourse] = useState<string | null>(null);

    const [isSyncing, setIsSyncing] = useState(false);
    const [requestError, setRequestError] = useState<string | null>(null);
    const [statusAnnouncement, setStatusAnnouncement] = useState<string>('');
    const [showBackToTop, setShowBackToTop] = useState(false);

    const isFirstSearchRun = useRef(true);
    const searchDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const directorySectionRef = useRef<HTMLElement | null>(null);

    // Sync local filter state when props update via navigation
    useEffect(() => {
        setDateRange(filters?.range || '12m');
        setSearch(filters?.search || '');
        setStatusFilter((filters?.status as DirectoryStatus) || 'all');
        setSortBy((filters?.sort as DirectorySort) || 'recent');
    }, [filters?.range, filters?.search, filters?.status, filters?.sort]);

    // Track scroll position for non-intrusive back-to-top button
    useEffect(() => {
        const handleScroll = () => {
            setShowBackToTop(window.scrollY > 480);
        };
        window.addEventListener('scroll', handleScroll, { passive: true });
        return () => window.removeEventListener('scroll', handleScroll);
    }, []);

    const visitAnalytics = (
        overrides: Partial<Filters & { page?: number }> = {},
        announcement?: string
    ) => {
        const nextQuery: Record<string, string | number> = {
            range: overrides.range ?? dateRange,
            search: overrides.search ?? search,
            status: overrides.status ?? statusFilter,
            sort: overrides.sort ?? sortBy,
        };

        if (overrides.page && overrides.page > 1) {
            nextQuery.page = overrides.page;
        }

        setRequestError(null);
        if (announcement) {
            setStatusAnnouncement(announcement);
        }

        router.get('/admin/analytics', nextQuery, {
            preserveState: true,
            preserveScroll: true,
            replace: true,
            onStart: () => setIsSyncing(true),
            onFinish: () => setIsSyncing(false),
            onError: () => {
                setRequestError(
                    'Unable to refresh analytics data. Check your network connection or try again.'
                );
            },
        });
    };

    // Debounced search for Event Performance Directory (resets to page 1)
    useEffect(() => {
        if (isFirstSearchRun.current) {
            isFirstSearchRun.current = false;
            return;
        }

        if (searchDebounceRef.current) clearTimeout(searchDebounceRef.current);
        searchDebounceRef.current = setTimeout(() => {
            visitAnalytics(
                { search, page: 1 },
                search ? `Searching events matching ${search}` : 'Cleared event search filter'
            );
        }, 350);

        return () => {
            if (searchDebounceRef.current) clearTimeout(searchDebounceRef.current);
        };
    }, [search]);

    const handleRangeChange = (range: string) => {
        if (range === dateRange) return;
        const label = RANGE_OPTIONS.find((r) => r.key === range)?.label ?? range;
        setDateRange(range);
        visitAnalytics({ range, page: 1 }, `Reporting period updated to ${label}`);
    };

    const handleStatusChange = (status: DirectoryStatus) => {
        if (status === statusFilter) return;
        setStatusFilter(status);
        visitAnalytics({ status, page: 1 }, `Filtered event directory by ${status}`);
    };

    const handleSortChange = (sort: DirectorySort) => {
        if (sort === sortBy) return;
        setSortBy(sort);
        visitAnalytics({ sort, page: 1 }, `Sorted event directory by ${sort.replace('_', ' ')}`);
    };

    const handlePageChange = (page: number | null) => {
        if (!page || page < 1 || isSyncing) return;
        visitAnalytics({ page }, `Loaded page ${page} of event directory`);
        directorySectionRef.current?.scrollIntoView({
            behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches
                ? 'auto'
                : 'smooth',
            block: 'nearest',
        });
    };

    const handleResetFilters = () => {
        setSearch('');
        setStatusFilter('all');
        setSortBy('recent');
        visitAnalytics(
            { search: '', status: 'all', sort: 'recent', page: 1 },
            'Reset all event directory filters'
        );
    };

    // Sanitized Monthly Trend Data
    const normalizedMonthlyTrend = useMemo(
        () =>
            monthlyTrend.map((row) => {
                const total = safeNumber(row.total);
                const successful = safeNumber(row.successful);
                const computedPassRate =
                    row.pass_rate !== undefined
                        ? safeNumber(row.pass_rate)
                        : total > 0
                          ? Math.round((successful / total) * 1000) / 10
                          : 0;
                return {
                    month: row.month,
                    total,
                    successful,
                    pass_rate: computedPassRate,
                    avg_confidence: safeNumber(row.avg_confidence),
                };
            }),
        [monthlyTrend]
    );

    // Scale-safe Top 8 Events Leaderboard Data
    const activeLeaderboardData = useMemo(() => {
        const rawList =
            topEvents?.[leaderboardMode] ??
            [...eventSummary]
                .filter((e) => safeNumber(e.attended) > 0)
                .sort((a, b) =>
                    leaderboardMode === 'highestTurnout'
                        ? safeNumber(b.attended) - safeNumber(a.attended)
                        : safeNumber(a.attended) - safeNumber(b.attended)
                )
                .slice(0, 8);

        return rawList.slice(0, 8).map((item) => ({
            ...item,
            shortLabel: truncateLabel(item.event, 20),
            fullTitle:
                item.total_days && item.total_days > 1
                    ? `${item.event} (${item.total_days} Days)`
                    : item.event,
            attended: safeNumber(item.attended),
            successful: safeNumber(item.successful),
        }));
    }, [topEvents, eventSummary, leaderboardMode]);

    // Directory rows (paginated when provided, fallback to eventSummary)
    const directoryRows: EventSummaryRow[] = eventDirectory?.data ?? eventSummary;
    const directoryLinks: PageLink[] = eventDirectory?.links ?? [];
    const directoryTotal = eventDirectory?.total ?? directoryRows.length;

    const totalStudents = courseBreakdown.reduce((s, r) => s + safeNumber(r.total), 0);
    const selectedCourseStat = selectedCourse
        ? courseBreakdown.find((c) => c.course === selectedCourse) ?? null
        : null;

    const hasActiveDirectoryFilters =
        search.trim() !== '' || statusFilter !== 'all' || sortBy !== 'recent';

    const activeRangeLabel =
        RANGE_OPTIONS.find((r) => r.key === dateRange)?.label ?? 'Last 12 Months';

    return (
        <>
            <Head title="System Analytics & Reports | 4ttnd Attendance System" />

            {/* Screen reader live status region */}
            <div role="status" aria-live="polite" className="sr-only">
                {statusAnnouncement}
            </div>

            <div className="w-full space-y-3.5 bg-[#F5F6FA] font-sans text-gray-900 antialiased">
                {/* ERROR ALERT BANNER */}
                {requestError && (
                    <div
                        role="alert"
                        className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-rose-900 shadow-xs"
                    >
                        <div className="flex items-center gap-2.5 text-xs font-bold sm:text-sm">
                            <AlertCircle
                                className="h-4 w-4 shrink-0 text-rose-600"
                                aria-hidden="true"
                            />
                            <span>{requestError}</span>
                        </div>
                        <div className="flex items-center gap-2">
                            <button
                                type="button"
                                onClick={() => visitAnalytics()}
                                className="inline-flex min-h-[38px] items-center gap-1.5 rounded-xl border border-rose-300 bg-white px-3 py-1.5 text-xs font-bold text-rose-800 transition-colors hover:bg-rose-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            >
                                <RotateCcw className="h-3.5 w-3.5" aria-hidden="true" />
                                <span>Retry</span>
                            </button>
                            <button
                                type="button"
                                onClick={() => setRequestError(null)}
                                aria-label="Dismiss error alert"
                                className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-xl text-rose-700 transition-colors hover:bg-rose-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            >
                                <X className="h-4 w-4" aria-hidden="true" />
                            </button>
                        </div>
                    </div>
                )}

                {/* COMPACT EXECUTIVE HEADER & REPORTING CONTROLS */}
                <header className="flex flex-col justify-between gap-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs lg:flex-row lg:items-center">
                    <div className="min-w-0 space-y-0.5">
                        <div className="flex flex-wrap items-center gap-2">
                            <h1 className="text-lg font-black tracking-tight text-[#1B1F5C] sm:text-xl">
                                System Analytics
                            </h1>
                            <span className="inline-flex items-center rounded-lg border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 px-2 py-0.5 text-[11px] font-bold text-[#1B1F5C]">
                                {activeRangeLabel}
                            </span>
                            {isSyncing && (
                                <span className="inline-flex items-center gap-1 rounded-lg border border-amber-200 bg-amber-50 px-2 py-0.5 text-[11px] font-bold text-amber-800">
                                    <Loader2
                                        className="h-3 w-3 animate-spin motion-reduce:animate-none"
                                        aria-hidden="true"
                                    />
                                    <span>Updating</span>
                                </span>
                            )}
                        </div>
                        <p className="text-xs font-medium text-gray-600">
                            Institutional biometric verification rates, turnout trends, and event audit logs
                        </p>
                    </div>

                    <div className="flex flex-wrap items-center gap-2 print:hidden">
                        {/* Reporting Period Segmented Control */}
                        <div
                            role="group"
                            aria-label="Analytics reporting period"
                            className="inline-flex items-center rounded-xl border border-gray-200 bg-[#F5F6FA] p-1"
                        >
                            {RANGE_OPTIONS.map((item) => {
                                const isActive = dateRange === item.key;
                                return (
                                    <button
                                        key={item.key}
                                        type="button"
                                        disabled={isSyncing}
                                        aria-pressed={isActive}
                                        onClick={() => handleRangeChange(item.key)}
                                        className={[
                                            'min-h-[34px] rounded-lg px-2.5 py-1 text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-70 sm:px-3',
                                            isActive
                                                ? 'bg-[#1B1F5C] text-white shadow-2xs'
                                                : 'text-gray-600 hover:text-gray-900',
                                        ].join(' ')}
                                    >
                                        <span className="sm:hidden">{item.shortLabel}</span>
                                        <span className="hidden sm:inline">{item.label}</span>
                                    </button>
                                );
                            })}
                        </div>

                        <button
                            type="button"
                            onClick={() => window.print()}
                            className="inline-flex min-h-[40px] items-center justify-center gap-1.5 rounded-xl border border-gray-300 bg-white px-3.5 py-2 text-xs font-bold text-gray-700 transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                        >
                            <Download className="h-3.5 w-3.5 text-[#1B1F5C]" aria-hidden="true" />
                            <span>Export Report</span>
                        </button>

                        <Link
                            href="/admin/events"
                            className="inline-flex min-h-[40px] items-center justify-center gap-1.5 rounded-xl bg-[#1B1F5C] px-4 py-2 text-xs font-bold text-white shadow-2xs transition-colors hover:bg-[#131644] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                        >
                            <span>Manage Events</span>
                            <ArrowUpRight className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                        </Link>
                    </div>
                </header>

                {/* KPI SUMMARY RIBBON (ABOVE THE FOLD) */}
                <section
                    aria-label="System Performance Indicators"
                    className={`grid grid-cols-1 gap-3 transition-opacity sm:grid-cols-2 xl:grid-cols-4 ${
                        isSyncing ? 'opacity-65' : 'opacity-100'
                    }`}
                >
                    <KpiCard
                        label="Enrolled Students"
                        value={fmt.format(safeNumber(metrics.totalStudents))}
                        sub="Active biometric vectors"
                        subColor="text-[#1B1F5C]"
                        icon={<Users className="h-4 w-4" aria-hidden="true" />}
                        iconBg="border-[#1B1F5C]/15 bg-[#1B1F5C]/5 text-[#1B1F5C]"
                    />
                    <KpiCard
                        label="Held-Event Turnout"
                        value={`${safeNumber(metrics.globalAttendanceRate)}%`}
                        sub={
                            metrics.heldEvents !== undefined
                                ? `Across ${fmt.format(metrics.heldEvents)} held event${metrics.heldEvents !== 1 ? 's' : ''}`
                                : 'System-wide turnout'
                        }
                        icon={<CheckCircle2 className="h-4 w-4" aria-hidden="true" />}
                        iconBg="border-emerald-200 bg-emerald-50 text-emerald-700"
                        delta={<DeltaBadge value={deltas.attendances} />}
                    />
                    <KpiCard
                        label="Biometric Success"
                        value={`${safeNumber(metrics.biometricSuccessRate)}%`}
                        sub="Verified check-in pass rate"
                        subColor="text-[#1B1F5C]"
                        icon={<ShieldCheck className="h-4 w-4" aria-hidden="true" />}
                        iconBg="border-[#1B1F5C]/15 bg-[#1B1F5C]/5 text-[#1B1F5C]"
                        delta={<DeltaBadge value={deltas.biometricSuccessRate} />}
                    />
                    <KpiCard
                        label="Scheduled Events"
                        value={fmt.format(safeNumber(metrics.totalEvents))}
                        sub={
                            metrics.heldEvents !== undefined
                                ? `${fmt.format(Math.max(0, metrics.totalEvents - metrics.heldEvents))} upcoming`
                                : 'Recorded sessions'
                        }
                        icon={<Calendar className="h-4 w-4" aria-hidden="true" />}
                        iconBg="border-amber-200 bg-amber-50 text-amber-800"
                    />
                </section>

                {/* PRIMARY BENTO ANALYTICS ROW (12-COLUMN ASYMMETRIC GRID) */}
                <div className="grid grid-cols-1 gap-3.5 lg:grid-cols-12">
                    {/* Monthly Attendance & Verification Trend (8 Cols) */}
                    <section
                        aria-labelledby="monthly-trend-heading"
                        className="min-w-0 overflow-hidden space-y-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs lg:col-span-8"
                    >
                        <SectionHeader
                            id="monthly-trend-heading"
                            title="Monthly Attendance & Verification Trend"
                            description="Check-in volume vs. biometric verification pass rate (%) over the selected period"
                        />
                        {normalizedMonthlyTrend.length > 0 ? (
                            <div className="h-60 w-full min-w-0">
                                <ResponsiveContainer width="100%" height="100%">
                                    <ComposedChart
                                        data={normalizedMonthlyTrend}
                                        margin={{ top: 8, right: 6, left: -18, bottom: 0 }}
                                    >
                                        <CartesianGrid
                                            strokeDasharray="3 3"
                                            vertical={false}
                                            stroke="#f1f5f9"
                                        />
                                        <XAxis
                                            dataKey="month"
                                            tick={{ fontSize: 10, fill: '#64748b' }}
                                            tickLine={false}
                                            axisLine={false}
                                        />
                                        <YAxis
                                            yAxisId="left"
                                            allowDecimals={false}
                                            tick={{ fontSize: 10, fill: '#64748b' }}
                                            tickLine={false}
                                            axisLine={false}
                                        />
                                        <YAxis
                                            yAxisId="right"
                                            orientation="right"
                                            domain={[0, 100]}
                                            tickFormatter={(v) => `${v}%`}
                                            tick={{ fontSize: 10, fill: '#64748b' }}
                                            tickLine={false}
                                            axisLine={false}
                                        />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Legend
                                            wrapperStyle={{
                                                fontSize: 11,
                                                fontWeight: 600,
                                                paddingTop: '4px',
                                            }}
                                        />
                                        <Bar
                                            yAxisId="left"
                                            dataKey="total"
                                            name="Total Check-ins"
                                            fill={NAVY}
                                            radius={[4, 4, 0, 0]}
                                            barSize={16}
                                        />
                                        <Bar
                                            yAxisId="left"
                                            dataKey="successful"
                                            name="Verified"
                                            fill={EMERALD}
                                            radius={[4, 4, 0, 0]}
                                            barSize={16}
                                        />
                                        <Line
                                            yAxisId="right"
                                            type="monotone"
                                            dataKey="pass_rate"
                                            name="Pass Rate %"
                                            stroke={GOLD}
                                            strokeWidth={2.5}
                                            dot={{ r: 3, fill: GOLD }}
                                            activeDot={{ r: 5 }}
                                        />
                                    </ComposedChart>
                                </ResponsiveContainer>
                            </div>
                        ) : (
                            <EmptyState
                                title="No Monthly Trend Data"
                                message="No attendance records were logged during this reporting period."
                                actionLabel={dateRange !== '12m' ? 'Switch to Last 12 Months' : undefined}
                                onAction={dateRange !== '12m' ? () => handleRangeChange('12m') : undefined}
                            />
                        )}
                    </section>

                    {/* Check-in Time Distribution (4 Cols) */}
                    <section
                        aria-labelledby="hourly-dist-heading"
                        className="min-w-0 overflow-hidden space-y-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs lg:col-span-4"
                    >
                        <SectionHeader
                            id="hourly-dist-heading"
                            title="Peak Check-in Hours"
                            description="Hourly distribution of verified check-ins"
                        />
                        {hourlyDistribution.length > 0 ? (
                            <div className="h-60 w-full min-w-0">
                                <ResponsiveContainer width="100%" height="100%">
                                    <BarChart
                                        data={hourlyDistribution}
                                        margin={{ top: 8, right: 8, left: -22, bottom: 0 }}
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
                                        <Bar
                                            dataKey="count"
                                            name="Check-ins"
                                            radius={[4, 4, 0, 0]}
                                            barSize={14}
                                        >
                                            {hourlyDistribution.map((_, i) => (
                                                <Cell key={i} fill={COLORS[i % COLORS.length]} />
                                            ))}
                                        </Bar>
                                    </BarChart>
                                </ResponsiveContainer>
                            </div>
                        ) : (
                            <EmptyState
                                title="No Hourly Logs"
                                message="No verified check-in timestamps recorded for this period."
                            />
                        )}
                    </section>
                </div>

                {/* SECONDARY BENTO ROW: EVENT LEADERBOARD & COURSE COHORT BREAKDOWN */}
                <div className="grid grid-cols-1 gap-3.5 lg:grid-cols-12">
                    {/* Top 8 Events Turnout Leaderboard (6 Cols) */}
                    <section
                        aria-labelledby="event-bar-heading"
                        className="min-w-0 overflow-hidden space-y-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs lg:col-span-6"
                    >
                        <div className="flex flex-wrap items-start justify-between gap-2">
                            <SectionHeader
                                id="event-bar-heading"
                                title="Event Turnout Leaderboard"
                                description="Top 8 held events aggregated across session days"
                            />
                            <div
                                role="group"
                                aria-label="Leaderboard ranking order"
                                className="inline-flex rounded-xl border border-gray-200 bg-[#F5F6FA] p-1 print:hidden"
                            >
                                <button
                                    type="button"
                                    aria-pressed={leaderboardMode === 'highestTurnout'}
                                    onClick={() => setLeaderboardMode('highestTurnout')}
                                    className={`min-h-[32px] rounded-lg px-2.5 py-1 text-[11px] font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                        leaderboardMode === 'highestTurnout'
                                            ? 'bg-[#1B1F5C] text-white shadow-2xs'
                                            : 'text-gray-600 hover:text-gray-900'
                                    }`}
                                >
                                    Highest
                                </button>
                                <button
                                    type="button"
                                    aria-pressed={leaderboardMode === 'lowestTurnout'}
                                    onClick={() => setLeaderboardMode('lowestTurnout')}
                                    className={`min-h-[32px] rounded-lg px-2.5 py-1 text-[11px] font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                        leaderboardMode === 'lowestTurnout'
                                            ? 'bg-[#1B1F5C] text-white shadow-2xs'
                                            : 'text-gray-600 hover:text-gray-900'
                                    }`}
                                >
                                    Lowest
                                </button>
                            </div>
                        </div>

                        {activeLeaderboardData.length > 0 ? (
                            <div className="h-60 w-full min-w-0">
                                <ResponsiveContainer width="100%" height="100%">
                                    <BarChart
                                        data={activeLeaderboardData}
                                        layout="vertical"
                                        margin={{ top: 4, right: 12, left: 4, bottom: 0 }}
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
                                            dataKey="shortLabel"
                                            type="category"
                                            width={115}
                                            tick={{ fontSize: 10, fill: '#1B1F5C', fontWeight: 600 }}
                                            tickLine={false}
                                            axisLine={false}
                                        />
                                        <Tooltip content={<ChartTooltip />} />
                                        <Legend
                                            wrapperStyle={{
                                                fontSize: 11,
                                                fontWeight: 600,
                                                paddingTop: '4px',
                                            }}
                                        />
                                        <Bar
                                            dataKey="attended"
                                            name="Attended"
                                            fill={NAVY}
                                            radius={[0, 4, 4, 0]}
                                            barSize={8}
                                        />
                                        <Bar
                                            dataKey="successful"
                                            name="Verified"
                                            fill={EMERALD}
                                            radius={[0, 4, 4, 0]}
                                            barSize={8}
                                        />
                                    </BarChart>
                                </ResponsiveContainer>
                            </div>
                        ) : (
                            <EmptyState
                                title="No Completed Events"
                                message="No held events with attendance logs were found in this period."
                            />
                        )}
                    </section>

                    {/* Student Distribution by Course (6 Cols) */}
                    <section
                        aria-labelledby="course-dist-heading"
                        className="min-w-0 overflow-hidden space-y-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs lg:col-span-6"
                    >
                        <div className="flex flex-wrap items-start justify-between gap-2">
                            <SectionHeader
                                id="course-dist-heading"
                                title="Student Distribution by Course"
                                description="Select a program chip or bar to highlight cohort share"
                            />
                            {selectedCourseStat && (
                                <div className="flex items-center gap-1.5">
                                    <span className="rounded-lg border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 px-2.5 py-1 text-[11px] font-bold text-[#1B1F5C]">
                                        {selectedCourseStat.course}:{' '}
                                        {fmt.format(safeNumber(selectedCourseStat.total))} (
                                        {totalStudents > 0
                                            ? Math.round(
                                                  (safeNumber(selectedCourseStat.total) /
                                                      totalStudents) *
                                                      100
                                              )
                                            : 0}
                                        %)
                                    </span>
                                    <button
                                        type="button"
                                        onClick={() => setSelectedCourse(null)}
                                        aria-label="Clear selected course highlight"
                                        className="inline-flex min-h-[32px] min-w-[32px] items-center justify-center rounded-lg border border-gray-200 bg-white text-gray-600 transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    >
                                        <X className="h-3.5 w-3.5" aria-hidden="true" />
                                    </button>
                                </div>
                            )}
                        </div>

                        {courseBreakdown.length > 0 ? (
                            <div className="space-y-3">
                                <div className="h-44 w-full min-w-0">
                                    <ResponsiveContainer width="100%" height="100%">
                                        <BarChart
                                            data={courseBreakdown}
                                            layout="vertical"
                                            margin={{ top: 4, right: 10, left: 4, bottom: 0 }}
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
                                                width={88}
                                                tick={{
                                                    fontSize: 10,
                                                    fill: '#1B1F5C',
                                                    fontWeight: 600,
                                                }}
                                                tickLine={false}
                                                axisLine={false}
                                            />
                                            <Tooltip content={<ChartTooltip />} />
                                            <Bar
                                                dataKey="total"
                                                name="Students"
                                                radius={[0, 4, 4, 0]}
                                                barSize={10}
                                            >
                                                {courseBreakdown.map((item, i) => (
                                                    <Cell
                                                        key={i}
                                                        fill={COLORS[i % COLORS.length]}
                                                        opacity={
                                                            selectedCourse &&
                                                            selectedCourse !== item.course
                                                                ? 0.3
                                                                : 1
                                                        }
                                                        className="cursor-pointer transition-opacity"
                                                        onClick={() =>
                                                            setSelectedCourse(
                                                                selectedCourse === item.course
                                                                    ? null
                                                                    : item.course
                                                            )
                                                        }
                                                    />
                                                ))}
                                            </Bar>
                                        </BarChart>
                                    </ResponsiveContainer>
                                </div>

                                <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                                    {courseBreakdown.map((item, i) => {
                                        const pct =
                                            totalStudents > 0
                                                ? Math.round(
                                                      (safeNumber(item.total) / totalStudents) * 100
                                                  )
                                                : 0;
                                        const isSelected = selectedCourse === item.course;
                                        return (
                                            <button
                                                key={i}
                                                type="button"
                                                aria-pressed={isSelected}
                                                onClick={() =>
                                                    setSelectedCourse(
                                                        isSelected ? null : item.course
                                                    )
                                                }
                                                className={[
                                                    'flex min-h-[38px] w-full items-center justify-between rounded-xl border px-3 py-2 text-left transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]',
                                                    isSelected
                                                        ? 'border-[#1B1F5C] bg-[#1B1F5C]/5'
                                                        : 'border-gray-200/80 bg-[#F5F6FA]/70 hover:border-gray-300 hover:bg-gray-100/70',
                                                ].join(' ')}
                                            >
                                                <div className="flex min-w-0 items-center gap-2 pr-2">
                                                    <span
                                                        className="h-2.5 w-2.5 shrink-0 rounded-full"
                                                        style={{
                                                            backgroundColor:
                                                                COLORS[i % COLORS.length],
                                                        }}
                                                        aria-hidden="true"
                                                    />
                                                    <span
                                                        className="truncate text-xs font-bold text-gray-900"
                                                        title={item.course}
                                                    >
                                                        {item.course}
                                                    </span>
                                                </div>
                                                <div className="flex shrink-0 items-center gap-1.5">
                                                    <span className="font-mono text-[11px] font-bold text-gray-600">
                                                        {pct}%
                                                    </span>
                                                    <span className="rounded-md border border-gray-200 bg-white px-2 py-0.5 font-mono text-xs font-black text-[#1B1F5C]">
                                                        {fmt.format(safeNumber(item.total))}
                                                    </span>
                                                </div>
                                            </button>
                                        );
                                    })}
                                </div>
                            </div>
                        ) : (
                            <EmptyState
                                title="No Course Records"
                                message="No student program distribution records were found."
                            />
                        )}
                    </section>
                </div>

                {/* EVENT PERFORMANCE DIRECTORY (SEARCHABLE, FILTERABLE, PAGINATED) */}
                <section
                    ref={directorySectionRef}
                    aria-labelledby="event-drilldown-heading"
                    className="min-w-0 overflow-hidden space-y-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs"
                >
                    <div className="flex flex-col gap-3 border-b border-gray-100 pb-3 lg:flex-row lg:items-center lg:justify-between">
                        <div className="space-y-0.5">
                            <div className="flex flex-wrap items-center gap-2">
                                <h2
                                    id="event-drilldown-heading"
                                    className="text-sm font-extrabold tracking-tight text-[#1B1F5C] sm:text-base"
                                >
                                    Event Performance Directory
                                </h2>
                                <span className="rounded-md border border-gray-200 bg-[#F5F6FA] px-2 py-0.5 font-mono text-[11px] font-bold text-gray-700">
                                    {fmt.format(directoryTotal)} total
                                </span>
                            </div>
                            <p className="text-xs font-medium text-gray-600">
                                Select any event to open per-day turnout, biometric confidence, and student roster logs
                            </p>
                        </div>

                        {/* Search, Status & Sort Controls */}
                        <div className="flex flex-wrap items-center gap-2 print:hidden">
                            {/* Status Segmented Filter */}
                            <div
                                role="group"
                                aria-label="Filter directory by event status"
                                className="inline-flex rounded-xl border border-gray-200 bg-[#F5F6FA] p-1"
                            >
                                {(
                                    [
                                        { key: 'all', label: 'All' },
                                        { key: 'held', label: 'Held' },
                                        { key: 'upcoming', label: 'Upcoming' },
                                    ] as const
                                ).map((opt) => (
                                    <button
                                        key={opt.key}
                                        type="button"
                                        aria-pressed={statusFilter === opt.key}
                                        onClick={() => handleStatusChange(opt.key)}
                                        className={`min-h-[32px] rounded-lg px-2.5 py-1 text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                            statusFilter === opt.key
                                                ? 'bg-[#1B1F5C] text-white shadow-2xs'
                                                : 'text-gray-600 hover:text-gray-900'
                                        }`}
                                    >
                                        {opt.label}
                                    </button>
                                ))}
                            </div>

                            {/* Sort Dropdown */}
                            <label className="sr-only" htmlFor="directory-sort-select">
                                Sort events by
                            </label>
                            <select
                                id="directory-sort-select"
                                value={sortBy}
                                onChange={(e) =>
                                    handleSortChange(e.target.value as DirectorySort)
                                }
                                className="min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-bold text-gray-700 transition-colors hover:border-gray-400 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            >
                                <option value="recent">Sort: Most Recent</option>
                                <option value="highest_turnout">Sort: Highest Turnout</option>
                                <option value="lowest_turnout">Sort: Lowest Turnout</option>
                                <option value="lowest_confidence">Sort: Lowest Confidence</option>
                            </select>

                            {/* Debounced Search Input */}
                            <div className="relative w-full sm:w-60">
                                <Search
                                    className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-gray-400"
                                    aria-hidden="true"
                                />
                                <input
                                    type="text"
                                    value={search}
                                    onChange={(e) => setSearch(e.target.value)}
                                    placeholder="Search event or venue..."
                                    aria-label="Search event performance directory"
                                    className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white py-1.5 pl-8 pr-8 text-xs font-medium text-gray-900 placeholder:text-gray-400 transition-colors focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                />
                                {search && (
                                    <button
                                        type="button"
                                        onClick={() => setSearch('')}
                                        aria-label="Clear event search"
                                        className="absolute right-1.5 top-1/2 inline-flex h-7 w-7 -translate-y-1/2 items-center justify-center rounded-lg text-gray-400 hover:bg-gray-100 hover:text-gray-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    >
                                        <X className="h-3.5 w-3.5" aria-hidden="true" />
                                    </button>
                                )}
                            </div>
                        </div>
                    </div>

                    {directoryRows.length === 0 ? (
                        <EmptyState
                            icon={hasActiveDirectoryFilters ? 'filter' : 'calendar'}
                            title={
                                hasActiveDirectoryFilters
                                    ? 'No Matching Events'
                                    : 'No Scheduled Events'
                            }
                            message={
                                hasActiveDirectoryFilters
                                    ? 'No events matched your active search query or status filter. Adjust your terms or reset filters.'
                                    : 'There are no events recorded within this reporting period.'
                            }
                            actionLabel={
                                hasActiveDirectoryFilters
                                    ? 'Reset Search & Filters'
                                    : dateRange !== '12m'
                                      ? 'View Last 12 Months'
                                      : undefined
                            }
                            onAction={
                                hasActiveDirectoryFilters
                                    ? handleResetFilters
                                    : dateRange !== '12m'
                                      ? () => handleRangeChange('12m')
                                      : undefined
                            }
                        />
                    ) : (
                        <>
                            {/* Mobile & Tablet Card Stack (< md) */}
                            <div
                                className={`divide-y divide-gray-100 transition-opacity md:hidden ${
                                    isSyncing ? 'opacity-65' : 'opacity-100'
                                }`}
                            >
                                {directoryRows.map((row) => {
                                    const attended = safeNumber(row.attended);
                                    const successful = safeNumber(row.successful);
                                    const passPct =
                                        row.pass_rate !== undefined
                                            ? safeNumber(row.pass_rate)
                                            : attended > 0
                                              ? Math.round((successful / attended) * 100)
                                              : 0;
                                    const hasLogs = attended > 0;

                                    return (
                                        <article
                                            key={row.id}
                                            className="space-y-2.5 py-3 first:pt-1 last:pb-1"
                                        >
                                            <div className="flex items-start justify-between gap-2">
                                                <div className="min-w-0">
                                                    <Link
                                                        href={`/admin/analytics/events/${row.id}`}
                                                        className="block truncate text-xs font-extrabold text-[#1B1F5C] hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                    >
                                                        {row.event}
                                                    </Link>
                                                    <p className="mt-0.5 text-[11px] font-medium text-gray-600">
                                                        {row.date}
                                                        {row.total_days && row.total_days > 1
                                                            ? ` • ${row.total_days} Days`
                                                            : ''}
                                                    </p>
                                                    {row.location && (
                                                        <p className="mt-0.5 flex items-center gap-1 truncate text-[11px] font-medium text-gray-500">
                                                            <MapPin
                                                                className="h-3 w-3 shrink-0 text-[#F5A623]"
                                                                aria-hidden="true"
                                                            />
                                                            <span className="truncate">
                                                                {row.location}
                                                            </span>
                                                        </p>
                                                    )}
                                                </div>
                                                <Link
                                                    href={`/admin/analytics/events/${row.id}`}
                                                    aria-label={`Inspect analytics for ${row.event}`}
                                                    className="inline-flex min-h-[38px] shrink-0 items-center gap-1 rounded-xl border border-gray-200 bg-white px-3 py-1.5 text-xs font-bold text-[#1B1F5C] transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                >
                                                    <span>Details</span>
                                                    <ChevronRight
                                                        className="h-3.5 w-3.5 text-[#F5A623]"
                                                        aria-hidden="true"
                                                    />
                                                </Link>
                                            </div>

                                            <div className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-gray-100 bg-[#F5F6FA]/70 px-3 py-2 text-xs">
                                                <span className="font-mono font-bold text-gray-800">
                                                    {fmt.format(attended)} check-ins
                                                </span>
                                                <div className="flex items-center gap-2">
                                                    {hasLogs ? (
                                                        <span className="inline-flex items-center gap-1 rounded-full border border-emerald-200 bg-emerald-50 px-2 py-0.5 text-[11px] font-bold text-emerald-800">
                                                            <CheckCircle2
                                                                className="h-3 w-3"
                                                                aria-hidden="true"
                                                            />
                                                            <span>
                                                                {fmt.format(successful)} ({passPct}
                                                                %)
                                                            </span>
                                                        </span>
                                                    ) : (
                                                        <span className="rounded-full border border-gray-200 bg-white px-2 py-0.5 text-[11px] font-bold text-gray-600">
                                                            {row.is_upcoming
                                                                ? 'Upcoming'
                                                                : 'No Logs'}
                                                        </span>
                                                    )}
                                                    <ConfidencePill
                                                        score={safeNumber(row.avg_confidence)}
                                                        hasLogs={hasLogs}
                                                    />
                                                </div>
                                            </div>
                                        </article>
                                    );
                                })}
                            </div>

                            {/* Desktop Data Table (>= md) */}
                            <div
                                className={`hidden overflow-x-auto transition-opacity md:block ${
                                    isSyncing ? 'opacity-65' : 'opacity-100'
                                }`}
                            >
                                <table className="w-full text-left text-xs text-gray-700">
                                    <thead>
                                        <tr className="border-b border-gray-200/80 text-[10px] font-extrabold uppercase tracking-wider text-gray-500">
                                            <th scope="col" className="pb-2.5 pr-4">
                                                Event & Venue
                                            </th>
                                            <th scope="col" className="pb-2.5 pr-4">
                                                Schedule Span
                                            </th>
                                            <th scope="col" className="pb-2.5 pr-4 text-right">
                                                Check-ins
                                            </th>
                                            <th scope="col" className="pb-2.5 pr-4 text-right">
                                                Verified Turnout
                                            </th>
                                            <th scope="col" className="pb-2.5 pr-4 text-right">
                                                Avg. Confidence
                                            </th>
                                            <th scope="col" className="pb-2.5 text-right print:hidden">
                                                Report
                                            </th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-gray-100">
                                        {directoryRows.map((row) => {
                                            const attended = safeNumber(row.attended);
                                            const successful = safeNumber(row.successful);
                                            const passPct =
                                                row.pass_rate !== undefined
                                                    ? safeNumber(row.pass_rate)
                                                    : attended > 0
                                                      ? Math.round((successful / attended) * 100)
                                                      : 0;
                                            const hasLogs = attended > 0;

                                            return (
                                                <tr
                                                    key={row.id}
                                                    className="transition-colors hover:bg-[#F5F6FA]/80"
                                                >
                                                    <td className="max-w-[300px] py-2.5 pr-4">
                                                        <Link
                                                            href={`/admin/analytics/events/${row.id}`}
                                                            title={row.event}
                                                            className="block truncate rounded-sm text-xs font-extrabold text-[#1B1F5C] hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                        >
                                                            {row.event}
                                                        </Link>
                                                        {row.location && (
                                                            <span className="mt-0.5 flex items-center gap-1 truncate text-[11px] font-medium text-gray-500">
                                                                <MapPin
                                                                    className="h-3 w-3 shrink-0 text-[#F5A623]"
                                                                    aria-hidden="true"
                                                                />
                                                                <span className="truncate">
                                                                    {row.location}
                                                                </span>
                                                            </span>
                                                        )}
                                                    </td>
                                                    <td className="whitespace-nowrap py-2.5 pr-4 font-medium text-gray-600">
                                                        <div className="flex items-center gap-1.5">
                                                            <span>{row.date}</span>
                                                            {row.total_days &&
                                                                row.total_days > 1 && (
                                                                    <span className="rounded-md border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 px-1.5 py-0.5 text-[10px] font-bold text-[#1B1F5C]">
                                                                        {row.total_days}d
                                                                    </span>
                                                                )}
                                                        </div>
                                                    </td>
                                                    <td className="py-2.5 pr-4 text-right font-mono font-bold text-gray-900">
                                                        {fmt.format(attended)}
                                                    </td>
                                                    <td className="py-2.5 pr-4 text-right">
                                                        {hasLogs ? (
                                                            <span className="inline-flex items-center gap-1 rounded-full border border-emerald-200 bg-emerald-50 px-2.5 py-0.5 text-[11px] font-bold text-emerald-800">
                                                                <CheckCircle2
                                                                    className="h-3 w-3"
                                                                    aria-hidden="true"
                                                                />
                                                                <span>
                                                                    {fmt.format(successful)} (
                                                                    {passPct}%)
                                                                </span>
                                                            </span>
                                                        ) : (
                                                            <span className="inline-flex items-center rounded-full border border-gray-200 bg-gray-100 px-2.5 py-0.5 text-[11px] font-bold text-gray-600">
                                                                {row.is_upcoming
                                                                    ? 'Upcoming'
                                                                    : 'No Logs'}
                                                            </span>
                                                        )}
                                                    </td>
                                                    <td className="py-2.5 pr-4 text-right">
                                                        <ConfidencePill
                                                            score={safeNumber(row.avg_confidence)}
                                                            hasLogs={hasLogs}
                                                        />
                                                    </td>
                                                    <td className="py-2.5 text-right print:hidden">
                                                        <Link
                                                            href={`/admin/analytics/events/${row.id}`}
                                                            aria-label={`Inspect analytics for ${row.event}`}
                                                            className="inline-flex min-h-[34px] items-center gap-1 rounded-xl border border-gray-200 bg-white px-2.5 py-1 text-xs font-bold text-[#1B1F5C] transition-colors hover:border-gray-300 hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                        >
                                                            <span>Details</span>
                                                            <ChevronRight
                                                                className="h-3.5 w-3.5 text-[#F5A623]"
                                                                aria-hidden="true"
                                                            />
                                                        </Link>
                                                    </td>
                                                </tr>
                                            );
                                        })}
                                    </tbody>
                                </table>
                            </div>

                            {/* Accessible Pagination Footer */}
                            {directoryLinks.length > 3 && (
                                <nav
                                    aria-label="Event directory pagination"
                                    className="flex flex-wrap items-center justify-between gap-3 border-t border-gray-100 pt-3 print:hidden"
                                >
                                    <p className="text-xs font-medium text-gray-600">
                                        {eventDirectory?.from && eventDirectory?.to
                                            ? `Showing ${fmt.format(eventDirectory.from)}–${fmt.format(eventDirectory.to)} of ${fmt.format(directoryTotal)} events`
                                            : `${fmt.format(directoryTotal)} total events`}
                                    </p>
                                    <div className="flex flex-wrap items-center gap-1.5">
                                        {directoryLinks.map((link, idx) => {
                                            const targetPage = extractPageNumber(link.url);
                                            const isDisabled = !link.url || link.active || isSyncing;
                                            const formatted = formatPaginationLabel(link.label);

                                            return (
                                                <button
                                                    key={idx}
                                                    type="button"
                                                    disabled={isDisabled}
                                                    onClick={() => handlePageChange(targetPage)}
                                                    aria-label={formatted.ariaLabel}
                                                    aria-current={link.active ? 'page' : undefined}
                                                    className={[
                                                        'inline-flex min-h-[38px] min-w-[38px] items-center justify-center gap-1 rounded-xl px-3 py-1.5 text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]',
                                                        link.active
                                                            ? 'bg-[#1B1F5C] text-white shadow-2xs'
                                                            : link.url
                                                              ? 'border border-gray-200 bg-white text-gray-700 hover:border-gray-300 hover:bg-gray-50'
                                                              : 'cursor-not-allowed border border-gray-100 bg-gray-50/60 text-gray-300',
                                                    ].join(' ')}
                                                >
                                                    {formatted.type === 'prev' && (
                                                        <ChevronLeft
                                                            className="h-3.5 w-3.5"
                                                            aria-hidden="true"
                                                        />
                                                    )}
                                                    <span>{formatted.text}</span>
                                                    {formatted.type === 'next' && (
                                                        <ChevronRight
                                                            className="h-3.5 w-3.5"
                                                            aria-hidden="true"
                                                        />
                                                    )}
                                                </button>
                                            );
                                        })}
                                    </div>
                                </nav>
                            )}
                        </>
                    )}
                </section>
            </div>

            {/* Subtle Back-to-Top Floating Button */}
            {showBackToTop && (
                <button
                    type="button"
                    onClick={() =>
                        window.scrollTo({
                            top: 0,
                            behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches
                                ? 'auto'
                                : 'smooth',
                        })
                    }
                    aria-label="Scroll back to top"
                    className="fixed bottom-5 right-5 z-30 inline-flex h-11 w-11 items-center justify-center rounded-xl border border-gray-200 bg-white text-[#1B1F5C] shadow-xs transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] print:hidden"
                >
                    <ArrowUp className="h-4 w-4 text-[#F5A623]" aria-hidden="true" />
                </button>
            )}
        </>
    );
}

function KpiCard({
    label,
    value,
    sub,
    subColor = 'text-gray-600',
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
        <div className="flex flex-col justify-between rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs">
            <div className="flex items-center justify-between gap-2">
                <span className="text-[11px] font-extrabold uppercase tracking-wider text-gray-500">
                    {label}
                </span>
                <div className={`rounded-xl border p-2 ${iconBg}`}>{icon}</div>
            </div>
            <div className="mt-2.5">
                <p className="font-mono text-2xl font-black tracking-tight text-gray-900">
                    {value}
                </p>
                <div className="mt-1 flex flex-wrap items-center justify-between gap-1.5">
                    <span className={`text-[11px] font-bold ${subColor}`}>{sub}</span>
                    {delta}
                </div>
            </div>
        </div>
    );
}

AnalyticsIndex.layout = (page: React.ReactNode) => (
    <AdminLayout title="System Analytics">{page}</AdminLayout>
);