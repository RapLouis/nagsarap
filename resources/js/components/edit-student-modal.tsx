import { useEffect, useState } from 'react';
import { router } from '@inertiajs/react';
import { Loader2, Pencil, X, CheckCircle2, AlertCircle } from 'lucide-react';

type EditableStudent = {
    student_id: number;
    student_number: string;
    firstname: string;
    surname: string;
    email: string;
    degree: string | null;
    year_section: string | null;
};

type Props = {
    student: EditableStudent | null;
    isOpen: boolean;
    onClose: () => void;
};

type FormState = {
    student_number: string;
    firstname: string;
    surname: string;
    email: string;
    degree: string;
    year_section: string;
};

const emptyForm: FormState = {
    student_number: '',
    firstname: '',
    surname: '',
    email: '',
    degree: '',
    year_section: '',
};

export default function EditStudentModal({ student, isOpen, onClose }: Props) {
    const [form, setForm] = useState<FormState>(emptyForm);
    const [errors, setErrors] = useState<Record<string, string>>({});
    const [isSaving, setIsSaving] = useState(false);
    
    // States for confirmation and success steps
    const [showConfirmModal, setShowConfirmModal] = useState(false);
    const [showSuccessModal, setShowSuccessModal] = useState(false);

    useEffect(() => {
        if (student) {
            setForm({
                student_number: student.student_number ?? '',
                firstname: student.firstname ?? '',
                surname: student.surname ?? '',
                email: student.email ?? '',
                degree: student.degree ?? '',
                year_section: student.year_section ?? '',
            });
            setErrors({});
            setShowConfirmModal(false);
            setShowSuccessModal(false);
        }
    }, [student]);

    if (!isOpen || !student) return null;

    const field = (name: keyof FormState) => ({
        value: form[name],
        onChange: (e: React.ChangeEvent<HTMLInputElement>) => setForm((prev) => ({ ...prev, [name]: e.target.value })),
    });

    const handleInitialSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        setShowConfirmModal(true);
    };

    const executeSave = () => {
        setShowConfirmModal(false);
        setIsSaving(true);

        router.patch(`/admin/students/${student.student_id}`, form, {
            preserveScroll: true,
            onSuccess: () => {
                setIsSaving(false);
                setShowSuccessModal(true);

                setTimeout(() => {
                    setShowSuccessModal(false);
                    onClose();
                }, 1000);
            },
            onError: (formErrors: Record<string, string>) => {
                setIsSaving(false);
                setErrors(formErrors);
            },
            onFinish: () => setIsSaving(false),
        });
    };

    return (
        <>
            {/* MAIN EDIT MODAL */}
            <div
                role="dialog"
                aria-modal="true"
                aria-labelledby="edit-student-title"
                className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 backdrop-blur-sm transition-opacity duration-300 animate-fadeIn"
            >
                <div className="w-full max-w-lg transform rounded-2xl border border-gray-100 bg-white p-6 shadow-2xl transition-all duration-300 animate-scaleUp">
                    <div className="mb-5 flex items-center justify-between">
                        <div className="flex items-center gap-3">
                            <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-[#1B1F5C]/10 text-[#1B1F5C]">
                                <Pencil className="h-5 w-5" />
                            </div>
                            <h3 id="edit-student-title" className="text-lg font-bold text-gray-800">
                                Edit Student Information
                            </h3>
                        </div>
                        <button
                            type="button"
                            onClick={onClose}
                            className="rounded-xl p-2 text-gray-400 transition hover:bg-gray-100 hover:text-gray-600"
                        >
                            <X className="h-5 w-5" />
                        </button>
                    </div>

                    <form onSubmit={handleInitialSubmit} className="space-y-4">
                        <div className="grid grid-cols-2 gap-4">
                            <FormField label="First name" error={errors.firstname}>
                                <input {...field('firstname')} className={inputClass(!!errors.firstname)} />
                            </FormField>
                            <FormField label="Surname" error={errors.surname}>
                                <input {...field('surname')} className={inputClass(!!errors.surname)} />
                            </FormField>
                        </div>

                        <FormField label="Student number" error={errors.student_number}>
                            <input {...field('student_number')} className={inputClass(!!errors.student_number)} />
                        </FormField>

                        <FormField label="Email" error={errors.email}>
                            <input type="email" {...field('email')} className={inputClass(!!errors.email)} />
                        </FormField>

                        <div className="grid grid-cols-2 gap-4">
                            <FormField label="Degree / Program" error={errors.degree}>
                                <input {...field('degree')} className={inputClass(!!errors.degree)} />
                            </FormField>
                            <FormField label="Year & Section" error={errors.year_section}>
                                <input {...field('year_section')} className={inputClass(!!errors.year_section)} />
                            </FormField>
                        </div>

                        <div className="flex items-center justify-end gap-3 pt-3">
                            <button
                                type="button"
                                onClick={onClose}
                                className="rounded-xl px-5 py-2.5 text-sm font-semibold text-gray-600 transition hover:bg-gray-100"
                            >
                                Cancel
                            </button>
                            <button
                                type="submit"
                                disabled={isSaving}
                                className="inline-flex items-center gap-2 rounded-xl bg-[#1B1F5C] px-5 py-2.5 text-sm font-semibold text-white shadow-md transition hover:bg-[#131644] disabled:cursor-not-allowed disabled:opacity-60"
                            >
                                {isSaving && <Loader2 className="h-4 w-4 animate-spin" />}
                                Save changes
                            </button>
                        </div>
                    </form>
                </div>
            </div>

            {/* STEP 1: CONFIRMATION MODAL */}
            {showConfirmModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-xs transition-opacity duration-300 animate-fadeIn">
                    <div className="w-full max-w-sm transform rounded-2xl bg-white p-6 text-center shadow-2xl transition-all duration-300 animate-scaleUp">
                        <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-amber-50 text-amber-600">
                            <AlertCircle className="h-6 w-6" />
                        </div>
                        <h4 className="text-base font-bold text-gray-900">Confirm Changes</h4>
                        <p className="mt-1 text-sm text-gray-500">
                            Are you sure you want to update this student's records?
                        </p>
                        <div className="mt-6 flex justify-center gap-3">
                            <button
                                type="button"
                                onClick={() => setShowConfirmModal(false)}
                                className="rounded-xl px-4 py-2 text-sm font-semibold text-gray-600 transition hover:bg-gray-100"
                            >
                                Cancel
                            </button>
                            <button
                                type="button"
                                onClick={executeSave}
                                className="rounded-xl bg-[#1B1F5C] px-5 py-2 text-sm font-semibold text-white shadow-md transition hover:bg-[#131644]"
                            >
                                Yes, Save
                            </button>
                        </div>
                    </div>
                </div>
            )}

            {/* STEP 2: SUCCESS POP-UP MODAL */}
            {showSuccessModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-xs transition-opacity duration-300 animate-fadeIn">
                    <div className="w-full max-w-xs transform rounded-2xl bg-white p-6 text-center shadow-2xl transition-all duration-300 animate-scaleUp">
                        <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-emerald-50 text-emerald-600">
                            <CheckCircle2 className="h-7 w-7" />
                        </div>
                        <h4 className="text-base font-bold text-gray-900">Successfully Updated!</h4>
                        <p className="mt-1 text-xs text-gray-500">Returning to student management...</p>
                    </div>
                </div>
            )}
        </>
    );
}

function FormField({ label, error, children }: { label: string; error?: string; children: React.ReactNode }) {
    return (
        <label className="block">
            <span className="mb-1.5 block text-xs font-bold uppercase tracking-wider text-gray-500">{label}</span>
            {children}
            {error && <span className="mt-1 block text-xs font-medium text-rose-600">{error}</span>}
        </label>
    );
}

function inputClass(hasError: boolean) {
    return `w-full rounded-xl border px-3.5 py-2.5 text-sm text-gray-800 focus:outline-none focus:ring-2 ${
        hasError
            ? 'border-rose-300 focus:ring-rose-200'
            : 'border-gray-200 focus:border-[#1B1F5C] focus:ring-[#1B1F5C]/20'
    }`;
}