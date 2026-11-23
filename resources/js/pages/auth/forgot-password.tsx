import { Form, Head } from '@inertiajs/react';
import InputError from '@/components/input-error';
import TextLink from '@/components/text-link';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Spinner } from '@/components/ui/spinner';
import { login } from '@/routes';
import { email } from '@/routes/password';
import { ArrowLeft, CheckCircle2, KeyRound, Mail } from 'lucide-react';
import logoImage from '../logo.jpeg';

type Props = {
    status?: string;
};

// Flat Design Input Base Styling with Accessible Focus Ring & Touch Target Height
const inputClass =
    'w-full min-h-[44px] rounded-lg border border-gray-300 bg-white text-gray-900 placeholder:text-gray-400 caret-[#1B1F5C] shadow-sm transition-all focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none text-sm disabled:cursor-not-allowed disabled:bg-gray-100 disabled:opacity-75';

const iconClass =
    'pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400';

export default function ForgotPassword({ status }: Props) {
    return (
        <div className="min-h-screen w-full bg-[#F5F6FA] font-sans text-gray-900 antialiased">
            <Head title="Forgot Password | 4ttnd Attendance System" />

            {/* MAIN LAYOUT WRAPPER
                - Mobile: Continuous scrolling column layout
                - Desktop (lg:): Fixed 100vh height container where Left panel stays pinned & Right panel scrolls independently
            */}
            <div className="flex min-h-screen flex-col lg:h-screen lg:flex-row lg:overflow-hidden">

                {/* =====================================================
                    LEFT BRANDING PANEL
                    - Non-scrollable on desktop, stacked on mobile
                ====================================================== */}
                <aside className="relative flex flex-col items-center justify-center overflow-hidden bg-[#1B1F5C] p-8 text-center text-white shrink-0 lg:w-5/12 lg:h-screen lg:p-16">

                    {/* Circuit Background Pattern */}
                    <div
                        className="pointer-events-none absolute inset-0 opacity-15"
                        style={{
                            backgroundImage: `
                                radial-gradient(
                                    #F5A623 1.5px,
                                    transparent 1.5px
                                ),
                                linear-gradient(
                                    to right,
                                    rgba(255,255,255,0.08) 1px,
                                    transparent 1px
                                ),
                                linear-gradient(
                                    to bottom,
                                    rgba(255,255,255,0.08) 1px,
                                    transparent 1px
                                )
                            `,
                            backgroundSize: '28px 28px, 28px 28px, 28px 28px',
                        }}
                    />

                    {/* Subtle Decorative Rings */}
                    <div className="pointer-events-none absolute -left-20 -top-20 h-64 w-64 rounded-full border border-[#F5A623]/20" />
                    <div className="pointer-events-none absolute -bottom-32 -right-32 h-80 w-80 rounded-full border border-[#F5A623]/20" />

                    {/* Branding Identity */}
                    <div className="relative z-10 my-auto flex flex-col items-center">
                        <div className="mx-auto mb-6 flex h-24 w-24 items-center justify-center overflow-hidden rounded-full border-4 border-[#F5A623] bg-white p-2 shadow-xl ring-4 ring-white/10">
                            <img
                                src={logoImage}
                                alt="4ttnd System Logo"
                                className="h-full w-full scale-125 object-contain"
                            />
                        </div>

                        <h1 className="text-4xl font-black tracking-tight text-[#F5A623] sm:text-5xl">
                            4ttnd
                        </h1>

                        <h2 className="mt-1 text-xl font-bold tracking-wide text-white/95 sm:text-2xl">
                            Attendance System
                        </h2>

                        <p className="mx-auto mt-4 max-w-sm text-sm leading-relaxed text-white/80">
                            Account Recovery & Password Reset Verification.
                        </p>

                        <div className="mx-auto mt-8 h-1 w-16 rounded-full bg-[#F5A623]" />
                    </div>

                    <div className="mt-8 text-xs text-white/50">
                        &copy; {new Date().getFullYear()} Mariano Marcos State University
                    </div>
                </aside>

                {/* =====================================================
                    RIGHT FORM PANEL
                    - Independently scrollable on desktop
                ====================================================== */}
                <div className="flex flex-1 items-center justify-center bg-[#F5F6FA] p-4 sm:p-8 lg:w-7/12 lg:h-screen lg:overflow-y-auto lg:p-12">
                    <main className="w-full max-w-md rounded-2xl border border-gray-200/80 bg-white p-6 shadow-xl sm:p-10 my-auto">

                        {/* Header Badge & Title */}
                        <header className="mb-8 text-center">
                            <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-xl bg-indigo-50 text-[#1B1F5C]">
                                <KeyRound className="h-6 w-6 text-[#1B1F5C]" aria-hidden="true" />
                            </div>
                            <h3 className="text-2xl font-black tracking-tight text-[#1B1F5C] sm:text-3xl">
                                Forgot Password?
                            </h3>
                            <p className="mt-1.5 text-xs sm:text-sm font-medium text-gray-500 leading-relaxed">
                                Enter your registered email address and we'll send you a link to reset your password.
                            </p>
                        </header>

                        {/* Status Message (e.g. Email Reset Link Sent Confirmation) */}
                        {status && (
                            <div
                                role="status"
                                aria-live="polite"
                                className="mb-6 flex items-start gap-2.5 rounded-xl border border-emerald-200 bg-emerald-50/80 p-3.5 text-xs font-semibold text-emerald-700 shadow-sm"
                            >
                                <CheckCircle2 className="h-4 w-4 shrink-0 text-emerald-600 mt-0.5" aria-hidden="true" />
                                <span className="leading-normal">{status}</span>
                            </div>
                        )}

                        {/* =================================================
                            FORM
                        ================================================== */}
                        <Form {...email.form()} noValidate className="flex flex-col gap-5">
                            {({ processing, errors }) => (
                                <>
                                    {/* EMAIL ADDRESS */}
                                    <div className="grid gap-1.5">
                                        <Label
                                            htmlFor="email"
                                            className="text-xs font-semibold text-gray-700"
                                        >
                                            Email Address <span className="text-red-500" aria-hidden="true">*</span>
                                        </Label>
                                        <div className="relative">
                                            <Mail className={iconClass} />
                                            <Input
                                                id="email"
                                                type="email"
                                                name="email"
                                                required
                                                aria-required="true"
                                                aria-invalid={!!errors.email}
                                                aria-describedby={errors.email ? 'email_error' : undefined}
                                                autoFocus
                                                autoComplete="email"
                                                placeholder="student@mmsu.edu.ph"
                                                className={`${inputClass} pl-9`}
                                            />
                                        </div>
                                        <InputError id="email_error" message={errors.email} />
                                    </div>

                                    {/* SUBMIT BUTTON */}
                                    <Button
                                        type="submit"
                                        disabled={processing}
                                        data-test="email-password-reset-link-button"
                                        className="mt-2 w-full min-h-[48px] bg-[#1B1F5C] py-3 text-sm font-bold text-white shadow-lg hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                                    >
                                        {processing ? (
                                            <>
                                                <Spinner className="mr-2 h-4 w-4" /> Sending Reset Link...
                                            </>
                                        ) : (
                                            'Email Password Reset Link →'
                                        )}
                                    </Button>

                                    {/* RETURN TO LOGIN LINK */}
                                    <div className="mt-3 text-center text-xs text-gray-600">
                                        Remember your password?{' '}
                                        <TextLink
                                            href={login()}
                                            className="font-bold text-[#1B1F5C] transition-colors hover:text-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-sm px-1"
                                        >
                                            Log in here
                                        </TextLink>
                                    </div>
                                </>
                            )}
                        </Form>

                        {/* HOME NAVIGATION */}
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

ForgotPassword.layout = {
    title: 'Forgot password | 4ttnd Attendance System',
    description: 'Enter your email to receive a password reset link',
};