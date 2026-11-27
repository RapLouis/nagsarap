import React, { useEffect, useMemo, useState } from 'react';
import { Head, Link } from '@inertiajs/react';
import AdminLayout from '@/layouts/admin-layout';
import {
    Filter,
    Calendar,
    CheckCircle2,
    Clock,
    FileCheck,
    Plus,
    ArrowUpRight,
    TrendingUp,
    ShieldAlert,
    Activity,
    Check,
    Radio,
    ShieldCheck,
    CalendarX,
    RotateCcw,
    WifiOff,
    MapPin,
} from 'lucide-react';

type SectionCounts = Record<string, number>;
type DegreeGroup = {
    total: number;
    sections: SectionCounts;
};
type DegreesMap = Record<string, DegreeGroup>;

type OngoingEvent = {
    event_id: number;
    title: string;
    location?: string | null;
    start_time?: string;
    attendances_count?: number;
    is_geofenced?: boolean;
    radius_meters?: number | null;
    avg_confidence?: number;
};

type ActivityItem = {
    text: string;
    time: string;
};

type ClearanceRequest = {
    id: number;
    student_name: string;
    student_number: string;
    program: string;
    submitted_at: string;
};

type Props = {
    totalStudents?: number;
    degrees?: DegreesMap;
    activeEventsCount?: number;
    todayAttendanceRate?: number;
    pendingClearancesCount?: number;
    ongoingEvents?: OngoingEvent[];
    recentActivities?: ActivityItem[];
    pendingClearancesList?: ClearanceRequest[];
};

const ALL = 'all';
const fmt = new Intl.NumberFormat('en-PH');

