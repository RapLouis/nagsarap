import React, { useMemo, useState } from 'react';
import { Head, Link } from '@inertiajs/react';
import AdminLayout from '@/layouts/admin-layout';
import { 
    Users, 
    Filter, 
    Calendar, 
    CheckCircle2, 
    Clock, 
    FileCheck, 
    Plus, 
    ArrowUpRight,
    TrendingUp
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
};

type ActivityItem = {
    text: string;
    time: string;
};

type Props = {
    totalStudents?: number;
    degrees?: DegreesMap;
    activeEventsCount?: number;
    todayAttendanceRate?: number;
    pendingClearancesCount?: number;
    ongoingEvent?: OngoingEvent | null;
    recentActivities?: ActivityItem[];
};

const ALL = 'all';

export default function AdminDashboard({ 
    totalStudents = 0, 
    degrees = {},
    activeEventsCount = 0,
    todayAttendanceRate = 0,
    pendingClearancesCount = 0,
    ongoingEvent = null,
    recentActivities = []
}: Props) {
    const [selectedDegree, setSelectedDegree] = useState<string>(ALL);
    const [selectedSection, setSelectedSection] = useState<string>(ALL);

    const availableDegrees = useMemo(() => Object.keys(degrees).sort(), [degrees]);

    const availableSections = useMemo(() => {
        const sections = new Set<string>();
        const degreeSource = selectedDegree === ALL
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

        const degreeGroups = selectedDegree === ALL
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

    const handleDegreeChange = (value: string) => {
        setSelectedDegree(value);
        setSelectedSection(ALL);
    };

    return (
        <>
            <Head title="Admin Dashboard" />

            <div className="space-y-6 p-6">
                {/* PAGE HEADER & QUICK ACTIONS */}
                <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                    <div>
                        <h1 className="text-2xl font-bold tracking-tight text-[#1B1F5C]">Dashboard Overview</h1>
                        <p className="text-xs text-gray-500">
                            Welcome back. Here is what is happening across CCIS today.
                        </p>
                    </div>
                    <div className="flex items-center gap-2">
                        <Link
                            href="/admin/events/create"
                            className="inline-flex items-center gap-1.5 rounded-lg bg-[#1B1F5C] px-3.5 py-2 text-xs font-semibold text-white shadow-sm hover:bg-[#141747] transition-colors"
                        >
                            <Plus className="h-4 w-4" />
                            Create Event
                        </Link>
                    </div>
                </div>

                {/* METRICS GRID */}
                <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-4">
                    {/* CARD 1: Interactive Student Filter Counter */}
                    <div className="rounded-2xl border border-gray-100 bg-white p-5 shadow-sm">
                        <div className="flex items-start justify-between gap-3">
                            <div className="flex-1 space-y-2">
                                <div className="flex items-center gap-1.5 text-[11px] font-semibold text-gray-400">
                                    <Filter className="h-3.5 w-3.5 text-gray-400" />
                                    <span>Registered Students Filter</span>
                                </div>
                                <div className="space-y-1.5">
                                    <select
                                        value={selectedDegree}
                                        onChange={(e) => handleDegreeChange(e.target.value)}
                                        className="w-full rounded-md border-gray-200 bg-gray-50/50 py-1 text-[11px] font-semibold text-[#1B1F5C] focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                    >
                                        <option value={ALL}>All Programs</option>
                                        {availableDegrees.map((deg) => (
                                            <option key={deg} value={deg}>{deg}</option>
                                        ))}
                                    </select>

                                    <select
                                        value={selectedSection}
                                        onChange={(e) => setSelectedSection(e.target.value)}
                                        className="w-full rounded-md border-gray-200 bg-gray-50/50 py-1 text-[11px] font-semibold text-[#1B1F5C] focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                    >
                                        <option value={ALL}>All Sections</option>
                                        {availableSections.map((sec) => (
                                            <option key={sec} value={sec}>{sec}</option>
                                        ))}
                                    </select>
                                </div>
                            </div>
                            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-[#1B1F5C]/10 text-[#1B1F5C]">
                                <Users className="h-5 w-5" />
                            </div>
                        </div>
                        <div className="mt-4 border-t border-gray-100 pt-3">
                            <p className="text-[10px] font-medium text-gray-400 uppercase tracking-wider">Total Count</p>
                            <h3 className="text-2xl font-bold text-[#1B1F5C]">
                                {filteredCount.toLocaleString()}
                            </h3>
                        </div>
                    </div>

                    {/* CARD 2: Active Events */}
                    <div className="flex flex-col justify-between rounded-2xl border border-gray-100 bg-white p-5 shadow-sm">
                        <div className="flex items-center justify-between">
                            <span className="text-xs font-semibold text-gray-400">Active / Upcoming Events</span>
                            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-amber-500/10 text-amber-600">
                                <Calendar className="h-5 w-5" />
                            </div>
                        </div>
                        <div>
                            <h3 className="text-3xl font-bold text-[#1B1F5C]">{activeEventsCount}</h3>
                            <p className="mt-1 text-xs text-gray-500">Scheduled for this week</p>
                        </div>
                        <Link href="/admin/events" className="mt-3 flex items-center gap-1 text-xs font-semibold text-[#1B1F5C] hover:underline">
                            View Schedule <ArrowUpRight className="h-3.5 w-3.5" />
                        </Link>
                    </div>

                    {/* CARD 3: Today's Attendance Rate */}
                    <div className="flex flex-col justify-between rounded-2xl border border-gray-100 bg-white p-5 shadow-sm">
                        <div className="flex items-center justify-between">
                            <span className="text-xs font-semibold text-gray-400">Today's Attendance</span>
                            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-emerald-500/10 text-emerald-600">
                                <TrendingUp className="h-5 w-5" />
                            </div>
                        </div>
                        <div>
                            <h3 className="text-3xl font-bold text-[#1B1F5C]">{todayAttendanceRate}%</h3>
                            <p className="mt-1 text-xs text-emerald-600 font-medium">Real-time check-ins today</p>
                        </div>
                        <Link href="/admin/analysis" className="mt-3 flex items-center gap-1 text-xs font-semibold text-[#1B1F5C] hover:underline">
                            View Analytics <ArrowUpRight className="h-3.5 w-3.5" />
                        </Link>
                    </div>

                    {/* CARD 4: Clearance Requests */}
                    <div className="flex flex-col justify-between rounded-2xl border border-gray-100 bg-white p-5 shadow-sm">
                        <div className="flex items-center justify-between">
                            <span className="text-xs font-semibold text-gray-400">Pending Clearances</span>
                            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-blue-500/10 text-blue-600">
                                <FileCheck className="h-5 w-5" />
                            </div>
                        </div>
                        <div>
                            <h3 className="text-3xl font-bold text-[#1B1F5C]">{pendingClearancesCount}</h3>
                            <p className="mt-1 text-xs text-gray-500">Requires verification</p>
                        </div>
                        <Link href="/admin/clearance" className="mt-3 flex items-center gap-1 text-xs font-semibold text-[#1B1F5C] hover:underline">
                            Review Clearances <ArrowUpRight className="h-3.5 w-3.5" />
                        </Link>
                    </div>
                </div>

                {/* MAIN CONTENT AREA */}
                <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
                    {/* LEFT COLUMN: Active Event Quick Verification Card */}
                    <div className="lg:col-span-2 rounded-2xl border border-gray-100 bg-white p-6 shadow-sm">
                        <div className="flex items-center justify-between pb-4 border-b border-gray-100">
                            <div>
                                <h2 className="text-base font-bold text-[#1B1F5C]">Ongoing Event Verification</h2>
                                <p className="text-xs text-gray-500">Live attendance monitoring</p>
                            </div>
                            <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-medium text-emerald-700">
                                <span className="h-2 w-2 rounded-full bg-emerald-500 animate-pulse"></span>
                                Live Now
                            </span>
                        </div>

                        <div className="mt-4 space-y-4">
                            {ongoingEvent ? (
                                <div className="rounded-xl border border-gray-100 bg-gray-50/50 p-4">
                                    <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                                        <div>
                                            <h3 className="text-sm font-bold text-[#1B1F5C]">{ongoingEvent.title}</h3>
                                            <p className="text-xs text-gray-500">
                                                {ongoingEvent.location || 'Location TBA'} • {ongoingEvent.start_time || 'Started'}
                                            </p>
                                        </div>
                                        <div className="text-right">
                                            <span className="text-lg font-bold text-[#1B1F5C]">
                                                {ongoingEvent.attendances_count ?? 0}
                                            </span>
                                            <p className="text-[10px] text-gray-400 uppercase tracking-wider">Checked In</p>
                                        </div>
                                    </div>
                                    {/* Progress Bar */}
                                    <div className="mt-3 h-2 w-full overflow-hidden rounded-full bg-gray-200">
                                        <div className="h-full rounded-full bg-[#1B1F5C]" style={{ width: '100%' }}></div>
                                    </div>
                                </div>
                            ) : (
                                <div className="py-8 text-center text-gray-400 text-xs">
                                    No active event running right now.
                                </div>
                            )}
                        </div>
                    </div>

                    {/* RIGHT COLUMN: Recent Activity Log */}
                    <div className="rounded-2xl border border-gray-100 bg-white p-6 shadow-sm">
                        <h2 className="text-base font-bold text-[#1B1F5C]">Recent System Activity</h2>
                        <div className="mt-4 space-y-4">
                            {recentActivities.length > 0 ? (
                                recentActivities.map((act, i) => (
                                    <div key={i} className="flex items-start gap-3">
                                        <CheckCircle2 className="h-4 w-4 mt-0.5 shrink-0 text-emerald-500" />
                                        <div>
                                            <p className="text-xs text-gray-700 font-medium">{act.text}</p>
                                            <span className="text-[10px] text-gray-400">{act.time}</span>
                                        </div>
                                    </div>
                                ))
                            ) : (
                                <p className="text-xs text-gray-400">No recent activity recorded.</p>
                            )}
                        </div>
                    </div>
                </div>
            </div>
        </>
    );
}

AdminDashboard.layout = (page: React.ReactNode) => <AdminLayout title="Dashboard">{page}</AdminLayout>;