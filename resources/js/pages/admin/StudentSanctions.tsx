import React, { useState } from 'react';
import { Head, router, useForm } from '@inertiajs/react';
import AdminLayout from '@/layouts/admin-layout';
import {
    Banknote,
    CheckCircle2,
    ChevronDown,
    ChevronUp,
    Clock,
    ExternalLink,
    FileCheck2,
    Filter,
    HandHelping,
    Receipt,
    Search,
    Settings2,
    ShieldCheck,
    X,
    XCircle,
} from 'lucide-react';

interface SanctionDetail {
    sanction_id: number;
    event_title: string;
    event_date: string;
    slot_label: string | null;
    infraction_type: string;
    fine_amount: number;
    status: 'unsettled' | 'pending_verification' | 'settled' | 'excused';
    preferred_mode: 'unselected' | 'cash' | 'community_service' | 'excuse';
    excuse_category: string | null;
    student_notes: string | null;
    has_proof: boolean;
    proof_url: string | null;
    official_receipt_no: string | null;
    comm_service_hours: number | null;
    admin_remarks: string | null;
    resolved_at: string | null;
}

interface StudentRow {
    student_id: number;
    student_number: string;
    full_name: string;
    degree: string;
    year_section: string;
    clearance_status: string;
    unsettled_balance: number;
    unsettled_count: number;
    pending_cash_count: number;
    pending_serv_count: number;
    pending_exc_count: number;
    sanctions: SanctionDetail[];
}

interface Props {
    students: StudentRow[];
    metrics: {
        total_collectible: number;
        total_collected: number;
        total_service_hrs: number;
        pending_cash: number;
        pending_service: number;
        pending_excuses: number;
    };
    fineRatePerLog: number;
    filterOptions: {
        degrees: string[];
        sections: string[];
    };
    filters: {
        search: string;
        degree: string;
        section: string;
        status: string;
        mode: string;
    };
}

