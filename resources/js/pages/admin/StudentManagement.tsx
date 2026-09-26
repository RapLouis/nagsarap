import React, { useEffect, useState } from 'react';
import { Head, router } from '@inertiajs/react';
import AdminLayout from '@/layouts/admin-layout';
import DeleteModal from '@/components/delete-modal';
import EditStudentModal from '@/components/edit-student-modal';
import {
    Search,
    Trash2,
    UserCheck,
    ShieldAlert,
    CheckCircle2,
    X,
    Filter,
    Users,
    UserX,
    Loader2,
    RotateCcw,
    Pencil,
    ArrowUp,
    ArrowDown,
    ArrowUpDown,
} from 'lucide-react';

type Student = {
    student_id: number;
    student_number: string;
    firstname: string;
    surname: string;
    email: string;
    degree: string | null;
    year_section: string | null;
    verification_status: string;
};

type SortableColumn = 'student_number' | 'firstname' | 'email' | 'degree' | 'verification_status' | 'created_at';

type Props = {
    students: {
        data: Student[];
        links: { url: string | null; label: string; active: boolean }[];
        total?: number;
    };
    availableDegrees?: string[];
    availableSections?: string[];
    filters: {
        search?: string;
        degree?: string;
        year_section?: string;
        status?: string;
        sort?: string;
        direction?: 'asc' | 'desc';
    };
    stats?: {
        total?: number;
        verified?: number;
        pending?: number;
    };
};

const COLUMNS: { key: SortableColumn; label: string }[] = [
    { key: 'student_number', label: 'Student No.' },
    { key: 'firstname', label: 'Name' },
    { key: 'email', label: 'Email' },
    { key: 'degree', label: 'Program & Section' },
    { key: 'verification_status', label: 'Status' },
];

