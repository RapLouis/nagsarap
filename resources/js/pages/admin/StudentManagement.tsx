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

type SortableColumn =
    | 'student_number'
    | 'firstname'
    | 'email'
    | 'degree'
    | 'verification_status'
    | 'created_at';

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
        router.get(
            '/admin/students',
            {},
            { preserveState: true, replace: true, onFinish: () => setIsLoading(false) }
        );
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
    const verifiedCount =
        stats?.verified ??
        students.data.filter((s) => s.verification_status === 'verified').length;
    const pendingCount =
        stats?.pending ??
        students.data.filter((s) => s.verification_status !== 'verified').length;

    const hasActiveFilters =
        search.trim() !== '' ||
        selectedDegree !== 'all' ||
        selectedSection !== 'all' ||
        selectedStatus !== 'all';

    const removeFilter = (key: 'search' | 'degree' | 'year_section' | 'status') => {
        if (key === 'search') setSearch('');
        if (key === 'degree') setSelectedDegree('all');
        if (key === 'year_section') setSelectedSection('all');
        if (key === 'status') setSelectedStatus('all');
        applyFilters({ [key]: key === 'search' ? '' : 'all', page: '1' });
    };

    const extractPageParam = (url: string | null): string | null => {
        if (!url) return null;
        try {
            const urlObj = new URL(url, window.location.origin);
            return urlObj.searchParams.get('page');
        } catch {
            return null;
        }
    };

    return (
        <>
            <Head title="Student Management | 4ttnd Attendance System" />

            <div className="min-h-screen space-y-4 bg-[#F5F6FA] p-3 font-sans text-gray-900 antialiased sm:p-5">
                {successMessage && (
                    <div
                        role="status"
                        aria-live="polite"
                        className="flex items-center justify-between gap-3 rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-emerald-900 shadow-xs"
                    >
                        <div className="flex items-center gap-2.5 text-xs font-bold sm:text-sm">
                            <CheckCircle2
                                className="h-5 w-5 shrink-0 text-emerald-600"
                                aria-hidden="true"
                            />
                            <span>{successMessage}</span>
                        </div>
                        <button
                            type="button"
                            onClick={() => setSuccessMessage(null)}
                            aria-label="Dismiss notification"
                            className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-lg text-emerald-700 transition-colors hover:bg-emerald-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                        >
                            <X className="h-4 w-4" aria-hidden="true" />
                        </button>
                    </div>
                )}

                {/* PAGE HEADER */}
                <header className="flex flex-col gap-2 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs sm:flex-row sm:items-center sm:justify-between sm:p-5">
                    <div className="space-y-0.5">
                        <h1 className="text-xl font-black tracking-tight text-[#1B1F5C] sm:text-2xl">
                            Student Management
                        </h1>
                        <p className="text-xs font-medium text-gray-600">
                            View, search, filter, and manage registered student accounts and facial verification status.
                        </p>
                    </div>
                </header>

                {/* STAT CARDS (QUICK STATUS FILTERS) */}
                <section
                    aria-label="Student Account Statistics"
                    className="grid grid-cols-1 gap-3 sm:grid-cols-3"
                >
                    <StatCard
                        icon={Users}
                        iconClass="border-[#1B1F5C]/15 bg-[#1B1F5C]/5 text-[#1B1F5C]"
                        label="Total Students"
                        value={totalCount}
                        active={selectedStatus === 'all'}
                        onClick={() => filterByStatus('all')}
                    />
                    <StatCard
                        icon={UserCheck}
                        iconClass="border-emerald-200/80 bg-emerald-50 text-emerald-700"
                        label="Verified Accounts"
                        value={verifiedCount}
                        active={selectedStatus === 'verified'}
                        onClick={() => filterByStatus('verified')}
                    />
                    <StatCard
                        icon={ShieldAlert}
                        iconClass="border-amber-200/80 bg-amber-50 text-amber-800"
                        label="Pending Verification"
                        value={pendingCount}
                        active={selectedStatus === 'pending_face_verification'}
                        onClick={() => filterByStatus('pending_face_verification')}
                    />
                </section>

                {/* FILTER TOOLBAR */}
                <section
                    aria-label="Student Filter Controls"
                    className="space-y-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs"
                >
                    <div className="flex flex-col justify-between gap-3 lg:flex-row lg:items-center">
                        <div className="flex flex-wrap items-center gap-2">
                            <div className="mr-1 flex items-center gap-1.5 text-[11px] font-extrabold uppercase tracking-wider text-gray-500">
                                <Filter className="h-3.5 w-3.5 text-[#1B1F5C]" aria-hidden="true" />
                                <span>Filter</span>
                            </div>

                            <select
                                aria-label="Filter by Degree or Program"
                                value={selectedDegree}
                                onChange={(e) => {
                                    setSelectedDegree(e.target.value);
                                    applyFilters({ degree: e.target.value, page: '1' });
                                }}
                                className="min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-bold text-[#1B1F5C] transition-colors focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            >
                                <option value="all">All Degrees &amp; Programs</option>
                                {availableDegrees.map((deg) => (
                                    <option key={deg} value={deg}>
                                        {deg}
                                    </option>
                                ))}
                            </select>

                            <select
                                aria-label="Filter by Year and Section"
                                value={selectedSection}
                                onChange={(e) => {
                                    setSelectedSection(e.target.value);
                                    applyFilters({ year_section: e.target.value, page: '1' });
                                }}
                                className="min-h-[38px] rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-bold text-[#1B1F5C] transition-colors focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            >
                                <option value="all">All Years &amp; Sections</option>
                                {availableSections.map((sec) => (
                                    <option key={sec} value={sec}>
                                        {sec}
                                    </option>
                                ))}
                            </select>
                        </div>

                        <form
                            onSubmit={handleSearchSubmit}
                            role="search"
                            className="flex w-full items-center gap-2 lg:w-auto"
                        >
                            <div className="relative flex-1 lg:w-72">
                                <Search
                                    className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400"
                                    aria-hidden="true"
                                />
                                <input
                                    type="text"
                                    aria-label="Search students by student number, name, or email"
                                    placeholder="Search student no., name..."
                                    value={search}
                                    onChange={(e) => setSearch(e.target.value)}
                                    className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white py-1.5 pl-9 pr-8 text-xs font-medium text-gray-900 placeholder:text-gray-400 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                />
                                {search && (
                                    <button
                                        type="button"
                                        onClick={() => removeFilter('search')}
                                        aria-label="Clear search text"
                                        className="absolute right-2 top-1/2 -translate-y-1/2 rounded-md p-1 text-gray-400 hover:bg-gray-100 hover:text-gray-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    >
                                        <X className="h-3.5 w-3.5" aria-hidden="true" />
                                    </button>
                                )}
                            </div>
                            <button
                                type="submit"
                                disabled={isLoading}
                                className="inline-flex min-h-[38px] shrink-0 items-center justify-center rounded-xl bg-[#1B1F5C] px-3.5 py-1.5 text-xs font-bold text-white transition-colors hover:bg-[#131644] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-60"
                            >
                                Search
                            </button>
                        </form>
                    </div>

                    {hasActiveFilters && (
                        <div className="flex flex-wrap items-center justify-between gap-2 border-t border-gray-100 pt-2.5 text-xs">
                            <div className="flex flex-wrap items-center gap-1.5">
                                <span className="font-bold text-gray-500">Active filters:</span>
                                {search.trim() !== '' && (
                                    <FilterChip
                                        label={`Search: "${search}"`}
                                        onRemove={() => removeFilter('search')}
                                    />
                                )}
                                {selectedDegree !== 'all' && (
                                    <FilterChip
                                        label={`Program: ${selectedDegree}`}
                                        onRemove={() => removeFilter('degree')}
                                    />
                                )}
                                {selectedSection !== 'all' && (
                                    <FilterChip
                                        label={`Section: ${selectedSection}`}
                                        onRemove={() => removeFilter('year_section')}
                                    />
                                )}
                                {selectedStatus !== 'all' && (
                                    <FilterChip
                                        label={`Status: ${selectedStatus === 'verified' ? 'Verified' : 'Pending'}`}
                                        onRemove={() => removeFilter('status')}
                                    />
                                )}
                            </div>
                            <button
                                type="button"
                                onClick={resetAllFilters}
                                className="inline-flex min-h-[32px] items-center gap-1 rounded-lg px-2 py-1 text-xs font-bold text-gray-600 transition-colors hover:bg-rose-50 hover:text-rose-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            >
                                <RotateCcw className="h-3.5 w-3.5" aria-hidden="true" />
                                <span>Reset All</span>
                            </button>
                        </div>
                    )}
                </section>

                {/* RECORDS CONTAINER (MOBILE CARDS + DESKTOP TABLE) */}
                <main
                    aria-label="Student Directory"
                    className="relative overflow-hidden rounded-2xl border border-gray-200/80 bg-white shadow-xs"
                >
                    {isLoading && (
                        <div
                            role="status"
                            aria-live="polite"
                            className="absolute inset-0 z-20 flex items-center justify-center bg-white/75"
                        >
                            <div className="flex items-center gap-2 rounded-xl border border-gray-200 bg-white px-4 py-2.5 text-xs font-bold text-[#1B1F5C] shadow-xs">
                                <Loader2
                                    className="h-4 w-4 animate-spin text-[#1B1F5C] motion-reduce:animate-none"
                                    aria-hidden="true"
                                />
                                <span>Updating records...</span>
                            </div>
                        </div>
                    )}

                    {/* MOBILE VIEW (< md): Compact Stacked Cards */}
                    <div className="divide-y divide-gray-100 md:hidden" aria-live="polite">
                        {students.data.length > 0 ? (
                            students.data.map((student) => {
                                const initials = `${student.firstname?.[0] || ''}${student.surname?.[0] || ''}`.toUpperCase();
                                const isVerified = student.verification_status === 'verified';
                                const fullName = `${student.firstname} ${student.surname}`;

                                return (
                                    <article key={student.student_id} className="space-y-2.5 p-3.5">
                                        <div className="flex items-start justify-between gap-2">
                                            <div className="flex min-w-0 items-center gap-2.5">
                                                <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 text-xs font-black text-[#1B1F5C]">
                                                    {initials || 'ST'}
                                                </div>
                                                <div className="min-w-0">
                                                    <p className="truncate text-sm font-extrabold text-gray-900">
                                                        {fullName}
                                                    </p>
                                                    <p className="font-mono text-xs font-bold text-[#1B1F5C]">
                                                        {student.student_number}
                                                    </p>
                                                </div>
                                            </div>
                                            <StatusBadge isVerified={isVerified} />
                                        </div>

                                        <div className="space-y-0.5 pl-11 text-xs text-gray-600">
                                            <p className="truncate">{student.email}</p>
                                            <p className="font-medium text-gray-700">
                                                {student.degree || 'N/A'}
                                                {student.year_section ? ` • ${student.year_section}` : ''}
                                            </p>
                                        </div>

                                        <div className="flex items-center justify-end gap-2 border-t border-gray-100 pt-2">
                                            <button
                                                type="button"
                                                onClick={() => setEditingStudent(student)}
                                                aria-label={`Edit ${fullName}`}
                                                className="inline-flex min-h-[38px] items-center gap-1.5 rounded-lg border border-gray-200 bg-white px-3 py-1.5 text-xs font-bold text-[#1B1F5C] transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                            >
                                                <Pencil className="h-3.5 w-3.5" aria-hidden="true" />
                                                <span>Edit</span>
                                            </button>
                                            <button
                                                type="button"
                                                onClick={() => promptDelete(student)}
                                                aria-label={`Delete ${fullName}`}
                                                className="inline-flex min-h-[38px] items-center gap-1.5 rounded-lg border border-rose-200 bg-rose-50/70 px-3 py-1.5 text-xs font-bold text-rose-700 transition-colors hover:bg-rose-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                            >
                                                <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
                                                <span>Delete</span>
                                            </button>
                                        </div>
                                    </article>
                                );
                            })
                        ) : (
                            <EmptyRecordsState
                                hasActiveFilters={hasActiveFilters}
                                onReset={resetAllFilters}
                            />
                        )}
                    </div>

                    {/* DESKTOP & TABLET VIEW (>= md): High-Density Data Table */}
                    <div className="hidden overflow-x-auto md:block">
                        <table className="w-full text-left text-xs text-gray-700 sm:text-sm">
                            <thead className="border-b border-gray-200/80 bg-gray-50/80 text-[10px] font-extrabold uppercase tracking-wider text-gray-500">
                                <tr>
                                    {COLUMNS.map((col) => {
                                        const isSorted = sort === col.key;
                                        const ariaSort = isSorted
                                            ? direction === 'asc'
                                                ? 'ascending'
                                                : 'descending'
                                            : 'none';

                                        return (
                                            <th
                                                key={col.key}
                                                scope="col"
                                                aria-sort={ariaSort}
                                                className="px-4 py-3 lg:px-5"
                                            >
                                                <button
                                                    type="button"
                                                    onClick={() => handleSort(col.key)}
                                                    className="inline-flex min-h-[32px] items-center gap-1.5 rounded-md px-1 transition-colors hover:text-[#1B1F5C] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                >
                                                    <span>{col.label}</span>
                                                    {isSorted ? (
                                                        direction === 'asc' ? (
                                                            <ArrowUp
                                                                className="h-3.5 w-3.5 text-[#1B1F5C]"
                                                                aria-hidden="true"
                                                            />
                                                        ) : (
                                                            <ArrowDown
                                                                className="h-3.5 w-3.5 text-[#1B1F5C]"
                                                                aria-hidden="true"
                                                            />
                                                        )
                                                    ) : (
                                                        <ArrowUpDown
                                                            className="h-3.5 w-3.5 text-gray-400"
                                                            aria-hidden="true"
                                                        />
                                                    )}
                                                </button>
                                            </th>
                                        );
                                    })}
                                    <th scope="col" className="px-4 py-3 text-right lg:px-5">
                                        Actions
                                    </th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100 text-xs sm:text-sm" aria-live="polite">
                                {students.data.length > 0 ? (
                                    students.data.map((student) => {
                                        const initials = `${student.firstname?.[0] || ''}${student.surname?.[0] || ''}`.toUpperCase();
                                        const isVerified = student.verification_status === 'verified';
                                        const fullName = `${student.firstname} ${student.surname}`;

                                        return (
                                            <tr
                                                key={student.student_id}
                                                className="transition-colors hover:bg-[#F5F6FA]/70"
                                            >
                                                <td className="whitespace-nowrap px-4 py-3 font-mono text-xs font-bold text-[#1B1F5C] lg:px-5">
                                                    {student.student_number}
                                                </td>
                                                <td className="px-4 py-3 font-bold text-gray-900 lg:px-5">
                                                    <div className="flex items-center gap-2.5">
                                                        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 text-xs font-black text-[#1B1F5C]">
                                                            {initials || 'ST'}
                                                        </div>
                                                        <span className="font-extrabold text-gray-900">
                                                            {fullName}
                                                        </span>
                                                    </div>
                                                </td>
                                                <td className="px-4 py-3 text-xs font-medium text-gray-600 lg:px-5">
                                                    {student.email}
                                                </td>
                                                <td className="whitespace-nowrap px-4 py-3 text-xs font-medium text-gray-700 lg:px-5">
                                                    {student.degree || 'N/A'}
                                                    {student.year_section
                                                        ? ` - ${student.year_section}`
                                                        : ''}
                                                </td>
                                                <td className="whitespace-nowrap px-4 py-3 lg:px-5">
                                                    <StatusBadge isVerified={isVerified} />
                                                </td>
                                                <td className="whitespace-nowrap px-4 py-3 text-right lg:px-5">
                                                    <div className="inline-flex items-center justify-end gap-1">
                                                        <ActionButton
                                                            title={`Edit ${fullName}`}
                                                            onClick={() => setEditingStudent(student)}
                                                            className="hover:bg-[#1B1F5C]/10 hover:text-[#1B1F5C]"
                                                        >
                                                            <Pencil className="h-4 w-4" aria-hidden="true" />
                                                        </ActionButton>
                                                        <ActionButton
                                                            title={`Delete ${fullName}`}
                                                            onClick={() => promptDelete(student)}
                                                            className="hover:bg-rose-50 hover:text-rose-700"
                                                        >
                                                            <Trash2 className="h-4 w-4" aria-hidden="true" />
                                                        </ActionButton>
                                                    </div>
                                                </td>
                                            </tr>
                                        );
                                    })
                                ) : (
                                    <tr>
                                        <td colSpan={6}>
                                            <EmptyRecordsState
                                                hasActiveFilters={hasActiveFilters}
                                                onReset={resetAllFilters}
                                            />
                                        </td>
                                    </tr>
                                )}
                            </tbody>
                        </table>
                    </div>

                    {/* PAGINATION FOOTER */}
                    {students.links && students.links.length > 3 && (
                        <nav
                            aria-label="Student directory pagination"
                            className="flex flex-col items-center justify-between gap-2.5 border-t border-gray-200/80 bg-gray-50/60 px-4 py-3 sm:flex-row lg:px-5"
                        >
                            <p className="text-xs font-medium text-gray-600">
                                Showing{' '}
                                <span className="font-bold text-gray-900">
                                    {students.data.length}
                                </span>
                                {typeof students.total === 'number' && (
                                    <>
                                        {' '}
                                        of{' '}
                                        <span className="font-bold text-gray-900">
                                            {students.total.toLocaleString()}
                                        </span>
                                    </>
                                )}{' '}
                                students
                            </p>

                            <div className="flex flex-wrap items-center justify-center gap-1.5">
                                {students.links.map((link, key) => {
                                    const pageParam = extractPageParam(link.url);

                                    return link.url ? (
                                        <button
                                            type="button"
                                            key={key}
                                            disabled={link.active || isLoading}
                                            aria-current={link.active ? 'page' : undefined}
                                            onClick={() =>
                                                pageParam && applyFilters({ page: pageParam })
                                            }
                                            className={`min-h-[38px] min-w-[38px] rounded-xl px-3 py-1 text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                link.active
                                                    ? 'cursor-default bg-[#1B1F5C] text-white'
                                                    : 'border border-gray-200 bg-white text-gray-700 hover:bg-gray-100'
                                            }`}
                                            dangerouslySetInnerHTML={{ __html: link.label }}
                                        />
                                    ) : (
                                        <span
                                            key={key}
                                            aria-hidden="true"
                                            className="flex min-h-[38px] items-center rounded-xl px-2.5 py-1 text-xs font-bold text-gray-400"
                                            dangerouslySetInnerHTML={{ __html: link.label }}
                                        />
                                    );
                                })}
                            </div>
                        </nav>
                    )}
                </main>
            </div>

            <DeleteModal
                isOpen={isDeleteModalOpen}
                title="Delete Student Record"
                message={`Are you sure you want to delete ${selectedStudent?.firstname} ${selectedStudent?.surname} (${selectedStudent?.student_number})?`}
                onClose={() => setIsDeleteModalOpen(false)}
                onConfirm={confirmDelete}
                isDeleting={isDeleting}
            />

            <EditStudentModal
                student={editingStudent}
                isOpen={editingStudent !== null}
                onClose={() => setEditingStudent(null)}
            />
        </>
    );
}

function StatusBadge({ isVerified }: { isVerified: boolean }) {
    return (
        <span
            className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-bold ${
                isVerified
                    ? 'border-emerald-200 bg-emerald-50 text-emerald-800'
                    : 'border-amber-200 bg-amber-50 text-amber-800'
            }`}
        >
            {isVerified ? (
                <UserCheck className="h-3.5 w-3.5 text-emerald-600" aria-hidden="true" />
            ) : (
                <ShieldAlert className="h-3.5 w-3.5 text-amber-600" aria-hidden="true" />
            )}
            <span>{isVerified ? 'Verified' : 'Pending'}</span>
        </span>
    );
}

function EmptyRecordsState({
    hasActiveFilters,
    onReset,
}: {
    hasActiveFilters: boolean;
    onReset: () => void;
}) {
    return (
        <div className="flex flex-col items-center justify-center space-y-2.5 px-6 py-14 text-center">
            <div className="rounded-2xl border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 p-3 text-[#1B1F5C]">
                <UserX className="h-7 w-7" aria-hidden="true" />
            </div>
            <p className="text-sm font-bold text-gray-900">
                {hasActiveFilters ? 'No matching student records' : 'No students registered yet'}
            </p>
            <p className="max-w-xs text-xs text-gray-500">
                {hasActiveFilters
                    ? 'Try adjusting your search query or clearing active filters to view matching students.'
                    : 'Registered student accounts and their facial verification status will appear here.'}
            </p>
            {hasActiveFilters && (
                <div className="pt-1">
                    <button
                        type="button"
                        onClick={onReset}
                        className="inline-flex min-h-[38px] items-center gap-1.5 rounded-xl border border-gray-300 bg-white px-3.5 py-1.5 text-xs font-bold text-[#1B1F5C] transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                    >
                        <RotateCcw className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                        <span>Clear All Filters</span>
                    </button>
                </div>
            )}
        </div>
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
            aria-pressed={active}
            onClick={onClick}
            className={`flex min-h-[44px] items-center gap-3.5 rounded-2xl border bg-white p-4 text-left shadow-xs transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                active
                    ? 'border-[#1B1F5C] ring-1 ring-[#1B1F5C]'
                    : 'border-gray-200/80 hover:border-gray-300'
            }`}
        >
            <div className={`shrink-0 rounded-xl border p-2.5 ${iconClass}`}>
                <Icon className="h-5 w-5" aria-hidden="true" />
            </div>
            <div>
                <p className="text-[11px] font-extrabold uppercase tracking-wider text-gray-600">
                    {label}
                </p>
                <p className="text-xl font-black tracking-tight text-gray-900">
                    {value.toLocaleString()}
                </p>
            </div>
        </button>
    );
}

function FilterChip({ label, onRemove }: { label: string; onRemove: () => void }) {
    return (
        <span className="inline-flex items-center gap-1.5 rounded-lg border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 px-2.5 py-1 text-xs font-bold text-[#1B1F5C]">
            <span>{label}</span>
            <button
                type="button"
                onClick={onRemove}
                aria-label={`Remove ${label} filter`}
                className="rounded-md p-0.5 transition-colors hover:bg-[#1B1F5C]/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
            >
                <X className="h-3 w-3" aria-hidden="true" />
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
            aria-label={title}
            onClick={onClick}
            className={`inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-lg p-2 text-gray-500 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${className}`}
        >
            {children}
        </button>
    );
}

StudentManagement.layout = (page: React.ReactNode) => (
    <AdminLayout title="Student Management">{page}</AdminLayout>
);