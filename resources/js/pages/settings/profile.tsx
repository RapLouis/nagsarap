import React from 'react';
import { Form, Head, usePage, Link } from '@inertiajs/react';
import ProfileController from '@/actions/App/Http/Controllers/Settings/ProfileController';
import DeleteUser from '@/components/delete-user';
import Heading from '@/components/heading';
import InputError from '@/components/input-error';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { edit } from '@/routes/profile';
import { send } from '@/routes/verification';
import { ShieldCheck, ShieldAlert, User, GraduationCap, KeyRound } from 'lucide-react';
import type { Auth } from '@/types';
import { route } from 'ziggy-js';

type StudentFillableData = {
    student_id?: number;
    student_number?: string;
    firstname?: string;
    middlename?: string;
    surname?: string;
    ext?: string;
    degree?: string;
    degree_id?: number;
    year_section?: string;
    semester?: string;
    academic_year?: string;
    entrance_status?: string;
    verification_status?: string;
    face_photo_path?: string | null;
    face_photo_url?: string | null;
};

type UserData = Auth['user'] & StudentFillableData & {
    student?: StudentFillableData;
};

type PageProps = {
    auth: {
        user: UserData;
    };
    user?: UserData;
};

const inputClass =
    'mt-1 block w-full min-h-[44px] rounded-lg border border-gray-300 bg-white text-gray-900 placeholder:text-gray-400 caret-[#1B1F5C] shadow-sm transition-all focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none text-sm';