export default function StudentManagement({
    students,
    availableDegrees = [],
    availableSections = [],
    filters,
    stats,
}: Props) {
    const [search, setSearch] = useState(filters.search || '');
    const [selectedDegree, setSelectedDegree] = useState(filters.degree || 'all');
    const [selectedSection, setSelectedSection] = useState(filters.year_section || 'all');
    const [selectedStatus, setSelectedStatus] = useState(filters.status || 'all');
    const sort = filters.sort || 'created_at';
    const direction = filters.direction || 'desc';

    // Loading & modal state
    const [isLoading, setIsLoading] = useState(false);
    const [isDeleteModalOpen, setIsDeleteModalOpen] = useState(false);
    const [editingStudent, setEditingStudent] = useState<Student | null>(null);
    const [selectedStudent, setSelectedStudent] = useState<Student | null>(null);
    const [isDeleting, setIsDeleting] = useState(false);
    const [successMessage, setSuccessMessage] = useState<string | null>(null);

    useEffect(() => {
        if (successMessage) {
            const timer = setTimeout(() => setSuccessMessage(null), 5000);
            return () => clearTimeout(timer);
        }
    }, [successMessage]);

    const applyFilters = (newFilters: Record<string, string>) => {
        setIsLoading(true);
        router.get(
            '/admin/students',
            {
                search,
                degree: selectedDegree,
                year_section: selectedSection,
                status: selectedStatus,
                sort,
                direction,
                ...newFilters,
            },
            {
                preserveState: true,
                replace: true,
                onFinish: () => setIsLoading(false),
            }
        );
    };

    const handleSearchSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        applyFilters({ search, page: '1' });
    };

    const resetAllFilters = () => {
        setSearch('');
        setSelectedDegree('all');
        setSelectedSection('all');
        setSelectedStatus('all');
        setIsLoading(true);
        router.get('/admin/students', {}, { preserveState: true, replace: true, onFinish: () => setIsLoading(false) });
    };

    const handleSort = (column: SortableColumn) => {
        const nextDirection = sort === column && direction === 'asc' ? 'desc' : 'asc';
        applyFilters({ sort: column, direction: nextDirection, page: '1' });
    };

    const filterByStatus = (status: string) => {
        setSelectedStatus(status);
        applyFilters({ status, page: '1' });
    };

    const promptDelete = (student: Student) => {
        setSelectedStudent(student);
        setIsDeleteModalOpen(true);
    };

    const confirmDelete = () => {
        if (!selectedStudent) return;

        setIsDeleting(true);
        router.delete(`/admin/students/${selectedStudent.student_id}`, {
            onSuccess: () => {
                setIsDeleteModalOpen(false);
                setSuccessMessage(
                    `Student ${selectedStudent.firstname} ${selectedStudent.surname} (${selectedStudent.student_number}) was deleted successfully.`
                );
                setSelectedStudent(null);
            },
            onFinish: () => setIsDeleting(false),
        });
    };

    const totalCount = stats?.total ?? students.data.length;
    const verifiedCount = stats?.verified ?? students.data.filter((s) => s.verification_status === 'verified').length;
    const pendingCount = stats?.pending ?? students.data.filter((s) => s.verification_status !== 'verified').length;

    const hasActiveFilters =
        search.trim() !== '' || selectedDegree !== 'all' || selectedSection !== 'all' || selectedStatus !== 'all';

    const removeFilter = (key: 'search' | 'degree' | 'year_section' | 'status') => {
        if (key === 'search') setSearch('');
        if (key === 'degree') setSelectedDegree('all');
        if (key === 'year_section') setSelectedSection('all');
        if (key === 'status') setSelectedStatus('all');
        applyFilters({ [key]: key === 'search' ? '' : 'all', page: '1' });
    };

    return (
        <>
            <Head title="Student Management" />

            <div className="space-y-6 p-6">
                {successMessage && (
                    <div className="flex items-center justify-between rounded-2xl border border-emerald-200 bg-emerald-50 p-4 text-emerald-800 shadow-xs">
                        <div className="flex items-center gap-2.5 text-sm font-semibold">
                            <CheckCircle2 className="h-5 w-5 shrink-0 text-emerald-600" />
                            <span>{successMessage}</span>
                        </div>
                        <button onClick={() => setSuccessMessage(null)} className="rounded-lg p-1 text-emerald-600 hover:bg-emerald-100">
                            <X className="h-5 w-5" />
                        </button>
                    </div>
                )}

                <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                    <div>
                        <h2 className="text-2xl font-bold text-gray-800">Student Management</h2>
                        <p className="text-sm text-gray-500">View, search, filter, and manage registered student accounts.</p>
                    </div>
                </div>

                {/* STAT CARDS */}
                <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
                    <StatCard
                        icon={Users}
                        iconClass="bg-indigo-50 text-[#1B1F5C]"
                        label="Total Students"
                        value={totalCount}
                        active={selectedStatus === 'all'}
                        onClick={() => filterByStatus('all')}
                    />
                    <StatCard
                        icon={UserCheck}
                        iconClass="bg-emerald-50 text-emerald-600"
                        label="Verified Accounts"
                        value={verifiedCount}
                        active={selectedStatus === 'verified'}
                        onClick={() => filterByStatus('verified')}
                    />
                    <StatCard
                        icon={ShieldAlert}
                        iconClass="bg-amber-50 text-amber-600"
                        label="Pending Verification"
                        value={pendingCount}
                        active={selectedStatus === 'pending_face_verification'}
                        onClick={() => filterByStatus('pending_face_verification')}
                    />
                </div>

                {/* FILTER TOOLBAR */}
                <div className="space-y-4 rounded-2xl border border-gray-100 bg-white p-5 shadow-xs">
                    <div className="flex flex-wrap items-center justify-between gap-4">
                        <div className="flex w-full flex-wrap items-center gap-3 lg:w-auto">
                            <div className="mr-1 flex items-center gap-1.5 text-sm font-bold uppercase text-gray-400">
                                <Filter className="h-4 w-4" /> Filter:
                            </div>

                            <select
                                value={selectedDegree}
                                onChange={(e) => {
                                    setSelectedDegree(e.target.value);
                                    applyFilters({ degree: e.target.value, page: '1' });
                                }}
                                className="rounded-xl border-gray-200 bg-gray-50/50 py-2 px-3 text-sm font-semibold text-[#1B1F5C] focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                            >
                                <option value="all">All Degrees & Programs</option>
                                {availableDegrees.map((deg) => (
                                    <option key={deg} value={deg}>
                                        {deg}
                                    </option>
                                ))}
                            </select>

                            <select
                                value={selectedSection}
                                onChange={(e) => {
                                    setSelectedSection(e.target.value);
                                    applyFilters({ year_section: e.target.value, page: '1' });
                                }}
                                className="rounded-xl border-gray-200 bg-gray-50/50 py-2 px-3 text-sm font-semibold text-[#1B1F5C] focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                            >
                                <option value="all">All Years & Sections</option>
                                {availableSections.map((sec) => (
                                    <option key={sec} value={sec}>
                                        {sec}
                                    </option>
                                ))}
                            </select>
                        </div>

                        <form onSubmit={handleSearchSubmit} className="relative w-full sm:w-72">
                            <input
                                type="text"
                                placeholder="Search student no., name..."
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                className="w-full rounded-xl border border-gray-200 py-2 pl-10 pr-4 text-sm focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                            />
                            <Search className="absolute left-3.5 top-2.5 h-4 w-4 text-gray-400" />
                        </form>
                    </div>

                    {hasActiveFilters && (
                        <div className="flex items-center justify-between border-t border-gray-100 pt-3 text-sm">
                            <div className="flex flex-wrap items-center gap-2">
                                <span className="font-medium text-gray-400">Active filters:</span>
                                {search && <FilterChip label={`Search: "${search}"`} onRemove={() => removeFilter('search')} />}
                                {selectedDegree !== 'all' && (
                                    <FilterChip label={`Program: ${selectedDegree}`} onRemove={() => removeFilter('degree')} />
                                )}
                                {selectedSection !== 'all' && (
                                    <FilterChip label={`Section: ${selectedSection}`} onRemove={() => removeFilter('year_section')} />
                                )}
                                {selectedStatus !== 'all' && (
                                    <FilterChip
                                        label={`Status: ${selectedStatus === 'verified' ? 'Verified' : 'Pending'}`}
                                        onRemove={() => removeFilter('status')}
                                    />
                                )}
                            </div>
                            <button
                                onClick={resetAllFilters}
                                className="inline-flex items-center gap-1 font-semibold text-gray-500 transition hover:text-rose-600"
                            >
                                <RotateCcw className="h-3.5 w-3.5" /> Reset Filters
                            </button>
                        </div>
                    )}
                </div>

                {/* TABLE */}
                <div className="relative overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-xs">
                    {isLoading && (
                        <div className="absolute inset-0 z-20 flex items-center justify-center bg-white/60">
                            <div className="flex items-center gap-2.5 rounded-2xl border border-gray-100 bg-white px-5 py-3 text-sm font-bold text-[#1B1F5C] shadow-md">
                                <Loader2 className="h-5 w-5 animate-spin text-[#1B1F5C]" />
                                Updating records...
                            </div>
                        </div>
                    )}

                    <div className="overflow-x-auto">
                        <table className="w-full text-left text-sm text-gray-700">
                            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wider text-gray-500">
                                <tr>
                                    {COLUMNS.map((col) => (
                                        <th key={col.key} className="px-6 py-4">
                                            <button
                                                type="button"
                                                onClick={() => handleSort(col.key)}
                                                className="inline-flex items-center gap-1.5 transition hover:text-gray-900"
                                            >
                                                {col.label}
                                                {sort === col.key ? (
                                                    direction === 'asc' ? (
                                                        <ArrowUp className="h-4 w-4 text-[#1B1F5C]" />
                                                    ) : (
                                                        <ArrowDown className="h-4 w-4 text-[#1B1F5C]" />
                                                    )
                                                ) : (
                                                    <ArrowUpDown className="h-4 w-4 text-gray-300" />
                                                )}
                                            </button>
                                        </th>
                                    ))}
                                    <th className="px-6 py-4 text-right">Actions</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100 text-sm">
                                {students.data.length > 0 ? (
                                    students.data.map((student) => {
                                        const initials = `${student.firstname?.[0] || ''}${student.surname?.[0] || ''}`.toUpperCase();
                                        const isVerified = student.verification_status === 'verified';

                                        return (
                                            <tr key={student.student_id} className="group transition-colors hover:bg-gray-50/50">
                                                <td className="px-6 py-5 font-mono text-sm font-bold text-[#1B1F5C]">
                                                    {student.student_number}
                                                </td>
                                                <td className="px-6 py-5 font-medium text-gray-900">
                                                    <div className="flex items-center gap-3.5">
                                                        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-[#1B1F5C]/10 text-sm font-bold text-[#1B1F5C]">
                                                            {initials || 'ST'}
                                                        </div>
                                                        <span className="text-base font-semibold text-gray-900">
                                                            {student.firstname} {student.surname}
                                                        </span>
                                                    </div>
                                                </td>
                                                <td className="px-6 py-5 text-gray-600 text-sm">{student.email}</td>
                                                <td className="px-6 py-5 text-gray-600 text-sm">
                                                    {student.degree || 'N/A'} {student.year_section ? `- ${student.year_section}` : ''}
                                                </td>
                                                <td className="px-6 py-5">
                                                    <span
                                                        className={`inline-flex items-center gap-1.5 rounded-full px-3.5 py-1 text-xs font-bold ${
                                                            isVerified ? 'bg-emerald-50 text-emerald-700' : 'bg-amber-50 text-amber-700'
                                                        }`}
                                                    >
                                                        {isVerified ? <UserCheck className="h-4 w-4" /> : <ShieldAlert className="h-4 w-4" />}
                                                        {isVerified ? 'Verified' : 'Pending'}
                                                    </span>
                                                </td>
                                                <td className="px-6 py-5 text-right">
                                                    <div className="flex items-center justify-end gap-2 opacity-80 transition-opacity group-hover:opacity-100">
                                                        <ActionButton
                                                            title="Edit student"
                                                            onClick={() => setEditingStudent(student)}
                                                            className="hover:bg-indigo-50 hover:text-[#1B1F5C]"
                                                        >
                                                            <Pencil className="h-5 w-5" />
                                                        </ActionButton>
                                                        <ActionButton
                                                            title="Delete student"
                                                            onClick={() => promptDelete(student)}
                                                            className="hover:bg-rose-50 hover:text-rose-600"
                                                        >
                                                            <Trash2 className="h-5 w-5" />
                                                        </ActionButton>
                                                    </div>
                                                </td>
                                            </tr>
                                        );
                                    })
                                ) : (
                                    <tr>
                                        <td colSpan={6} className="px-6 py-20 text-center text-gray-400">
                                            <div className="flex flex-col items-center justify-center space-y-3">
                                                <div className="rounded-full bg-gray-50 p-4 text-gray-300">
                                                    <UserX className="h-10 w-10" />
                                                </div>
                                                <p className="text-lg font-semibold text-gray-700">No student records found</p>
                                                <p className="max-w-sm text-sm text-gray-400">
                                                    Try modifying your search query or removing active filters to view results.
                                                </p>
                                            </div>
                                        </td>
                                    </tr>
                                )}
                            </tbody>
                        </table>
                    </div>

                    {students.links && students.links.length > 3 && (
                        <div className="flex items-center justify-between border-t border-gray-100 bg-gray-50/50 px-6 py-4">
                            <div className="flex flex-wrap gap-1.5">
                                {students.links.map((link, key) => {
                                    const urlObj = link.url ? new URL(link.url, window.location.origin) : null;
                                    const pageParam = urlObj?.searchParams.get('page');

                                    return link.url ? (
                                        <button
                                            type="button"
                                            key={key}
                                            disabled={link.active || isLoading}
                                            onClick={() => pageParam && applyFilters({ page: pageParam })}
                                            className={`rounded-xl px-3.5 py-1.5 text-sm font-semibold transition ${
                                                link.active
                                                    ? 'cursor-default bg-[#1B1F5C] text-white'
                                                    : 'border border-gray-200/60 bg-white text-gray-600 hover:bg-gray-100'
                                            }`}
                                            dangerouslySetInnerHTML={{ __html: link.label }}
                                        />
                                    ) : (
                                        <span
                                            key={key}
                                            className="rounded-xl bg-transparent px-3.5 py-1.5 text-sm font-semibold text-gray-300"
                                            dangerouslySetInnerHTML={{ __html: link.label }}
                                        />
                                    );
                                })}
                            </div>
                        </div>
                    )}
                </div>
            </div>

            <DeleteModal
                isOpen={isDeleteModalOpen}
                title="Delete Student Record"
                message={`Are you sure you want to delete ${selectedStudent?.firstname} ${selectedStudent?.surname} (${selectedStudent?.student_number})?`}
                onClose={() => setIsDeleteModalOpen(false)}
                onConfirm={confirmDelete}
                isDeleting={isDeleting}
            />

            <EditStudentModal student={editingStudent} isOpen={editingStudent !== null} onClose={() => setEditingStudent(null)} />
        </>
    );
}

