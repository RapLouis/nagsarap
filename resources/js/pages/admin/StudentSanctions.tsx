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
    fine_amount: number | string;
    status: 'unsettled' | 'pending_verification' | 'settled' | 'excused';
    preferred_mode: 'unselected' | 'cash' | 'community_service' | 'excuse';
    excuse_category: string | null;
    student_notes: string | null;
    has_proof: boolean;
    proof_url: string | null;
    official_receipt_no: string | null;
    comm_service_hours: number | string | null;
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
    unsettled_balance: number | string;
    unsettled_count: number;
    pending_cash_count: number;
    pending_serv_count: number;
    pending_exc_count: number;
    sanctions: SanctionDetail[];
}

interface Props {
    students?: StudentRow[] | null;
    metrics?: {
        total_collectible?: number | string;
        total_collected?: number | string;
        total_service_hrs?: number | string;
        pending_cash?: number;
        pending_service?: number;
        pending_excuses?: number;
    } | null;
    fineRatePerLog?: number | string | null;
    filterOptions?: {
        degrees?: string[];
        sections?: string[];
    } | null;
    filters?: {
        search?: string;
        degree?: string;
        section?: string;
        status?: string;
        mode?: string;
    } | null;
}

export default function StudentSanctions(props: Props) {
    const students = Array.isArray(props.students) ? props.students : [];
    const metrics = {
        total_collectible: Number(props.metrics?.total_collectible ?? 0),
        total_collected: Number(props.metrics?.total_collected ?? 0),
        total_service_hrs: Number(props.metrics?.total_service_hrs ?? 0),
        pending_cash: Number(props.metrics?.pending_cash ?? 0),
        pending_service: Number(props.metrics?.pending_service ?? 0),
        pending_excuses: Number(props.metrics?.pending_excuses ?? 0),
    };
    const fineRatePerLog = Number(props.fineRatePerLog ?? 0);
    const filterOptions = {
        degrees: Array.isArray(props.filterOptions?.degrees) ? props.filterOptions!.degrees : [],
        sections: Array.isArray(props.filterOptions?.sections) ? props.filterOptions!.sections : [],
    };
    const filters = props.filters ?? {};

    const [search, setSearch] = useState(filters.search ?? '');
    const [degree, setDegree] = useState(filters.degree ?? 'all');
    const [section, setSection] = useState(filters.section ?? 'all');
    const [status, setStatus] = useState(filters.status ?? 'all');
    const [mode, setMode] = useState(filters.mode ?? 'all');

    const [expandedStudents, setExpandedStudents] = useState<Record<number, boolean>>({});
    const [selectedByStudent, setSelectedByStudent] = useState<Record<number, number[]>>({});

    const [rateModalOpen, setRateModalOpen] = useState(false);
    const [cashModal, setCashModal] = useState<{
        student: StudentRow;
        ids: number[];
        total: number;
    } | null>(null);
    const [serviceModal, setServiceModal] = useState<{
        student: StudentRow;
        ids: number[];
        count: number;
    } | null>(null);
    const [excuseModal, setExcuseModal] = useState<{
        student: StudentRow;
        sanction: SanctionDetail;
    } | null>(null);

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

    const applyFilters = (
        overrides?: Partial<{
            search: string;
            degree: string;
            section: string;
            status: string;
            mode: string;
        }>
    ) => {
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

    const handleResetFilters = () => {
        setSearch('');
        setDegree('all');
        setSection('all');
        setStatus('all');
        setMode('all');
        applyFilters({
            search: '',
            degree: 'all',
            section: 'all',
            status: 'all',
            mode: 'all',
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
        const openIds = (student.sanctions ?? [])
            .filter((s) => s.status === 'unsettled' || s.status === 'pending_verification')
            .map((s) => s.sanction_id);
        const current = selectedByStudent[student.student_id] ?? [];
        setSelectedByStudent((prev) => ({
            ...prev,
            [student.student_id]: current.length === openIds.length ? [] : openIds,
        }));
    };

    const openCashModal = (student: StudentRow, ids: number[]) => {
        const total = (student.sanctions ?? [])
            .filter((s) => ids.includes(s.sanction_id))
            .reduce((sum, s) => sum + Number(s.fine_amount ?? 0), 0);

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
                    setSelectedByStudent((prev) => ({
                        ...prev,
                        [cashModal.student.student_id]: [],
                    }));
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
                    setSelectedByStudent((prev) => ({
                        ...prev,
                        [serviceModal.student.student_id]: [],
                    }));
                }
                setServiceModal(null);
            },
        });
    };

    const submitExcuseDecision = (e: React.FormEvent) => {
        e.preventDefault();
        if (!excuseModal) return;
        excuseReviewForm.post(
            `/admin/sanctions/${excuseModal.sanction.sanction_id}/review-excuse`,
            {
                preserveScroll: true,
                onSuccess: () => setExcuseModal(null),
            }
        );
    };

    const activeScopeLabel =
        status === 'all' && mode === 'all'
            ? 'All Records'
            : status === 'pending_verification' && mode === 'cash'
              ? 'Cash Walk-ins'
              : status === 'pending_verification' && mode === 'community_service'
                ? 'Comm. Service'
                : status === 'pending_verification' && mode === 'excuse'
                  ? 'Excuse Appeals'
                  : 'Filtered View';

    return (
        <>
            <Head title="Student Sanctions Management" />

            <div className="min-h-screen space-y-4 bg-[#F5F6FA] p-3 font-sans text-gray-900 antialiased sm:p-5">
                {/* TOP HEADER BAR (Matching System Analytics Layout) */}
                <header className="flex flex-col justify-between gap-4 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs lg:flex-row lg:items-center lg:p-5">
                    <div className="space-y-1">
                        <div className="flex flex-wrap items-center gap-2.5">
                            <h1 className="text-xl font-black tracking-tight text-[#1B1F5C] sm:text-2xl">
                                Student Sanctions
                            </h1>
                            <span className="rounded-full border border-gray-200 bg-gray-50 px-2.5 py-0.5 text-[11px] font-bold text-gray-600">
                                {activeScopeLabel}
                            </span>
                        </div>
                        <p className="text-xs font-medium text-gray-500 sm:text-sm">
                            Verify F2F cash payments, log community service hours, and review submitted excuse proofs across 4 checkpoints
                        </p>
                    </div>

                    <div className="flex flex-wrap items-center gap-2.5">
                        {/* Segmented Quick-Filter Pill Control (Matches Period Selector) */}
                        <div
                            role="group"
                            aria-label="Quick queue views"
                            className="inline-flex flex-wrap items-center rounded-xl border border-gray-200 bg-[#F5F6FA] p-1"
                        >
                            <button
                                type="button"
                                onClick={handleResetFilters}
                                className={`rounded-lg px-3 py-1.5 text-xs font-bold transition-colors ${
                                    status === 'all' && mode === 'all'
                                        ? 'bg-[#1B1F5C] text-white shadow-2xs'
                                        : 'text-gray-600 hover:text-[#1B1F5C]'
                                }`}
                            >
                                All Records
                            </button>
                            <button
                                type="button"
                                onClick={() => {
                                    setStatus('pending_verification');
                                    setMode('all');
                                    applyFilters({ status: 'pending_verification', mode: 'all' });
                                }}
                                className={`rounded-lg px-3 py-1.5 text-xs font-bold transition-colors ${
                                    status === 'pending_verification' && mode === 'all'
                                        ? 'bg-[#1B1F5C] text-white shadow-2xs'
                                        : 'text-gray-600 hover:text-[#1B1F5C]'
                                }`}
                            >
                                Pending Queue
                            </button>
                            <button
                                type="button"
                                onClick={() => {
                                    setStatus('unsettled');
                                    setMode('all');
                                    applyFilters({ status: 'unsettled', mode: 'all' });
                                }}
                                className={`rounded-lg px-3 py-1.5 text-xs font-bold transition-colors ${
                                    status === 'unsettled'
                                        ? 'bg-[#1B1F5C] text-white shadow-2xs'
                                        : 'text-gray-600 hover:text-[#1B1F5C]'
                                }`}
                            >
                                Unsettled
                            </button>
                        </div>

                        {/* Secondary Outlined Action (Matches Export Report) */}
                        <button
                            type="button"
                            onClick={() => {
                                setStatus('settled');
                                setMode('all');
                                applyFilters({ status: 'settled', mode: 'all' });
                            }}
                            className="inline-flex min-h-[38px] items-center gap-1.5 rounded-xl border border-gray-200 bg-white px-3.5 py-2 text-xs font-bold text-gray-700 transition-colors hover:bg-gray-50 hover:text-[#1B1F5C]"
                        >
                            <Receipt className="h-3.5 w-3.5 text-gray-500" />
                            <span>Settled Ledger</span>
                        </button>

                        {/* Primary Navy CTA Button (Matches Manage Events) */}
                        <button
                            type="button"
                            onClick={() => {
                                rateForm.setData('fine_per_log', fineRatePerLog.toString());
                                setRateModalOpen(true);
                            }}
                            className="inline-flex min-h-[38px] items-center gap-1.5 rounded-xl bg-[#1B1F5C] px-4 py-2 text-xs font-bold text-white shadow-xs transition-colors hover:bg-[#131644]"
                        >
                            <Settings2 className="h-3.5 w-3.5 text-[#F5A623]" />
                            <span>Fine Rate: ₱{fineRatePerLog.toFixed(2)}</span>
                        </button>
                    </div>
                </header>

                {/* 4-COLUMN KPI CARDS ROW (Matching System Analytics Metric Cards) */}
                <section
                    aria-label="Sanctions overview metrics"
                    className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4"
                >
                    {/* KPI 1: Pending Cash Walk-ins */}
                    <button
                        type="button"
                        onClick={() => {
                            setStatus('pending_verification');
                            setMode('cash');
                            applyFilters({ status: 'pending_verification', mode: 'cash' });
                        }}
                        className={`flex flex-col justify-between rounded-2xl border bg-white p-5 text-left shadow-xs transition-colors hover:border-[#1B1F5C]/40 ${
                            status === 'pending_verification' && mode === 'cash'
                                ? 'border-[#1B1F5C] ring-1 ring-[#1B1F5C]'
                                : 'border-gray-200/80'
                        }`}
                    >
                        <div className="flex items-start justify-between gap-2">
                            <span className="text-[11px] font-bold uppercase tracking-wider text-gray-500">
                                Pending Cash Walk-ins
                            </span>
                            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 text-[#1B1F5C]">
                                <Banknote className="h-4 w-4" />
                            </span>
                        </div>
                        <div className="my-3 text-3xl font-black tracking-tight text-gray-900">
                            {metrics.pending_cash}
                        </div>
                        <div className="flex items-center justify-between gap-2 text-xs">
                            <span className="font-semibold text-gray-600">
                                Awaiting F2F payment & OR #
                            </span>
                            <span className="font-mono text-[11px] text-gray-400">Cash queue</span>
                        </div>
                    </button>

                    {/* KPI 2: Pending Comm. Service */}
                    <button
                        type="button"
                        onClick={() => {
                            setStatus('pending_verification');
                            setMode('community_service');
                            applyFilters({
                                status: 'pending_verification',
                                mode: 'community_service',
                            });
                        }}
                        className={`flex flex-col justify-between rounded-2xl border bg-white p-5 text-left shadow-xs transition-colors hover:border-emerald-500/40 ${
                            status === 'pending_verification' && mode === 'community_service'
                                ? 'border-emerald-600 ring-1 ring-emerald-600'
                                : 'border-gray-200/80'
                        }`}
                    >
                        <div className="flex items-start justify-between gap-2">
                            <span className="text-[11px] font-bold uppercase tracking-wider text-gray-500">
                                Pending Comm. Service
                            </span>
                            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-emerald-200 bg-emerald-50 text-emerald-600">
                                <HandHelping className="h-4 w-4" />
                            </span>
                        </div>
                        <div className="my-3 text-3xl font-black tracking-tight text-gray-900">
                            {metrics.pending_service}
                        </div>
                        <div className="flex items-center justify-between gap-2 text-xs">
                            <span className="font-semibold text-gray-600">
                                {metrics.total_service_hrs.toFixed(1)} hrs rendered total
                            </span>
                            <span className="font-mono text-[11px] text-gray-400">Duty logs</span>
                        </div>
                    </button>

                    {/* KPI 3: Excuses Waiting Approval */}
                    <button
                        type="button"
                        onClick={() => {
                            setStatus('pending_verification');
                            setMode('excuse');
                            applyFilters({ status: 'pending_verification', mode: 'excuse' });
                        }}
                        className={`flex flex-col justify-between rounded-2xl border bg-white p-5 text-left shadow-xs transition-colors hover:border-[#1B1F5C]/40 ${
                            status === 'pending_verification' && mode === 'excuse'
                                ? 'border-[#1B1F5C] ring-1 ring-[#1B1F5C]'
                                : 'border-gray-200/80'
                        }`}
                    >
                        <div className="flex items-start justify-between gap-2">
                            <span className="text-[11px] font-bold uppercase tracking-wider text-gray-500">
                                Excuses Waiting Approval
                            </span>
                            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 text-[#1B1F5C]">
                                <FileCheck2 className="h-4 w-4" />
                            </span>
                        </div>
                        <div className="my-3 text-3xl font-black tracking-tight text-gray-900">
                            {metrics.pending_excuses}
                        </div>
                        <div className="flex items-center justify-between gap-2 text-xs">
                            <span className="font-semibold text-gray-600">
                                Uploaded letters & proofs
                            </span>
                            <span className="font-mono text-[11px] text-gray-400">Appeals</span>
                        </div>
                    </button>

                    {/* KPI 4: Collectible vs. Collected */}
                    <div className="flex flex-col justify-between rounded-2xl border border-gray-200/80 bg-white p-5 shadow-xs">
                        <div className="flex items-start justify-between gap-2">
                            <span className="text-[11px] font-bold uppercase tracking-wider text-gray-500">
                                Collectible Balance
                            </span>
                            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-amber-200 bg-amber-50 text-[#B4730A]">
                                <Receipt className="h-4 w-4" />
                            </span>
                        </div>
                        <div className="my-3 text-3xl font-black tracking-tight text-gray-900">
                            ₱{metrics.total_collectible.toFixed(2)}
                        </div>
                        <div className="flex items-center justify-between gap-2 text-xs">
                            <span className="font-semibold text-emerald-700">
                                ₱{metrics.total_collected.toFixed(2)} collected
                            </span>
                            <span className="font-mono text-[11px] text-gray-400">
                                {students.length} student(s)
                            </span>
                        </div>
                    </div>
                </section>

                {/* FILTER & SEARCH PANEL CARD */}
                <section
                    aria-label="Filter student sanctions"
                    className="rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs sm:p-5"
                >
                    <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                        <div>
                            <h2 className="text-sm font-black text-[#1B1F5C]">
                                Sanctions Directory & Filters
                            </h2>
                            <p className="text-xs text-gray-500">
                                Filter student infraction ledgers by course, section, resolution mode, or verification status
                            </p>
                        </div>
                        {(search !== '' ||
                            degree !== 'all' ||
                            section !== 'all' ||
                            status !== 'all' ||
                            mode !== 'all') && (
                            <button
                                type="button"
                                onClick={handleResetFilters}
                                className="inline-flex items-center gap-1 rounded-lg border border-gray-200 bg-gray-50 px-2.5 py-1 text-xs font-bold text-gray-600 hover:bg-gray-100 hover:text-[#1B1F5C]"
                            >
                                <X className="h-3.5 w-3.5" />
                                <span>Clear Filters</span>
                            </button>
                        )}
                    </div>

                    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-6">
                        <div className="relative lg:col-span-2">
                            <Search className="pointer-events-none absolute top-1/2 left-3.5 h-4 w-4 -translate-y-1/2 text-gray-400" />
                            <input
                                type="text"
                                placeholder="Search Student ID or Name..."
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                onKeyDown={(e) => e.key === 'Enter' && applyFilters()}
                                className="min-h-[40px] w-full rounded-xl border border-gray-300 bg-white py-2 pr-3 pl-10 text-xs font-medium text-gray-900 placeholder:text-gray-400 focus:border-[#1B1F5C] focus:outline-none focus:ring-2 focus:ring-[#1B1F5C]/20 sm:text-sm"
                            />
                        </div>

                        <select
                            value={degree}
                            onChange={(e) => {
                                setDegree(e.target.value);
                                applyFilters({ degree: e.target.value });
                            }}
                            aria-label="Filter by course"
                            className="min-h-[40px] rounded-xl border border-gray-300 bg-white px-3 py-2 text-xs font-medium text-gray-700 focus:border-[#1B1F5C] focus:outline-none focus:ring-2 focus:ring-[#1B1F5C]/20 sm:text-sm"
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
                            aria-label="Filter by year and section"
                            className="min-h-[40px] rounded-xl border border-gray-300 bg-white px-3 py-2 text-xs font-medium text-gray-700 focus:border-[#1B1F5C] focus:outline-none focus:ring-2 focus:ring-[#1B1F5C]/20 sm:text-sm"
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
                            aria-label="Filter by resolution mode"
                            className="min-h-[40px] rounded-xl border border-gray-300 bg-white px-3 py-2 text-xs font-medium text-gray-700 focus:border-[#1B1F5C] focus:outline-none focus:ring-2 focus:ring-[#1B1F5C]/20 sm:text-sm"
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
                                aria-label="Filter by status"
                                className="min-h-[40px] w-full rounded-xl border border-gray-300 bg-white px-3 py-2 text-xs font-medium text-gray-700 focus:border-[#1B1F5C] focus:outline-none focus:ring-2 focus:ring-[#1B1F5C]/20 sm:text-sm"
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
                                className="inline-flex min-h-[40px] shrink-0 items-center justify-center rounded-xl bg-[#1B1F5C] px-3.5 py-2 text-white transition-colors hover:bg-[#131644]"
                                title="Apply Filters"
                                aria-label="Apply filters"
                            >
                                <Filter className="h-4 w-4" />
                            </button>
                        </div>
                    </div>
                </section>

                {/* STUDENT SANCTIONS DIRECTORY */}
                <main aria-label="Student sanctions list" className="space-y-3">
                    {students.length === 0 ? (
                        <div className="rounded-2xl border border-gray-200/80 bg-white p-14 text-center shadow-xs">
                            <div className="mx-auto flex h-11 w-11 items-center justify-center rounded-xl border border-emerald-200 bg-emerald-50 text-emerald-600">
                                <ShieldCheck className="h-5 w-5" />
                            </div>
                            <h3 className="mt-3 text-sm font-black text-gray-900">
                                No Matching Student Sanctions
                            </h3>
                            <p className="mt-1 text-xs font-medium text-gray-500">
                                Try adjusting your course, year & section, or status filters.
                            </p>
                        </div>
                    ) : (
                        students.map((student) => {
                            const isExpanded = !!expandedStudents[student.student_id];
                            const selectedIds = selectedByStudent[student.student_id] ?? [];
                            const unsettledBalance = Number(student.unsettled_balance ?? 0);
                            const initials = (student.full_name || 'ST')
                                .split(' ')
                                .filter(Boolean)
                                .map((n) => n[0])
                                .slice(0, 2)
                                .join('');

                            return (
                                <div
                                    key={student.student_id}
                                    className="overflow-hidden rounded-2xl border border-gray-200/80 bg-white shadow-xs transition-colors hover:border-gray-300"
                                >
                                    {/* Student Summary Row */}
                                    <div
                                        onClick={() => toggleExpand(student.student_id)}
                                        className="flex cursor-pointer flex-col justify-between gap-4 px-5 py-4 transition-colors hover:bg-[#F5F6FA]/60 sm:flex-row sm:items-center"
                                    >
                                        <div className="flex items-start gap-3.5 sm:items-center">
                                            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-[#1B1F5C] text-xs font-black text-white">
                                                {initials}
                                            </div>
                                            <div>
                                                <div className="flex flex-wrap items-center gap-2">
                                                    <span className="text-sm font-extrabold text-gray-900">
                                                        {student.full_name}
                                                    </span>
                                                    <span className="rounded-md border border-gray-200 bg-gray-50 px-2 py-0.5 font-mono text-[11px] font-semibold text-gray-600">
                                                        {student.student_number}
                                                    </span>
                                                    <span className="rounded-md border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 px-2 py-0.5 text-[11px] font-bold text-[#1B1F5C]">
                                                        {student.degree} — {student.year_section}
                                                    </span>
                                                </div>

                                                <div className="mt-1.5 flex flex-wrap items-center gap-2 text-xs">
                                                    {student.pending_cash_count > 0 && (
                                                        <span className="inline-flex items-center gap-1 rounded-full border border-amber-200 bg-amber-50 px-2.5 py-0.5 text-[10px] font-bold text-amber-800">
                                                            <Banknote className="h-3 w-3" />
                                                            {student.pending_cash_count} Cash Pending
                                                        </span>
                                                    )}
                                                    {student.pending_serv_count > 0 && (
                                                        <span className="inline-flex items-center gap-1 rounded-full border border-purple-200 bg-purple-50 px-2.5 py-0.5 text-[10px] font-bold text-purple-800">
                                                            <HandHelping className="h-3 w-3" />
                                                            {student.pending_serv_count} Comm. Service
                                                        </span>
                                                    )}
                                                    {student.pending_exc_count > 0 && (
                                                        <span className="inline-flex items-center gap-1 rounded-full border border-blue-200 bg-blue-50 px-2.5 py-0.5 text-[10px] font-bold text-blue-800">
                                                            <FileCheck2 className="h-3 w-3" />
                                                            {student.pending_exc_count} Excuse Waiting
                                                        </span>
                                                    )}
                                                    {student.unsettled_count === 0 && (
                                                        <span className="inline-flex items-center gap-1 rounded-full border border-emerald-200 bg-emerald-50 px-2.5 py-0.5 text-[10px] font-bold text-emerald-700">
                                                            <CheckCircle2 className="h-3 w-3" />
                                                            All Clear
                                                        </span>
                                                    )}
                                                </div>
                                            </div>
                                        </div>

                                        <div className="flex items-center justify-between gap-4 sm:justify-end">
                                            <div className="text-right">
                                                <div className="text-[10px] font-bold uppercase tracking-wider text-gray-400">
                                                    Unsettled Balance
                                                </div>
                                                <div
                                                    className={`text-base font-black ${
                                                        unsettledBalance > 0
                                                            ? 'text-rose-700'
                                                            : 'text-emerald-700'
                                                    }`}
                                                >
                                                    ₱{unsettledBalance.toFixed(2)}
                                                </div>
                                            </div>
                                            <div className="rounded-xl border border-gray-200 bg-[#F5F6FA] p-2 text-gray-600">
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
                                        <div className="border-t border-gray-100 bg-[#F5F6FA]/70 p-4 sm:p-5">
                                            {selectedIds.length > 0 && (
                                                <div className="mb-4 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-[#F5A623] bg-amber-50 px-4 py-3">
                                                    <span className="text-xs font-bold text-gray-800">
                                                        Selected {selectedIds.length} infraction(s) for{' '}
                                                        {student.full_name}
                                                    </span>
                                                    <div className="flex flex-wrap gap-2">
                                                        <button
                                                            type="button"
                                                            onClick={() =>
                                                                openCashModal(student, selectedIds)
                                                            }
                                                            className="inline-flex items-center gap-1.5 rounded-xl bg-[#1B1F5C] px-3.5 py-2 text-xs font-bold text-white transition-colors hover:bg-[#131644]"
                                                        >
                                                            <Receipt className="h-3.5 w-3.5 text-[#F5A623]" />
                                                            Verify Cash Payment (Log OR #)
                                                        </button>
                                                        <button
                                                            type="button"
                                                            onClick={() =>
                                                                openServiceModal(student, selectedIds)
                                                            }
                                                            className="inline-flex items-center gap-1.5 rounded-xl bg-[#F5A623] px-3.5 py-2 text-xs font-bold text-[#1B1F5C] transition-colors hover:bg-[#e0961c]"
                                                        >
                                                            <HandHelping className="h-3.5 w-3.5" />
                                                            Verify Comm. Service
                                                        </button>
                                                    </div>
                                                </div>
                                            )}

                                            <div className="overflow-x-auto rounded-xl border border-gray-200/80 bg-white shadow-2xs">
                                                <table className="min-w-full divide-y divide-gray-100 text-xs">
                                                    <thead className="bg-gray-50/80 text-left text-[10px] font-extrabold uppercase tracking-wider text-gray-500">
                                                        <tr>
                                                            <th className="w-10 px-4 py-3">
                                                                <input
                                                                    type="checkbox"
                                                                    onChange={() =>
                                                                        selectAllOpenForStudent(student)
                                                                    }
                                                                    aria-label={`Select all open sanctions for ${student.full_name}`}
                                                                    className="h-4 w-4 rounded-md border-gray-300 text-[#1B1F5C] focus:ring-[#1B1F5C]"
                                                                />
                                                            </th>
                                                            <th className="px-4 py-3">Event & Date</th>
                                                            <th className="px-4 py-3">
                                                                Missed Checkpoint
                                                            </th>
                                                            <th className="px-4 py-3">Fine</th>
                                                            <th className="px-4 py-3">
                                                                Student Choice / Status
                                                            </th>
                                                            <th className="px-4 py-3 text-right">
                                                                Admin Verification
                                                            </th>
                                                        </tr>
                                                    </thead>
                                                    <tbody className="divide-y divide-gray-100 font-medium">
                                                        {(student.sanctions ?? []).map((s) => {
                                                            const isOpen =
                                                                s.status === 'unsettled' ||
                                                                s.status === 'pending_verification';
                                                            const fineAmount = Number(
                                                                s.fine_amount ?? 0
                                                            );

                                                            return (
                                                                <tr
                                                                    key={s.sanction_id}
                                                                    className="transition-colors hover:bg-[#F5F6FA]/60"
                                                                >
                                                                    <td className="px-4 py-3">
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
                                                                                className="h-4 w-4 rounded-md border-gray-300 text-[#1B1F5C] focus:ring-[#1B1F5C]"
                                                                            />
                                                                        )}
                                                                    </td>
                                                                    <td className="px-4 py-3">
                                                                        <div className="font-bold text-gray-900">
                                                                            {s.event_title ??
                                                                                'Deleted Event'}
                                                                        </div>
                                                                        <div className="text-[11px] text-gray-500">
                                                                            {s.event_date}
                                                                            {s.slot_label
                                                                                ? ` • ${s.slot_label}`
                                                                                : ''}
                                                                        </div>
                                                                    </td>
                                                                    <td className="px-4 py-3">
                                                                        <span className="rounded-lg border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 px-2.5 py-1 text-[10px] font-bold text-[#1B1F5C] capitalize">
                                                                            {(
                                                                                s.infraction_type ??
                                                                                ''
                                                                            ).replace(/_/g, ' ')}
                                                                        </span>
                                                                    </td>
                                                                    <td className="px-4 py-3 font-black text-[#1B1F5C]">
                                                                        ₱{fineAmount.toFixed(2)}
                                                                    </td>
                                                                    <td className="px-4 py-3">
                                                                        {s.status === 'settled' && (
                                                                            <span className="inline-flex items-center gap-1 rounded-full border border-emerald-200 bg-emerald-50 px-2.5 py-0.5 text-[10px] font-bold text-emerald-700">
                                                                                <CheckCircle2 className="h-3 w-3" />
                                                                                {s.preferred_mode ===
                                                                                'cash'
                                                                                    ? `Paid (OR #${s.official_receipt_no})`
                                                                                    : `Service (${s.comm_service_hours} hrs)`}
                                                                            </span>
                                                                        )}
                                                                        {s.status === 'excused' && (
                                                                            <span className="inline-flex items-center gap-1 rounded-full border border-blue-200 bg-blue-50 px-2.5 py-0.5 text-[10px] font-bold text-blue-700">
                                                                                <FileCheck2 className="h-3 w-3" />
                                                                                Excused
                                                                            </span>
                                                                        )}
                                                                        {isOpen && (
                                                                            <span className="inline-flex items-center gap-1 rounded-full border border-amber-200 bg-amber-50 px-2.5 py-0.5 text-[10px] font-bold text-amber-800">
                                                                                <Clock className="h-3 w-3" />
                                                                                {s.preferred_mode ===
                                                                                'unselected'
                                                                                    ? 'Unselected'
                                                                                    : (
                                                                                          s.preferred_mode ??
                                                                                          ''
                                                                                      ).replace(
                                                                                          '_',
                                                                                          ' '
                                                                                      )}
                                                                            </span>
                                                                        )}
                                                                    </td>
                                                                    <td className="px-4 py-3 text-right">
                                                                        {isOpen ? (
                                                                            <div className="flex flex-wrap justify-end gap-1.5">
                                                                                {s.preferred_mode ===
                                                                                    'excuse' && (
                                                                                    <button
                                                                                        type="button"
                                                                                        onClick={() =>
                                                                                            openExcuseReviewModal(
                                                                                                student,
                                                                                                s
                                                                                            )
                                                                                        }
                                                                                        className="rounded-xl bg-blue-600 px-3 py-1.5 font-bold text-white shadow-2xs transition-colors hover:bg-blue-700"
                                                                                    >
                                                                                        Review Excuse Proof
                                                                                    </button>
                                                                                )}
                                                                                <button
                                                                                    type="button"
                                                                                    onClick={() =>
                                                                                        openCashModal(
                                                                                            student,
                                                                                            [
                                                                                                s.sanction_id,
                                                                                            ]
                                                                                        )
                                                                                    }
                                                                                    className="rounded-xl border border-gray-200 bg-white px-3 py-1.5 font-bold text-gray-700 shadow-2xs transition-colors hover:bg-gray-50 hover:text-[#1B1F5C]"
                                                                                >
                                                                                    Verify Cash
                                                                                </button>
                                                                                <button
                                                                                    type="button"
                                                                                    onClick={() =>
                                                                                        openServiceModal(
                                                                                            student,
                                                                                            [
                                                                                                s.sanction_id,
                                                                                            ]
                                                                                        )
                                                                                    }
                                                                                    className="rounded-xl border border-gray-200 bg-white px-3 py-1.5 font-bold text-gray-700 shadow-2xs transition-colors hover:bg-gray-50 hover:text-[#1B1F5C]"
                                                                                >
                                                                                    Verify Service
                                                                                </button>
                                                                            </div>
                                                                        ) : (
                                                                            <span className="font-medium text-gray-400">
                                                                                {s.resolved_at ??
                                                                                    'Completed'}
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
                </main>
            </div>

            {/* MODAL 1: CONFIGURE FINE RATE */}
            {rateModalOpen && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/60 p-4 backdrop-blur-xs">
                    <div className="w-full max-w-md overflow-hidden rounded-2xl bg-white shadow-xl">
                        <div className="flex items-center justify-between bg-[#1B1F5C] px-6 py-4 text-white">
                            <h3 className="text-sm font-black uppercase tracking-wider">
                                Configure Sanction Fine Rate
                            </h3>
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
                                    className="mt-1.5 w-full rounded-xl border border-slate-300 px-3 py-2 text-xs font-bold sm:text-sm"
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
                                <h3 className="text-sm font-black uppercase tracking-wider">
                                    Verify Cash Payment
                                </h3>
                                <p className="text-xs font-medium text-slate-200">
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
                                    className="mt-1.5 w-full rounded-xl border border-slate-300 px-3 py-2 text-xs font-bold sm:text-sm"
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
                                <h3 className="text-sm font-black uppercase tracking-wider">
                                    Verify Community Service
                                </h3>
                                <p className="text-xs font-medium text-slate-200">
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
                                    className="mt-1.5 w-full rounded-xl border border-slate-300 px-3 py-2 text-xs font-bold sm:text-sm"
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
                                    onChange={(e) =>
                                        serviceForm.setData('admin_remarks', e.target.value)
                                    }
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
                                <h3 className="text-sm font-black uppercase tracking-wider">
                                    Review Student Excuse Appeal
                                </h3>
                                <p className="text-xs font-medium text-slate-200">
                                    {excuseModal.student.full_name} • {excuseModal.sanction.event_title}
                                </p>
                            </div>
                            <button type="button" onClick={() => setExcuseModal(null)}>
                                <X className="h-5 w-5" />
                            </button>
                        </div>
                        <form onSubmit={submitExcuseDecision} className="space-y-4 p-6">
                            <div className="space-y-2 rounded-2xl border border-slate-200 bg-slate-50 p-4 text-xs">
                                <div className="font-bold text-[#1B1F5C]">
                                    Category: {excuseModal.sanction.excuse_category ?? 'General'}
                                </div>
                                <p className="whitespace-pre-wrap font-medium text-slate-700">
                                    {excuseModal.sanction.student_notes}
                                </p>
                                {excuseModal.sanction.proof_url && (
                                    <a
                                        href={excuseModal.sanction.proof_url}
                                        target="_blank"
                                        rel="noreferrer"
                                        className="inline-flex items-center gap-1.5 rounded-xl bg-white px-3 py-2 font-bold text-[#1B1F5C] ring-1 ring-slate-300 transition-all hover:bg-slate-100"
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
                                    className="mt-1.5 w-full rounded-xl border border-slate-300 px-3 py-2 text-xs font-medium sm:text-sm"
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

StudentSanctions.layout = (page: React.ReactNode) => (
    <AdminLayout title="Student Sanctions Management">{page}</AdminLayout>
);