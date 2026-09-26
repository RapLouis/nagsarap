import { Head } from '@inertiajs/react';
import {
    CheckCircle2,
    Clock3,
    FileCheck2,
    Search,
    ShieldCheck,
    Users,
} from 'lucide-react';
import { useMemo, useState } from 'react';

type ClearanceStatus =
    | 'pending'
    | 'cleared'
    | 'review';

type ClearanceRecord = {
    id: number;
    studentNumber: string;
    name: string;
    program: string;
    yearSection: string;
    status: ClearanceStatus;
    updatedAt: string;
};

const demoRecords: ClearanceRecord[] = [
    {
        id: 1,
        studentNumber: '24-123423',
        name: 'Student Clearance',
        program: 'BS Computer Science',
        yearSection: '4-A',
        status: 'pending',
        updatedAt: 'Awaiting review',
    },
];

export default function Clearance() {
    const [search, setSearch] = useState('');
    const [status, setStatus] = useState<
        ClearanceStatus | 'all'
    >('all');

    const filteredRecords = useMemo(() => {
        const normalizedSearch =
            search.trim().toLowerCase();

        return demoRecords.filter((record) => {
            const matchesSearch =
                normalizedSearch.length === 0 ||
                record.name
                    .toLowerCase()
                    .includes(normalizedSearch) ||
                record.studentNumber
                    .toLowerCase()
                    .includes(normalizedSearch) ||
                record.program
                    .toLowerCase()
                    .includes(normalizedSearch);

            const matchesStatus =
                status === 'all' ||
                record.status === status;

            return matchesSearch && matchesStatus;
        });
    }, [search, status]);

    const pendingCount = demoRecords.filter(
        (record) => record.status === 'pending',
    ).length;

    const clearedCount = demoRecords.filter(
        (record) => record.status === 'cleared',
    ).length;

    const reviewCount = demoRecords.filter(
        (record) => record.status === 'review',
    ).length;

    return (
        <>
            <Head title="Student Clearance" />

            <div className="min-h-full space-y-6 p-6">
                {/* HEADER */}
                <div>
                    <h1 className="text-2xl font-bold tracking-tight text-[#1B1F5C]">
                        Student Clearance
                    </h1>

                    <p className="mt-1 text-xs text-gray-500">
                        Review and monitor student clearance
                        requests.
                    </p>
                </div>

                {/* SUMMARY */}
                <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
                    <SummaryCard
                        title="Pending"
                        value={pendingCount}
                        description="Awaiting review"
                        icon={Clock3}
                    />

                    <SummaryCard
                        title="For Review"
                        value={reviewCount}
                        description="Requires attention"
                        icon={FileCheck2}
                    />

                    <SummaryCard
                        title="Cleared"
                        value={clearedCount}
                        description="Completed clearance"
                        icon={CheckCircle2}
                    />
                </div>

                {/* CONTENT */}
                <div className="rounded-2xl border border-gray-100 bg-white shadow-sm">
                    <div className="border-b border-gray-100 p-5">
                        <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
                            <div>
                                <h2 className="text-sm font-bold text-[#1B1F5C]">
                                    Clearance Requests
                                </h2>

                                <p className="mt-1 text-xs text-gray-500">
                                    Search and review student
                                    clearance records.
                                </p>
                            </div>

                            <div className="flex flex-col gap-2 sm:flex-row">
                                <div className="relative">
                                    <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />

                                    <input
                                        type="text"
                                        value={search}
                                        onChange={(event) =>
                                            setSearch(
                                                event.target.value,
                                            )
                                        }
                                        placeholder="Search student..."
                                        className="w-full rounded-lg border border-gray-200 bg-gray-50 py-2 pl-9 pr-3 text-xs outline-none transition focus:border-[#1B1F5C] focus:ring-1 focus:ring-[#1B1F5C] sm:w-64"
                                    />
                                </div>

                                <select
                                    value={status}
                                    onChange={(event) =>
                                        setStatus(
                                            event.target
                                                .value as ClearanceStatus |
                                                'all',
                                        )
                                    }
                                    className="rounded-lg border border-gray-200 bg-gray-50 px-3 py-2 text-xs font-medium text-gray-700 outline-none focus:border-[#1B1F5C] focus:ring-1 focus:ring-[#1B1F5C]"
                                >
                                    <option value="all">
                                        All Status
                                    </option>
                                    <option value="pending">
                                        Pending
                                    </option>
                                    <option value="review">
                                        For Review
                                    </option>
                                    <option value="cleared">
                                        Cleared
                                    </option>
                                </select>
                            </div>
                        </div>
                    </div>

                    {/* TABLE */}
                    <div className="overflow-x-auto">
                        <table className="w-full min-w-[760px] text-left">
                            <thead>
                                <tr className="border-b border-gray-100 bg-gray-50/70">
                                    <th className="px-5 py-3 text-[10px] font-bold uppercase tracking-wide text-gray-400">
                                        Student
                                    </th>

                                    <th className="px-5 py-3 text-[10px] font-bold uppercase tracking-wide text-gray-400">
                                        Program
                                    </th>

                                    <th className="px-5 py-3 text-[10px] font-bold uppercase tracking-wide text-gray-400">
                                        Year / Section
                                    </th>

                                    <th className="px-5 py-3 text-[10px] font-bold uppercase tracking-wide text-gray-400">
                                        Status
                                    </th>

                                    <th className="px-5 py-3 text-[10px] font-bold uppercase tracking-wide text-gray-400">
                                        Updated
                                    </th>
                                </tr>
                            </thead>

                            <tbody>
                                {filteredRecords.length === 0 ? (
                                    <tr>
                                        <td
                                            colSpan={5}
                                            className="px-5 py-16 text-center"
                                        >
                                            <div className="flex flex-col items-center">
                                                <Users className="h-10 w-10 text-gray-300" />

                                                <p className="mt-3 text-sm font-semibold text-gray-600">
                                                    No clearance records
                                                    found
                                                </p>

                                                <p className="mt-1 text-xs text-gray-400">
                                                    Try changing your
                                                    search or filter.
                                                </p>
                                            </div>
                                        </td>
                                    </tr>
                                ) : (
                                    filteredRecords.map(
                                        (record) => (
                                            <tr
                                                key={record.id}
                                                className="border-b border-gray-50 last:border-0"
                                            >
                                                <td className="px-5 py-4">
                                                    <div>
                                                        <p className="text-xs font-semibold text-gray-800">
                                                            {
                                                                record.name
                                                            }
                                                        </p>

                                                        <p className="mt-1 text-[11px] text-gray-400">
                                                            {
                                                                record.studentNumber
                                                            }
                                                        </p>
                                                    </div>
                                                </td>

                                                <td className="px-5 py-4 text-xs text-gray-600">
                                                    {
                                                        record.program
                                                    }
                                                </td>

                                                <td className="px-5 py-4 text-xs text-gray-600">
                                                    {
                                                        record.yearSection
                                                    }
                                                </td>

                                                <td className="px-5 py-4">
                                                    <StatusBadge
                                                        status={
                                                            record.status
                                                        }
                                                    />
                                                </td>

                                                <td className="px-5 py-4 text-xs text-gray-500">
                                                    {
                                                        record.updatedAt
                                                    }
                                                </td>
                                            </tr>
                                        ),
                                    )
                                )}
                            </tbody>
                        </table>
                    </div>
                </div>

                {/* INFORMATION */}
                <div className="rounded-2xl border border-[#E5E7F5] bg-[#F8F8FF] p-5">
                    <div className="flex gap-3">
                        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-[#1B1F5C] text-white">
                            <ShieldCheck className="h-4 w-4" />
                        </div>

                        <div>
                            <h3 className="text-xs font-bold text-[#1B1F5C]">
                                Clearance workflow
                            </h3>

                            <p className="mt-1 max-w-3xl text-[11px] leading-5 text-gray-500">
                                This page is now connected to the
                                admin navigation. The request
                                management actions can be connected
                                to the clearance database once the
                                clearance workflow and database
                                records are enabled.
                            </p>
                        </div>
                    </div>
                </div>
            </div>
        </>
    );
}

function SummaryCard({
    title,
    value,
    description,
    icon: Icon,
}: {
    title: string;
    value: number;
    description: string;
    icon: typeof Clock3;
}) {
    return (
        <div className="rounded-2xl border border-gray-100 bg-white p-5 shadow-sm">
            <div className="flex items-start justify-between">
                <div>
                    <p className="text-[10px] font-bold uppercase tracking-wide text-gray-400">
                        {title}
                    </p>

                    <p className="mt-2 text-2xl font-bold text-[#1B1F5C]">
                        {value}
                    </p>

                    <p className="mt-1 text-[11px] text-gray-400">
                        {description}
                    </p>
                </div>

                <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-[#F1F1FF] text-[#1B1F5C]">
                    <Icon className="h-4 w-4" />
                </div>
            </div>
        </div>
    );
}

function StatusBadge({
    status,
}: {
    status: ClearanceStatus;
}) {
    const configuration = {
        pending: {
            label: 'Pending',
            className:
                'bg-amber-50 text-amber-700 border-amber-100',
        },
        review: {
            label: 'For Review',
            className:
                'bg-blue-50 text-blue-700 border-blue-100',
        },
        cleared: {
            label: 'Cleared',
            className:
                'bg-green-50 text-green-700 border-green-100',
        },
    };

    const current = configuration[status];

    return (
        <span
            className={`inline-flex rounded-full border px-2.5 py-1 text-[10px] font-bold ${current.className}`}
        >
            {current.label}
        </span>
    );
}