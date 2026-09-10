import React, { useState, useEffect } from 'react';
import { Head, Link, router } from '@inertiajs/react';
import AdminLayout from '@/layouts/admin-layout';
import DeleteModal from '@/components/delete-modal';
import { Search, Trash2, UserCheck, ShieldAlert, CheckCircle2, X, Filter } from 'lucide-react';

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

type Props = {
    students: {
        data: Student[];
        links: { url: string | null; label: string; active: boolean }[];
    };
    availableDegrees?: string[];
    availableSections?: string[];
    filters: {
        search?: string;
        degree?: string;
        year_section?: string;
        status?: string;
    };
};

export default function StudentManagement({
    students,
    availableDegrees = [],
    availableSections = [],
    filters,
}: Props) {
    const [search, setSearch] = useState(filters.search || '');
    const [selectedDegree, setSelectedDegree] = useState(filters.degree || 'all');
    const [selectedSection, setSelectedSection] = useState(filters.year_section || 'all');
    const [selectedStatus, setSelectedStatus] = useState(filters.status || 'all');

    // Modal & Toast Notification State
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [selectedStudent, setSelectedStudent] = useState<Student | null>(null);
    const [isDeleting, setIsDeleting] = useState(false);
    const [successMessage, setSuccessMessage] = useState<string | null>(null);

    // Auto-dismiss 5-second banner timer
    useEffect(() => {
        if (successMessage) {
            const timer = setTimeout(() => setSuccessMessage(null), 5000);
            return () => clearTimeout(timer);
        }
    }, [successMessage]);

    // Dispatch search/filter parameters
    const applyFilters = (newFilters: Record<string, string>) => {
        router.get(
            '/admin/students',
            {
                search,
                degree: selectedDegree,
                year_section: selectedSection,
                status: selectedStatus,
                ...newFilters,
            },
            { preserveState: true, replace: true }
        );
    };

    const handleSearchSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        applyFilters({ search });
    };

    const promptDelete = (student: Student) => {
        setSelectedStudent(student);
        setIsModalOpen(true);
    };

    const confirmDelete = () => {
        if (!selectedStudent) return;

        setIsDeleting(true);
        router.delete(`/admin/students/${selectedStudent.student_id}`, {
            onSuccess: () => {
                setIsModalOpen(false);
                setSuccessMessage(
                    `Student ${selectedStudent.firstname} ${selectedStudent.surname} (${selectedStudent.student_number}) was deleted successfully.`
                );
                setSelectedStudent(null);
            },
            onFinish: () => setIsDeleting(false),
        });
    };

    return (
        <>
            <Head title="Student Management" />

            <div className="p-6 space-y-6">
                {/* 5-SECOND SUCCESS BANNER */}
                {successMessage && (
                    <div className="flex items-center justify-between rounded-2xl bg-emerald-50 border border-emerald-200 p-4 text-emerald-800 shadow-xs transition-all">
                        <div className="flex items-center gap-2 text-xs font-semibold">
                            <CheckCircle2 className="h-4 w-4 text-emerald-600 shrink-0" />
                            <span>{successMessage}</span>
                        </div>
                        <button
                            onClick={() => setSuccessMessage(null)}
                            className="rounded-lg p-1 text-emerald-600 hover:bg-emerald-100"
                        >
                            <X className="h-4 w-4" />
                        </button>
                    </div>
                )}

                {/* HEADER */}
                <div>
                    <h2 className="text-xl font-bold text-gray-800">Student Management</h2>
                    <p className="text-xs text-gray-500">View, search, and filter registered student accounts</p>
                </div>

                {/* FILTER TOOLBAR */}
                <div className="flex flex-wrap items-center justify-between gap-4 bg-white p-4 rounded-2xl border border-gray-100 shadow-xs">
                    {/* DROPDOWN FILTERS */}
                    <div className="flex flex-wrap items-center gap-3">
                        <div className="flex items-center gap-1.5 text-xs font-bold text-gray-400 uppercase mr-1">
                            <Filter className="h-3.5 w-3.5" /> Filter:
                        </div>

                        {/* Degree / Program Filter */}
                        <select
                            value={selectedDegree}
                            onChange={(e) => {
                                setSelectedDegree(e.target.value);
                                applyFilters({ degree: e.target.value });
                            }}
                            className="rounded-xl border-gray-200 bg-gray-50/50 py-1.5 text-xs font-semibold text-[#1B1F5C] focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                        >
                            <option value="all">All Degrees & Programs</option>
                            {availableDegrees.map((deg) => (
                                <option key={deg} value={deg}>
                                    {deg}
                                </option>
                            ))}
                        </select>

                        {/* Year & Section Filter */}
                        <select
                            value={selectedSection}
                            onChange={(e) => {
                                setSelectedSection(e.target.value);
                                applyFilters({ year_section: e.target.value });
                            }}
                            className="rounded-xl border-gray-200 bg-gray-50/50 py-1.5 text-xs font-semibold text-[#1B1F5C] focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                        >
                            <option value="all">All Years & Sections</option>
                            {availableSections.map((sec) => (
                                <option key={sec} value={sec}>
                                    {sec}
                                </option>
                            ))}
                        </select>

                        {/* Status Filter */}
                        <select
                            value={selectedStatus}
                            onChange={(e) => {
                                setSelectedStatus(e.target.value);
                                applyFilters({ status: e.target.value });
                            }}
                            className="rounded-xl border-gray-200 bg-gray-50/50 py-1.5 text-xs font-semibold text-[#1B1F5C] focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                        >
                            <option value="all">All Statuses</option>
                            <option value="verified">Verified</option>
                            <option value="pending_face_verification">Pending Verification</option>
                        </select>
                    </div>

                    {/* SEARCH INPUT */}
                    <form onSubmit={handleSearchSubmit} className="relative w-full sm:w-64">
                        <input
                            type="text"
                            placeholder="Search student no., name, or email..."
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                            className="w-full pl-9 pr-4 py-1.5 text-xs rounded-xl border border-gray-200 focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                        />
                        <Search className="absolute left-3 top-2 h-3.5 w-3.5 text-gray-400" />
                    </form>
                </div>

                {/* STUDENTS TABLE */}
                <div className="overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-xs">
                    <table className="w-full text-left text-sm text-gray-600">
                        <thead className="bg-gray-50 text-[11px] font-semibold uppercase text-gray-500">
                            <tr>
                                <th className="px-6 py-3">Student No.</th>
                                <th className="px-6 py-3">Name</th>
                                <th className="px-6 py-3">Email</th>
                                <th className="px-6 py-3">Program & Section</th>
                                <th className="px-6 py-3">Status</th>
                                <th className="px-6 py-3 text-right">Actions</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-100 text-xs">
                            {students.data.length > 0 ? (
                                students.data.map((student) => (
                                    <tr key={student.student_id} className="hover:bg-gray-50/50">
                                        <td className="px-6 py-4 font-bold text-[#1B1F5C]">
                                            {student.student_number}
                                        </td>
                                        <td className="px-6 py-4 font-medium text-gray-900">
                                            {student.firstname} {student.surname}
                                        </td>
                                        <td className="px-6 py-4 text-gray-500">{student.email}</td>
                                        <td className="px-6 py-4 text-gray-500">
                                            {student.degree || 'N/A'}{' '}
                                            {student.year_section ? `- ${student.year_section}` : ''}
                                        </td>
                                        <td className="px-6 py-4">
                                            <span
                                                className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[10px] font-semibold ${
                                                    student.verification_status === 'verified'
                                                        ? 'bg-emerald-50 text-emerald-700'
                                                        : 'bg-amber-50 text-amber-700'
                                                }`}
                                            >
                                                {student.verification_status === 'verified' ? (
                                                    <UserCheck className="h-3 w-3" />
                                                ) : (
                                                    <ShieldAlert className="h-3 w-3" />
                                                )}
                                                {student.verification_status === 'verified' ? 'Verified' : 'Pending'}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4 text-right">
                                            <button
                                                onClick={() => promptDelete(student)}
                                                className="rounded-lg p-1.5 text-gray-400 hover:bg-rose-50 hover:text-rose-600 transition"
                                                title="Delete Student"
                                            >
                                                <Trash2 className="h-4 w-4" />
                                            </button>
                                        </td>
                                    </tr>
                                ))
                            ) : (
                                <tr>
                                    <td colSpan={6} className="px-6 py-8 text-center text-gray-400">
                                        No student records match your selected filters.
                                    </td>
                                </tr>
                            )}
                        </tbody>
                    </table>

                    {/* PAGINATION */}
                    {students.links && students.links.length > 3 && (
                        <div className="flex items-center justify-between border-t border-gray-100 bg-gray-50/50 px-6 py-3">
                            <div className="flex gap-1">
                                {students.links.map((link, key) =>
                                    link.url ? (
                                        <Link
                                            key={key}
                                            href={link.url}
                                            className={`rounded-lg px-3 py-1 text-xs font-semibold transition ${
                                                link.active
                                                    ? 'bg-[#1B1F5C] text-white'
                                                    : 'bg-white text-gray-600 hover:bg-gray-100'
                                            }`}
                                            dangerouslySetInnerHTML={{ __html: link.label }}
                                        />
                                    ) : (
                                        <span
                                            key={key}
                                            className="rounded-lg px-3 py-1 text-xs font-semibold text-gray-400"
                                            dangerouslySetInnerHTML={{ __html: link.label }}
                                        />
                                    )
                                )}
                            </div>
                        </div>
                    )}
                </div>
            </div>

            {/* DELETE MODAL */}
            <DeleteModal
                isOpen={isModalOpen}
                title="Delete Student Record"
                message={`Are you sure you want to delete ${selectedStudent?.firstname} ${selectedStudent?.surname} (${selectedStudent?.student_number})?`}
                onClose={() => setIsModalOpen(false)}
                onConfirm={confirmDelete}
                isDeleting={isDeleting}
            />
        </>
    );
}

StudentManagement.layout = (page: React.ReactNode) => <AdminLayout title="Student Management">{page}</AdminLayout>;