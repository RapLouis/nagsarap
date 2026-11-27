import React, { useEffect, useMemo, useState } from 'react';
import { Head, router, useForm } from '@inertiajs/react';
import AdminLayout from '@/layouts/admin-layout';
import {
    KeyRound,
    Plus,
    Search,
    Filter,
    Copy,
    Check,
    ShieldCheck,
    ShieldAlert,
    Trash2,
    RefreshCw,
    UserCheck,
    UserX,
    Key,
    X,
    RotateCcw,
    CheckCircle2,
    Loader2,
    FilterX,
    ArrowUp,
} from 'lucide-react';

interface OrganizerItem {
    id: number;
    name: string;
    email: string;
    department?: string;
    key_code: string;
    status: 'active' | 'suspended' | 'pending';
    events_managed_count: number;
    created_at: string;
}

interface PageProps {
    organizers: OrganizerItem[];
    flash?: {
        success?: string;
        error?: string;
    };
}

const fmt = new Intl.NumberFormat('en-PH');

export default function OrganizersManagement({ organizers = [], flash }: PageProps) {
    const [search, setSearch] = useState('');
    const [statusFilter, setStatusFilter] = useState<string>('all');
    const [copiedId, setCopiedId] = useState<number | null>(null);

    const [showCreateModal, setShowCreateModal] = useState(false);
    const [selectedOrganizer, setSelectedOrganizer] = useState<OrganizerItem | null>(null);
    const [showDeleteModal, setShowDeleteModal] = useState(false);
    const [isDeleting, setIsDeleting] = useState(false);
    const [togglingId, setTogglingId] = useState<number | null>(null);
    const [dismissedFlash, setDismissedFlash] = useState<string | null>(null);
    const [showBackToTop, setShowBackToTop] = useState(false);

    const { data, setData, post, processing, errors, reset, clearErrors } = useForm({
        name: '',
        email: '',
        department: '',
        key_code: '',
        password: '', // Will be dynamically populated by generateNewKeyCode()
    });

    // Close open modals on Escape key
    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.key !== 'Escape') return;
            if (showCreateModal && !processing) {
                setShowCreateModal(false);
            } else if (showDeleteModal && !isDeleting) {
                setShowDeleteModal(false);
                setSelectedOrganizer(null);
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [showCreateModal, showDeleteModal, processing, isDeleting]);

    useEffect(() => {
        const handleScroll = () => {
            setShowBackToTop(window.scrollY > 480);
        };
        window.addEventListener('scroll', handleScroll, { passive: true });
        return () => window.removeEventListener('scroll', handleScroll);
    }, []);

    const generateNewKeyCode = () => {
        const prefix = '4TTND-ORG';
        const randomPart = Math.random().toString(36).substring(2, 8).toUpperCase();
        const code = `${prefix}-${randomPart}`;
        setData((prev) => ({
            ...prev,
            key_code: code,
            password: code, // Keep password perfectly synced with key_code for login
        }));
    };

    const openCreateModal = () => {
        clearErrors();
        generateNewKeyCode();
        setShowCreateModal(true);
    };

    const handleCreateSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        post('/admin/organizers', {
            onSuccess: () => {
                setShowCreateModal(false);
                reset();
            },
        });
    };

    const handleCopyKey = (id: number, code: string) => {
        navigator.clipboard?.writeText(code);
        setCopiedId(id);
        setTimeout(() => setCopiedId(null), 2000);
    };

    const handleToggleStatus = (organizer: OrganizerItem) => {
        setTogglingId(organizer.id);
        router.patch(
            `/admin/organizers/${organizer.id}/status`,
            {},
            {
                preserveScroll: true,
                onFinish: () => setTogglingId(null),
            }
        );
    };

    const handleDeleteKey = () => {
        if (!selectedOrganizer || isDeleting) return;
        setIsDeleting(true);
        router.delete(`/admin/organizers/${selectedOrganizer.id}`, {
            onSuccess: () => {
                setShowDeleteModal(false);
                setSelectedOrganizer(null);
            },
            onFinish: () => setIsDeleting(false),
        });
    };

    const filteredOrganizers = useMemo(() => {
        const query = search.trim().toLowerCase();
        return organizers.filter((item) => {
            const matchesSearch =
                query === '' ||
                item.name.toLowerCase().includes(query) ||
                item.email.toLowerCase().includes(query) ||
                item.key_code.toLowerCase().includes(query) ||
                (item.department ?? '').toLowerCase().includes(query);
            const matchesStatus = statusFilter === 'all' || item.status === statusFilter;
            return matchesSearch && matchesStatus;
        });
    }, [organizers, search, statusFilter]);

    const activeCount = useMemo(
        () => organizers.filter((o) => o.status === 'active').length,
        [organizers]
    );
    const pendingCount = useMemo(
        () => organizers.filter((o) => o.status === 'pending').length,
        [organizers]
    );
    const suspendedCount = useMemo(
        () => organizers.filter((o) => o.status === 'suspended').length,
        [organizers]
    );

    const hasActiveFilters = search.trim() !== '' || statusFilter !== 'all';

    const resetFilters = () => {
        setSearch('');
        setStatusFilter('all');
    };

    const activeFlashSuccess =
        flash?.success && dismissedFlash !== flash.success ? flash.success : null;
    const activeFlashError =
        flash?.error && dismissedFlash !== flash.error ? flash.error : null;

    return (
        <>
            <Head title="Organizer Keys & Access Control | 4ttend" />

            {/* Screen reader announcement for live filter and clipboard updates */}
            <div role="status" aria-live="polite" className="sr-only">
                {copiedId !== null
                    ? 'Organizer access key copied to clipboard.'
                    : `Showing ${filteredOrganizers.length} of ${organizers.length} organizer access keys`}
            </div>

            <div className="w-full space-y-3.5 bg-[#F5F6FA] font-sans text-gray-900 antialiased">
                {/* FLASH NOTIFICATIONS */}
                {activeFlashSuccess && (
                    <div
                        role="status"
                        aria-live="polite"
                        className="flex items-center justify-between gap-3 rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-emerald-900 shadow-xs"
                    >
                        <div className="flex items-center gap-2.5 text-xs font-bold sm:text-sm">
                            <CheckCircle2
                                className="h-4 w-4 shrink-0 text-emerald-600"
                                aria-hidden="true"
                            />
                            <span>{activeFlashSuccess}</span>
                        </div>
                        <button
                            type="button"
                            onClick={() => setDismissedFlash(activeFlashSuccess)}
                            aria-label="Dismiss notification"
                            className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-xl text-emerald-700 transition-colors hover:bg-emerald-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                        >
                            <X className="h-4 w-4" aria-hidden="true" />
                        </button>
                    </div>
                )}

                {activeFlashError && (
                    <div
                        role="alert"
                        className="flex items-center justify-between gap-3 rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-rose-900 shadow-xs"
                    >
                        <div className="flex items-center gap-2.5 text-xs font-bold sm:text-sm">
                            <ShieldAlert
                                className="h-4 w-4 shrink-0 text-rose-600"
                                aria-hidden="true"
                            />
                            <span>{activeFlashError}</span>
                        </div>
                        <button
                            type="button"
                            onClick={() => setDismissedFlash(activeFlashError)}
                            aria-label="Dismiss error alert"
                            className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-xl text-rose-700 transition-colors hover:bg-rose-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                        >
                            <X className="h-4 w-4" aria-hidden="true" />
                        </button>
                    </div>
                )}

                {/* COMPACT EXECUTIVE HEADER & PRIMARY CTA */}
                <header className="flex flex-col justify-between gap-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs sm:flex-row sm:items-center">
                    <div className="min-w-0 space-y-1">
                        <div className="flex flex-wrap items-center gap-2">
                            <span className="inline-flex items-center gap-1.5 rounded-full border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 px-2.5 py-0.5 text-[11px] font-bold text-[#1B1F5C]">
                                <KeyRound className="h-3 w-3 text-[#F5A623]" aria-hidden="true" />
                                <span>Access Control & Security Realm</span>
                            </span>
                        </div>
                        <h1 className="text-lg font-black tracking-tight text-[#1B1F5C] sm:text-xl">
                            Organizer Access Management
                        </h1>
                        <p className="text-xs font-medium text-gray-600">
                            Provision security keys, suspend or activate credentials, and audit
                            event execution privileges
                        </p>
                    </div>

                    <button
                        type="button"
                        onClick={openCreateModal}
                        className="inline-flex min-h-[44px] shrink-0 cursor-pointer items-center justify-center gap-2 rounded-xl bg-[#1B1F5C] px-4 py-2.5 text-xs font-bold text-white shadow-2xs transition-colors hover:bg-[#131644] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] active:scale-[0.99] motion-reduce:transform-none"
                    >
                        <Plus className="h-4 w-4 text-[#FFD600]" aria-hidden="true" />
                        <span>Issue Organizer Key</span>
                    </button>
                </header>

                {/* KPI SUMMARY RIBBON (INTERACTIVE STATUS FILTERS) */}
                <section
                    aria-label="Key Management Statistics"
                    className="grid grid-cols-1 gap-3 sm:grid-cols-3"
                >
                    <OrganizerStatCard
                        label="Active Organizers"
                        sub="Fully authorized access"
                        count={activeCount}
                        active={statusFilter === 'active'}
                        onClick={() =>
                            setStatusFilter((prev) => (prev === 'active' ? 'all' : 'active'))
                        }
                        valueClass="text-[#1B1F5C]"
                        subClass="text-emerald-700"
                        icon={<UserCheck className="h-5 w-5" aria-hidden="true" />}
                        iconClass="border-emerald-200/80 bg-emerald-50 text-emerald-700"
                    />

                    <OrganizerStatCard
                        label="Pending Invitations"
                        sub="Awaiting initial activation"
                        count={pendingCount}
                        active={statusFilter === 'pending'}
                        onClick={() =>
                            setStatusFilter((prev) => (prev === 'pending' ? 'all' : 'pending'))
                        }
                        valueClass="text-amber-700"
                        subClass="text-amber-800"
                        icon={<Key className="h-5 w-5" aria-hidden="true" />}
                        iconClass="border-amber-200/80 bg-amber-50 text-amber-800"
                    />

                    <OrganizerStatCard
                        label="Suspended Keys"
                        sub="Execution access revoked"
                        count={suspendedCount}
                        active={statusFilter === 'suspended'}
                        onClick={() =>
                            setStatusFilter((prev) => (prev === 'suspended' ? 'all' : 'suspended'))
                        }
                        valueClass="text-rose-700"
                        subClass="text-rose-700"
                        icon={<UserX className="h-5 w-5" aria-hidden="true" />}
                        iconClass="border-rose-200/80 bg-rose-50 text-rose-700"
                    />
                </section>

                {/* SEARCH, FILTER & RECORDS WORKSPACE */}
                <section
                    aria-label="Organizer Keys Directory"
                    className="min-w-0 space-y-3.5 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs"
                >
                    <div className="flex flex-col justify-between gap-3 border-b border-gray-100 pb-3 lg:flex-row lg:items-center">
                        <div className="relative max-w-md flex-1">
                            <label htmlFor="organizer-directory-search" className="sr-only">
                                Search organizer keys by name, email, department, or key code
                            </label>
                            <Search
                                className="pointer-events-none absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-gray-400"
                                aria-hidden="true"
                            />
                            <input
                                id="organizer-directory-search"
                                type="text"
                                aria-label="Search organizer keys by name, email, department, or key code"
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                placeholder="Search by name, email, department, or key code..."
                                className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white pl-9 pr-8 text-xs font-medium text-gray-900 placeholder:text-gray-400 transition-colors focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            />
                            {search && (
                                <button
                                    type="button"
                                    onClick={() => setSearch('')}
                                    aria-label="Clear search query"
                                    className="absolute right-1.5 top-1/2 inline-flex h-7 w-7 -translate-y-1/2 items-center justify-center rounded-lg text-gray-400 hover:bg-gray-100 hover:text-gray-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                >
                                    <X className="h-3.5 w-3.5" aria-hidden="true" />
                                </button>
                            )}
                        </div>

                        <div className="flex flex-wrap items-center gap-2">
                            <span className="rounded-md border border-gray-200 bg-[#F5F6FA] px-2 py-1 font-mono text-[11px] font-bold text-gray-700">
                                {fmt.format(filteredOrganizers.length)} of{' '}
                                {fmt.format(organizers.length)}
                            </span>

                            <label
                                htmlFor="organizer-status-filter"
                                className="inline-flex items-center gap-1.5 text-[11px] font-extrabold uppercase tracking-wider text-gray-500"
                            >
                                <Filter className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                                <span>Status</span>
                            </label>
                            <select
                                id="organizer-status-filter"
                                value={statusFilter}
                                onChange={(e) => setStatusFilter(e.target.value)}
                                className="min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-bold text-[#1B1F5C] transition-colors hover:border-gray-400 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            >
                                <option value="all">All Keys ({organizers.length})</option>
                                <option value="active">Active Only</option>
                                <option value="pending">Pending Activation</option>
                                <option value="suspended">Suspended</option>
                            </select>

                            {hasActiveFilters && (
                                <button
                                    type="button"
                                    onClick={resetFilters}
                                    className="inline-flex min-h-[38px] items-center gap-1 rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-bold text-[#1B1F5C] transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                >
                                    <RotateCcw
                                        className="h-3.5 w-3.5 text-[#F5A623]"
                                        aria-hidden="true"
                                    />
                                    <span>Reset</span>
                                </button>
                            )}
                        </div>
                    </div>

                    {/* RECORDS LIST (MOBILE CARDS + DESKTOP TABLE) */}
                    {filteredOrganizers.length > 0 ? (
                        <>
                            {/* MOBILE CARD VIEW (< md) */}
                            <div className="space-y-2.5 md:hidden">
                                {filteredOrganizers.map((org) => {
                                    const isToggling = togglingId === org.id;
                                    const isActive = org.status === 'active';
                                    return (
                                        <article
                                            key={org.id}
                                            className="space-y-2.5 rounded-xl border border-gray-200/80 bg-[#F5F6FA]/70 p-3.5"
                                        >
                                            <div className="flex items-start justify-between gap-2">
                                                <div className="min-w-0">
                                                    <p className="truncate text-sm font-extrabold text-gray-900">
                                                        {org.name}
                                                    </p>
                                                    <p className="truncate text-xs font-medium text-gray-600">
                                                        {org.email}
                                                    </p>
                                                    <p className="mt-0.5 text-[11px] font-semibold text-gray-500">
                                                        {org.department || 'General Admin'} •{' '}
                                                        <span className="font-mono font-bold text-gray-800">
                                                            {fmt.format(org.events_managed_count)}{' '}
                                                            event
                                                            {org.events_managed_count === 1
                                                                ? ''
                                                                : 's'}
                                                        </span>
                                                    </p>
                                                </div>
                                                <OrganizerStatusBadge status={org.status} />
                                            </div>

                                            <div className="flex items-center justify-between gap-2 rounded-xl border border-gray-200 bg-white px-3 py-1">
                                                <span className="truncate font-mono text-xs font-bold text-[#1B1F5C]">
                                                    {org.key_code}
                                                </span>
                                                <button
                                                    type="button"
                                                    onClick={() => handleCopyKey(org.id, org.key_code)}
                                                    aria-label={`Copy access key for ${org.name}`}
                                                    className="inline-flex min-h-[38px] shrink-0 items-center gap-1 rounded-lg px-2 text-xs font-bold text-[#1B1F5C] transition-colors hover:bg-gray-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                >
                                                    {copiedId === org.id ? (
                                                        <>
                                                            <Check
                                                                className="h-3.5 w-3.5 text-emerald-600"
                                                                aria-hidden="true"
                                                            />
                                                            <span className="text-emerald-700">
                                                                Copied
                                                            </span>
                                                        </>
                                                    ) : (
                                                        <>
                                                            <Copy
                                                                className="h-3.5 w-3.5"
                                                                aria-hidden="true"
                                                            />
                                                            <span>Copy</span>
                                                        </>
                                                    )}
                                                </button>
                                            </div>

                                            <div className="flex items-center justify-end gap-2 border-t border-gray-200/70 pt-2">
                                                <button
                                                    type="button"
                                                    disabled={isToggling}
                                                    onClick={() => handleToggleStatus(org)}
                                                    aria-label={
                                                        isActive
                                                            ? `Suspend access for ${org.name}`
                                                            : `Activate access for ${org.name}`
                                                    }
                                                    className={`inline-flex min-h-[38px] items-center justify-center rounded-xl border px-3 py-1.5 text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-60 ${
                                                        isActive
                                                            ? 'border-amber-200 bg-amber-50 text-amber-800 hover:bg-amber-100'
                                                            : 'border-emerald-200 bg-emerald-50 text-emerald-800 hover:bg-emerald-100'
                                                    }`}
                                                >
                                                    {isToggling ? 'Updating...' : isActive ? 'Suspend' : 'Activate'}
                                                </button>

                                                <button
                                                    type="button"
                                                    onClick={() => {
                                                        setSelectedOrganizer(org);
                                                        setShowDeleteModal(true);
                                                    }}
                                                    aria-label={`Delete key record for ${org.name}`}
                                                    className="inline-flex min-h-[38px] items-center gap-1 rounded-xl border border-rose-200 bg-rose-50 px-3 py-1.5 text-xs font-bold text-rose-700 transition-colors hover:bg-rose-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                >
                                                    <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
                                                    <span>Delete</span>
                                                </button>
                                            </div>
                                        </article>
                                    );
                                })}
                            </div>

                            {/* DESKTOP & TABLET DATA TABLE (>= md) */}
                            <div className="hidden overflow-x-auto md:block">
                                <table className="w-full text-left text-xs text-gray-700">
                                    <thead>
                                        <tr className="border-b border-gray-200/80 text-[10px] font-extrabold uppercase tracking-wider text-gray-500">
                                            <th scope="col" className="pb-2.5 pr-4">
                                                Organizer
                                            </th>
                                            <th scope="col" className="pb-2.5 pr-4">
                                                Department
                                            </th>
                                            <th scope="col" className="pb-2.5 pr-4">
                                                Key Access Code
                                            </th>
                                            <th scope="col" className="pb-2.5 pr-4">
                                                Status
                                            </th>
                                            <th scope="col" className="pb-2.5 pr-4 text-center">
                                                Managed Events
                                            </th>
                                            <th scope="col" className="pb-2.5 text-right">
                                                Actions
                                            </th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-gray-100">
                                        {filteredOrganizers.map((org) => {
                                            const isToggling = togglingId === org.id;
                                            const isActive = org.status === 'active';
                                            return (
                                                <tr
                                                    key={org.id}
                                                    className="transition-colors hover:bg-[#F5F6FA]/80"
                                                >
                                                    <td className="py-2.5 pr-4">
                                                        <p className="font-extrabold text-gray-900">
                                                            {org.name}
                                                        </p>
                                                        <p className="text-[11px] font-medium text-gray-500">
                                                            {org.email}
                                                        </p>
                                                    </td>
                                                    <td className="py-2.5 pr-4 font-semibold text-gray-700">
                                                        {org.department || 'General Admin'}
                                                    </td>
                                                    <td className="py-2.5 pr-4">
                                                        <div className="inline-flex items-center gap-1.5 rounded-xl border border-gray-200 bg-[#F5F6FA] px-2.5 py-0.5 font-mono text-xs font-bold text-[#1B1F5C]">
                                                            <span>{org.key_code}</span>
                                                            <button
                                                                type="button"
                                                                onClick={() =>
                                                                    handleCopyKey(org.id, org.key_code)
                                                                }
                                                                aria-label={
                                                                    copiedId === org.id
                                                                        ? `Copied key code for ${org.name}`
                                                                        : `Copy key code for ${org.name}`
                                                                }
                                                                title="Copy Key Code"
                                                                className="inline-flex min-h-[32px] min-w-[32px] items-center justify-center rounded-lg text-gray-500 transition-colors hover:bg-gray-200/70 hover:text-[#1B1F5C] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                            >
                                                                {copiedId === org.id ? (
                                                                    <Check
                                                                        className="h-3.5 w-3.5 text-emerald-600"
                                                                        aria-hidden="true"
                                                                    />
                                                                ) : (
                                                                    <Copy
                                                                        className="h-3.5 w-3.5"
                                                                        aria-hidden="true"
                                                                    />
                                                                )}
                                                            </button>
                                                        </div>
                                                    </td>
                                                    <td className="py-2.5 pr-4">
                                                        <OrganizerStatusBadge status={org.status} />
                                                    </td>
                                                    <td className="py-2.5 pr-4 text-center">
                                                        <span className="rounded-md border border-gray-200 bg-[#F5F6FA] px-2 py-0.5 font-mono text-xs font-extrabold text-gray-900">
                                                            {fmt.format(org.events_managed_count)}
                                                        </span>
                                                    </td>
                                                    <td className="py-2.5 text-right">
                                                        <div className="inline-flex items-center justify-end gap-1.5">
                                                            <button
                                                                type="button"
                                                                disabled={isToggling}
                                                                onClick={() => handleToggleStatus(org)}
                                                                aria-label={
                                                                    isActive
                                                                        ? `Suspend access for ${org.name}`
                                                                        : `Activate access for ${org.name}`
                                                                }
                                                                title={
                                                                    isActive
                                                                        ? 'Suspend Access'
                                                                        : 'Activate Access'
                                                                }
                                                                className={`min-h-[38px] rounded-xl border px-3 py-1.5 text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-60 ${
                                                                    isActive
                                                                        ? 'border-amber-200 bg-amber-50 text-amber-800 hover:bg-amber-100'
                                                                        : 'border-emerald-200 bg-emerald-50 text-emerald-800 hover:bg-emerald-100'
                                                                }`}
                                                            >
                                                                {isToggling
                                                                    ? 'Updating...'
                                                                    : isActive
                                                                      ? 'Suspend'
                                                                      : 'Activate'}
                                                            </button>

                                                            <button
                                                                type="button"
                                                                onClick={() => {
                                                                    setSelectedOrganizer(org);
                                                                    setShowDeleteModal(true);
                                                                }}
                                                                aria-label={`Delete key record for ${org.name}`}
                                                                title="Delete Key Record"
                                                                className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-xl p-2 text-gray-500 transition-colors hover:bg-rose-50 hover:text-rose-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                            >
                                                                <Trash2
                                                                    className="h-4 w-4"
                                                                    aria-hidden="true"
                                                                />
                                                            </button>
                                                        </div>
                                                    </td>
                                                </tr>
                                            );
                                        })}
                                    </tbody>
                                </table>
                            </div>
                        </>
                    ) : (
                        <div className="flex min-h-[210px] flex-col items-center justify-center space-y-2.5 rounded-xl border border-dashed border-gray-200 bg-[#F5F6FA]/70 p-6 text-center">
                            <div className="flex h-10 w-10 items-center justify-center rounded-xl border border-[#1B1F5C]/15 bg-white text-[#1B1F5C] shadow-2xs">
                                {hasActiveFilters ? (
                                    <FilterX className="h-5 w-5 text-[#F5A623]" aria-hidden="true" />
                                ) : (
                                    <KeyRound className="h-5 w-5" aria-hidden="true" />
                                )}
                            </div>
                            <p className="text-sm font-extrabold text-[#1B1F5C]">
                                {hasActiveFilters
                                    ? 'No organizer keys match your filters'
                                    : 'No organizer keys issued yet'}
                            </p>
                            <p className="max-w-xs text-xs font-medium text-gray-600">
                                {hasActiveFilters
                                    ? 'Try clearing your search term or switching the status filter to view issued keys.'
                                    : 'Issue an organizer access key to authorize faculty or student event coordinators.'}
                            </p>
                            <div className="pt-1">
                                {hasActiveFilters ? (
                                    <button
                                        type="button"
                                        onClick={resetFilters}
                                        className="inline-flex min-h-[38px] items-center gap-1.5 rounded-xl border border-gray-300 bg-white px-3.5 py-1.5 text-xs font-bold text-[#1B1F5C] transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    >
                                        <RotateCcw
                                            className="h-3.5 w-3.5 text-[#F5A623]"
                                            aria-hidden="true"
                                        />
                                        <span>Clear Filters</span>
                                    </button>
                                ) : (
                                    <button
                                        type="button"
                                        onClick={openCreateModal}
                                        className="inline-flex min-h-[38px] items-center gap-1.5 rounded-xl bg-[#1B1F5C] px-3.5 py-1.5 text-xs font-bold text-white shadow-2xs transition-colors hover:bg-[#131644] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    >
                                        <Plus className="h-3.5 w-3.5 text-[#FFD600]" aria-hidden="true" />
                                        <span>Issue Organizer Key</span>
                                    </button>
                                )}
                            </div>
                        </div>
                    )}
                </section>

                {/* MODAL: ISSUE NEW ORGANIZER KEY */}
                {showCreateModal && (
                    <div
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="issue-key-modal-title"
                        onClick={(e) => {
                            if (e.target === e.currentTarget && !processing) {
                                setShowCreateModal(false);
                            }
                        }}
                        className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-3 sm:p-4"
                    >
                        <div className="w-full max-w-md space-y-4 rounded-2xl border border-gray-200/80 bg-white p-5 shadow-lg">
                            <div className="flex items-center justify-between border-b border-gray-100 pb-3">
                                <h2
                                    id="issue-key-modal-title"
                                    className="flex items-center gap-2 text-base font-black text-[#1B1F5C]"
                                >
                                    <KeyRound className="h-5 w-5 text-[#F5A623]" aria-hidden="true" />
                                    <span>Issue Organizer Access Key</span>
                                </h2>
                                <button
                                    type="button"
                                    disabled={processing}
                                    onClick={() => setShowCreateModal(false)}
                                    aria-label="Close issue key dialog"
                                    className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-xl text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                >
                                    <X className="h-4 w-4" aria-hidden="true" />
                                </button>
                            </div>

                            <form onSubmit={handleCreateSubmit} className="space-y-3.5">
                                <div>
                                    <label
                                        htmlFor="name"
                                        className="mb-1 block text-xs font-bold uppercase tracking-wider text-gray-700"
                                    >
                                        Organizer Full Name <span className="text-rose-600">*</span>
                                    </label>
                                    <input
                                        id="name"
                                        type="text"
                                        value={data.name}
                                        onChange={(e) => setData('name', e.target.value)}
                                        placeholder="e.g., Dr. Juan Dela Cruz"
                                        aria-invalid={Boolean(errors.name)}
                                        aria-describedby={errors.name ? 'name-error' : undefined}
                                        className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white px-3 text-xs text-gray-900 transition-colors focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                        required
                                    />
                                    {errors.name && (
                                        <p
                                            id="name-error"
                                            role="alert"
                                            className="mt-1 text-[11px] font-bold text-rose-700"
                                        >
                                            {errors.name}
                                        </p>
                                    )}
                                </div>

                                <div>
                                    <label
                                        htmlFor="email"
                                        className="mb-1 block text-xs font-bold uppercase tracking-wider text-gray-700"
                                    >
                                        Institutional Email <span className="text-rose-600">*</span>
                                    </label>
                                    <input
                                        id="email"
                                        type="email"
                                        value={data.email}
                                        onChange={(e) => setData('email', e.target.value)}
                                        placeholder="e.g., organizer@mmsu.edu.ph"
                                        aria-invalid={Boolean(errors.email)}
                                        aria-describedby={errors.email ? 'email-error' : undefined}
                                        className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white px-3 text-xs text-gray-900 transition-colors focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                        required
                                    />
                                    {errors.email && (
                                        <p
                                            id="email-error"
                                            role="alert"
                                            className="mt-1 text-[11px] font-bold text-rose-700"
                                        >
                                            {errors.email}
                                        </p>
                                    )}
                                </div>

                                <div>
                                    <label
                                        htmlFor="department"
                                        className="mb-1 block text-xs font-bold uppercase tracking-wider text-gray-700"
                                    >
                                        Department / College
                                    </label>
                                    <input
                                        id="department"
                                        type="text"
                                        list="department-options"
                                        value={data.department}
                                        onChange={(e) => setData('department', e.target.value)}
                                        placeholder="Enter or select your department..."
                                        aria-invalid={Boolean(errors.department)}
                                        aria-describedby={
                                            errors.department ? 'department-error' : undefined
                                        }
                                        className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white px-3 text-xs text-gray-900 transition-colors focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    />
                                    <datalist id="department-options">
                                        <option value="CCIS">
                                            College of Computing and Information Sciences
                                        </option>
                                        <option value="COE">College of Engineering</option>
                                        <option value="CBEA">
                                            College of Business, Economics and Accountancy
                                        </option>
                                        <option value="CAS">College of Arts and Sciences</option>
                                    </datalist>
                                    {errors.department && (
                                        <p
                                            id="department-error"
                                            role="alert"
                                            className="mt-1 text-[11px] font-bold text-rose-700"
                                        >
                                            {errors.department}
                                        </p>
                                    )}
                                </div>

                                <div>
                                    <div className="mb-1 flex items-center justify-between">
                                        <label
                                            htmlFor="key_code"
                                            className="block text-xs font-bold uppercase tracking-wider text-gray-700"
                                        >
                                            Generated Access Key Code
                                        </label>
                                        <button
                                            type="button"
                                            onClick={generateNewKeyCode}
                                            className="inline-flex min-h-[28px] items-center gap-1 rounded-lg px-2 py-0.5 text-[11px] font-bold text-[#1B1F5C] transition-colors hover:bg-gray-100 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                        >
                                            <RefreshCw
                                                className="h-3 w-3 text-[#F5A623]"
                                                aria-hidden="true"
                                            />
                                            <span>Regenerate</span>
                                        </button>
                                    </div>
                                    <input
                                        id="key_code"
                                        type="text"
                                        value={data.key_code}
                                        readOnly
                                        className="min-h-[38px] w-full rounded-xl border border-gray-200 bg-[#F5F6FA] px-3 font-mono text-xs font-extrabold text-[#1B1F5C] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    />
                                </div>

                                <div className="flex justify-end gap-2 border-t border-gray-100 pt-3">
                                    <button
                                        type="button"
                                        disabled={processing}
                                        onClick={() => setShowCreateModal(false)}
                                        className="min-h-[38px] rounded-xl border border-gray-300 bg-white px-4 py-2 text-xs font-bold text-gray-700 transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    >
                                        Cancel
                                    </button>
                                    <button
                                        type="submit"
                                        disabled={processing}
                                        className="inline-flex min-h-[38px] items-center gap-1.5 rounded-xl bg-[#1B1F5C] px-4 py-2 text-xs font-bold text-white shadow-2xs transition-colors hover:bg-[#131644] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-60"
                                    >
                                        {processing && (
                                            <Loader2
                                                className="h-3.5 w-3.5 animate-spin motion-reduce:animate-none"
                                                aria-hidden="true"
                                            />
                                        )}
                                        <span>
                                            {processing ? 'Issuing Key...' : 'Confirm & Issue Key'}
                                        </span>
                                    </button>
                                </div>
                            </form>
                        </div>
                    </div>
                )}

                {/* MODAL: DELETE CONFIRMATION */}
                {showDeleteModal && selectedOrganizer && (
                    <div
                        role="dialog"
                        aria-modal="true"
                        aria-labelledby="delete-key-modal-title"
                        onClick={(e) => {
                            if (e.target === e.currentTarget && !isDeleting) {
                                setShowDeleteModal(false);
                                setSelectedOrganizer(null);
                            }
                        }}
                        className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-3 sm:p-4"
                    >
                        <div className="w-full max-w-sm space-y-4 rounded-2xl border border-gray-200/80 bg-white p-5 text-center shadow-lg">
                            <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-2xl border border-rose-200 bg-rose-50 text-rose-600">
                                <ShieldAlert className="h-6 w-6" aria-hidden="true" />
                            </div>
                            <div>
                                <h2
                                    id="delete-key-modal-title"
                                    className="text-base font-black text-gray-900"
                                >
                                    Delete Key Record?
                                </h2>
                                <p className="mt-1 text-xs font-medium text-gray-600">
                                    Are you sure you want to permanently remove the organizer key for{' '}
                                    <span className="font-extrabold text-gray-900">
                                        {selectedOrganizer.name}
                                    </span>
                                    ? This action cannot be undone.
                                </p>
                            </div>
                            <div className="flex justify-center gap-2 pt-2">
                                <button
                                    type="button"
                                    disabled={isDeleting}
                                    onClick={() => {
                                        setShowDeleteModal(false);
                                        setSelectedOrganizer(null);
                                    }}
                                    className="min-h-[38px] rounded-xl border border-gray-300 bg-white px-4 py-2 text-xs font-bold text-gray-700 transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                >
                                    Cancel
                                </button>
                                <button
                                    type="button"
                                    disabled={isDeleting}
                                    onClick={handleDeleteKey}
                                    className="inline-flex min-h-[38px] items-center gap-1.5 rounded-xl bg-rose-600 px-4 py-2 text-xs font-bold text-white shadow-2xs transition-colors hover:bg-rose-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-60"
                                >
                                    {isDeleting && (
                                        <Loader2
                                            className="h-3.5 w-3.5 animate-spin motion-reduce:animate-none"
                                            aria-hidden="true"
                                        />
                                    )}
                                    <span>{isDeleting ? 'Deleting...' : 'Yes, Delete Record'}</span>
                                </button>
                            </div>
                        </div>
                    </div>
                )}
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
                    className="fixed bottom-5 right-5 z-30 inline-flex h-11 w-11 items-center justify-center rounded-xl border border-gray-200 bg-white text-[#1B1F5C] shadow-xs transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                >
                    <ArrowUp className="h-4 w-4 text-[#F5A623]" aria-hidden="true" />
                </button>
            )}
        </>
    );
}

