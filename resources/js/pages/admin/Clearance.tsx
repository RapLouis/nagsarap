import { Head, router, Link } from '@inertiajs/react';
import {
    Search,
    Users,
    Calendar,
    Clock3,
    FileCheck2,
    CheckCircle2,
    Loader2,
} from 'lucide-react';
import { useState, useRef, useEffect } from 'react';
import AdminLayout from '@/layouts/admin-layout';

type ClearanceStatus = 'pending' | 'review' | 'cleared';

type ClearanceRecord = {
    id: number;
    studentNumber: string;
    name: string;
    program: string;
    yearSection: string;
    status: ClearanceStatus;
    updatedAt: string;
};

type EventItem = {
    event_id: number;
    title: string;
    event_date: string;
};

type PageLink = { url: string | null; label: string; active: boolean };

type Props = {
    events?: EventItem[];
    currentEventId?: number | null;
    records?: {
        data: ClearanceRecord[];
        links: PageLink[];
    };
    counts?: {
        pending: number;
        review: number;
        cleared: number;
    };
    filters?: {
        search?: string;
        event_id?: string | number;
        status?: string;
    };
};

export default function Clearance({
    events = [],
    currentEventId = null,
    records = { data: [], links: [] },
    counts = { pending: 0, review: 0, cleared: 0 },
    filters = { search: '', event_id: '', status: 'all' },
}: Props) {
    const [search, setSearch] = useState(filters?.search || '');
    const [selectedEventId, setSelectedEventId] = useState(currentEventId || filters?.event_id || '');
    const [statusFilter, setStatusFilter] = useState(filters?.status || 'all');
    const [isFiltering, setIsFiltering] = useState(false);
    const [updatingId, setUpdatingId] = useState<number | null>(null);

    const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const isFirstRun = useRef(true);

    useEffect(() => {
        if (isFirstRun.current) {
            isFirstRun.current = false;
            return;
        }

        if (debounceRef.current) clearTimeout(debounceRef.current);
        setIsFiltering(true);

        debounceRef.current = setTimeout(() => {
            router.get(
                '/admin/clearance',
                { search, event_id: selectedEventId, status: statusFilter },
                {
                    preserveState: true,
                    replace: true,
                    onFinish: () => setIsFiltering(false),
                }
            );
        }, 350);

        return () => {
            if (debounceRef.current) clearTimeout(debounceRef.current);
        };
    }, [search, selectedEventId, statusFilter]);

    const handleStatusUpdate = (id: number, newStatus: ClearanceStatus) => {
        setUpdatingId(id);
        router.patch(
            `/admin/clearance/${id}/status`,
            { status: newStatus },
            {
                preserveScroll: true,
                onFinish: () => setUpdatingId(null),
            }
        );
    };

    const recordList = records?.data || [];
    const paginationLinks = records?.links || [];

    return (
        <>
            <Head title="Absenteeism & Clearance" />

            <div className="min-h-full space-y-6 p-4 sm:p-6 lg:p-8">
                {/* HEADER */}
                <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 bg-white p-6 rounded-3xl border border-gray-100 shadow-xs">
                    <div>
                        <h1 className="text-2xl font-black tracking-tight text-[#1B1F5C]">
                            Absenteeism & Clearance Triage
                        </h1>
                        <p className="mt-1 text-xs text-gray-500">
                            Monitor event absentees and resolve student clearance requests.
                        </p>
                    </div>

                    <div className="flex items-center gap-2">
                        <Calendar className="h-4 w-4 text-gray-400 shrink-0" />
                        <select
                            value={selectedEventId}
                            onChange={(e) => setSelectedEventId(e.target.value)}
                            className="rounded-xl border border-gray-200 bg-gray-50 px-3.5 py-2.5 text-xs font-bold text-[#1B1F5C] focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                        >
                            {events.map((evt) => (
                                <option key={evt.event_id} value={evt.event_id}>
                                    {evt.title} ({evt.event_date})
                                </option>
                            ))}
                        </select>
                    </div>
                </div>

                {/* SUMMARY CARDS */}
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
                    <SummaryCard title="Pending Absentees" value={counts.pending} description="Awaiting sanction resolution" icon={Clock3} />
                    <SummaryCard title="For Review" value={counts.review} description="Under administrative review" icon={FileCheck2} />
                    <SummaryCard title="Cleared" value={counts.cleared} description="Sanction cleared" icon={CheckCircle2} />
                </div>

                {/* TABLE CONTAINER */}
                <div className="rounded-3xl border border-gray-100 bg-white shadow-xs overflow-hidden">
                    <div className="border-b border-gray-100 p-5 sm:p-6">
                        <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
                            <div>
                                <h2 className="text-sm font-bold text-[#1B1F5C]">
                                    Absent Students Queue
                                </h2>
                                <p className="mt-1 text-xs text-gray-500">
                                    Search absentees and update their clearance standings.
                                </p>
                            </div>

                            <div className="flex flex-col gap-2.5 sm:flex-row">
                                <div className="relative">
                                    <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
                                    <input
                                        type="text"
                                        value={search}
                                        onChange={(event) => setSearch(event.target.value)}
                                        placeholder="Search student or ID..."
                                        className="w-full rounded-xl border border-gray-200 bg-gray-50/50 py-2.5 pl-10 pr-9 text-xs font-medium outline-none transition focus:border-[#1B1F5C] focus:ring-1 focus:ring-[#1B1F5C] sm:w-64"
                                    />
                                    {isFiltering && (
                                        <Loader2 className="absolute right-3 top-3 h-4 w-4 text-gray-400 animate-spin" />
                                    )}
                                </div>

                                <select
                                    value={statusFilter}
                                    onChange={(event) => setStatusFilter(event.target.value)}
                                    className="rounded-xl border border-gray-200 bg-gray-50/50 px-3.5 py-2.5 text-xs font-bold text-gray-700 outline-none focus:border-[#1B1F5C] focus:ring-1 focus:ring-[#1B1F5C]"
                                >
                                    <option value="all">All Status</option>
                                    <option value="pending">Pending</option>
                                    <option value="review">For Review</option>
                                    <option value="cleared">Cleared</option>
                                </select>
                            </div>
                        </div>
                    </div>

                    <div className="overflow-x-auto">
                        <table className="w-full min-w-[760px] text-left">
                            <thead>
                                <tr className="border-b border-gray-100 bg-gray-50/70 text-[10px] font-bold uppercase tracking-wider text-gray-400">
                                    <th className="px-6 py-4">Student</th>
                                    <th className="px-6 py-4">Program</th>
                                    <th className="px-6 py-4">Year / Section</th>
                                    <th className="px-6 py-4">Status</th>
                                    <th className="px-6 py-4 text-right">Actions</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100 text-xs">
                                {recordList.length === 0 ? (
                                    <tr>
                                        <td colSpan={5} className="px-6 py-16 text-center">
                                            <div className="flex flex-col items-center space-y-2">
                                                <Users className="h-10 w-10 text-gray-300" />
                                                <p className="font-bold text-gray-700 text-sm">No absentees found</p>
                                                <p className="text-xs text-gray-400">All students attended this event or no records match filters.</p>
                                            </div>
                                        </td>
                                    </tr>
                                ) : (
                                    recordList.map((record) => {
                                        const isUpdating = updatingId === record.id;
                                        return (
                                            <tr key={record.id} className="hover:bg-gray-50/50 transition-colors">
                                                <td className="px-6 py-4">
                                                    <div>
                                                        <p className="font-bold text-gray-900">{record.name}</p>
                                                        <p className="text-[11px] text-gray-400 font-mono mt-0.5">{record.studentNumber}</p>
                                                    </div>
                                                </td>
                                                <td className="px-6 py-4 text-gray-600 font-medium">{record.program}</td>
                                                <td className="px-6 py-4 text-gray-600 font-medium">{record.yearSection}</td>
                                                <td className="px-6 py-4">
                                                    <StatusBadge status={record.status} />
                                                </td>
                                                <td className="px-6 py-4 text-right">
                                                    <div className="flex items-center justify-end gap-2">
                                                        {record.status !== 'cleared' && (
                                                            <button
                                                                type="button"
                                                                disabled={isUpdating}
                                                                onClick={() => handleStatusUpdate(record.id, 'cleared')}
                                                                className="px-3 py-1.5 rounded-xl bg-emerald-600 text-white font-bold text-[11px] hover:bg-emerald-700 transition disabled:opacity-50"
                                                            >
                                                                {isUpdating ? 'Saving...' : 'Mark Cleared'}
                                                            </button>
                                                        )}
                                                        {record.status !== 'review' && (
                                                            <button
                                                                type="button"
                                                                disabled={isUpdating}
                                                                onClick={() => handleStatusUpdate(record.id, 'review')}
                                                                className="px-3 py-1.5 rounded-xl border border-gray-200 bg-white text-gray-700 font-bold text-[11px] hover:bg-gray-50 transition disabled:opacity-50"
                                                            >
                                                                For Review
                                                            </button>
                                                        )}
                                                    </div>
                                                </td>
                                            </tr>
                                        );
                                    })
                                )}
                            </tbody>
                        </table>
                    </div>
                </div>

                {/* PAGINATION */}
                {paginationLinks.length > 3 && (
                    <nav className="flex flex-wrap items-center justify-center gap-1.5 pt-2" aria-label="Pagination">
                        {paginationLinks.map((link, idx) => (
                            <Link
                                key={idx}
                                href={link.url ?? '#'}
                                preserveState
                                preserveScroll
                                className={`min-w-[2.25rem] rounded-xl px-3.5 py-2 text-center text-xs font-bold transition ${
                                    link.active
                                        ? 'bg-[#1B1F5C] text-white'
                                        : link.url
                                        ? 'bg-white text-gray-600 border border-gray-200 hover:bg-gray-50'
                                        : 'bg-white text-gray-300 border border-gray-100 pointer-events-none'
                                }`}
                                dangerouslySetInnerHTML={{ __html: link.label }}
                            />
                        ))}
                    </nav>
                )}
            </div>
        </>
    );
}

