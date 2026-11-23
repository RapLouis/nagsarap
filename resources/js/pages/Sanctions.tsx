import React, { useState, useMemo } from 'react';
import { Head, router, useForm } from '@inertiajs/react';
import AppLayout from '@/layouts/app-layout';
import {
    AlertTriangle,
    Banknote,
    CheckCircle2,
    Clock,
    FileCheck2,
    FileText,
    HandHelping,
    History,
    Image as ImageIcon,
    Info,
    Receipt,
    ShieldCheck,
    Upload,
    X,
} from 'lucide-react';

interface SanctionItem {
    sanction_id: number;
    event_id: number;
    event_title: string;
    event_date: string;
    slot_index: number;
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

interface AttendanceLogItem {
    attendance_id: number;
    event_title: string;
    event_date: string;
    slot_index: number;
    type: 'in' | 'out';
    checkpoint_key?: string;
    logged_at: string;
}

interface Props {
    student: {
        student_id: number;
        first_name: string;
        last_name: string;
        degree: string;
        year_section: string;
    };
    sanctions: SanctionItem[];
    attendanceLogs: AttendanceLogItem[];
    fineRatePerLog: number;
    summary: {
        unsettled_balance: number;
        active_count: number;
        missing_morning_in: number;
        missing_morning_out: number;
        missing_aft_in: number;
        missing_aft_out: number;
        is_cleared: boolean;
        clearance_status: string;
    };
}

export default function Sanctions({
    sanctions = [],
    attendanceLogs = [],
    fineRatePerLog = 0,
    summary,
}: Props) {
    const [activeTab, setActiveTab] = useState<'active' | 'resolved' | 'logs'>('active');
    const [selectedIds, setSelectedIds] = useState<number[]>([]);
    const [submittingMode, setSubmittingMode] = useState(false);

    // Excuse Modal State
    const [excuseTarget, setExcuseTarget] = useState<SanctionItem | null>(null);
    const [previewUrl, setPreviewUrl] = useState<string | null>(null);

    const excuseForm = useForm<{
        excuse_category: string;
        student_notes: string;
        excuse_proof: File | null;
    }>({
        excuse_category: 'Medical / Illness',
        student_notes: '',
        excuse_proof: null,
    });

    const activeSanctions = useMemo(
        () => sanctions.filter((s) => s.status === 'unsettled' || s.status === 'pending_verification'),
        [sanctions]
    );

    const resolvedSanctions = useMemo(
        () => sanctions.filter((s) => s.status === 'settled' || s.status === 'excused'),
        [sanctions]
    );

    const selectedTotal = useMemo(
        () =>
            activeSanctions
                .filter((s) => selectedIds.includes(s.sanction_id))
                .reduce((acc, s) => acc + s.fine_amount, 0),
        [activeSanctions, selectedIds]
    );

    const toggleSelectAll = () => {
        if (selectedIds.length === activeSanctions.length) {
            setSelectedIds([]);
        } else {
            setSelectedIds(activeSanctions.map((s) => s.sanction_id));
        }
    };

    const toggleSelectOne = (id: number) => {
        setSelectedIds((prev) =>
            prev.includes(id) ? prev.filter((item) => item !== id) : [...prev, id]
        );
    };

    const handleDeclareMode = (mode: 'cash' | 'community_service', idsOverride?: number[]) => {
        const targetIds = idsOverride ?? selectedIds;
        if (targetIds.length === 0) return;

        setSubmittingMode(true);
        router.post(
            '/sanctions/declare',
            {
                sanction_ids: targetIds,
                preferred_mode: mode,
            },
            {
                preserveScroll: true,
                onSuccess: () => {
                    setSelectedIds([]);
                },
                onFinish: () => setSubmittingMode(false),
            }
        );
    };

    const openExcuseModal = (sanction: SanctionItem) => {
        setExcuseTarget(sanction);
        setPreviewUrl(null);
        excuseForm.reset();
        excuseForm.clearErrors();
    };

    const closeExcuseModal = () => {
        setExcuseTarget(null);
        if (previewUrl) URL.revokeObjectURL(previewUrl);
        setPreviewUrl(null);
    };

    const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0] ?? null;
        excuseForm.setData('excuse_proof', file);
        if (previewUrl) URL.revokeObjectURL(previewUrl);
        if (file && file.type.startsWith('image/')) {
            setPreviewUrl(URL.createObjectURL(file));
        } else {
            setPreviewUrl(null);
        }
    };

    const handleExcuseSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        if (!excuseTarget) return;

        excuseForm.post(`/sanctions/${excuseTarget.sanction_id}/excuse`, {
            forceFormData: true,
            preserveScroll: true,
            onSuccess: () => {
                closeExcuseModal();
            },
        });
    };

    const renderStatusBadge = (s: SanctionItem) => {
        if (s.status === 'settled' && s.preferred_mode === 'cash') {
            return (
                <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-semibold text-emerald-700 ring-1 ring-emerald-200">
                    <Receipt className="h-3.5 w-3.5" />
                    Paid Cash {s.official_receipt_no ? `(OR #${s.official_receipt_no})` : ''}
                </span>
            );
        }
        if (s.status === 'settled' && s.preferred_mode === 'community_service') {
            return (
                <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-semibold text-emerald-700 ring-1 ring-emerald-200">
                    <HandHelping className="h-3.5 w-3.5" />
                    Service Completed ({s.comm_service_hours ?? 0} hrs)
                </span>
            );
        }
        if (s.status === 'excused') {
            return (
                <span className="inline-flex items-center gap-1.5 rounded-full bg-blue-50 px-2.5 py-1 text-xs font-semibold text-blue-700 ring-1 ring-blue-200">
                    <FileCheck2 className="h-3.5 w-3.5" />
                    Excused (Waived)
                </span>
            );
        }
        if (s.status === 'pending_verification') {
            const labelMap: Record<string, string> = {
                cash: 'Pending F2F Cash Payment',
                community_service: 'Pending Comm. Service',
                excuse: 'Excuse Under SASC Review',
            };
            return (
                <span className="inline-flex items-center gap-1.5 rounded-full bg-amber-50 px-2.5 py-1 text-xs font-semibold text-amber-800 ring-1 ring-amber-300">
                    <Clock className="h-3.5 w-3.5" />
                    {labelMap[s.preferred_mode] ?? 'Pending Verification'}
                </span>
            );
        }
        return (
            <span className="inline-flex items-center gap-1.5 rounded-full bg-rose-50 px-2.5 py-1 text-xs font-semibold text-rose-700 ring-1 ring-rose-200">
                <AlertTriangle className="h-3.5 w-3.5" />
                Unsettled — Action Required
            </span>
        );
    };

    return (
        <>
            <Head title="Sanctions & Compliance | 4ttend Attendance System" />

            <div className="p-4 sm:p-8 font-sans text-gray-900 antialiased bg-[#F5F6FA] min-h-screen space-y-6">
                {/* Header */}
                <div className="flex flex-col justify-between gap-4 bg-white p-5 rounded-2xl border border-gray-200/80 shadow-xs sm:flex-row sm:items-center">
                    <div>
                        <h1 className="text-xl sm:text-2xl font-black tracking-tight text-[#1B1F5C]">
                            Sanctions & Attendance Compliance
                        </h1>
                        <p className="mt-1 text-xs text-gray-500 font-medium">
                            Review missed 4-checkpoint logs (₱{fineRatePerLog.toFixed(2)} per missing checkpoint),
                            declare settlement options, or submit excuse appeals.
                        </p>
                    </div>
                </div>

                {/* Compliance Summary KPI Cards */}
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
                    {/* Card 1: Unsettled Balance */}
                    <div className="rounded-2xl border border-gray-200/80 bg-white p-5 shadow-xs">
                        <div className="flex items-center justify-between">
                            <span className="text-[10px] font-extrabold uppercase tracking-wider text-gray-500">
                                Unsettled Fine Balance
                            </span>
                            <div className="rounded-xl bg-[#1B1F5C]/10 p-2.5 text-[#1B1F5C]">
                                <Banknote className="h-5 w-5" />
                            </div>
                        </div>
                        <div className="mt-3 flex items-baseline gap-2">
                            <span className="text-2xl font-black text-[#1B1F5C]">
                                ₱{summary.unsettled_balance.toFixed(2)}
                            </span>
                            <span className="text-xs text-gray-500 font-bold">
                                ({summary.active_count} active infraction{summary.active_count === 1 ? '' : 's'})
                            </span>
                        </div>
                        <p className="mt-1 text-xs text-gray-500 font-medium">
                            Settle via F2F Cash, Community Service, or Approved Excuse
                        </p>
                    </div>

                    {/* Card 2: 4-Checkpoint Breakdown */}
                    <div className="rounded-2xl border border-gray-200/80 bg-white p-5 shadow-xs">
                        <div className="flex items-center justify-between">
                            <span className="text-[10px] font-extrabold uppercase tracking-wider text-gray-500">
                                Missed Checkpoints Breakdown
                            </span>
                            <div className="rounded-xl bg-[#F5A623]/15 p-2.5 text-[#B4730A]">
                                <Clock className="h-5 w-5" />
                            </div>
                        </div>
                        <div className="mt-3 grid grid-cols-2 gap-2 text-xs">
                            <div className="bg-gray-50 p-2 rounded-xl border border-gray-100">
                                <span className="font-black text-gray-900 text-sm">{summary.missing_morning_in}</span>
                                <span className="block text-[10px] text-gray-500 font-bold uppercase">Morn. In</span>
                            </div>
                            <div className="bg-gray-50 p-2 rounded-xl border border-gray-100">
                                <span className="font-black text-gray-900 text-sm">{summary.missing_morning_out}</span>
                                <span className="block text-[10px] text-gray-500 font-bold uppercase">Morn. Out</span>
                            </div>
                            <div className="bg-gray-50 p-2 rounded-xl border border-gray-100">
                                <span className="font-black text-gray-900 text-sm">{summary.missing_aft_in}</span>
                                <span className="block text-[10px] text-gray-500 font-bold uppercase">Aft. In</span>
                            </div>
                            <div className="bg-gray-50 p-2 rounded-xl border border-gray-100">
                                <span className="font-black text-gray-900 text-sm">{summary.missing_aft_out}</span>
                                <span className="block text-[10px] text-gray-500 font-bold uppercase">Aft. Out</span>
                            </div>
                        </div>
                    </div>

                    {/* Card 3: Clearance Status */}
                    <div className="rounded-2xl border border-gray-200/80 bg-white p-5 shadow-xs">
                        <div className="flex items-center justify-between">
                            <span className="text-[10px] font-extrabold uppercase tracking-wider text-gray-500">
                                SASC Clearance Status
                            </span>
                            <div
                                className={`rounded-xl p-2.5 ${
                                    summary.is_cleared
                                        ? 'bg-emerald-100 text-emerald-700'
                                        : 'bg-rose-100 text-rose-700'
                                }`}
                            >
                                <ShieldCheck className="h-5 w-5" />
                            </div>
                        </div>
                        <div className="mt-3">
                            {summary.is_cleared ? (
                                <span className="inline-flex items-center gap-1.5 text-base font-black text-emerald-700">
                                    <CheckCircle2 className="h-5 w-5" />
                                    Cleared — No Holds
                                </span>
                            ) : (
                                <span className="inline-flex items-center gap-1.5 text-base font-black text-rose-700">
                                    <AlertTriangle className="h-5 w-5" />
                                    Clearance Hold Active
                                </span>
                            )}
                        </div>
                        <p className="mt-1 text-xs text-gray-500 font-medium">
                            {summary.is_cleared
                                ? 'Eligible for semester SASC clearance sign-off.'
                                : 'Clearance lifts automatically once balance reaches ₱0.00.'}
                        </p>
                    </div>
                </div>

                {/* Navigation Tabs */}
                <div className="border-b border-gray-200">
                    <nav className="-mb-px flex space-x-6">
                        <button
                            type="button"
                            onClick={() => setActiveTab('active')}
                            className={`flex items-center gap-2 border-b-2 py-3 text-sm font-bold transition-colors ${
                                activeTab === 'active'
                                    ? 'border-[#1B1F5C] text-[#1B1F5C]'
                                    : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700'
                            }`}
                        >
                            Active Sanctions
                            <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-bold text-gray-700">
                                {activeSanctions.length}
                            </span>
                        </button>

                        <button
                            type="button"
                            onClick={() => setActiveTab('resolved')}
                            className={`flex items-center gap-2 border-b-2 py-3 text-sm font-bold transition-colors ${
                                activeTab === 'resolved'
                                    ? 'border-[#1B1F5C] text-[#1B1F5C]'
                                    : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700'
                            }`}
                        >
                            Settled & Excused
                            <span className="rounded-full bg-gray-100 px-2 py-0.5 text-xs font-bold text-gray-700">
                                {resolvedSanctions.length}
                            </span>
                        </button>

                        <button
                            type="button"
                            onClick={() => setActiveTab('logs')}
                            className={`flex items-center gap-2 border-b-2 py-3 text-sm font-bold transition-colors ${
                                activeTab === 'logs'
                                    ? 'border-[#1B1F5C] text-[#1B1F5C]'
                                    : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700'
                            }`}
                        >
                            <History className="h-4 w-4" />
                            Attendance Logs ({attendanceLogs.length})
                        </button>
                    </nav>
                </div>

                {/* TAB 1: ACTIVE SANCTIONS */}
                {activeTab === 'active' && (
                    <div className="space-y-4">
                        {selectedIds.length > 0 && (
                            <div className="flex flex-col justify-between gap-3 rounded-2xl border border-[#F5A623] bg-amber-50/80 p-4 sm:flex-row sm:items-center">
                                <div className="text-xs font-bold text-gray-800">
                                    Selected{' '}
                                    <span className="font-black text-[#1B1F5C]">
                                        {selectedIds.length} infraction(s)
                                    </span>{' '}
                                    — Total Fine:{' '}
                                    <span className="font-black text-[#1B1F5C]">
                                        ₱{selectedTotal.toFixed(2)}
                                    </span>
                                </div>
                                <div className="flex flex-wrap items-center gap-2">
                                    <button
                                        type="button"
                                        disabled={submittingMode}
                                        onClick={() => handleDeclareMode('cash')}
                                        className="inline-flex items-center gap-1.5 rounded-xl bg-[#1B1F5C] px-3.5 py-2 text-xs font-bold text-white shadow-xs hover:bg-[#141747] disabled:opacity-50"
                                    >
                                        <Banknote className="h-4 w-4 text-[#F5A623]" />
                                        Declare Cash Payment (F2F)
                                    </button>
                                    <button
                                        type="button"
                                        disabled={submittingMode}
                                        onClick={() => handleDeclareMode('community_service')}
                                        className="inline-flex items-center gap-1.5 rounded-xl bg-[#F5A623] px-3.5 py-2 text-xs font-bold text-[#1B1F5C] shadow-xs hover:bg-[#e0961c] disabled:opacity-50"
                                    >
                                        <HandHelping className="h-4 w-4" />
                                        Declare Community Service
                                    </button>
                                </div>
                            </div>
                        )}

                        {activeSanctions.length === 0 ? (
                            <div className="rounded-2xl border border-gray-200/80 bg-white p-12 text-center">
                                <CheckCircle2 className="mx-auto h-10 w-10 text-emerald-500" />
                                <h3 className="mt-3 text-sm font-bold text-gray-900">
                                    No Active Sanctions
                                </h3>
                                <p className="mt-1 text-xs text-gray-500 font-medium">
                                    You have zero unsettled or pending attendance infractions.
                                </p>
                            </div>
                        ) : (
                            <div className="overflow-hidden rounded-2xl border border-gray-200/80 bg-white shadow-xs">
                                <div className="overflow-x-auto">
                                    <table className="min-w-full divide-y divide-gray-200 text-xs sm:text-sm">
                                        <thead className="bg-gray-50 text-left text-[10px] font-black uppercase tracking-wider text-gray-500">
                                            <tr>
                                                <th className="w-10 px-4 py-3.5">
                                                    <input
                                                        type="checkbox"
                                                        checked={
                                                            activeSanctions.length > 0 &&
                                                            selectedIds.length === activeSanctions.length
                                                        }
                                                        onChange={toggleSelectAll}
                                                        className="h-4 w-4 rounded-md border-gray-300 text-[#1B1F5C] focus:ring-[#1B1F5C]"
                                                    />
                                                </th>
                                                <th className="px-4 py-3.5">Event & Date</th>
                                                <th className="px-4 py-3.5">Slot & Missing Checkpoint</th>
                                                <th className="px-4 py-3.5">Fine</th>
                                                <th className="px-4 py-3.5">Status</th>
                                                <th className="px-4 py-3.5 text-right">Resolution Action</th>
                                            </tr>
                                        </thead>
                                        <tbody className="divide-y divide-gray-200 font-medium">
                                            {activeSanctions.map((item) => (
                                                <tr key={item.sanction_id} className="hover:bg-gray-50/70">
                                                    <td className="px-4 py-4">
                                                        <input
                                                            type="checkbox"
                                                            checked={selectedIds.includes(item.sanction_id)}
                                                            onChange={() => toggleSelectOne(item.sanction_id)}
                                                            className="h-4 w-4 rounded-md border-gray-300 text-[#1B1F5C] focus:ring-[#1B1F5C]"
                                                        />
                                                    </td>
                                                    <td className="px-4 py-4">
                                                        <div className="font-bold text-gray-900">
                                                            {item.event_title}
                                                        </div>
                                                        <div className="text-xs text-gray-500 font-normal">
                                                            {item.event_date}
                                                        </div>
                                                        {item.admin_remarks && (
                                                            <div className="mt-1.5 inline-flex items-center gap-1 rounded-md bg-rose-50 px-2 py-0.5 text-xs text-rose-700 font-semibold">
                                                                <Info className="h-3 w-3 shrink-0" />
                                                                {item.admin_remarks}
                                                            </div>
                                                        )}
                                                    </td>
                                                    <td className="px-4 py-4">
                                                        <div className="font-bold text-gray-800">
                                                            {item.slot_label ?? `Slot ${item.slot_index + 1}`}
                                                        </div>
                                                        <span className="mt-1 inline-block rounded-lg bg-indigo-50 border border-indigo-100 px-2 py-0.5 text-[10px] font-extrabold text-[#1B1F5C] capitalize">
                                                            {item.infraction_type.replace(/_/g, ' ')}
                                                        </span>
                                                    </td>
                                                    <td className="px-4 py-4 font-black text-[#1B1F5C]">
                                                        ₱{item.fine_amount.toFixed(2)}
                                                    </td>
                                                    <td className="px-4 py-4">{renderStatusBadge(item)}</td>
                                                    <td className="px-4 py-4 text-right">
                                                        <div className="flex flex-wrap justify-end gap-1.5">
                                                            <button
                                                                type="button"
                                                                onClick={() =>
                                                                    handleDeclareMode('cash', [item.sanction_id])
                                                                }
                                                                className="rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-bold text-gray-700 hover:bg-gray-50 transition-all shadow-2xs"
                                                            >
                                                                Pay Cash
                                                            </button>
                                                            <button
                                                                type="button"
                                                                onClick={() =>
                                                                    handleDeclareMode('community_service', [
                                                                        item.sanction_id,
                                                                    ])
                                                                }
                                                                className="rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-bold text-gray-700 hover:bg-gray-50 transition-all shadow-2xs"
                                                            >
                                                                Comm. Service
                                                            </button>
                                                            <button
                                                                type="button"
                                                                onClick={() => openExcuseModal(item)}
                                                                className="rounded-xl bg-[#1B1F5C]/10 px-3 py-1.5 text-xs font-bold text-[#1B1F5C] hover:bg-[#1B1F5C]/20 transition-all"
                                                            >
                                                                {item.preferred_mode === 'excuse'
                                                                    ? 'Update Excuse'
                                                                    : 'Submit Excuse'}
                                                            </button>
                                                        </div>
                                                    </td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                            </div>
                        )}
                    </div>
                )}

                {/* TAB 2: SETTLED & EXCUSED */}
                {activeTab === 'resolved' && (
                    <div className="overflow-hidden rounded-2xl border border-gray-200/80 bg-white shadow-xs">
                        {resolvedSanctions.length === 0 ? (
                            <div className="p-12 text-center text-xs font-medium text-gray-500">
                                No settled or excused sanction records yet.
                            </div>
                        ) : (
                            <div className="overflow-x-auto">
                                <table className="min-w-full divide-y divide-gray-200 text-xs sm:text-sm">
                                    <thead className="bg-gray-50 text-left text-[10px] font-black uppercase tracking-wider text-gray-500">
                                        <tr>
                                            <th className="px-4 py-3.5">Event & Date</th>
                                            <th className="px-4 py-3.5">Infraction</th>
                                            <th className="px-4 py-3.5">Resolution & Receipt</th>
                                            <th className="px-4 py-3.5">Admin Remarks</th>
                                            <th className="px-4 py-3.5">Verified At</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-gray-200 font-medium">
                                        {resolvedSanctions.map((item) => (
                                            <tr key={item.sanction_id}>
                                                <td className="px-4 py-4">
                                                    <div className="font-bold text-gray-900">
                                                        {item.event_title}
                                                    </div>
                                                    <div className="text-xs text-gray-500 font-normal">{item.event_date}</div>
                                                </td>
                                                <td className="px-4 py-4">
                                                    <div className="font-bold text-gray-800">
                                                        {item.slot_label ?? `Slot ${item.slot_index + 1}`}
                                                    </div>
                                                    <div className="text-[10px] font-bold text-gray-500 capitalize">
                                                        {item.infraction_type.replace(/_/g, ' ')}
                                                    </div>
                                                </td>
                                                <td className="px-4 py-4">{renderStatusBadge(item)}</td>
                                                <td className="px-4 py-4 text-xs text-gray-600">
                                                    {item.admin_remarks ?? '—'}
                                                </td>
                                                <td className="px-4 py-4 text-xs text-gray-500">
                                                    {item.resolved_at ?? '—'}
                                                </td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        )}
                    </div>
                )}

                {/* TAB 3: COMPLETE ATTENDANCE LOGS */}
                {activeTab === 'logs' && (
                    <div className="overflow-hidden rounded-2xl border border-gray-200/80 bg-white shadow-xs">
                        {attendanceLogs.length === 0 ? (
                            <div className="p-12 text-center text-xs font-medium text-gray-500">
                                No attendance check-in or check-out logs recorded yet.
                            </div>
                        ) : (
                            <div className="overflow-x-auto">
                                <table className="min-w-full divide-y divide-gray-200 text-xs sm:text-sm">
                                    <thead className="bg-gray-50 text-left text-[10px] font-black uppercase tracking-wider text-gray-500">
                                        <tr>
                                            <th className="px-4 py-3.5">Event</th>
                                            <th className="px-4 py-3.5">Event Date</th>
                                            <th className="px-4 py-3.5">Slot</th>
                                            <th className="px-4 py-3.5">Checkpoint</th>
                                            <th className="px-4 py-3.5">Timestamp</th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-gray-200 font-medium">
                                        {attendanceLogs.map((log) => (
                                            <tr key={log.attendance_id}>
                                                <td className="px-4 py-3.5 font-bold text-gray-900">
                                                    {log.event_title}
                                                </td>
                                                <td className="px-4 py-3.5 text-gray-600">{log.event_date}</td>
                                                <td className="px-4 py-3.5 text-gray-600">
                                                    Slot {log.slot_index + 1}
                                                </td>
                                                <td className="px-4 py-3.5">
                                                    <span className="inline-flex rounded-lg bg-gray-100 px-2.5 py-1 text-[10px] font-bold text-gray-700 capitalize">
                                                        {log.checkpoint_key ? log.checkpoint_key.replace(/_/g, ' ') : log.type}
                                                    </span>
                                                </td>
                                                <td className="px-4 py-3.5 text-xs text-gray-500">
                                                    {log.logged_at}
                                                </td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        )}
                    </div>
                )}
            </div>

            {/* EXCUSE APPEAL & PROOF UPLOAD MODAL */}
            {excuseTarget && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-gray-900/60 p-4 backdrop-blur-xs">
                    <div className="w-full max-w-lg overflow-hidden rounded-2xl bg-white shadow-xl">
                        <div className="flex items-center justify-between border-b border-gray-200 bg-[#1B1F5C] px-6 py-4 text-white">
                            <div>
                                <h3 className="text-sm font-black uppercase tracking-wider">Submit Excuse Appeal</h3>
                                <p className="text-xs text-gray-200 font-medium">
                                    {excuseTarget.event_title} ({excuseTarget.event_date}) —{' '}
                                    <span className="capitalize">{excuseTarget.infraction_type.replace(/_/g, ' ')}</span>
                                </p>
                            </div>
                            <button
                                type="button"
                                onClick={closeExcuseModal}
                                className="rounded-lg p-1 text-gray-200 hover:bg-white/10 hover:text-white"
                            >
                                <X className="h-5 w-5" />
                            </button>
                        </div>

                        <form onSubmit={handleExcuseSubmit} className="space-y-4 p-6">
                            <div>
                                <label className="block text-[10px] font-black uppercase tracking-wider text-gray-700">
                                    Excuse Category
                                </label>
                                <select
                                    value={excuseForm.data.excuse_category}
                                    onChange={(e) =>
                                        excuseForm.setData('excuse_category', e.target.value)
                                    }
                                    className="mt-1.5 w-full rounded-xl border border-gray-300 px-3 py-2 text-xs sm:text-sm font-bold focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                >
                                    <option value="Medical / Illness">Medical / Illness</option>
                                    <option value="Official University / CCIS Representation">
                                        Official University / CCIS Representation
                                    </option>
                                    <option value="Family Emergency">Family Emergency</option>
                                    <option value="Academic / Exam Conflict">
                                        Academic / Exam Conflict
                                    </option>
                                    <option value="Other Valid Reason">Other Valid Reason</option>
                                </select>
                                {excuseForm.errors.excuse_category && (
                                    <p className="mt-1 text-xs text-rose-600 font-semibold">
                                        {excuseForm.errors.excuse_category}
                                    </p>
                                )}
                            </div>

                            <div>
                                <label className="block text-[10px] font-black uppercase tracking-wider text-gray-700">
                                    Detailed Explanation / Reason Note
                                </label>
                                <textarea
                                    rows={3}
                                    required
                                    placeholder="Explain why you missed this checkpoint log..."
                                    value={excuseForm.data.student_notes}
                                    onChange={(e) =>
                                        excuseForm.setData('student_notes', e.target.value)
                                    }
                                    className="mt-1.5 w-full rounded-xl border border-gray-300 px-3 py-2 text-xs sm:text-sm font-medium focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                />
                                {excuseForm.errors.student_notes && (
                                    <p className="mt-1 text-xs text-rose-600 font-semibold">
                                        {excuseForm.errors.student_notes}
                                    </p>
                                )}
                            </div>

                            <div>
                                <label className="block text-[10px] font-black uppercase tracking-wider text-gray-700">
                                    Supporting Proof (Signed Excuse Letter, Medical Cert, or Memo)
                                </label>
                                <label className="mt-1.5 flex cursor-pointer flex-col items-center justify-center rounded-2xl border-2 border-dashed border-gray-300 bg-gray-50 px-4 py-5 text-center transition hover:border-[#1B1F5C] hover:bg-gray-100/70">
                                    <Upload className="h-6 w-6 text-[#1B1F5C]" />
                                    <span className="mt-1.5 text-xs font-bold text-gray-700">
                                        {excuseForm.data.excuse_proof
                                            ? excuseForm.data.excuse_proof.name
                                            : 'Click to upload photo or PDF (Max 5MB)'}
                                    </span>
                                    <span className="mt-0.5 text-[11px] text-gray-500 font-medium">
                                        Accepts JPG, PNG, WEBP, or PDF
                                    </span>
                                    <input
                                      type="file"
                                      accept=".jpg,.jpeg,.png,.webp,.pdf"
                                      onChange={handleFileChange}
                                      className="hidden"
                                    />
                                </label>

                                {previewUrl && (
                                    <div className="mt-3 overflow-hidden rounded-xl border border-gray-200 bg-gray-100 p-2">
                                        <div className="mb-1 flex items-center gap-1 text-[11px] font-bold text-gray-600">
                                            <ImageIcon className="h-3.5 w-3.5" />
                                            Document Preview
                                        </div>
                                        <img
                                            src={previewUrl}
                                            alt="Excuse proof preview"
                                            className="max-h-44 w-full rounded-lg object-contain"
                                        />
                                    </div>
                                )}

                                {excuseForm.data.excuse_proof && !previewUrl && (
                                    <div className="mt-2 flex items-center gap-2 rounded-xl bg-gray-100 px-3 py-2 text-xs text-gray-700 font-bold">
                                        <FileText className="h-4 w-4 text-[#1B1F5C]" />
                                        {excuseForm.data.excuse_proof.name}
                                    </div>
                                )}

                                {excuseForm.errors.excuse_proof && (
                                    <p className="mt-1 text-xs text-rose-600 font-semibold">
                                        {excuseForm.errors.excuse_proof}
                                    </p>
                                )}
                            </div>

                            <div className="flex items-center justify-end gap-2 border-t border-gray-200 pt-4">
                                <button
                                    type="button"
                                    onClick={closeExcuseModal}
                                    className="rounded-xl border border-gray-300 px-4 py-2 text-xs font-bold text-gray-700 hover:bg-gray-50"
                                >
                                    Cancel
                                </button>
                                <button
                                    type="submit"
                                    disabled={excuseForm.processing}
                                    className="rounded-xl bg-[#1B1F5C] px-4 py-2 text-xs font-bold text-white hover:bg-[#141747] disabled:opacity-50"
                                >
                                    {excuseForm.processing ? 'Uploading...' : 'Submit Excuse for Review'}
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            )}
        </>
    );
}

Sanctions.layout = (page: React.ReactNode) => (
    <AppLayout>{page}</AppLayout>
);