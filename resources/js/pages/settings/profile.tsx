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

const GOLD = '#C9973E';

export default function Profile({
    mustVerifyEmail,
    status,
}: {
    mustVerifyEmail: boolean;
    status?: string;
}) {
    const props = usePage<PageProps>().props;
    
    // Fallback to auth.user if custom controller prop is absent
    const currentUser = props.user || props.auth.user;
    const student = currentUser.student || currentUser;

    // Build full name: First Middle Surname Extension
    const fullName = [
        student.firstname,
        student.middlename,
        student.surname,
        student.ext,
    ]
        .filter(Boolean)
        .join(' ') || currentUser.name || 'Student';

    // Secure Image URL resolution targeting the private stream route
    const photoUrl = student.face_photo_url
        ? student.face_photo_url
        : student.student_id
            ? route('student.face-photo', { student: student.student_id })
            : null;

    // Verification check based on verification_status column
    const isVerified =
        student.verification_status?.toLowerCase() === 'verified' ||
        student.verification_status?.toLowerCase() === 'approved';

    return (
        <>
            <Head title="Profile settings" />

            <div className="w-full space-y-8 pb-10">
                {/* 1. PERSONAL & ACADEMIC IDENTITY */}
                <section className="rounded-xl bg-card text-card-foreground p-6 shadow-sm border border-border space-y-6">
                    <div className="flex items-center gap-2 border-b border-border pb-4">
                        <User className="h-5 w-5 text-primary" />
                        <Heading
                            variant="small"
                            title="Personal & Academic Identity"
                            description="Your registered student details and facial verification photo"
                        />
                    </div>

                    <div className="flex flex-col md:flex-row items-start md:items-center gap-6">
                        {/* Facial Reference Photo (Streamed securely from private disk) */}
                        <div className="relative shrink-0">
                            {photoUrl ? (
                                <img
                                    src={photoUrl}
                                    alt="Registered Face Reference"
                                    className="h-24 w-24 rounded-full object-cover border-2 border-primary shadow-sm"
                                    onError={(e) => {
                                        // Fallback if private stream fails
                                        (e.target as HTMLImageElement).style.display = 'none';
                                    }}
                                />
                            ) : (
                                <div className="flex h-24 w-24 items-center justify-center rounded-full bg-primary/10 text-primary font-bold text-2xl border-2 border-primary">
                                    {fullName[0]}
                                </div>
                            )}
                        </div>

                        <div className="space-y-2 flex-1">
                            <div className="flex flex-wrap items-center gap-3">
                                <h2 className="text-xl font-bold text-foreground">{fullName}</h2>
                                {isVerified ? (
                                    <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-500/10 px-3 py-1 text-xs font-semibold text-emerald-600 dark:text-emerald-400 border border-emerald-500/20">
                                        <ShieldCheck className="h-3.5 w-3.5" />
                                        Facial Verification Verified
                                    </span>
                                ) : (
                                    <span className="inline-flex items-center gap-1.5 rounded-full bg-amber-500/10 px-3 py-1 text-xs font-semibold text-amber-600 dark:text-amber-400 border border-amber-500/20">
                                        <ShieldAlert className="h-3.5 w-3.5" />
                                        {student.verification_status || 'Pending Verification'}
                                    </span>
                                )}
                            </div>
                            <p className="text-xs text-muted-foreground font-mono">
                                Student ID: {student.student_number || 'N/A'}
                            </p>
                        </div>
                    </div>

                    {/* Email / Profile Form */}
                    <Form
                        {...ProfileController.update.form()}
                        options={{ preserveScroll: true }}
                        className="space-y-6 pt-2"
                    >
                        {({ processing, errors }) => (
                            <>
                                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                                    <div className="grid gap-2">
                                        <Label htmlFor="name">Full Name</Label>
                                        <Input
                                            id="name"
                                            className="mt-1 block w-full bg-background"
                                            defaultValue={fullName}
                                            name="name"
                                            required
                                            autoComplete="name"
                                            placeholder="Full name"
                                        />
                                        <InputError className="mt-2" message={errors.name} />
                                    </div>

                                    <div className="grid gap-2">
                                        <Label htmlFor="email">Email address</Label>
                                        <Input
                                            id="email"
                                            type="email"
                                            className="mt-1 block w-full bg-background"
                                            defaultValue={currentUser.email}
                                            name="email"
                                            required
                                            autoComplete="username"
                                            placeholder="Email address"
                                        />
                                        <InputError className="mt-2" message={errors.email} />
                                    </div>
                                </div>

                                {mustVerifyEmail && currentUser.email_verified_at === null && (
                                    <div className="rounded-lg bg-amber-500/10 p-4 border border-amber-500/20">
                                        <p className="text-sm text-amber-800 dark:text-amber-300">
                                            Your email address is unverified.{' '}
                                            <Link
                                                href={send()}
                                                as="button"
                                                className="font-semibold underline underline-offset-4 hover:text-amber-900 dark:hover:text-amber-100"
                                            >
                                                Click here to re-send the verification email.
                                            </Link>
                                        </p>

                                        {status === 'verification-link-sent' && (
                                            <div className="mt-2 text-sm font-medium text-emerald-600 dark:text-emerald-400">
                                                A new verification link has been sent to your email address.
                                            </div>
                                        )}
                                    </div>
                                )}

                                <div className="flex items-center gap-4 pt-2">
                                    <Button
                                        disabled={processing}
                                        style={{ backgroundColor: GOLD }}
                                        className="text-white hover:opacity-90 transition-opacity"
                                    >
                                        Save Changes
                                    </Button>
                                </div>
                            </>
                        )}
                    </Form>
                </section>

                {/* 2. ACADEMIC INFORMATION */}
                <section className="rounded-xl bg-card text-card-foreground p-6 shadow-sm border border-border space-y-6">
                    <div className="flex items-center gap-2 border-b border-border pb-4">
                        <GraduationCap className="h-5 w-5 text-primary" />
                        <Heading
                            variant="small"
                            title="Academic Information"
                        />
                    </div>

                    <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-6">
                        <div className="space-y-1">
                            <span className="text-xs font-medium text-muted-foreground">Degree / Program</span>
                            <p className="text-sm font-semibold text-foreground">
                                {student.degree || 'N/A'}
                            </p>
                        </div>

                        <div className="space-y-1">
                            <span className="text-xs font-medium text-muted-foreground">Year & Section</span>
                            <p className="text-sm font-semibold text-foreground">
                                {student.year_section || 'N/A'}
                            </p>
                        </div>

                        <div className="space-y-1">
                            <span className="text-xs font-medium text-muted-foreground">Academic Year & Semester</span>
                            <p className="text-sm font-semibold text-foreground">
                                {student.academic_year ? `A.Y. ${student.academic_year}` : ''} {student.semester ? `(${student.semester})` : ''}
                                {!student.academic_year && !student.semester && 'N/A'}
                            </p>
                        </div>

                        <div className="space-y-1">
                            <span className="text-xs font-medium text-muted-foreground">Entrance Status</span>
                            <div>
                                <span
                                    className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium border ${
                                        Number(student.entrance_status) === 1
                                            ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border-emerald-500/20'
                                            : 'bg-amber-500/10 text-amber-600 dark:text-amber-400 border-amber-500/20'
                                    }`}
                                >
                                    {Number(student.entrance_status) === 1 ? 'Enrolled' : student.entrance_status || 'Not Enrolled'}
                                </span>
                            </div>
                        </div>
                    </div>
                </section>

                {/* 3. ACCOUNT & SECURITY SETTINGS */}
                <section className="rounded-xl bg-card text-card-foreground p-6 shadow-sm border border-border space-y-6">
                    <div className="flex items-center gap-2 border-b border-border pb-4">
                        <KeyRound className="h-5 w-5 text-primary" />
                        <Heading
                            variant="small"
                            title="Password & Danger Zone"
                            description="Manage your password security or remove your account"
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