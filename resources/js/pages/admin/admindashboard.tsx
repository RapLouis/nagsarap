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
    TrendingUp,
    ShieldAlert,
    Activity,
    Check,
    Radio,
    ShieldCheck
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

export default function AdminDashboard({ 
    totalStudents = 0, 
    degrees = {},
    activeEventsCount = 0,
    todayAttendanceRate = 0,
    pendingClearancesCount = 0,
    ongoingEvents = [],
    recentActivities = [],
    pendingClearancesList = []
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
            <Head title="Executive Command Dashboard" />

            <div className="space-y-6 p-6 lg:p-8 bg-gray-50/50 min-h-screen">
                
                {/* EXECUTIVE HEADER & QUICK ACTIONS */}
                <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between bg-white p-6 rounded-3xl border border-gray-100 shadow-xs">
                    <div>
                        <div className="flex items-center gap-2">
                            <span className="rounded-full bg-indigo-50 border border-indigo-100 px-3 py-0.5 text-xs font-semibold text-[#1B1F5C] flex items-center gap-1">
                                <Activity className="h-3 w-3 text-indigo-600 animate-pulse" /> CCIS Executive Command
                            </span>
                        </div>
                        <h1 className="text-2xl font-black tracking-tight text-[#1B1F5C] mt-1">Dashboard Overview</h1>
                        <p className="text-xs text-gray-500">
                            Real-time institutional metrics, telemetry, and operational exception management.
                        </p>
                    </div>
                    <div className="flex items-center gap-3">
                        <Link
                            href="/admin/events"
                            className="inline-flex items-center gap-2 rounded-2xl bg-[#1B1F5C] px-5 py-3 text-xs font-bold text-white shadow-md transition hover:bg-[#151848] active:scale-[0.98]"
                        >
                            <Plus className="h-4 w-4" />
                            <span>Create Event Session</span>
                        </Link>
                    </div>
                </div>

                {/* TIER 1: EXECUTIVE KPI RIBBON */}
                <div className="grid grid-cols-1 gap-5 md:grid-cols-2 lg:grid-cols-4">
                    
                    {/* KPI 1: Attendance Rate */}
                    <div className="flex flex-col justify-between rounded-3xl border border-gray-100 bg-white p-6 shadow-xs">
                        <div className="flex items-center justify-between">
                            <span className="text-xs font-bold uppercase tracking-wider text-gray-400">Today's Attendance</span>
                            <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-emerald-50 text-emerald-600">
                                <TrendingUp className="h-5 w-5" />
                            </div>
                        </div>
                        <div className="mt-4">
                            <div className="flex items-baseline gap-2">
                                <h3 className="text-3xl font-black text-gray-900 tracking-tight">{todayAttendanceRate}%</h3>
                                <span className="text-xs font-bold text-emerald-600 bg-emerald-50 px-2 py-0.5 rounded-full">Live telemetry</span>
                            </div>
                            <p className="mt-1 text-xs text-gray-400">Real-time campus check-in velocity</p>
                        </div>
                        <Link href="/admin/analysis" className="mt-4 pt-3 border-t border-gray-100 flex items-center justify-between text-xs font-bold text-[#1B1F5C] hover:text-indigo-900">
                            <span>Deep Dive Analytics</span>
                            <ArrowUpRight className="h-4 w-4" />
                        </Link>
                    </div>

                    {/* KPI 2: Active / Upcoming Events */}
                    <div className="flex flex-col justify-between rounded-3xl border border-gray-100 bg-white p-6 shadow-xs">
                        <div className="flex items-center justify-between">
                            <span className="text-xs font-bold uppercase tracking-wider text-gray-400">Scheduled Events</span>
                            <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-amber-50 text-amber-600">
                                <Calendar className="h-5 w-5" />
                            </div>
                        </div>
                        <div className="mt-4">
                            <div className="flex items-baseline gap-2">
                                <h3 className="text-3xl font-black text-gray-900 tracking-tight">{activeEventsCount}</h3>
                                <span className="text-xs font-bold text-amber-600 bg-amber-50 px-2 py-0.5 rounded-full">This week</span>
                            </div>
                            <p className="mt-1 text-xs text-gray-400">Active windows & sessions</p>
                        </div>
                        <Link href="/admin/events" className="mt-4 pt-3 border-t border-gray-100 flex items-center justify-between text-xs font-bold text-[#1B1F5C] hover:text-indigo-900">
                            <span>Manage Schedule</span>
                            <ArrowUpRight className="h-4 w-4" />
                        </Link>
                    </div>

                    {/* KPI 3: Pending Clearances */}
                    <div className="flex flex-col justify-between rounded-3xl border border-gray-100 bg-white p-6 shadow-xs">
                        <div className="flex items-center justify-between">
                            <span className="text-xs font-bold uppercase tracking-wider text-gray-400">Pending Clearances</span>
                            <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-blue-50 text-blue-600">
                                <FileCheck className="h-5 w-5" />
                            </div>
                        </div>
                        <div className="mt-4">
                            <div className="flex items-baseline gap-2">
                                <h3 className="text-3xl font-black text-gray-900 tracking-tight">{pendingClearancesCount}</h3>
                                {pendingClearancesCount > 0 && (
                                    <span className="text-xs font-bold text-rose-600 bg-rose-50 px-2 py-0.5 rounded-full flex items-center gap-1">
                                        <ShieldAlert className="h-3 w-3" /> Action required
                                    </span>
                                )}
                            </div>
                            <p className="mt-1 text-xs text-gray-400">Awaiting executive sign-off</p>
                        </div>
                        <Link href="/admin/clearance" className="mt-4 pt-3 border-t border-gray-100 flex items-center justify-between text-xs font-bold text-[#1B1F5C] hover:text-indigo-900">
                            <span>Review Queue</span>
                            <ArrowUpRight className="h-4 w-4" />
                        </Link>
                    </div>

                    {/* KPI 4: Interactive Student Filter Widget */}
                    <div className="rounded-3xl border border-gray-100 bg-white p-6 shadow-xs flex flex-col justify-between">
                        <div>
                            <div className="flex items-center justify-between mb-3">
                                <span className="text-xs font-bold uppercase tracking-wider text-gray-400">Student Census</span>
                                <Filter className="h-4 w-4 text-gray-400" />
                            </div>
                            <div className="grid grid-cols-2 gap-2">
                                <select
                                    value={selectedDegree}
                                    onChange={(e) => handleDegreeChange(e.target.value)}
                                    className="w-full rounded-xl border border-gray-200 bg-gray-50 py-1.5 px-2 text-xs font-bold text-[#1B1F5C] focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                >
                                    <option value={ALL}>All Programs</option>
                                    {availableDegrees.map((deg) => (
                                        <option key={deg} value={deg}>{deg}</option>
                                    ))}
                                </select>

                                <select
                                    value={selectedSection}
                                    onChange={(e) => setSelectedSection(e.target.value)}
                                    className="w-full rounded-xl border border-gray-200 bg-gray-50 py-1.5 px-2 text-xs font-bold text-[#1B1F5C] focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                >
                                    <option value={ALL}>All Sections</option>
                                    {availableSections.map((sec) => (
                                        <option key={sec} value={sec}>{sec}</option>
                                    ))}
                                </select>
                            </div>
                        </div>
                        <div className="mt-4 pt-3 border-t border-gray-100 flex items-baseline justify-between">
                            <span className="text-xs text-gray-400 uppercase tracking-wider font-bold">Filtered Total</span>
                            <h3 className="text-2xl font-black text-[#1B1F5C]">
                                {filteredCount.toLocaleString()}
                            </h3>
                        </div>
                    </div>

                </div>

                {/* TIER 2: DUAL-PANEL OPERATIONAL COMMAND */}
                <div className="grid grid-cols-1 gap-8 lg:grid-cols-3">
                    
                    {/* LEFT PANEL: Multi-Stream Live Operations & Biometric Telemetry (Takes 2 columns) */}
                    <div className="lg:col-span-2 rounded-3xl border border-gray-100 bg-white p-6 lg:p-8 shadow-xs space-y-6">
                        <div className="flex items-center justify-between pb-4 border-b border-gray-100">
                            <div>
                                <h2 className="text-lg font-bold text-gray-900">Live Operations & Biometric Telemetry</h2>
                                <p className="text-xs text-gray-500">Real-time monitoring for all active campus sessions today</p>
                            </div>
                            <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-3 py-1 text-xs font-bold text-emerald-700 border border-emerald-200/50">
                                <Radio className="h-3.5 w-3.5 text-emerald-600 animate-pulse" />
                                {ongoingEvents.length} Active Stream{ongoingEvents.length === 1 ? '' : 's'}
                            </span>
                        </div>

                        {ongoingEvents.length > 0 ? (
                            <div className="space-y-4">
                                {ongoingEvents.map((evt) => (
                                    <div key={evt.event_id} className="rounded-2xl border border-indigo-100 bg-indigo-50/40 p-5 space-y-4">
                                        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                                            <div>
                                                <div className="flex items-center gap-2">
                                                    <span className="text-[10px] font-black tracking-wider uppercase text-indigo-600 bg-indigo-100/70 px-2.5 py-0.5 rounded-full">
                                                        Active Session
                                                    </span>
                                                    {evt.is_geofenced && (
                                                        <span className="text-[10px] font-bold text-emerald-700 bg-emerald-100/70 px-2 py-0.5 rounded-full flex items-center gap-1">
                                                            <ShieldCheck className="h-3 w-3" /> Geofence Active ({evt.radius_meters}m)
                                                        </span>
                                                    )}
                                                </div>
                                                <h3 className="text-base font-black text-[#1B1F5C] mt-2">{evt.title}</h3>
                                                <p className="text-xs text-gray-500 flex items-center gap-1.5 mt-0.5">
                                                    <Clock className="h-3.5 w-3.5 text-gray-400" /> Started: {evt.start_time} 
                                                    <span>&bull;</span> 
                                                    <span className="font-semibold text-gray-700">{evt.location}</span>
                                                </p>
                                            </div>
                                            <div className="flex items-center gap-3 shrink-0">
                                                <div className="bg-white px-4 py-2.5 rounded-2xl shadow-2xs border border-indigo-100 text-center">
                                                    <span className="text-xl font-black text-[#1B1F5C]">
                                                        {evt.attendances_count ?? 0}
                                                    </span>
                                                    <p className="text-[9px] text-gray-400 uppercase tracking-wider font-bold">Checked In</p>
                                                </div>
                                                <div className="bg-white px-3 py-2.5 rounded-2xl shadow-2xs border border-indigo-100 text-center">
                                                    <span className="text-sm font-black text-emerald-600">
                                                        {evt.avg_confidence}%
                                                    </span>
                                                    <p className="text-[9px] text-gray-400 uppercase tracking-wider font-bold">Confidence</p>
                                                </div>
                                            </div>
                                        </div>

                                        <div className="flex items-center justify-between pt-2 border-t border-indigo-100/60 text-xs">
                                            <span className="text-gray-500 font-medium">Biometric & facial recognition telemetry nominal.</span>
                                            <Link 
                                                href={`/admin/events`} 
                                                className="font-bold text-[#1B1F5C] hover:underline flex items-center gap-1"
                                            >
                                                Manage Windows &rarr;
                                            </Link>
                                        </div>
                                    </div>
                                ))}
                            </div>
                        ) : (
                            <div className="py-16 text-center space-y-3">
                                <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-gray-100 text-gray-400">
                                    <Calendar className="h-6 w-6" />
                                </div>
                                <p className="font-bold text-gray-700 text-sm">No active events running right now.</p>
                                <p className="text-xs text-gray-400">Scheduled events will automatically initialize telemetry when live.</p>
                            </div>
                        )}
                    </div>

                    {/* RIGHT PANEL: Actionable Clearance Triage Queue */}
                    <div className="rounded-3xl border border-gray-100 bg-white p-6 lg:p-8 shadow-xs space-y-6">
                        <div className="flex items-center justify-between pb-4 border-b border-gray-100">
                            <div>
                                <h2 className="text-lg font-bold text-gray-900">Clearance Triage</h2>
                                <p className="text-xs text-gray-500">Actionable student requests</p>
                            </div>
                            <span className="text-xs font-bold text-blue-600 bg-blue-50 px-2.5 py-1 rounded-full">
                                {pendingClearancesCount} pending
                            </span>
                        </div>

                        <div className="space-y-3 max-h-[320px] overflow-y-auto pr-1">
                            {pendingClearancesList.length > 0 ? (
                                pendingClearancesList.slice(0, 4).map((req) => (
                                    <div key={req.id} className="p-3.5 rounded-2xl bg-gray-50 border border-gray-100 space-y-2">
                                        <div className="flex items-start justify-between">
                                            <div>
                                                <p className="text-xs font-bold text-gray-900">{req.student_name}</p>
                                                <p className="text-[11px] text-gray-400 font-mono">{req.student_number} &bull; {req.program}</p>
                                            </div>
                                            <span className="text-[10px] text-gray-400">{req.submitted_at}</span>
                                        </div>
                                        <div className="flex items-center gap-2 pt-1 border-t border-gray-200/60">
                                            <Link
                                                href={`/admin/clearance/${req.id}`}
                                                className="flex-1 py-1.5 px-3 rounded-xl bg-[#1B1F5C] text-white text-center text-xs font-bold hover:bg-[#151848] transition"
                                            >
                                                Review
                                            </Link>
                                        </div>
                                    </div>
                                ))
                            ) : (
                                <div className="py-12 text-center text-gray-400 text-xs space-y-1">
                                    <CheckCircle2 className="h-8 w-8 mx-auto text-emerald-400" />
                                    <p className="font-bold text-gray-700 mt-2">All Clearances Processed</p>
                                    <p className="text-gray-400 text-[11px]">No pending requests require your attention right now.</p>
                                </div>
                            )}
                        </div>
                        <Link href="/admin/clearance" className="block text-center text-xs font-bold text-[#1B1F5C] hover:underline pt-2">
                            View All Clearance Records &rarr;
                        </Link>
                    </div>

                </div>

                {/* TIER 3: AUDIT STREAM & SYSTEM ACTIVITY FOOTER */}
                <div className="rounded-3xl border border-gray-100 bg-white p-6 lg:p-8 shadow-xs space-y-4">
                    <div className="flex items-center justify-between pb-4 border-b border-gray-100">
                        <div className="flex items-center gap-2">
                            <Activity className="h-5 w-5 text-[#1B1F5C]" />
                            <h2 className="text-lg font-bold text-gray-900">Security & System Audit Stream</h2>
                        </div>
                        <span className="text-xs text-gray-400">Real-time log trail</span>
                    </div>

                    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 pt-2">
                        {recentActivities.length > 0 ? (
                            recentActivities.map((act, i) => (
                                <div key={i} className="flex items-start gap-3 p-3.5 rounded-2xl bg-gray-50 border border-gray-100">
                                    <div className="h-8 w-8 rounded-xl bg-emerald-50 text-emerald-600 flex items-center justify-center shrink-0 mt-0.5">
                                        <Check className="h-4 w-4" />
                                    </div>
                                    <div className="min-w-0 flex-1">
                                        <p className="text-xs font-bold text-gray-900">{act.text}</p>
                                        <span className="text-[11px] text-gray-400 mt-0.5 block">{act.time}</span>
                                    </div>
                                </div>
                            ))
                        ) : (
                            <div className="col-span-full py-8 text-center text-gray-400 text-xs">
                                No recent system activity logged.
                            </div>
                        )}
                    </div>
                </div>

            </div>
        </>
    );
}

AdminDashboard.layout = (page: React.ReactNode) => <AdminLayout title="Executive Dashboard">{page}</AdminLayout>;