export default function AdminDashboard({
    totalStudents = 0,
    degrees = {},
    activeEventsCount = 0,
    todayAttendanceRate = 0,
    pendingClearancesCount = 0,
    ongoingEvents = [],
    recentActivities = [],
    pendingClearancesList = [],
}: Props) {
    const [selectedDegree, setSelectedDegree] = useState<string>(ALL);
    const [selectedSection, setSelectedSection] = useState<string>(ALL);
    const [isOnline, setIsOnline] = useState<boolean>(
        typeof navigator !== 'undefined' ? navigator.onLine : true
    );

    useEffect(() => {
        const handleOnline = () => setIsOnline(true);
        const handleOffline = () => setIsOnline(false);

        window.addEventListener('online', handleOnline);
        window.addEventListener('offline', handleOffline);

        return () => {
            window.removeEventListener('online', handleOnline);
            window.removeEventListener('offline', handleOffline);
        };
    }, []);

    const availableDegrees = useMemo(() => Object.keys(degrees).sort(), [degrees]);

    const availableSections = useMemo(() => {
        const sections = new Set<string>();
        const degreeSource =
            selectedDegree === ALL
                ? Object.values(degrees)
                : degrees[selectedDegree]
                  ? [degrees[selectedDegree]]
                  : [];

        degreeSource.forEach((deg) => {
            Object.keys(deg.sections).forEach((sec) => sections.add(sec));
        });

        return Array.from(sections).sort((a, b) =>
            a.localeCompare(b, undefined, { numeric: true })
        );
    }, [degrees, selectedDegree]);

    const filteredCount = useMemo(() => {
        if (selectedDegree === ALL && selectedSection === ALL) return totalStudents;

        const degreeGroups =
            selectedDegree === ALL
                ? Object.values(degrees)
                : degrees[selectedDegree]
                  ? [degrees[selectedDegree]]
                  : [];

        if (selectedSection === ALL) {
            return degreeGroups.reduce((sum, deg) => sum + deg.total, 0);
        }

        let sum = 0;
        degreeGroups.forEach((deg) => {
            sum += deg.sections[selectedSection] ?? 0;
        });

        return sum;
    }, [degrees, totalStudents, selectedDegree, selectedSection]);

    const isFiltered = selectedDegree !== ALL || selectedSection !== ALL;

    const handleDegreeChange = (value: string) => {
        setSelectedDegree(value);
        setSelectedSection(ALL);
    };

    const handleResetFilters = () => {
        setSelectedDegree(ALL);
        setSelectedSection(ALL);
    };

    return (
        <>
            <Head title="Executive Command Dashboard | 4ttnd Attendance System" />

            <div className="w-full space-y-3.5 bg-[#F5F6FA] font-sans text-gray-900 antialiased">
                {/* OFFLINE CONNECTIVITY NOTICE */}
                {!isOnline && (
                    <div
                        role="alert"
                        className="flex items-center justify-between gap-3 rounded-2xl border border-amber-300 bg-amber-50 px-4 py-2.5 text-xs font-semibold text-amber-900 shadow-2xs"
                    >
                        <div className="flex items-center gap-2">
                            <WifiOff className="h-4 w-4 shrink-0 text-amber-700" aria-hidden="true" />
                            <span>
                                Connection offline — displaying last synced data snapshot. Live
                                updates will resume automatically when reconnected.
                            </span>
                        </div>
                    </div>
                )}

                {/* COMPACT EXECUTIVE HEADER & PRIMARY CTA */}
                <header className="flex flex-col gap-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs sm:flex-row sm:items-center sm:justify-between">
                    <div className="min-w-0 space-y-1">
                        <div className="flex flex-wrap items-center gap-2">
                            <span className="inline-flex items-center gap-1.5 rounded-full border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 px-2.5 py-0.5 text-[11px] font-bold text-[#1B1F5C]">
                                <Activity
                                    className="h-3 w-3 animate-pulse text-[#F5A623] motion-reduce:animate-none"
                                    aria-hidden="true"
                                />
                                <span>CCIS Executive Command</span>
                            </span>
                        </div>
                        <h1 className="text-lg font-black tracking-tight text-[#1B1F5C] sm:text-xl">
                            Executive Dashboard
                        </h1>
                        <p className="text-xs font-medium text-gray-600">
                            Real-time institutional metrics, live biometric streams, and clearance
                            sign-offs
                        </p>
                    </div>

                    <div className="flex shrink-0 items-center gap-2.5">
                        <Link
                            href="/admin/events"
                            className="inline-flex min-h-[44px] items-center justify-center gap-2 rounded-xl bg-[#1B1F5C] px-4 py-2.5 text-xs font-bold text-white shadow-2xs transition-colors hover:bg-[#131644] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] active:scale-[0.99] motion-reduce:transform-none"
                        >
                            <Plus className="h-4 w-4 text-[#F5A623]" aria-hidden="true" />
                            <span>Create Event Session</span>
                        </Link>
                    </div>
                </header>

                {/* TIER 1: EXECUTIVE KPI RIBBON (ABOVE THE FOLD) */}
                <section
                    aria-label="Executive Key Performance Indicators"
                    className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4"
                >
                    {/* KPI 1: Attendance Rate */}
                    <div className="flex flex-col justify-between rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs">
                        <div>
                            <div className="flex items-center justify-between gap-2">
                                <span className="text-[11px] font-extrabold uppercase tracking-wider text-gray-500">
                                    Today's Attendance
                                </span>
                                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-emerald-200/80 bg-emerald-50 text-emerald-700">
                                    <TrendingUp className="h-4 w-4" aria-hidden="true" />
                                </div>
                            </div>
                            <div className="mt-2.5">
                                <div className="flex flex-wrap items-baseline gap-2">
                                    <p className="font-mono text-2xl font-black tracking-tight text-gray-900">
                                        {todayAttendanceRate}%
                                    </p>
                                    <span className="rounded-full border border-emerald-200/80 bg-emerald-50 px-2 py-0.5 text-[10px] font-bold text-emerald-800">
                                        Live Data
                                    </span>
                                </div>
                                <p className="mt-1 text-[11px] font-medium text-gray-600">
                                    Real-time campus check-in rate
                                </p>
                            </div>
                        </div>
                        <Link
                            href="/admin/analytics"
                            className="mt-3 flex min-h-[38px] items-center justify-between border-t border-gray-100 pt-2 text-xs font-bold text-[#1B1F5C] transition-colors hover:underline focus-visible:rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                        >
                            <span>Deep Dive Analytics</span>
                            <ArrowUpRight className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                        </Link>
                    </div>

                    {/* KPI 2: Active / Upcoming Events */}
                    <div className="flex flex-col justify-between rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs">
                        <div>
                            <div className="flex items-center justify-between gap-2">
                                <span className="text-[11px] font-extrabold uppercase tracking-wider text-gray-500">
                                    Scheduled Events
                                </span>
                                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-amber-200/80 bg-amber-50 text-amber-800">
                                    <Calendar className="h-4 w-4" aria-hidden="true" />
                                </div>
                            </div>
                            <div className="mt-2.5">
                                <div className="flex flex-wrap items-baseline gap-2">
                                    <p className="font-mono text-2xl font-black tracking-tight text-gray-900">
                                        {fmt.format(activeEventsCount)}
                                    </p>
                                    <span className="rounded-full border border-amber-200/80 bg-amber-50 px-2 py-0.5 text-[10px] font-bold text-amber-800">
                                        This Week
                                    </span>
                                </div>
                                <p className="mt-1 text-[11px] font-medium text-gray-600">
                                    Active windows & sessions
                                </p>
                            </div>
                        </div>
                        <Link
                            href="/admin/events"
                            className="mt-3 flex min-h-[38px] items-center justify-between border-t border-gray-100 pt-2 text-xs font-bold text-[#1B1F5C] transition-colors hover:underline focus-visible:rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                        >
                            <span>Manage Schedule</span>
                            <ArrowUpRight className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                        </Link>
                    </div>

                    {/* KPI 3: Pending Clearances */}
                    <div className="flex flex-col justify-between rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs">
                        <div>
                            <div className="flex items-center justify-between gap-2">
                                <span className="text-[11px] font-extrabold uppercase tracking-wider text-gray-500">
                                    Pending Sanctions
                                </span>
                                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 text-[#1B1F5C]">
                                    <FileCheck className="h-4 w-4" aria-hidden="true" />
                                </div>
                            </div>
                            <div className="mt-2.5">
                                <div className="flex flex-wrap items-baseline gap-2">
                                    <p className="font-mono text-2xl font-black tracking-tight text-gray-900">
                                        {fmt.format(pendingClearancesCount)}
                                    </p>
                                    {pendingClearancesCount > 0 ? (
                                        <span className="inline-flex items-center gap-1 rounded-full border border-rose-200/80 bg-rose-50 px-2 py-0.5 text-[10px] font-bold text-rose-800">
                                            <ShieldAlert className="h-3 w-3" aria-hidden="true" />
                                            <span>Action Required</span>
                                        </span>
                                    ) : (
                                        <span className="inline-flex items-center gap-1 rounded-full border border-gray-200 bg-gray-100 px-2 py-0.5 text-[10px] font-bold text-gray-600">
                                            <span>All Clear</span>
                                        </span>
                                    )}
                                </div>
                                <p className="mt-1 text-[11px] font-medium text-gray-600">
                                    Awaiting executive sign-off
                                </p>
                            </div>
                        </div>
                        <Link
                            href="/admin/sanctions"
                            className="mt-3 flex min-h-[38px] items-center justify-between border-t border-gray-100 pt-2 text-xs font-bold text-[#1B1F5C] transition-colors hover:underline focus-visible:rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                        >
                            <span>Review Queue</span>
                            <ArrowUpRight className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                        </Link>
                    </div>

                    {/* KPI 4: Interactive Student Census Filter Widget */}
                    <div className="flex flex-col justify-between rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs">
                        <div>
                            <div className="mb-2 flex items-center justify-between gap-2">
                                <span className="text-[11px] font-extrabold uppercase tracking-wider text-gray-500">
                                    Student Census
                                </span>
                                {isFiltered ? (
                                    <button
                                        type="button"
                                        onClick={handleResetFilters}
                                        className="inline-flex min-h-[26px] items-center gap-1 rounded-md border border-gray-200 bg-[#F5F6FA] px-2 py-0.5 text-[11px] font-bold text-[#1B1F5C] transition-colors hover:bg-gray-200/70 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                        aria-label="Reset program and section filters"
                                    >
                                        <RotateCcw
                                            className="h-3 w-3 text-[#F5A623]"
                                            aria-hidden="true"
                                        />
                                        <span>Reset</span>
                                    </button>
                                ) : (
                                    <div className="flex h-6 w-6 items-center justify-center rounded-lg border border-amber-200/70 bg-amber-50">
                                        <Filter
                                            className="h-3.5 w-3.5 text-[#F5A623]"
                                            aria-hidden="true"
                                        />
                                    </div>
                                )}
                            </div>

                            <div className="grid grid-cols-2 gap-2">
                                <div>
                                    <label htmlFor="census-program-select" className="sr-only">
                                        Filter by Program
                                    </label>
                                    <select
                                        id="census-program-select"
                                        aria-label="Filter by Program"
                                        value={selectedDegree}
                                        onChange={(e) => handleDegreeChange(e.target.value)}
                                        className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white px-2.5 py-1.5 text-xs font-bold text-[#1B1F5C] transition-colors hover:border-gray-400 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    >
                                        <option value={ALL}>All Programs</option>
                                        {availableDegrees.map((deg) => (
                                            <option key={deg} value={deg}>
                                                {deg}
                                            </option>
                                        ))}
                                    </select>
                                </div>

                                <div>
                                    <label htmlFor="census-section-select" className="sr-only">
                                        Filter by Section
                                    </label>
                                    <select
                                        id="census-section-select"
                                        aria-label="Filter by Section"
                                        value={selectedSection}
                                        onChange={(e) => setSelectedSection(e.target.value)}
                                        className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white px-2.5 py-1.5 text-xs font-bold text-[#1B1F5C] transition-colors hover:border-gray-400 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    >
                                        <option value={ALL}>All Sections</option>
                                        {availableSections.map((sec) => (
                                            <option key={sec} value={sec}>
                                                {sec}
                                            </option>
                                        ))}
                                    </select>
                                </div>
                            </div>
                        </div>

                        <div
                            role="status"
                            aria-live="polite"
                            className="mt-3 flex min-h-[38px] items-baseline justify-between border-t border-gray-100 pt-2"
                        >
                            <span className="text-[11px] font-extrabold uppercase tracking-wider text-gray-500">
                                {isFiltered ? 'Filtered Cohort' : 'Total Enrolled'}
                            </span>
                            <p className="font-mono text-xl font-black text-[#1B1F5C]">
                                {fmt.format(filteredCount)}
                            </p>
                        </div>
                    </div>
                </section>

                {/* TIER 2: BENTO ASYMMETRIC OPERATIONAL WORKSPACE (8 / 4 SPLIT) */}
                <div className="grid grid-cols-1 items-start gap-3.5 lg:grid-cols-12">
                    {/* LEFT PANEL (8 Cols): Multi-Stream Live Operations */}
                    <section
                        aria-labelledby="live-operations-heading"
                        className="min-w-0 space-y-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs lg:col-span-8"
                    >
                        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-gray-100 pb-3">
                            <div>
                                <h2
                                    id="live-operations-heading"
                                    className="text-sm font-extrabold tracking-tight text-[#1B1F5C] sm:text-base"
                                >
                                    Live Operations
                                </h2>
                                <p className="text-xs font-medium text-gray-600">
                                    Real-time telemetry for active campus check-in sessions today
                                </p>
                            </div>
                            <div className="flex items-center gap-2">
                                <span
                                    role="status"
                                    className="inline-flex items-center gap-1.5 rounded-full border border-emerald-200 bg-emerald-50 px-2.5 py-1 text-[11px] font-extrabold text-emerald-800"
                                >
                                    <Radio
                                        className="h-3 w-3 animate-pulse text-emerald-600 motion-reduce:animate-none"
                                        aria-hidden="true"
                                    />
                                    <span>
                                        {ongoingEvents.length} Active Stream
                                        {ongoingEvents.length === 1 ? '' : 's'}
                                    </span>
                                </span>
                                {ongoingEvents.length > 3 && (
                                    <Link
                                        href="/admin/events"
                                        className="inline-flex min-h-[38px] items-center gap-1 rounded-xl border border-gray-200 bg-white px-2.5 py-1 text-xs font-bold text-[#1B1F5C] transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    >
                                        <span>View All ({ongoingEvents.length})</span>
                                        <ArrowUpRight
                                            className="h-3.5 w-3.5 text-[#F5A623]"
                                            aria-hidden="true"
                                        />
                                    </Link>
                                )}
                            </div>
                        </div>

                        {ongoingEvents.length > 0 ? (
                            <div className="space-y-2.5">
                                {ongoingEvents.slice(0, 3).map((evt) => (
                                    <article
                                        key={evt.event_id}
                                        className="space-y-2.5 rounded-xl border border-gray-200/80 bg-[#F5F6FA]/70 p-3.5 transition-colors hover:border-[#1B1F5C]/30"
                                    >
                                        <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-center">
                                            <div className="min-w-0">
                                                <div className="flex flex-wrap items-center gap-1.5">
                                                    <span className="rounded-md bg-[#1B1F5C] px-2 py-0.5 text-[10px] font-extrabold uppercase tracking-wider text-white">
                                                        Active Session
                                                    </span>
                                                    {evt.is_geofenced && (
                                                        <span className="inline-flex items-center gap-1 rounded-md border border-emerald-200/80 bg-emerald-50 px-2 py-0.5 text-[10px] font-bold text-emerald-800">
                                                            <ShieldCheck
                                                                className="h-3 w-3"
                                                                aria-hidden="true"
                                                            />
                                                            <span>
                                                                Geofence Active
                                                                {evt.radius_meters != null
                                                                    ? ` (${evt.radius_meters}m)`
                                                                    : ''}
                                                            </span>
                                                        </span>
                                                    )}
                                                </div>
                                                <h3 className="mt-1.5 truncate text-sm font-black text-[#1B1F5C]">
                                                    {evt.title}
                                                </h3>
                                                <p className="mt-0.5 flex flex-wrap items-center gap-1.5 text-[11px] text-gray-600">
                                                    <Clock
                                                        className="h-3 w-3 shrink-0 text-gray-400"
                                                        aria-hidden="true"
                                                    />
                                                    <span>Started: {evt.start_time || 'TBA'}</span>
                                                    <span aria-hidden="true">•</span>
                                                    <span className="inline-flex items-center gap-1 truncate font-semibold text-gray-700">
                                                        <MapPin
                                                            className="h-3 w-3 shrink-0 text-[#F5A623]"
                                                            aria-hidden="true"
                                                        />
                                                        <span className="truncate">
                                                            {evt.location || 'Location TBA'}
                                                        </span>
                                                    </span>
                                                </p>
                                            </div>

                                            <div className="flex shrink-0 items-center gap-2">
                                                <div className="min-w-[82px] rounded-xl border border-gray-200/80 bg-white px-3 py-1.5 text-center shadow-2xs">
                                                    <span className="block font-mono text-base font-black leading-tight text-[#1B1F5C]">
                                                        {fmt.format(evt.attendances_count ?? 0)}
                                                    </span>
                                                    <span className="text-[9px] font-extrabold uppercase tracking-wider text-gray-500">
                                                        Checked In
                                                    </span>
                                                </div>
                                                <div className="min-w-[82px] rounded-xl border border-gray-200/80 bg-white px-3 py-1.5 text-center shadow-2xs">
                                                    <span className="block font-mono text-base font-black leading-tight text-emerald-700">
                                                        {evt.avg_confidence ?? 0}%
                                                    </span>
                                                    <span className="text-[9px] font-extrabold uppercase tracking-wider text-gray-500">
                                                        Confidence
                                                    </span>
                                                </div>
                                            </div>
                                        </div>

                                        <div className="flex flex-wrap items-center justify-between gap-2 border-t border-gray-200/80 pt-2 text-[11px]">
                                            <span className="font-medium text-gray-600">
                                                Biometric & facial recognition streams nominal.
                                            </span>
                                            <Link
                                                href="/admin/events"
                                                aria-label={`Manage windows for ${evt.title}`}
                                                className="inline-flex min-h-[30px] items-center gap-1 rounded-md px-1.5 font-bold text-[#1B1F5C] hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                            >
                                                <span>Manage Windows</span>
                                                <ArrowUpRight
                                                    className="h-3.5 w-3.5 text-[#F5A623]"
                                                    aria-hidden="true"
                                                />
                                            </Link>
                                        </div>
                                    </article>
                                ))}
                            </div>
                        ) : (
                            <div className="flex min-h-[210px] flex-col items-center justify-center space-y-2.5 rounded-xl border border-dashed border-gray-200 bg-[#F5F6FA]/70 p-6 text-center">
                                <div className="flex h-10 w-10 items-center justify-center rounded-xl border border-[#1B1F5C]/15 bg-white text-[#1B1F5C] shadow-2xs">
                                    <CalendarX className="h-5 w-5" aria-hidden="true" />
                                </div>
                                <p className="text-sm font-extrabold text-[#1B1F5C]">
                                    No active events running right now
                                </p>
                                <p className="max-w-sm text-xs font-medium text-gray-600">
                                    Scheduled events automatically initialize biometric verification
                                    streams when their check-in window opens.
                                </p>
                                <div className="pt-1">
                                    <Link
                                        href="/admin/events"
                                        className="inline-flex min-h-[38px] items-center justify-center gap-1.5 rounded-xl border border-gray-300 bg-white px-3.5 py-1.5 text-xs font-bold text-[#1B1F5C] transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    >
                                        <span>View Event Schedule</span>
                                        <ArrowUpRight
                                            className="h-3.5 w-3.5 text-[#F5A623]"
                                            aria-hidden="true"
                                        />
                                    </Link>
                                </div>
                            </div>
                        )}
                    </section>

                    {/* RIGHT PANEL (4 Cols): Actionable Clearance Triage Queue */}
                    <aside
                        aria-labelledby="sanctions-queue-heading"
                        className="min-w-0 space-y-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs lg:col-span-4"
                    >
                        <div className="flex items-center justify-between gap-2 border-b border-gray-100 pb-3">
                            <div>
                                <h2
                                    id="sanctions-queue-heading"
                                    className="text-sm font-extrabold tracking-tight text-[#1B1F5C] sm:text-base"
                                >
                                    Sanctions Queue
                                </h2>
                                <p className="text-xs font-medium text-gray-600">
                                    Actionable student clearance requests
                                </p>
                            </div>
                            <span
                                role="status"
                                className="shrink-0 rounded-full border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 px-2.5 py-1 font-mono text-xs font-extrabold text-[#1B1F5C]"
                            >
                                {fmt.format(pendingClearancesCount)} Pending
                            </span>
                        </div>

                        <div
                            className="max-h-[360px] space-y-2.5 overflow-y-auto pr-0.5"
                            aria-live="polite"
                        >
                            {pendingClearancesList.length > 0 ? (
                                pendingClearancesList.slice(0, 4).map((req) => (
                                    <article
                                        key={req.id}
                                        className="space-y-2 rounded-xl border border-gray-200/80 bg-[#F5F6FA]/70 p-3"
                                    >
                                        <div className="flex items-start justify-between gap-2">
                                            <div className="min-w-0">
                                                <p className="truncate text-xs font-extrabold text-gray-900">
                                                    {req.student_name}
                                                </p>
                                                <p className="truncate font-mono text-[11px] font-semibold text-gray-600">
                                                    {req.student_number} • {req.program}
                                                </p>
                                            </div>
                                            <span className="shrink-0 font-mono text-[10px] text-gray-500">
                                                {req.submitted_at}
                                            </span>
                                        </div>
                                        <div className="border-t border-gray-200/70 pt-2">
                                            <Link
                                                href="/admin/sanctions"
                                                aria-label={`Review clearance request for ${req.student_name}`}
                                                className="inline-flex min-h-[38px] w-full items-center justify-center rounded-xl bg-[#1B1F5C] px-3 py-1.5 text-xs font-bold text-white transition-colors hover:bg-[#131644] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                            >
                                                Review Request
                                            </Link>
                                        </div>
                                    </article>
                                ))
                            ) : (
                                <div className="flex min-h-[168px] flex-col items-center justify-center space-y-1.5 rounded-xl border border-dashed border-gray-200 bg-[#F5F6FA]/70 p-6 text-center">
                                    <CheckCircle2
                                        className="h-7 w-7 text-emerald-600"
                                        aria-hidden="true"
                                    />
                                    <p className="text-xs font-extrabold text-[#1B1F5C]">
                                        All Sanctions Processed
                                    </p>
                                    <p className="text-[11px] font-medium text-gray-600">
                                        No pending clearance requests require attention.
                                    </p>
                                </div>
                            )}
                        </div>

                        <Link
                            href="/admin/sanctions"
                            className="flex min-h-[38px] items-center justify-center gap-1 border-t border-gray-100 pt-2 text-xs font-bold text-[#1B1F5C] transition-colors hover:underline focus-visible:rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                        >
                            <span>View All Sanctions Records</span>
                            <ArrowUpRight className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                        </Link>
                    </aside>
                </div>

                {/* TIER 3: AUDIT STREAM & SYSTEM ACTIVITY FOOTER */}
                <section
                    aria-labelledby="audit-stream-heading"
                    className="min-w-0 space-y-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs"
                >
                    <div className="flex flex-wrap items-center justify-between gap-2 border-b border-gray-100 pb-2.5">
                        <div className="flex items-center gap-2">
                            <Activity className="h-4 w-4 text-[#F5A623]" aria-hidden="true" />
                            <h2
                                id="audit-stream-heading"
                                className="text-sm font-extrabold tracking-tight text-[#1B1F5C] sm:text-base"
                            >
                                Security & System Audit Stream
                            </h2>
                        </div>
                        <span className="text-xs font-medium text-gray-500">
                            Recent verification & administrative logs
                        </span>
                    </div>

                    {recentActivities.length > 0 ? (
                        <ul className="grid grid-cols-1 gap-2.5 pt-0.5 md:grid-cols-2 lg:grid-cols-3">
                            {recentActivities.slice(0, 6).map((act, i) => (
                                <li
                                    key={`${act.time}-${i}`}
                                    className="flex items-start gap-2.5 rounded-xl border border-gray-200/80 bg-[#F5F6FA]/70 p-2.5"
                                >
                                    <div className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-lg border border-emerald-200/80 bg-emerald-50 text-emerald-700">
                                        <Check className="h-3.5 w-3.5" aria-hidden="true" />
                                    </div>
                                    <div className="min-w-0 flex-1">
                                        <p className="text-xs font-bold leading-snug text-gray-900">
                                            {act.text}
                                        </p>
                                        <span className="mt-0.5 block font-mono text-[10px] text-gray-500">
                                            {act.time}
                                        </span>
                                    </div>
                                </li>
                            ))}
                        </ul>
                    ) : (
                        <div className="rounded-xl border border-dashed border-gray-200 bg-[#F5F6FA]/70 py-5 text-center text-xs font-medium text-gray-500">
                            No recent system activity logged.
                        </div>
                    )}
                </section>
            </div>
        </>
    );
}

AdminDashboard.layout = (page: React.ReactNode) => (
    <AdminLayout title="Executive Dashboard">{page}</AdminLayout>
);