function OrganizerStatCard({
    label,
    sub,
    count,
    active,
    onClick,
    valueClass,
    subClass,
    icon,
    iconClass,
}: {
    label: string;
    sub: string;
    count: number;
    active: boolean;
    onClick: () => void;
    valueClass: string;
    subClass: string;
    icon: React.ReactNode;
    iconClass: string;
}) {
    return (
        <button
            type="button"
            aria-pressed={active}
            onClick={onClick}
            className={`flex min-h-[44px] items-center justify-between gap-3 rounded-2xl border bg-white p-4 text-left shadow-xs transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                active
                    ? 'border-[#1B1F5C] ring-1 ring-[#1B1F5C]'
                    : 'border-gray-200/80 hover:border-gray-300'
            }`}
        >
            <div className="min-w-0">
                <div className="flex items-center gap-2">
                    <span className="block text-[11px] font-extrabold uppercase tracking-wider text-gray-500">
                        {label}
                    </span>
                    {active && (
                        <span className="rounded-md bg-[#1B1F5C] px-1.5 py-0.5 text-[9px] font-extrabold uppercase tracking-wider text-white">
                            Active
                        </span>
                    )}
                </div>
                <span className={`mt-1 block font-mono text-2xl font-black tracking-tight ${valueClass}`}>
                    {fmt.format(count)}
                </span>
                <span className={`mt-0.5 block text-[11px] font-bold ${subClass}`}>{sub}</span>
            </div>
            <div
                className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border ${iconClass}`}
            >
                {icon}
            </div>
        </button>
    );
}

function OrganizerStatusBadge({ status }: { status: OrganizerItem['status'] }) {
    return (
        <span
            className={`inline-flex shrink-0 items-center gap-1 rounded-full border px-2.5 py-0.5 text-[11px] font-extrabold ${
                status === 'active'
                    ? 'border-emerald-200 bg-emerald-50 text-emerald-800'
                    : status === 'pending'
                      ? 'border-amber-200 bg-amber-50 text-amber-800'
                      : 'border-rose-200 bg-rose-50 text-rose-800'
            }`}
        >
            {status === 'active' && <ShieldCheck className="h-3 w-3" aria-hidden="true" />}
            {status === 'pending' && <Key className="h-3 w-3" aria-hidden="true" />}
            {status === 'suspended' && <ShieldAlert className="h-3 w-3" aria-hidden="true" />}
            <span className="capitalize">{status}</span>
        </span>
    );
}

OrganizersManagement.layout = (page: React.ReactNode) => (
    <AdminLayout title="Organizer Keys Management">{page}</AdminLayout>
);