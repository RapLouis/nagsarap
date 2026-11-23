import { Form, Head } from '@inertiajs/react';
import InputError from '@/components/input-error';
import PasswordInput from '@/components/password-input';
import TextLink from '@/components/text-link';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Spinner } from '@/components/ui/spinner';
import { update } from '@/routes/password';
import { ArrowLeft, KeyRound, Mail } from 'lucide-react';
import logoImage from '../logo.jpeg';

type Props = {
    token: string;
    email: string;
    passwordRules: string;
};

// Flat Design Input Base Styling
const inputClass =
    'w-full min-h-[44px] rounded-lg border border-gray-300 bg-white text-gray-900 placeholder:text-gray-400 caret-[#1B1F5C] shadow-sm transition-all focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none text-sm disabled:cursor-not-allowed disabled:bg-gray-100 disabled:opacity-75';

const iconClass =
    'pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400';

export default function ResetPassword({ token, email, passwordRules }: Props) {
    return (
        <div className="min-h-screen w-full bg-[#F5F6FA] font-sans text-gray-900 antialiased">
            <Head title="Reset Password | 4ttnd Attendance System" />

            {/* MAIN LAYOUT WRAPPER */}
            <div className="flex min-h-screen flex-col lg:h-screen lg:flex-row lg:overflow-hidden">

                {/* LEFT BRANDING PANEL */}
                <aside className="relative flex flex-col items-center justify-center overflow-hidden bg-[#1B1F5C] p-8 text-center text-white shrink-0 lg:w-5/12 lg:h-screen lg:p-16">
                    <div
                        className="pointer-events-none absolute inset-0 opacity-15"
                        style={{
                            backgroundImage: `
                                radial-gradient(#F5A623 1.5px, transparent 1.5px),
                                linear-gradient(to right, rgba(255,255,255,0.08) 1px, transparent 1px),
                                linear-gradient(to bottom, rgba(255,255,255,0.08) 1px, transparent 1px)
                            `,
                            backgroundSize: '28px 28px, 28px 28px, 28px 28px',
                        }}
                    />
                    <div className="pointer-events-none absolute -left-20 -top-20 h-64 w-64 rounded-full border border-[#F5A623]/20" />
                    <div className="pointer-events-none absolute -bottom-32 -right-32 h-80 w-80 rounded-full border border-[#F5A623]/20" />

                    <div className="relative z-10 my-auto flex flex-col items-center">
                        <div className="mx-auto mb-6 flex h-24 w-24 items-center justify-center overflow-hidden rounded-full border-4 border-[#F5A623] bg-white p-2 shadow-xl ring-4 ring-white/10">
                            <img src={logoImage} alt="4ttnd System Logo" className="h-full w-full scale-125 object-contain" />
                        </div>
                        <h1 className="text-4xl font-black tracking-tight text-[#F5A623] sm:text-5xl">4ttnd</h1>
                        <h2 className="mt-1 text-xl font-bold tracking-wide text-white/95 sm:text-2xl">Attendance System</h2>
                        <p className="mx-auto mt-4 max-w-sm text-sm leading-relaxed text-white/80">
                            Set your new account password.
                        </p>
                        <div className="mx-auto mt-8 h-1 w-16 rounded-full bg-[#F5A623]" />
                    </div>

                    <div className="mt-8 text-xs text-white/50">
                        &copy; {new Date().getFullYear()} Mariano Marcos State University
                    </div>
                </aside>

                {/* RIGHT FORM PANEL */}
                <div className="flex flex-1 items-center justify-center bg-[#F5F6FA] p-4 sm:p-8 lg:w-7/12 lg:h-screen lg:overflow-y-auto lg:p-12">
                    <main className="w-full max-w-md rounded-2xl border border-gray-200/80 bg-white p-6 shadow-xl sm:p-10 my-auto">
                        <header className="mb-8 text-center">
                            <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-xl bg-indigo-50 text-[#1B1F5C]">
                                <KeyRound className="h-6 w-6 text-[#1B1F5C]" aria-hidden="true" />
                            </div>
                            <h3 className="text-2xl font-black tracking-tight text-[#1B1F5C] sm:text-3xl">
                                Reset Password
                            </h3>
                            <p className="mt-1.5 text-xs sm:text-sm font-medium text-gray-500">
                                Enter your new credentials below to update your password
                            </p>
                        </header>

                        <Form
                            {...update.form()}
                            transform={(data) => ({ ...data, token, email })}
                            resetOnSuccess={['password', 'password_confirmation']}
                            noValidate
                            className="flex flex-col gap-5"
                        >
                            {({ processing, errors }) => (
                                <>
                                    {/* READONLY EMAIL */}
                                    <div className="grid gap-1.5">
                                        <Label htmlFor="email" className="text-xs font-semibold text-gray-700">
                                            Email Address
                                        </Label>
                                        <div className="relative">
                                            <Mail className={iconClass} />
                                            <Input
                                                id="email"
                                                type="email"
                                                name="email"
                                                autoComplete="email"
                                                value={email}
                                                readOnly
                                                className={`${inputClass} pl-9 bg-gray-50 text-gray-500 cursor-not-allowed`}
                                            />
                                        </div>
                                        <InputError message={errors.email} />
                                    </div>

                                    {/* NEW PASSWORD */}
                                    <div className="grid gap-1.5">
                                        <Label htmlFor="password" className="text-xs font-semibold text-gray-700">
                                            New Password <span className="text-red-500" aria-hidden="true">*</span>
                                        </Label>
                                        <PasswordInput
                                            id="password"
                                            name="password"
                                            required
                                            aria-required="true"
                                            aria-invalid={!!errors.password}
                                            aria-describedby={errors.password ? 'password_error' : undefined}
                                            autoComplete="new-password"
                                            autoFocus
                                            placeholder="••••••••"
                                            passwordrules={passwordRules}
                                            className={inputClass}
                                        />
                                        <InputError id="password_error" message={errors.password} />
                                    </div>

                                    {/* CONFIRM NEW PASSWORD */}
                                    <div className="grid gap-1.5">
                                        <Label htmlFor="password_confirmation" className="text-xs font-semibold text-gray-700">
                                            Confirm New Password <span className="text-red-500" aria-hidden="true">*</span>
                                        </Label>
                                        <PasswordInput
                                            id="password_confirmation"
                                            name="password_confirmation"
                                            required
                                            aria-required="true"
                                            aria-invalid={!!errors.password_confirmation}
                                            aria-describedby={errors.password_confirmation ? 'confirm_password_error' : undefined}
                                            autoComplete="new-password"
                                            placeholder="••••••••"
                                            passwordrules={passwordRules}
                                            className={inputClass}
                                        />
                                        <InputError id="confirm_password_error" message={errors.password_confirmation} />
                                    </div>

                                    <Button
                                        type="submit"
                                        disabled={processing}
                                        data-test="reset-password-button"
                                        className="mt-2 w-full min-h-[48px] bg-[#1B1F5C] py-3 text-sm font-bold text-white shadow-lg hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                                    >
                                        {processing ? (
                                            <>
                                                <Spinner className="mr-2 h-4 w-4" /> Resetting Password...
                                            </>
                                        ) : (
                                            'Reset Password →'
                                        )}
                                    </Button>
                                </>
                            )}
                        </Form>

                        <div className="mt-8 text-center border-t border-gray-100 pt-6">
                            <TextLink
                                href="/"
                                className="inline-flex items-center gap-1.5 text-xs font-semibold text-gray-500 transition-colors hover:text-[#1B1F5C] focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-sm px-2 py-1"
                            >
                                <ArrowLeft className="h-3.5 w-3.5" /> Back to Home
                            </TextLink>
                        </div>
                    </main>
                </div>
            </div>
        </div>
    );
}

ResetPassword.layout = {
    title: 'Reset password | 4ttnd Attendance System',
    description: 'Please enter your new password below',
};