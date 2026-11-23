import React, { useState, useMemo } from 'react';
import { Head, useForm, router } from '@inertiajs/react';
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

export default function OrganizersManagement({ organizers = [] }: PageProps) {
    const [search, setSearch] = useState('');
    const [statusFilter, setStatusFilter] = useState<string>('all');
    const [copiedId, setCopiedId] = useState<number | null>(null);

    const [showCreateModal, setShowCreateModal] = useState(false);
    const [selectedOrganizer, setSelectedOrganizer] = useState<OrganizerItem | null>(null);
    const [showDeleteModal, setShowDeleteModal] = useState(false);

    const { data, setData, post, processing, errors, reset } = useForm({
        name: '',
        email: '',
        department: '',
        key_code: '',
        password: 'Password123!', // Default secure temporary password
    });

    const generateNewKeyCode = () => {
        const prefix = '4TTND-ORG';
        const randomPart = Math.random().toString(36).substring(2, 8).toUpperCase();
        setData('key_code', `${prefix}-${randomPart}`);
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
        navigator.clipboard.writeText(code);
        setCopiedId(id);
        setTimeout(() => setCopiedId(null), 2000);
    };

    const handleToggleStatus = (organizer: OrganizerItem) => {
        router.patch(`/admin/organizers/${organizer.id}/status`, {}, {
            preserveScroll: true,
        });
    };

    const handleDeleteKey = () => {
        if (!selectedOrganizer) return;
        router.delete(`/admin/organizers/${selectedOrganizer.id}`, {
            onSuccess: () => {
                setShowDeleteModal(false);
                setSelectedOrganizer(null);
            },
        });
    };

    const filteredOrganizers = useMemo(() => {
        return organizers.filter((item) => {
            const matchesSearch =
                item.name.toLowerCase().includes(search.toLowerCase()) ||
                item.email.toLowerCase().includes(search.toLowerCase()) ||
                item.key_code.toLowerCase().includes(search.toLowerCase());
            const matchesStatus = statusFilter === 'all' || item.status === statusFilter;
            return matchesSearch && matchesStatus;
        });
    }, [organizers, search, statusFilter]);

    const activeCount = organizers.filter((o) => o.status === 'active').length;
    const pendingCount = organizers.filter((o) => o.status === 'pending').length;
    const suspendedCount = organizers.filter((o) => o.status === 'suspended').length;

    return (
        <>
            <Head title="Organizer Keys & Access Control | 4ttend" />

            <div className="p-3 sm:p-5 font-sans text-gray-900 antialiased bg-[#F5F6FA] min-h-screen space-y-4">
                {/* EXECUTIVE HEADER & ACTIONS */}
                <header className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 bg-white p-4 sm:p-5 rounded-2xl border border-gray-200/80 shadow-xs">
                    <div className="space-y-0.5">
                        <h1 className="text-xl sm:text-2xl font-black text-[#1B1F5C] tracking-tight flex items-center gap-2">
                            <span>Organizer Access Management</span>
                            <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[10px] font-bold bg-indigo-50 text-[#1B1F5C] border border-indigo-200">
                                <KeyRound className="w-3 h-3 text-[#F5A623]" aria-hidden="true" /> Security Realm
                            </span>
                        </h1>
                        <p className="text-xs text-gray-500 font-medium">
                            Provision security keys, suspend or activate credentials, and monitor event execution access privileges.
                        </p>
                    </div>

                    <button
                        onClick={() => {
                            generateNewKeyCode();
                            setShowCreateModal(true);
                        }}
                        className="inline-flex items-center justify-center gap-2 px-4 py-2.5 min-h-[44px] bg-[#1B1F5C] hover:bg-[#131644] active:scale-98 text-white text-xs font-bold rounded-xl shadow-md transition-all cursor-pointer"
                    >
                        <Plus className="w-4 h-4 text-[#FFD600]" aria-hidden="true" />
                        <span>Issue Organizer Key</span>
                    </button>
                </header>

                {/* KPI SUMMARY RIBBON */}
                <section aria-label="Key Management Statistics" className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    <div className="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-xs flex items-center justify-between">
                        <div>
                            <span className="text-[10px] font-extrabold uppercase tracking-wider text-gray-500 block">Active Organizers</span>
                            <span className="text-2xl font-black text-[#1B1F5C] tracking-tight">{activeCount}</span>
                            <span className="text-[11px] text-emerald-600 font-bold block mt-0.5">Fully Authorized</span>
                        </div>
                        <div className="h-10 w-10 rounded-xl bg-emerald-50 text-emerald-700 border border-emerald-100 flex items-center justify-center">
                            <UserCheck className="w-5 h-5" aria-hidden="true" />
                        </div>
                    </div>

                    <div className="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-xs flex items-center justify-between">
                        <div>
                            <span className="text-[10px] font-extrabold uppercase tracking-wider text-gray-500 block">Pending Invitations</span>
                            <span className="text-2xl font-black text-amber-600 tracking-tight">{pendingCount}</span>
                            <span className="text-[11px] text-amber-700 font-bold block mt-0.5">Awaiting Activation</span>
                        </div>
                        <div className="h-10 w-10 rounded-xl bg-amber-50 text-amber-700 border border-amber-100 flex items-center justify-center">
                            <Key className="w-5 h-5" aria-hidden="true" />
                        </div>
                    </div>

                    <div className="bg-white p-4 rounded-2xl border border-gray-200/80 shadow-xs flex items-center justify-between">
                        <div>
                            <span className="text-[10px] font-extrabold uppercase tracking-wider text-gray-500 block">Suspended Keys</span>
                            <span className="text-2xl font-black text-rose-600 tracking-tight">{suspendedCount}</span>
                            <span className="text-[11px] text-rose-700 font-bold block mt-0.5">Access Revoked</span>
                        </div>
                        <div className="h-10 w-10 rounded-xl bg-rose-50 text-rose-700 border border-rose-100 flex items-center justify-center">
                            <UserX className="w-5 h-5" aria-hidden="true" />
                        </div>
                    </div>
                </section>

                {/* SEARCH & FILTER CONTROLS */}
                <main className="bg-white rounded-2xl border border-gray-200/80 shadow-xs p-4 sm:p-5 space-y-4">
                    <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-gray-100 pb-3">
                        <div className="relative flex-1 max-w-md">
                            <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" aria-hidden="true" />
                            <input
                                type="text"
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                placeholder="Search by name, email, or key code..."
                                className="w-full min-h-[38px] rounded-xl border border-gray-300 text-xs pl-10 pr-4 text-gray-900 bg-white focus-visible:outline-none"
                            />
                        </div>

                        <div className="flex items-center gap-2">
                            <Filter className="w-4 h-4 text-[#F5A623]" aria-hidden="true" />
                            <span className="text-xs font-extrabold text-gray-700">Filter Status:</span>
                            <select
                                value={statusFilter}
                                onChange={(e) => setStatusFilter(e.target.value)}
                                className="min-h-[38px] rounded-xl border border-gray-300 text-xs px-3 py-1.5 text-gray-800 bg-white font-bold focus-visible:outline-none"
                            >
                                <option value="all">All Keys ({organizers.length})</option>
                                <option value="active">Active Only</option>
                                <option value="pending">Pending Activation</option>
                                <option value="suspended">Suspended</option>
                            </select>
                        </div>
                    </div>

                    {/* ORGANIZERS DATA TABLE */}
                    {filteredOrganizers.length > 0 ? (
                        <div className="overflow-x-auto">
                            <table className="w-full text-left text-xs text-gray-700">
                                <thead>
                                    <tr className="border-b border-gray-100 text-[10px] font-extrabold uppercase tracking-wider text-gray-500">
                                        <th className="pb-3 pr-4">Organizer</th>
                                        <th className="pb-3 pr-4">Department</th>
                                        <th className="pb-3 pr-4">Key Access Code</th>
                                        <th className="pb-3 pr-4">Status</th>
                                        <th className="pb-3 pr-4 text-center">Managed Events</th>
                                        <th className="pb-3 text-right">Actions</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-gray-100">
                                    {filteredOrganizers.map((org) => (
                                        <tr key={org.id} className="hover:bg-gray-50/60 transition-colors">
                                            <td className="py-3 pr-4">
                                                <p className="font-extrabold text-gray-900">{org.name}</p>
                                                <p className="text-[11px] text-gray-500 font-medium">{org.email}</p>
                                            </td>
                                            <td className="py-3 pr-4 font-semibold text-gray-700">
                                                {org.department || 'General Admin'}
                                            </td>
                                            <td className="py-3 pr-4">
                                                <div className="inline-flex items-center gap-1.5 bg-gray-50 border border-gray-200 px-2.5 py-1 rounded-lg font-mono text-xs font-bold text-[#1B1F5C]">
                                                    <span>{org.key_code}</span>
                                                    <button
                                                        onClick={() => handleCopyKey(org.id, org.key_code)}
                                                        className="text-gray-400 hover:text-[#1B1F5C] p-0.5 rounded transition"
                                                        title="Copy Key Code"
                                                    >
                                                        {copiedId === org.id ? (
                                                            <Check className="w-3.5 h-3.5 text-emerald-600" />
                                                        ) : (
                                                            <Copy className="w-3.5 h-3.5" />
                                                        )}
                                                    </button>
                                                </div>
                                            </td>
                                            <td className="py-3 pr-4">
                                                <span
                                                    className={`inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[10px] font-extrabold border ${
                                                        org.status === 'active'
                                                            ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
                                                            : org.status === 'pending'
                                                            ? 'bg-amber-50 text-amber-700 border-amber-200'
                                                            : 'bg-rose-50 text-rose-700 border-rose-200'
                                                    }`}
                                                >
                                                    {org.status === 'active' && <ShieldCheck className="w-3 h-3" />}
                                                    {org.status === 'pending' && <Key className="w-3 h-3" />}
                                                    {org.status === 'suspended' && <ShieldAlert className="w-3 h-3" />}
                                                    <span className="capitalize">{org.status}</span>
                                                </span>
                                            </td>
                                            <td className="py-3 pr-4 text-center">
                                                <span className="font-extrabold text-gray-900 bg-gray-100 px-2 py-0.5 rounded-md text-xs">
                                                    {org.events_managed_count}
                                                </span>
                                            </td>
                                            <td className="py-3 text-right">
                                                <div className="flex items-center justify-end gap-1.5">
                                                    <button
                                                        onClick={() => handleToggleStatus(org)}
                                                        className={`px-2.5 py-1 rounded-lg border text-xs font-bold transition ${
                                                            org.status === 'active'
                                                                ? 'bg-amber-50 border-amber-200 text-amber-700 hover:bg-amber-100'
                                                                : 'bg-emerald-50 border-emerald-200 text-emerald-700 hover:bg-emerald-100'
                                                        }`}
                                                        title={org.status === 'active' ? 'Suspend Access' : 'Activate Access'}
                                                    >
                                                        {org.status === 'active' ? 'Suspend' : 'Activate'}
                                                    </button>

                                                    <button
                                                        onClick={() => {
                                                            setSelectedOrganizer(org);
                                                            setShowDeleteModal(true);
                                                        }}
                                                        className="p-1.5 text-gray-400 hover:text-rose-600 rounded-lg hover:bg-rose-50 transition"
                                                        title="Delete Key Record"
                                                    >
                                                        <Trash2 className="w-4 h-4" />
                                                    </button>
                                                </div>
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    ) : (
                        <div className="py-14 text-center space-y-2">
                            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-gray-100 text-gray-400 mx-auto">
                                <KeyRound className="w-5 h-5" aria-hidden="true" />
                            </div>
                            <p className="text-xs font-extrabold text-gray-800">No organizer keys match your filters.</p>
                        </div>
                    )}
                </main>

                {/* MODAL: ISSUE NEW ORGANIZER KEY */}
                {showCreateModal && (
                    <div className="fixed inset-0 z-50 bg-black/40 backdrop-blur-xs flex items-center justify-center p-3 sm:p-4">
                        <div className="bg-white rounded-2xl shadow-xl max-w-md w-full p-5 sm:p-6 space-y-4 border border-gray-200/80 animate-fadeIn">
                            <div className="flex items-center justify-between border-b border-gray-100 pb-3">
                                <h3 className="text-base font-black text-[#1B1F5C] flex items-center gap-2">
                                    <KeyRound className="w-5 h-5 text-[#F5A623]" />
                                    <span>Issue Organizer Access Key</span>
                                </h3>
                                <button
                                    onClick={() => setShowCreateModal(false)}
                                    className="text-gray-400 hover:text-gray-600 font-bold p-1 rounded-md"
                                >
                                    ✕
                                </button>
                            </div>

                            <form onSubmit={handleCreateSubmit} className="space-y-3.5">
                                <div>
                                    <label htmlFor="name" className="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">
                                        Organizer Full Name <span className="text-rose-500">*</span>
                                    </label>
                                    <input
                                        id="name"
                                        type="text"
                                        value={data.name}
                                        onChange={(e) => setData('name', e.target.value)}
                                        placeholder="e.g., Dr. Juan Dela Cruz"
                                        className="w-full min-h-[38px] rounded-xl border border-gray-300 text-xs px-3 text-gray-900 bg-white"
                                        required
                                    />
                                    {errors.name && <p className="text-rose-600 text-[11px] font-bold mt-1">{errors.name}</p>}
                                </div>

                                <div>
                                    <label htmlFor="email" className="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1">
                                        Institutional Email <span className="text-rose-500">*</span>
                                    </label>
                                    <input
                                        id="email"
                                        type="email"
                                        value={data.email}
                                        onChange={(e) => setData('email', e.target.value)}
                                        placeholder="e.g., organizer@mmsu.edu.ph"
                                        className="w-full min-h-[38px] rounded-xl border border-gray-300 text-xs px-3 text-gray-900 bg-white"
                                        required
                                    />
                                    {errors.email && <p className="text-rose-600 text-[11px] font-bold mt-1">{errors.email}</p>}
                                </div>

                                <div>
                                    <label
                                        htmlFor="department"
                                        className="block text-xs font-bold text-gray-700 uppercase tracking-wider mb-1"
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
                                        className="w-full min-h-[38px] rounded-xl border border-gray-300 text-xs px-3 text-gray-900 bg-white focus:outline-none focus:ring-2 focus:ring-[#1B1F5C]/20 focus:border-[#1B1F5C]"
                                    />

                                    <datalist id="department-options">
                                        <option value="CCIS">College of Computing and Information Sciences</option>
                                        <option value="COE">College of Engineering</option>
                                        <option value="CBEA">College of Business, Economics and Accountancy</option>
                                        <option value="CAS">College of Arts and Sciences</option>
                                    </datalist>
                                    {errors.department && <p className="text-rose-600 text-[11px] font-bold mt-1">{errors.department}</p>}
                                </div>

                                <div>
                                    <div className="flex justify-between items-center mb-1">
                                        <label htmlFor="key_code" className="block text-xs font-bold text-gray-700 uppercase tracking-wider">
                                            Generated Access Key Code
                                        </label>
                                        <button
                                            type="button"
                                            onClick={generateNewKeyCode}
                                            className="text-[11px] font-bold text-[#1B1F5C] hover:underline flex items-center gap-1"
                                        >
                                            <RefreshCw className="w-3 h-3 text-[#F5A623]" /> Regenerate
                                        </button>
                                    </div>
                                    <input
                                        id="key_code"
                                        type="text"
                                        value={data.key_code}
                                        readOnly
                                        className="w-full min-h-[38px] rounded-xl border border-gray-200 text-xs font-mono font-extrabold px-3 text-[#1B1F5C] bg-gray-50"
                                    />
                                </div>

                                <div className="flex justify-end gap-2 pt-3 border-t border-gray-100">
                                    <button
                                        type="button"
                                        onClick={() => setShowCreateModal(false)}
                                        className="px-4 py-2 bg-gray-100 text-gray-700 text-xs font-bold rounded-xl hover:bg-gray-200 transition"
                                    >
                                    Cancel
                                    </button>
                                    <button
                                        type="submit"
                                        disabled={processing}
                                        className="px-5 py-2 bg-[#1B1F5C] hover:bg-[#131644] text-white text-xs font-bold rounded-xl shadow-md transition"
                                    >
                                        Confirm & Issue Key
                                    </button>
                                </div>
                            </form>
                        </div>
                    </div>
                )}

                {/* MODAL: DELETE CONFIRMATION */}
                {showDeleteModal && selectedOrganizer && (
                    <div className="fixed inset-0 z-50 bg-black/40 backdrop-blur-xs flex items-center justify-center p-3 sm:p-4">
                        <div className="bg-white rounded-2xl shadow-xl max-w-sm w-full p-5 space-y-4 border border-gray-200/80 animate-fadeIn text-center">
                            <div className="h-12 w-12 rounded-2xl bg-rose-50 text-rose-600 border border-rose-100 flex items-center justify-center mx-auto">
                                <ShieldAlert className="w-6 h-6" />
                            </div>
                            <div>
                                <h3 className="text-base font-black text-gray-900">Delete Key Record?</h3>
                                <p className="text-xs text-gray-500 font-medium mt-1">
                                    Are you sure you want to permanently remove the account for{' '}
                                    <span className="font-extrabold text-gray-800">{selectedOrganizer.name}</span>?
                                </p>
                            </div>
                            <div className="flex justify-center gap-2 pt-2">
                                <button
                                    onClick={() => setShowDeleteModal(false)}
                                    className="px-4 py-2 bg-gray-100 text-gray-700 text-xs font-bold rounded-xl hover:bg-gray-200 transition"
                                >
                                    Cancel
                                </button>
                                <button
                                    onClick={handleDeleteKey}
                                    className="px-4 py-2 bg-rose-600 hover:bg-rose-700 text-white text-xs font-bold rounded-xl shadow-md transition"
                                >
                                    Yes, Delete Record
                                </button>
                            </div>
                        </div>
                    </div>
                )}
            </div>
        </>
    );
}

OrganizersManagement.layout = (page: React.ReactNode) => (
    <AdminLayout title="Organizer Keys Management">{page}</AdminLayout>
);