Clearance.layout = (page: React.ReactNode) => <AdminLayout title="Student Clearance">{page}</AdminLayout>;

function SummaryCard({ title, value, description, icon: Icon }: { title: string; value: number; description: string; icon: typeof Clock3 }) {
    return (
        <div className="rounded-3xl border border-gray-100 bg-white p-6 shadow-xs flex items-center justify-between">
            <div>
                <p className="text-[10px] font-bold uppercase tracking-wider text-gray-400">{title}</p>
                <p className="mt-2 text-3xl font-black text-[#1B1F5C] tracking-tight">{value}</p>
                <p className="mt-1 text-xs text-gray-400">{description}</p>
            </div>
            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-indigo-50 text-[#1B1F5C]">
                <Icon className="h-5 w-5" />
            </div>
        </div>
    );
}

function StatusBadge({ status }: { status: ClearanceStatus }) {
    const configuration = {
        pending: { label: 'Pending', className: 'bg-amber-50 text-amber-700 border-amber-200/60' },
        review: { label: 'For Review', className: 'bg-blue-50 text-blue-700 border-blue-200/60' },
        cleared: { label: 'Cleared', className: 'bg-emerald-50 text-emerald-700 border-emerald-200/60' },
    };

    const current = configuration[status];

    return (
        <span className={`inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-[11px] font-bold ${current.className}`}>
            <span className="h-1.5 w-1.5 rounded-full bg-current" />
            {current.label}
        </span>
    );
}