function StatCard({
    icon: Icon,
    iconClass,
    label,
    value,
    active,
    onClick,
}: {
    icon: React.ElementType;
    iconClass: string;
    label: string;
    value: number;
    active: boolean;
    onClick: () => void;
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            className={`flex items-center gap-4 rounded-2xl border bg-white p-5 text-left shadow-xs transition ${
                active ? 'border-[#1B1F5C] ring-2 ring-[#1B1F5C]/15' : 'border-gray-100 hover:border-gray-200'
            }`}
        >
            <div className={`rounded-xl p-3.5 ${iconClass}`}>
                <Icon className="h-6 w-6" />
            </div>
            <div>
                <p className="text-xs font-bold uppercase tracking-wider text-gray-400">{label}</p>
                <p className="text-xl font-extrabold text-gray-800">{value}</p>
            </div>
        </button>
    );
}

function FilterChip({ label, onRemove }: { label: string; onRemove: () => void }) {
    return (
        <span className="inline-flex items-center gap-1.5 rounded-xl bg-indigo-50 px-3 py-1 text-sm font-semibold text-[#1B1F5C]">
            {label}
            <button type="button" onClick={onRemove} className="rounded-full p-0.5 hover:bg-indigo-100">
                <X className="h-3.5 w-3.5" />
            </button>
        </span>
    );
}

function ActionButton({
    title,
    onClick,
    className,
    children,
}: {
    title: string;
    onClick: () => void;
    className: string;
    children: React.ReactNode;
}) {
    return (
        <button
            type="button"
            title={title}
            onClick={onClick}
            className={`rounded-xl p-2.5 text-gray-400 transition ${className}`}
        >
            {children}
        </button>
    );
}

StudentManagement.layout = (page: React.ReactNode) => <AdminLayout title="Student Management">{page}</AdminLayout>;