export default function Profile({
    mustVerifyEmail,
    status,
}: {
    mustVerifyEmail: boolean;
    status?: string;
}) {
    const props = usePage<PageProps>().props;
    
    const currentUser = props.user || props.auth.user;
    const student = currentUser.student || currentUser;

    const fullName = [
        student.firstname,
        student.middlename,
        student.surname,
        student.ext,
    ]
        .filter(Boolean)
        .join(' ') || currentUser.name || 'Student';

    const photoUrl = student.face_photo_url
        ? student.face_photo_url
        : student.student_id
            ? route('student.face-photo', { student: student.student_id })
            : null;

    const isVerified =
        student.verification_status?.toLowerCase() === 'verified' ||
        student.verification_status?.toLowerCase() === 'approved';

    return (
        <>
            <Head title="Profile Settings | 4ttnd Attendance System" />

            <div className="w-full space-y-8 pb-10 font-sans text-gray-900 antialiased">
                {/* 1. PERSONAL & ACADEMIC IDENTITY */}
                <section className="rounded-2xl bg-white p-6 sm:p-8 shadow-xs border border-gray-200/80 space-y-6">
                    <div className="flex items-center gap-2 border-b border-gray-100 pb-4">
                        <User className="h-5 w-5 text-[#1B1F5C]" aria-hidden="true" />
                        <Heading
                            variant="small"
                            title="Personal & Academic Identity"
                            description="Your registered student details and facial verification reference photo"
                        />
                    </div>

                    <div className="flex flex-col md:flex-row items-start md:items-center gap-6">
                        <div className="relative shrink-0">
                            {photoUrl ? (
                                <img
                                    src={photoUrl}
                                    alt="Registered Face Reference"
                                    className="h-24 w-24 rounded-full object-cover border-4 border-[#1B1F5C] shadow-md ring-2 ring-[#F5A623]"
                                    onError={(e) => {
                                        (e.target as HTMLImageElement).style.display = 'none';
                                    }}
                                />
                            ) : (
                                <div className="flex h-24 w-24 items-center justify-center rounded-full bg-indigo-50 text-[#1B1F5C] font-black text-2xl border-4 border-[#1B1F5C] ring-2 ring-[#F5A623]">
                                    {fullName[0]}
                                </div>
                            )}
                        </div>

                        <div className="space-y-1.5 flex-1">
                            <div className="flex flex-wrap items-center gap-3">
                                <h2 className="text-xl font-black text-gray-900 tracking-tight">{fullName}</h2>
                                {isVerified ? (
                                    <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-3 py-1 text-xs font-bold text-emerald-700 border border-emerald-200">
                                        <ShieldCheck className="h-3.5 w-3.5" aria-hidden="true" />
                                        Biometrics Verified
                                    </span>
                                ) : (
                                    <span className="inline-flex items-center gap-1.5 rounded-full bg-amber-50 px-3 py-1 text-xs font-bold text-amber-700 border border-amber-200">
                                        <ShieldAlert className="h-3.5 w-3.5" aria-hidden="true" />
                                        {student.verification_status || 'Pending Verification'}
                                    </span>
                                )}
                            </div>
                            <p className="text-xs font-mono font-medium text-gray-500">
                                Student ID: {student.student_number || 'N/A'}
                            </p>
                        </div>
                    </div>

                    {/* Profile Form */}
                    <Form
                        {...ProfileController.update.form()}
                        options={{ preserveScroll: true }}
                        className="space-y-6 pt-2"
                    >
                        {({ processing, errors }) => (
                            <>
                                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                                    <div className="grid gap-1.5">
                                        <Label htmlFor="name" className="text-xs font-semibold text-gray-700">Full Name</Label>
                                        <Input
                                            id="name"
                                            className={inputClass}
                                            defaultValue={fullName}
                                            name="name"
                                            required
                                            autoComplete="name"
                                            placeholder="Full name"
                                        />
                                        <InputError message={errors.name} />
                                    </div>

                                    <div className="grid gap-1.5">
                                        <Label htmlFor="email" className="text-xs font-semibold text-gray-700">Email Address</Label>
                                        <Input
                                            id="email"
                                            type="email"
                                            className={inputClass}
                                            defaultValue={currentUser.email}
                                            name="email"
                                            required
                                            autoComplete="username"
                                            placeholder="Email address"
                                        />
                                        <InputError message={errors.email} />
                                    </div>
                                </div>

                                {mustVerifyEmail && currentUser.email_verified_at === null && (
                                    <div className="rounded-xl bg-amber-50 p-4 border border-amber-200">
                                        <p className="text-xs text-amber-800 font-medium">
                                            Your email address is unverified.{' '}
                                            <Link
                                                href={send()}
                                                as="button"
                                                className="font-bold underline underline-offset-4 hover:text-amber-950 focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-sm px-1"
                                            >
                                                Click here to re-send the verification email.
                                            </Link>
                                        </p>

                                        {status === 'verification-link-sent' && (
                                            <div className="mt-2 text-xs font-bold text-emerald-700">
                                                A new verification link has been sent to your email address.
                                            </div>
                                        )}
                                    </div>
                                )}

                                <div className="flex items-center gap-4 pt-2">
                                    <Button
                                        disabled={processing}
                                        className="min-h-[44px] bg-[#1B1F5C] px-6 text-xs font-bold text-white shadow-md hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-50 transition-all"
                                    >
                                        Save Changes
                                    </Button>
                                </div>
                            </>
                        )}
                    </Form>
                </section>

                {/* 2. ACADEMIC INFORMATION */}
                <section className="rounded-2xl bg-white p-6 sm:p-8 shadow-xs border border-gray-200/80 space-y-6">
                    <div className="flex items-center gap-2 border-b border-gray-100 pb-4">
                        <GraduationCap className="h-5 w-5 text-[#1B1F5C]" aria-hidden="true" />
                        <Heading
                            variant="small"
                            title="Academic Information"
                        />
                    </div>

                    <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-6">
                        <div className="space-y-1">
                            <span className="text-xs font-semibold text-gray-500 uppercase tracking-wider block">Degree / Program</span>
                            <p className="text-sm font-bold text-gray-900">
                                {student.degree || 'N/A'}
                            </p>
                        </div>

                        <div className="space-y-1">
                            <span className="text-xs font-semibold text-gray-500 uppercase tracking-wider block">Year & Section</span>
                            <p className="text-sm font-bold text-gray-900">
                                {student.year_section || 'N/A'}
                            </p>
                        </div>

                        <div className="space-y-1">
                            <span className="text-xs font-semibold text-gray-500 uppercase tracking-wider block">Academic Term</span>
                            <p className="text-sm font-bold text-gray-900">
                                {student.academic_year ? `A.Y. ${student.academic_year}` : ''} {student.semester ? `(${student.semester})` : ''}
                                {!student.academic_year && !student.semester && 'N/A'}
                            </p>
                        </div>

                        <div className="space-y-1">
                            <span className="text-xs font-semibold text-gray-500 uppercase tracking-wider block">Enrolment Status</span>
                            <div>
                                <span
                                    className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-bold border ${
                                        Number(student.entrance_status) === 1
                                            ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
                                            : 'bg-amber-50 text-amber-700 border-amber-200'
                                    }`}
                                >
                                    {Number(student.entrance_status) === 1 ? 'Officially Enrolled' : student.entrance_status || 'Not Enrolled'}
                                </span>
                            </div>
                        </div>
                    </div>
                </section>

                {/* 3. DANGER ZONE */}
                <section className="rounded-2xl bg-white p-6 sm:p-8 shadow-xs border border-gray-200/80 space-y-6">
                    <div className="flex items-center gap-2 border-b border-gray-100 pb-4">
                        <KeyRound className="h-5 w-5 text-red-600" aria-hidden="true" />
                        <Heading
                            variant="small"
                            title="Danger Zone"
                            description="Permanently delete your account and remove all personal biometrics"
                        />
                    </div>

                    <DeleteUser />
                </section>
            </div>
        </>
    );
}

Profile.layout = {
    breadcrumbs: [
        {
            title: 'Profile settings',
            href: edit(),
        },
    ],
};