export default function StudentSanctions({
    students = [],
    metrics = {
        total_collectible: 0,
        total_collected: 0,
        total_service_hrs: 0,
        pending_cash: 0,
        pending_service: 0,
        pending_excuses: 0,
    },
    fineRatePerLog = 0,
    filterOptions = {
        degrees: [],
        sections: [],
    },
    filters = {
        search: '',
        degree: 'all',
        section: 'all',
        status: 'all',
        mode: 'all',
    },
}: Props) {
    const [search, setSearch] = useState(filters.search ?? '');
    const [degree, setDegree] = useState(filters.degree ?? 'all');
    const [section, setSection] = useState(filters.section ?? 'all');
    const [status, setStatus] = useState(filters.status ?? 'all');
    const [mode, setMode] = useState(filters.mode ?? 'all');

    const [expandedStudents, setExpandedStudents] = useState<Record<number, boolean>>({});
    const [selectedByStudent, setSelectedByStudent] = useState<Record<number, number[]>>({});

    const [rateModalOpen, setRateModalOpen] = useState(false);
    const [cashModal, setCashModal] = useState<{ student: StudentRow; ids: number[]; total: number } | null>(null);
    const [serviceModal, setServiceModal] = useState<{ student: StudentRow; ids: number[]; count: number } | null>(null);
    const [excuseModal, setExcuseModal] = useState<{ student: StudentRow; sanction: SanctionDetail } | null>(null);

    const rateForm = useForm({
        fine_per_log: fineRatePerLog.toString(),
        apply_to_unsettled: false,
    });

    const cashForm = useForm({
        student_id: 0,
        sanction_ids: [] as number[],
        official_receipt_no: '',
        admin_remarks: '',
    });

    const serviceForm = useForm({
        student_id: 0,
        sanction_ids: [] as number[],
        comm_service_hours: '',
        admin_remarks: '',
    });

    const excuseReviewForm = useForm({
        decision: 'approve' as 'approve' | 'reject',
        admin_remarks: '',
    });

    const applyFilters = (overrides?: Partial<{
        search: string;
        degree: string;
        section: string;
        status: string;
        mode: string;
    }>) => {
        const next = {
            search: overrides?.search ?? search,
            degree: overrides?.degree ?? degree,
            section: overrides?.section ?? section,
            status: overrides?.status ?? status,
            mode: overrides?.mode ?? mode,
        };
        router.get('/admin/sanctions', next, {
            preserveState: true,
            preserveScroll: true,
            replace: true,
        });
    };

    const toggleExpand = (studentId: number) => {
        setExpandedStudents((prev) => ({ ...prev, [studentId]: !prev[studentId] }));
    };

    const toggleSanctionSelection = (studentId: number, sanctionId: number) => {
        setSelectedByStudent((prev) => {
            const current = prev[studentId] ?? [];
            const exists = current.includes(sanctionId);
            return {
                ...prev,
                [studentId]: exists
                    ? current.filter((id) => id !== sanctionId)
                    : [...current, sanctionId],
            };
        });
    };

    const selectAllOpenForStudent = (student: StudentRow) => {
        const openIds = student.sanctions
            .filter((s) => s.status === 'unsettled' || s.status === 'pending_verification')
            .map((s) => s.sanction_id);
        const current = selectedByStudent[student.student_id] ?? [];
        setSelectedByStudent((prev) => ({
            ...prev,
            [student.student_id]: current.length === openIds.length ? [] : openIds,
        }));
    };

    const openCashModal = (student: StudentRow, ids: number[]) => {
        const total = student.sanctions
            .filter((s) => ids.includes(s.sanction_id))
            .reduce((sum, s) => sum + s.fine_amount, 0);

        cashForm.setData({
            student_id: student.student_id,
            sanction_ids: ids,
            official_receipt_no: '',
            admin_remarks: '',
        });
        cashForm.clearErrors();
        setCashModal({ student, ids, total });
    };

    const openServiceModal = (student: StudentRow, ids: number[]) => {
        serviceForm.setData({
            student_id: student.student_id,
            sanction_ids: ids,
            comm_service_hours: '',
            admin_remarks: '',
        });
        serviceForm.clearErrors();
        setServiceModal({ student, ids, count: ids.length });
    };

    const openExcuseReviewModal = (student: StudentRow, sanction: SanctionDetail) => {
        excuseReviewForm.setData({
            decision: 'approve',
            admin_remarks: '',
        });
        excuseReviewForm.clearErrors();
        setExcuseModal({ student, sanction });
    };

    const submitRateUpdate = (e: React.FormEvent) => {
        e.preventDefault();
        rateForm.post('/admin/sanctions/fine-rate', {
            preserveScroll: true,
            onSuccess: () => setRateModalOpen(false),
        });
    };

    const submitCashVerification = (e: React.FormEvent) => {
        e.preventDefault();
        cashForm.post('/admin/sanctions/verify-cash', {
            preserveScroll: true,
            onSuccess: () => {
                if (cashModal) {
                    setSelectedByStudent((prev) => ({ ...prev, [cashModal.student.student_id]: [] }));
                }
                setCashModal(null);
            },
        });
    };

    const submitServiceVerification = (e: React.FormEvent) => {
        e.preventDefault();
        serviceForm.post('/admin/sanctions/verify-service', {
            preserveScroll: true,
            onSuccess: () => {
                if (serviceModal) {
                    setSelectedByStudent((prev) => ({ ...prev, [serviceModal.student.student_id]: [] }));
                }
                setServiceModal(null);
            },
        });
    };

    const submitExcuseDecision = (e: React.FormEvent) => {
        e.preventDefault();
        if (!excuseModal) return;
        excuseReviewForm.post(`/admin/sanctions/${excuseModal.sanction.sanction_id}/review-excuse`, {
            preserveScroll: true,
            onSuccess: () => setExcuseModal(null),
        });
    };

    return (
        <>
            <Head title="Student Sanctions Management" />

            <div className="mx-auto max-w-7xl space-y-6 px-4 py-6 sm:px-6 lg:px-8 font-sans text-gray-900">
                {/* Page Header & Fine Rate Configuration */}
                <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
                    <div>
                        <h1 className="text-2xl font-black tracking-tight text-[#1B1F5C]">
                            Student Sanctions Management
                        </h1>
                        <p className="mt-1 text-xs sm:text-sm text-slate-600 font-medium">
                            Verify F2F cash payments, log community service hours, and review submitted excuse proofs across 4 checkpoints.
                        </p>
                    </div>

                    <button
                        type="button"
                        onClick={() => {
                            rateForm.setData('fine_per_log', fineRatePerLog.toString());
                            setRateModalOpen(true);
                        }}
                        className="inline-flex items-center gap-2 rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-xs font-extrabold text-[#1B1F5C] shadow-xs hover:bg-slate-50 transition-all"
                    >
                        <Settings2 className="h-4 w-4 text-[#F5A623]" />
                        Fine Rate: ₱{fineRatePerLog.toFixed(2)} / checkpoint
                    </button>
                </div>

                {/* Top Queue Action Cards (Interactive Filters) */}
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
                    <button
                        type="button"
                        onClick={() => {
                            setStatus('pending_verification');
                            setMode('cash');
                            applyFilters({ status: 'pending_verification', mode: 'cash' });
                        }}
                        className="rounded-2xl border border-slate-200 bg-white p-4 text-left shadow-xs transition hover:border-[#1B1F5C]"
                    >
                        <div className="flex items-center justify-between">
                            <span className="text-[10px] font-extrabold uppercase tracking-wider text-slate-500">
                                Pending Cash Walk-ins
                            </span>
                            <Banknote className="h-5 w-5 text-[#1B1F5C]" />
                        </div>
                        <div className="mt-2 text-2xl font-black text-[#1B1F5C]">
                            {metrics.pending_cash}
                        </div>
                        <p className="mt-1 text-xs text-slate-500 font-medium">
                            Awaiting F2F payment & OR # logging
                        </p>
                    </button>

                    <button
                        type="button"
                        onClick={() => {
                            setStatus('pending_verification');
                            setMode('community_service');
                            applyFilters({ status: 'pending_verification', mode: 'community_service' });
                        }}
                        className="rounded-2xl border border-slate-200 bg-white p-4 text-left shadow-xs transition hover:border-[#F5A623]"
                    >
                        <div className="flex items-center justify-between">
                            <span className="text-[10px] font-extrabold uppercase tracking-wider text-slate-500">
                                Pending Comm. Service
                            </span>
                            <HandHelping className="h-5 w-5 text-[#B4730A]" />
                        </div>
                        <div className="mt-2 text-2xl font-black text-slate-900">
                            {metrics.pending_service}
                        </div>
                        <p className="mt-1 text-xs text-slate-500 font-medium">
                            Total rendered: {metrics.total_service_hrs.toFixed(1)} hrs
                        </p>
                    </button>

                    <button
                        type="button"
                        onClick={() => {
                            setStatus('pending_verification');
                            setMode('excuse');
                            applyFilters({ status: 'pending_verification', mode: 'excuse' });
                        }}
                        className="rounded-2xl border border-slate-200 bg-white p-4 text-left shadow-xs transition hover:border-blue-500"
                    >
                        <div className="flex items-center justify-between">
                            <span className="text-[10px] font-extrabold uppercase tracking-wider text-slate-500">
                                Excuses Waiting Approval
                            </span>
                            <FileCheck2 className="h-5 w-5 text-blue-600" />
                        </div>
                        <div className="mt-2 text-2xl font-black text-blue-700">
                            {metrics.pending_excuses}
                        </div>
                        <p className="mt-1 text-xs text-slate-500 font-medium">
                            With uploaded letters / medical proofs
                        </p>
                    </button>

                    <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-xs">
                        <div className="flex items-center justify-between">
                            <span className="text-[10px] font-extrabold uppercase tracking-wider text-slate-500">
                                Collectible vs. Collected
                            </span>
                            <Receipt className="h-5 w-5 text-emerald-600" />
                        </div>
                        <div className="mt-2 flex items-baseline gap-2">
                            <span className="text-xl font-black text-rose-700">
                                ₱{metrics.total_collectible.toFixed(2)}
                            </span>
                            <span className="text-xs text-slate-400">/</span>
                            <span className="text-sm font-bold text-emerald-700">
                                ₱{metrics.total_collected.toFixed(2)} paid
                            </span>
                        </div>
                        <p className="mt-1 text-xs text-slate-500 font-medium">
                            Across all active student records
                        </p>
                    </div>
                </div>

                {/* Multi-Dimensional Filter Bar */}
                <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-xs">
                    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-6">
                        <div className="relative lg:col-span-2">
                            <Search className="pointer-events-none absolute top-2.5 left-3 h-4 w-4 text-slate-400" />
                            <input
                                type="text"
                                placeholder="Search Student ID or Name..."
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                onKeyDown={(e) => e.key === 'Enter' && applyFilters()}
                                className="w-full rounded-xl border border-slate-300 py-2 pr-3 pl-9 text-xs sm:text-sm focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                            />
                        </div>

                        <select
                            value={degree}
                            onChange={(e) => {
                                setDegree(e.target.value);
                                applyFilters({ degree: e.target.value });
                            }}
                            className="rounded-xl border border-slate-300 px-3 py-2 text-xs sm:text-sm focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                        >
                            <option value="all">All Courses</option>
                            {filterOptions.degrees.map((d) => (
                                <option key={d} value={d}>
                                    {d}
                                </option>
                            ))}
                        </select>

                        <select
                            value={section}
                            onChange={(e) => {
                                setSection(e.target.value);
                                applyFilters({ section: e.target.value });
                            }}
                            className="rounded-xl border border-slate-300 px-3 py-2 text-xs sm:text-sm focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                        >
                            <option value="all">All Year & Sections</option>
                            {filterOptions.sections.map((sec) => (
                                <option key={sec} value={sec}>
                                    {sec}
                                </option>
                            ))}
                        </select>

                        <select
                            value={mode}
                            onChange={(e) => {
                                setMode(e.target.value);
                                applyFilters({ mode: e.target.value });
                            }}
                            className="rounded-xl border border-slate-300 px-3 py-2 text-xs sm:text-sm focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                        >
                            <option value="all">All Resolution Modes</option>
                            <option value="cash">Paying Cash</option>
                            <option value="community_service">Community Service</option>
                            <option value="excuse">Excuse Appeal</option>
                            <option value="unselected">Unselected</option>
                        </select>

                        <div className="flex gap-2">
                            <select
                                value={status}
                                onChange={(e) => {
                                    setStatus(e.target.value);
                                    applyFilters({ status: e.target.value });
                                }}
                                className="w-full rounded-xl border border-slate-300 px-3 py-2 text-xs sm:text-sm focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                            >
                                <option value="all">All Statuses</option>
                                <option value="pending_verification">Pending Verification</option>
                                <option value="unsettled">Unsettled</option>
                                <option value="settled">Settled</option>
                                <option value="excused">Excused</option>
                            </select>

                            <button
                                type="button"
                                onClick={() => applyFilters()}
                                className="inline-flex shrink-0 items-center justify-center rounded-xl bg-[#1B1F5C] px-3 py-2 text-white hover:bg-[#141747] transition-all"
                                title="Apply Filters"
                            >
                                <Filter className="h-4 w-4" />
                            </button>
                        </div>
                    </div>
                </div>

                {/* Student Sanctions Directory */}
                <div className="space-y-3">
                    {students.length === 0 ? (
                        <div className="rounded-2xl border border-slate-200 bg-white p-12 text-center">
                            <ShieldCheck className="mx-auto h-10 w-10 text-emerald-500" />
                            <h3 className="mt-3 text-sm font-bold text-slate-900">
                                No Matching Student Sanctions
                            </h3>
                            <p className="mt-1 text-xs text-slate-500 font-medium">
                                Try adjusting your course, year & section, or status filters.
                            </p>
                        </div>
                    ) : (
                        students.map((student) => {
                            const isExpanded = !!expandedStudents[student.student_id];
                            const selectedIds = selectedByStudent[student.student_id] ?? [];

                            return (
                                <div
                                    key={student.student_id}
                                    className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-xs"
                                >
                                    {/* Student Summary Row */}
                                    <div
                                        onClick={() => toggleExpand(student.student_id)}
                                        className="flex cursor-pointer flex-col justify-between gap-4 px-5 py-4 transition hover:bg-slate-50/80 sm:flex-row sm:items-center"
                                    >
                                        <div className="flex items-start gap-3 sm:items-center">
                                            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-[#1B1F5C] text-xs font-black text-white">
                                                {student.full_name
                                                    .split(' ')
                                                    .map((n) => n[0])
                                                    .slice(0, 2)
                                                    .join('')}
                                            </div>
                                            <div>
                                                <div className="flex flex-wrap items-center gap-2">
                                                    <span className="font-bold text-slate-900 text-sm">
                                                        {student.full_name}
                                                    </span>
                                                    <span className="rounded-md bg-slate-100 px-2 py-0.5 font-mono text-[11px] font-semibold text-slate-600">
                                                        {student.student_number}
                                                    </span>
                                                    <span className="rounded-md bg-[#1B1F5C]/10 px-2 py-0.5 text-[11px] font-bold text-[#1B1F5C]">
                                                        {student.degree} — {student.year_section}
                                                    </span>
                                                </div>

                                                <div className="mt-1.5 flex flex-wrap items-center gap-2 text-xs">
                                                    {student.pending_cash_count > 0 && (
                                                        <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 px-2.5 py-0.5 font-bold text-amber-800 text-[10px]">
                                                            <Banknote className="h-3 w-3" />
                                                            {student.pending_cash_count} Cash Pending
                                                        </span>
                                                    )}
                                                    {student.pending_serv_count > 0 && (
                                                        <span className="inline-flex items-center gap-1 rounded-full bg-purple-100 px-2.5 py-0.5 font-bold text-purple-800 text-[10px]">
                                                            <HandHelping className="h-3 w-3" />
                                                            {student.pending_serv_count} Comm. Service
                                                        </span>
                                                    )}
                                                    {student.pending_exc_count > 0 && (
                                                        <span className="inline-flex items-center gap-1 rounded-full bg-blue-100 px-2.5 py-0.5 font-bold text-blue-800 text-[10px]">
                                                            <FileCheck2 className="h-3 w-3" />
                                                            {student.pending_exc_count} Excuse Waiting
                                                        </span>
                                                    )}
                                                    {student.unsettled_count === 0 && (
                                                        <span className="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2.5 py-0.5 font-bold text-emerald-700 text-[10px]">
                                                            <CheckCircle2 className="h-3 w-3" />
                                                            All Clear
                                                        </span>
                                                    )}
                                                </div>
                                            </div>
                                        </div>

                                        <div className="flex items-center justify-between gap-4 sm:justify-end">
                                            <div className="text-right">
                                                <div className="text-[10px] uppercase font-bold text-slate-400">Unsettled Balance</div>
                                                <div
                                                    className={`text-base font-black ${
                                                        student.unsettled_balance > 0
                                                            ? 'text-rose-700'
                                                            : 'text-emerald-700'
                                                    }`}
                                                >
                                                    ₱{student.unsettled_balance.toFixed(2)}
                                                </div>
                                            </div>
                                            <div className="rounded-xl bg-slate-100 p-2 text-slate-600">
                                                {isExpanded ? (
                                                    <ChevronUp className="h-4 w-4" />
                                                ) : (
                                                    <ChevronDown className="h-4 w-4" />
                                                )}
                                            </div>
                                        </div>
                                    </div>

                                    {/* Expanded Infraction Ledger */}
                                    {isExpanded && (
                                        <div className="border-t border-slate-200 bg-slate-50/60 p-4 sm:p-5">
                                            {selectedIds.length > 0 && (
                                                <div className="mb-4 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-[#F5A623] bg-amber-50 px-4 py-3">
                                                    <span className="text-xs font-bold text-slate-800">
                                                        Selected {selectedIds.length} infraction(s) for{' '}
                                                        {student.full_name}
                                                    </span>
                                                    <div className="flex flex-wrap gap-2">
                                                        <button
                                                            type="button"
                                                            onClick={() => openCashModal(student, selectedIds)}
                                                            className="inline-flex items-center gap-1.5 rounded-xl bg-[#1B1F5C] px-3.5 py-2 text-xs font-bold text-white hover:bg-[#141747] transition-all"
                                                        >
                                                            <Receipt className="h-3.5 w-3.5 text-[#F5A623]" />
                                                            Verify Cash Payment (Log OR #)
                                                        </button>
                                                        <button
                                                            type="button"
                                                            onClick={() => openServiceModal(student, selectedIds)}
                                                            className="inline-flex items-center gap-1.5 rounded-xl bg-[#F5A623] px-3.5 py-2 text-xs font-bold text-[#1B1F5C] hover:bg-[#e0961c] transition-all"
                                                        >
                                                            <HandHelping className="h-3.5 w-3.5" />
                                                            Verify Comm. Service
                                                        </button>
                                                    </div>
                                                </div>
                                            )}

                                            <div className="overflow-x-auto rounded-xl border border-slate-200 bg-white shadow-2xs">
                                                <table className="min-w-full divide-y divide-slate-200 text-xs">
                                                    <thead className="bg-slate-100 text-left font-black uppercase text-slate-600 tracking-wider text-[10px]">
                                                        <tr>
                                                            <th className="w-10 px-3 py-3">
                                                                <input
                                                                    type="checkbox"
                                                                    onChange={() => selectAllOpenForStudent(student)}
                                                                    className="h-4 w-4 rounded-md border-slate-300 text-[#1B1F5C] focus:ring-[#1B1F5C]"
                                                                />
                                                            </th>
                                                            <th className="px-3 py-3">Event & Date</th>
                                                            <th className="px-3 py-3">Missed Checkpoint</th>
                                                            <th className="px-3 py-3">Fine</th>
                                                            <th className="px-3 py-3">Student Choice / Status</th>
                                                            <th className="px-3 py-3 text-right">Admin Verification</th>
                                                        </tr>
                                                    </thead>
                                                    <tbody className="divide-y divide-slate-200 font-medium">
                                                        {student.sanctions.map((s) => {
                                                            const isOpen =
                                                                s.status === 'unsettled' ||
                                                                s.status === 'pending_verification';

                                                            return (
                                                                <tr key={s.sanction_id} className="hover:bg-slate-50/50">
                                                                    <td className="px-3 py-3">
                                                                        {isOpen && (
                                                                            <input
                                                                                type="checkbox"
                                                                                checked={selectedIds.includes(
                                                                                    s.sanction_id
                                                                                )}
                                                                                onChange={() =>
                                                                                    toggleSanctionSelection(
                                                                                        student.student_id,
                                                                                        s.sanction_id
                                                                                    )
                                                                                }
                                                                                className="h-4 w-4 rounded-md border-slate-300 text-[#1B1F5C] focus:ring-[#1B1F5C]"
                                                                            />
                                                                        )}
                                                                    </td>
                                                                    <td className="px-3 py-3">
                                                                        <div className="font-bold text-slate-900">
                                                                            {s.event_title}
                                                                        </div>
                                                                        <div className="text-slate-500 text-[11px]">
                                                                            {s.event_date} • {s.slot_label}
                                                                        </div>
                                                                    </td>
                                                                    <td className="px-3 py-3">
                                                                        <span className="rounded-lg bg-indigo-50 border border-indigo-100 px-2.5 py-1 font-bold text-[#1B1F5C] capitalize text-[10px]">
                                                                            {s.infraction_type.replace(/_/g, ' ')}
                                                                        </span>
                                                                    </td>
                                                                    <td className="px-3 py-3 font-black text-[#1B1F5C]">
                                                                        ₱{s.fine_amount.toFixed(2)}
                                                                    </td>
                                                                    <td className="px-3 py-3">
                                                                        {s.status === 'settled' && (
                                                                            <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2.5 py-0.5 font-bold text-emerald-700 text-[10px]">
                                                                                <CheckCircle2 className="h-3 w-3" />
                                                                                {s.preferred_mode === 'cash'
                                                                                    ? `Paid (OR #${s.official_receipt_no})`
                                                                                    : `Service (${s.comm_service_hours} hrs)`}
                                                                            </span>
                                                                        )}
                                                                        {s.status === 'excused' && (
                                                                            <span className="inline-flex items-center gap-1 rounded-full bg-blue-50 px-2.5 py-0.5 font-bold text-blue-700 text-[10px]">
                                                                                <FileCheck2 className="h-3 w-3" />
                                                                                Excused
                                                                            </span>
                                                                        )}
                                                                        {isOpen && (
                                                                            <span className="inline-flex items-center gap-1 rounded-full bg-amber-50 px-2.5 py-0.5 font-bold text-amber-800 text-[10px]">
                                                                                <Clock className="h-3 w-3" />
                                                                                {s.preferred_mode === 'unselected'
                                                                                    ? 'Unselected'
                                                                                    : s.preferred_mode.replace('_', ' ')}
                                                                            </span>
                                                                        )}
                                                                    </td>
                                                                    <td className="px-3 py-3 text-right">
                                                                        {isOpen ? (
                                                                            <div className="flex flex-wrap justify-end gap-1.5">
                                                                                {s.preferred_mode === 'excuse' && (
                                                                                    <button
                                                                                        type="button"
                                                                                        onClick={() =>
                                                                                            openExcuseReviewModal(
                                                                                                student,
                                                                                                s
                                                                                            )
                                                                                        }
                                                                                        className="rounded-xl bg-blue-600 px-3 py-1.5 font-bold text-white hover:bg-blue-700 transition-all shadow-2xs"
                                                                                    >
                                                                                        Review Excuse Proof
                                                                                    </button>
                                                                                )}
                                                                                <button
                                                                                    type="button"
                                                                                    onClick={() =>
                                                                                        openCashModal(student, [
                                                                                            s.sanction_id,
                                                                                        ])
                                                                                    }
                                                                                    className="rounded-xl border border-slate-300 bg-white px-3 py-1.5 font-bold text-slate-700 hover:bg-slate-50 transition-all shadow-2xs"
                                                                                >
                                                                                    Verify Cash
                                                                                </button>
                                                                                <button
                                                                                    type="button"
                                                                                    onClick={() =>
                                                                                        openServiceModal(student, [
                                                                                            s.sanction_id,
                                                                                        ])
                                                                                    }
                                                                                    className="rounded-xl border border-slate-300 bg-white px-3 py-1.5 font-bold text-slate-700 hover:bg-slate-50 transition-all shadow-2xs"
                                                                                >
                                                                                    Verify Service
                                                                                </button>
                                                                            </div>
                                                                        ) : (
                                                                            <span className="text-slate-400 font-medium">
                                                                                {s.resolved_at ?? 'Completed'}
                                                                            </span>
                                                                        )}
                                                                    </td>
                                                                </tr>
                                                            );
                                                        })}
                                                    </tbody>
                                                </table>
                                            </div>
                                        </div>
                                    )}
                                </div>
                            );
                        })
                    )}
                </div>
            </div>

            {/* MODAL 1: CONFIGURE FINE RATE */}
            {rateModalOpen && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 p-4 backdrop-blur-xs">
                    <div className="w-full max-w-md overflow-hidden rounded-2xl bg-white shadow-xl">
                        <div className="flex items-center justify-between bg-[#1B1F5C] px-6 py-4 text-white">
                            <h3 className="text-sm font-black uppercase tracking-wider">Configure Sanction Fine Rate</h3>
                            <button type="button" onClick={() => setRateModalOpen(false)}>
                                <X className="h-5 w-5" />
                            </button>
                        </div>
                        <form onSubmit={submitRateUpdate} className="space-y-4 p-6">
                            <div>
                                <label className="block text-[10px] font-black uppercase tracking-wider text-slate-700">
                                    Fine per Missing Checkpoint (₱)
                                </label>
                                <input
                                    type="number"
                                    step="0.01"
                                    min="0"
                                    required
                                    value={rateForm.data.fine_per_log}
                                    onChange={(e) => rateForm.setData('fine_per_log', e.target.value)}
                                    className="mt-1.5 w-full rounded-xl border border-slate-300 px-3 py-2 text-xs sm:text-sm font-bold"
                                />
                            </div>
                            <label className="flex items-center gap-2 text-xs font-medium text-slate-700">
                                <input
                                    type="checkbox"
                                    checked={rateForm.data.apply_to_unsettled}
                                    onChange={(e) =>
                                        rateForm.setData('apply_to_unsettled', e.target.checked)
                                    }
                                    className="h-4 w-4 rounded-md border-slate-300 text-[#1B1F5C]"
                                />
                                Also update existing unsettled / pending sanctions to this rate
                            </label>
                            <div className="flex justify-end gap-2 border-t pt-4">
                                <button
                                    type="button"
                                    onClick={() => setRateModalOpen(false)}
                                    className="rounded-xl border px-4 py-2 text-xs font-bold"
                                >
                                    Cancel
                                </button>
                                <button
                                    type="submit"
                                    disabled={rateForm.processing}
                                    className="rounded-xl bg-[#1B1F5C] px-4 py-2 text-xs font-bold text-white"
                                >
                                    Save Rate
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}

            {/* MODAL 2: VERIFY F2F CASH PAYMENT (OR #) */}
            {cashModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 p-4 backdrop-blur-xs">
                    <div className="w-full max-w-md overflow-hidden rounded-2xl bg-white shadow-xl">
                        <div className="flex items-center justify-between bg-[#1B1F5C] px-6 py-4 text-white">
                            <div>
                                <h3 className="text-sm font-black uppercase tracking-wider">Verify Cash Payment</h3>
                                <p className="text-xs text-slate-200 font-medium">
                                    {cashModal.student.full_name} — Total: ₱{cashModal.total.toFixed(2)}
                                </p>
                            </div>
                            <button type="button" onClick={() => setCashModal(null)}>
                                <X className="h-5 w-5" />
                            </button>
                        </div>
                        <form onSubmit={submitCashVerification} className="space-y-4 p-6">
                            <div>
                                <label className="block text-[10px] font-black uppercase tracking-wider text-slate-700">
                                    Official Receipt (OR) Number *
                                </label>
                                <input
                                    type="text"
                                    required
                                    placeholder="e.g., OR-2026-10492"
                                    value={cashForm.data.official_receipt_no}
                                    onChange={(e) =>
                                        cashForm.setData('official_receipt_no', e.target.value)
                                    }
                                    className="mt-1.5 w-full rounded-xl border border-slate-300 px-3 py-2 text-xs sm:text-sm font-bold"
                                />
                            </div>
                            <div>
                                <label className="block text-[10px] font-black uppercase tracking-wider text-slate-700">
                                    Remarks (Optional)
                                </label>
                                <input
                                    type="text"
                                    placeholder="Paid at CCIS/SASC office"
                                    value={cashForm.data.admin_remarks}
                                    onChange={(e) => cashForm.setData('admin_remarks', e.target.value)}
                                    className="mt-1.5 w-full rounded-xl border border-slate-300 px-3 py-2 text-xs sm:text-sm"
                                />
                            </div>
                            <div className="flex justify-end gap-2 border-t pt-4">
                                <button
                                    type="button"
                                    onClick={() => setCashModal(null)}
                                    className="rounded-xl border px-4 py-2 text-xs font-bold"
                                >
                                    Cancel
                                </button>
                                <button
                                    type="submit"
                                    disabled={cashForm.processing}
                                    className="rounded-xl bg-[#1B1F5C] px-4 py-2 text-xs font-bold text-white"
                                >
                                    Confirm Payment & Settle
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}

            {/* MODAL 3: VERIFY COMMUNITY SERVICE */}
            {serviceModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 p-4 backdrop-blur-xs">
                    <div className="w-full max-w-md overflow-hidden rounded-2xl bg-white shadow-xl">
                        <div className="flex items-center justify-between bg-[#1B1F5C] px-6 py-4 text-white">
                            <div>
                                <h3 className="text-sm font-black uppercase tracking-wider">Verify Community Service</h3>
                                <p className="text-xs text-slate-200 font-medium">
                                    {serviceModal.student.full_name} ({serviceModal.count} infraction(s))
                                </p>
                            </div>
                            <button type="button" onClick={() => setServiceModal(null)}>
                                <X className="h-5 w-5" />
                            </button>
                        </div>
                        <form onSubmit={submitServiceVerification} className="space-y-4 p-6">
                            <div>
                                <label className="block text-[10px] font-black uppercase tracking-wider text-slate-700">
                                    Total Service Hours Rendered *
                                </label>
                                <input
                                    type="number"
                                    step="0.25"
                                    min="0.25"
                                    required
                                    placeholder="e.g., 1.0"
                                    value={serviceForm.data.comm_service_hours}
                                    onChange={(e) =>
                                        serviceForm.setData('comm_service_hours', e.target.value)
                                    }
                                    className="mt-1.5 w-full rounded-xl border border-slate-300 px-3 py-2 text-xs sm:text-sm font-bold"
                                />
                            </div>
                            <div>
                                <label className="block text-[10px] font-black uppercase tracking-wider text-slate-700">
                                    Task Completed / Duty Remarks *
                                </label>
                                <textarea
                                    rows={2}
                                    required
                                    placeholder="e.g., Assisted in CCIS lab organization and event setup"
                                    value={serviceForm.data.admin_remarks}
                                    onChange={(e) => serviceForm.setData('admin_remarks', e.target.value)}
                                    className="mt-1.5 w-full rounded-xl border border-slate-300 px-3 py-2 text-xs sm:text-sm"
                                />
                            </div>
                            <div className="flex justify-end gap-2 border-t pt-4">
                                <button
                                    type="button"
                                    onClick={() => setServiceModal(null)}
                                    className="rounded-xl border px-4 py-2 text-xs font-bold"
                                >
                                    Cancel
                                </button>
                                <button
                                    type="submit"
                                    disabled={serviceForm.processing}
                                    className="rounded-xl bg-[#F5A623] px-4 py-2 text-xs font-bold text-[#1B1F5C]"
                                >
                                    Confirm Service & Settle
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}

            {/* MODAL 4: REVIEW EXCUSE APPEAL & PROOF */}
            {excuseModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 p-4 backdrop-blur-xs">
                    <div className="w-full max-w-lg overflow-hidden rounded-2xl bg-white shadow-xl">
                        <div className="flex items-center justify-between bg-[#1B1F5C] px-6 py-4 text-white">
                            <div>
                                <h3 className="text-sm font-black uppercase tracking-wider">Review Student Excuse Appeal</h3>
                                <p className="text-xs text-slate-200 font-medium">
                                    {excuseModal.student.full_name} • {excuseModal.sanction.event_title}
                                </p>
                            </div>
                            <button type="button" onClick={() => setExcuseModal(null)}>
                                <X className="h-5 w-5" />
                            </button>
                        </div>
                        <form onSubmit={submitExcuseDecision} className="space-y-4 p-6">
                            <div className="rounded-2xl border border-slate-200 bg-slate-50 p-4 text-xs space-y-2">
                                <div className="font-bold text-[#1B1F5C]">
                                    Category: {excuseModal.sanction.excuse_category ?? 'General'}
                                </div>
                                <p className="whitespace-pre-wrap text-slate-700 font-medium">
                                    {excuseModal.sanction.student_notes}
                                </p>
                                {excuseModal.sanction.proof_url && (
                                    <a
                                        href={excuseModal.sanction.proof_url}
                                        target="_blank"
                                        rel="noreferrer"
                                        className="inline-flex items-center gap-1.5 rounded-xl bg-white px-3 py-2 font-bold text-[#1B1F5C] ring-1 ring-slate-300 hover:bg-slate-100 transition-all"
                                    >
                                        <ExternalLink className="h-3.5 w-3.5" />
                                        Open Attached Proof Document
                                    </a>
                                )}
                            </div>

                            <div className="grid grid-cols-2 gap-3">
                                <button
                                    type="button"
                                    onClick={() => excuseReviewForm.setData('decision', 'approve')}
                                    className={`flex items-center justify-center gap-1.5 rounded-2xl border p-3 text-xs font-extrabold transition-all ${
                                        excuseReviewForm.data.decision === 'approve'
                                            ? 'border-emerald-600 bg-emerald-50 text-emerald-700 shadow-2xs'
                                            : 'border-slate-200 text-slate-600'
                                    }`}
                                >
                                    <CheckCircle2 className="h-4 w-4" />
                                    Approve & Waive Fine
                                </button>
                                <button
                                    type="button"
                                    onClick={() => excuseReviewForm.setData('decision', 'reject')}
                                    className={`flex items-center justify-center gap-1.5 rounded-2xl border p-3 text-xs font-extrabold transition-all ${
                                        excuseReviewForm.data.decision === 'reject'
                                            ? 'border-rose-600 bg-rose-50 text-rose-700 shadow-2xs'
                                            : 'border-slate-200 text-slate-600'
                                    }`}
                                >
                                    <XCircle className="h-4 w-4" />
                                    Reject Excuse
                                </button>
                            </div>

                            <div>
                                <label className="block text-[10px] font-black uppercase tracking-wider text-slate-700">
                                    Admin Review Note (Visible to Student) *
                                </label>
                                <textarea
                                    rows={2}
                                    required
                                    placeholder={
                                        excuseReviewForm.data.decision === 'approve'
                                            ? 'e.g., Valid medical certificate verified.'
                                            : 'e.g., Attached letter lacks adviser signature; please settle fine or service.'
                                    }
                                    value={excuseReviewForm.data.admin_remarks}
                                    onChange={(e) =>
                                        excuseReviewForm.setData('admin_remarks', e.target.value)
                                    }
                                    className="mt-1.5 w-full rounded-xl border border-slate-300 px-3 py-2 text-xs sm:text-sm font-medium"
                                />
                            </div>

                            <div className="flex justify-end gap-2 border-t pt-4">
                                <button
                                    type="button"
                                    onClick={() => setExcuseModal(null)}
                                    className="rounded-xl border px-4 py-2 text-xs font-bold"
                                >
                                    Cancel
                                </button>
                                <button
                                    type="submit"
                                    disabled={excuseReviewForm.processing}
                                    className="rounded-xl bg-[#1B1F5C] px-4 py-2 text-xs font-bold text-white"
                                >
                                    Submit Review Decision
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}
        </>
    );
}

StudentSanctions.layout = (page: React.ReactNode) => <AdminLayout title="Student Sanctions Management">{page}</AdminLayout>;