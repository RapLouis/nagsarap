import { Form, Head, Link } from '@inertiajs/react';
import InputError from '@/components/input-error';
import PasskeyVerify from '@/components/passkey-verify';
import PasswordInput from '@/components/password-input';
import TextLink from '@/components/text-link';
import { Button } from '@/components/ui/button';
import { Checkbox } from '@/components/ui/checkbox';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Spinner } from '@/components/ui/spinner';
import { register } from '@/routes';
import { store } from '@/routes/login';
import { request } from '@/routes/password';
import { ArrowLeft, CheckCircle2, Mail } from 'lucide-react';
import logoImage from '../logo.jpeg';

type Props = {
    status?: string;
    canResetPassword: boolean;
};

// Flat Design Input Base Styling with Accessible Focus Ring & Touch Target
const inputClass =
    'w-full min-h-[44px] rounded-lg border border-gray-300 bg-white text-gray-900 placeholder:text-gray-400 caret-[#1B1F5C] shadow-sm transition-all focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none text-sm disabled:cursor-not-allowed disabled:bg-gray-100 disabled:opacity-75';

const iconClass =
    'pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400';

export default function Login({ status, canResetPassword }: Props) {
    return (
        <div className="min-h-screen w-full bg-[#F5F6FA] font-sans text-gray-900 antialiased">
            <Head title="Log in | 4ttnd Attendance System" />

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
                            Smart. Simple. Secure Attendance Tracking & Biometric Verification.
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

                        {/* Passkey Component */}
                        <PasskeyVerify />

                        {/* Header */}
                        <header className="mb-8 text-center">
                            <h3 className="text-2xl font-black tracking-tight text-[#1B1F5C] sm:text-3xl">
                                Welcome Back
                            </h3>
                            <p className="mt-1.5 text-xs sm:text-sm font-medium text-gray-500">
                                Sign in to your 4ttnd Attendance account
                            </p>
                        </header>

                        {/* Status Message (e.g. Password Reset Confirmation) */}
                        {status && (
                            <div
                                role="status"
                                aria-live="polite"
                                className="mb-6 flex items-center gap-2 rounded-xl border border-emerald-200 bg-emerald-50/80 p-3.5 text-xs font-semibold text-emerald-700 shadow-sm"
                            >
                                <CheckCircle2 className="h-4 w-4 shrink-0 text-emerald-600" aria-hidden="true" />
                                <span>{status}</span>
                            </div>
                        )}

                        {/* =================================================
                            FORM
                        ================================================== */}
                        <Form
                            {...store.form()}
                            resetOnSuccess={['password']}
                            noValidate
                            className="flex flex-col gap-5"
                        >
                            {({ processing, errors }) => (
                                <>
                                    {/* EMAIL / USERNAME */}
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
                                                tabIndex={1}
                                                autoComplete="email"
                                                placeholder="student@mmsu.edu.ph"
                                                className={`${inputClass} pl-9`}
                                            />
                                        </div>
                                        <InputError id="email_error" message={errors.email} />
                                    </div>

                                    {/* PASSWORD */}
                                    <div className="grid gap-1.5">
                                        <Label
                                            htmlFor="password"
                                            className="text-xs font-semibold text-gray-700"
                                        >
                                            Password <span className="text-red-500" aria-hidden="true">*</span>
                                        </Label>
                                        <PasswordInput
                                            id="password"
                                            name="password"
                                            required
                                            aria-required="true"
                                            aria-invalid={!!errors.password}
                                            aria-describedby={errors.password ? 'password_error' : undefined}
                                            tabIndex={2}
                                            autoComplete="current-password"
                                            placeholder="••••••••"
                                            className={inputClass}
                                        />
                                        <InputError id="password_error" message={errors.password} />
                                    </div>

                                    {/* REMEMBER ME & FORGOT PASSWORD */}
                                    <div className="flex items-center justify-between pt-1">
                                        <div className="flex items-center gap-2">
                                            <Checkbox
                                                id="remember"
                                                name="remember"
                                                tabIndex={3}
                                                className="h-4 w-4 border-gray-300 data-[state=checked]:border-[#1B1F5C] data-[state=checked]:bg-[#1B1F5C] data-[state=checked]:text-white focus-visible:ring-2 focus-visible:ring-[#F5A623] cursor-pointer"
                                            />
                                            <Label
                                                htmlFor="remember"
                                                className="cursor-pointer text-xs font-medium text-gray-600 select-none"
                                            >
                                                Remember me
                                            </Label>
                                        </div>

                                        {canResetPassword && (
                                            <TextLink
                                                href={request()}
                                                tabIndex={5}
                                                className="text-xs font-semibold text-[#1B1F5C] transition-colors hover:text-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-sm px-1"
                                            >
                                                Forgot Password?
                                            </TextLink>
                                        )}
                                    </div>

                                    {/* LOGIN SUBMIT BUTTON */}
                                    <Button
                                        type="submit"
                                        disabled={processing}
                                        tabIndex={4}
                                        data-test="login-button"
                                        className="mt-2 w-full min-h-[48px] bg-[#1B1F5C] py-3 text-sm font-bold text-white shadow-lg hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                                    >
                                        {processing ? (
                                            <>
                                                <Spinner className="mr-2 h-4 w-4" /> Authenticating...
                                            </>
                                        ) : (
                                            'Log In →'
                                        )}
                                    </Button>

                                    {/* REGISTER LINK */}
                                    <div className="mt-3 text-center text-xs text-gray-600">
                                        Don't have an account?{' '}
                                        <TextLink
                                            href={register()}
                                            tabIndex={6}
                                            data-test="register-link"
                                            className="font-bold text-[#1B1F5C] transition-colors hover:text-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-sm px-1"
                                        >
                                            Register here
                                        </TextLink>
                                    </div>
                                </>
                            )}
                        </Form>

                        {/* HOME NAVIGATION */}
                        <div className="mt-8 text-center border-t border-gray-100 pt-6">
                            <Link
                                href="/"
                                className="inline-flex items-center gap-1.5 text-xs font-semibold text-gray-500 transition-colors hover:text-[#1B1F5C] focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-sm px-2 py-1"
                            >
                                <ArrowLeft className="h-3.5 w-3.5" /> Back to Home
                            </Link>
                        </div>

                    </main>
                </div>
            </div>
        </div>
    );
}

Login.layout = {
    title: 'Log in to 4ttnd Attendance System',
    description: 'Enter your credentials below to log in',
};