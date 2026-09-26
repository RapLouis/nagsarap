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
import { Cpu, Mail } from 'lucide-react';

type Props = {
    status?: string;
    canResetPassword: boolean;
};

const inputClass =
    'w-full rounded-lg border border-gray-300 bg-white text-black placeholder:text-gray-400 caret-[#1B1F5C] shadow-sm transition-colors focus-visible:border-[#F5A623] focus-visible:ring-1 focus-visible:ring-[#F5A623] focus-visible:outline-none';

const iconClass =
    'pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400';

export default function Login({
    status,
    canResetPassword,
}: Props) {
    return (
        <div className="min-h-screen w-full bg-[#F5F6FA] font-sans">
            <Head title="Log in" />

            <div className="flex min-h-screen w-full flex-col lg:flex-row">

                {/* =====================================================
                    LEFT PANEL
                ====================================================== */}
                <div className="relative flex flex-1 items-center justify-center overflow-hidden bg-[#1B1F5C] p-8 text-center text-white lg:p-16">

                    {/* Circuit Background */}
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
                            backgroundSize:
                                '28px 28px, 28px 28px, 28px 28px',
                        }}
                    />

                    {/* Decorative Circles */}
                    <div className="pointer-events-none absolute -left-20 -top-20 h-64 w-64 rounded-full border border-[#F5A623]/20" />

                    <div className="pointer-events-none absolute -bottom-32 -right-32 h-80 w-80 rounded-full border border-[#F5A623]/20" />

                    {/* Branding */}
                    <div className="relative z-10">

                        <div className="mx-auto mb-6 flex h-24 w-24 items-center justify-center rounded-full border-4 border-[#F5A623] bg-white shadow-[0_0_25px_rgba(245,166,35,0.3)]">
                            <Cpu className="h-12 w-12 text-[#1B1F5C]" />
                        </div>

                        <h1 className="text-4xl font-extrabold tracking-wider text-[#F5A623]">
                            CCIS
                        </h1>

                        <h2 className="mt-1 text-xl font-bold tracking-wide">
                            Attendance System
                        </h2>

                        <p className="mx-auto mt-4 max-w-xs text-sm leading-relaxed text-white/70">
                            Smart. Simple. Secure Attendance Tracking.
                        </p>

                        <div className="mx-auto mt-8 h-1 w-16 rounded-full bg-[#F5A623]" />
                    </div>
                </div>

                {/* =====================================================
                    RIGHT PANEL
                ====================================================== */}
                <div className="flex flex-1 items-center justify-center bg-[#F5F6FA] p-6 lg:p-12">

                    <div className="w-full max-w-md rounded-2xl border border-gray-100 bg-white p-8 shadow-xl">

                        {/* Passkey */}
                        <PasskeyVerify />

                        {/* Header */}
                        <div className="mb-8 text-center">

                            <h3 className="text-2xl font-bold text-[#1B1F5C]">
                                Welcome Back
                            </h3>

                            <p className="mt-2 text-xs text-gray-500">
                                Sign in to your CCIS Attendance account
                            </p>

                        </div>

                        {/* =================================================
                            FORM
                        ================================================== */}
                        <Form
                            {...store.form()}
                            resetOnSuccess={['password']}
                            className="flex flex-col gap-5"
                        >
                            {({ processing, errors }) => (
                                <>

                                    {/* EMAIL */}
                                    <div className="grid gap-2">

                                        <Label
                                            htmlFor="email"
                                            className="text-xs font-semibold text-gray-700"
                                        >
                                            Email / Username
                                        </Label>

                                        <div className="relative">

                                            <Mail className={iconClass} />

                                            <Input
                                                id="email"
                                                type="email"
                                                name="email"
                                                required
                                                autoFocus
                                                tabIndex={1}
                                                autoComplete="email"
                                                placeholder="Enter your email"
                                                className={`${inputClass} pl-9`}
                                            />

                                        </div>

                                        <InputError
                                            message={errors.email}
                                        />

                                    </div>

                                    {/* PASSWORD */}
                                    <div className="grid gap-2">

                                        <Label
                                            htmlFor="password"
                                            className="text-xs font-semibold text-gray-700"
                                        >
                                            Password
                                        </Label>

                                        <PasswordInput
                                            id="password"
                                            name="password"
                                            required
                                            tabIndex={2}
                                            autoComplete="current-password"
                                            placeholder="Enter your password"
                                            className={inputClass}
                                        />

                                        <InputError
                                            message={errors.password}
                                        />

                                    </div>

                                    {/* REMEMBER / FORGOT */}
                                    <div className="flex items-center justify-between pt-1">

                                        <div className="flex items-center gap-2">

                                            <Checkbox
                                                id="remember"
                                                name="remember"
                                                tabIndex={3}
                                                className="border-gray-300 data-[state=checked]:border-[#1B1F5C] data-[state=checked]:bg-[#1B1F5C] data-[state=checked]:text-white focus-visible:ring-[#F5A623]"
                                            />

                                            <Label
                                                htmlFor="remember"
                                                className="cursor-pointer text-xs font-normal text-gray-600"
                                            >
                                                Remember me
                                            </Label>

                                        </div>

                                        {canResetPassword && (
                                            <TextLink
                                                href={request()}
                                                tabIndex={5}
                                                className="text-xs font-medium text-[#1B1F5C] transition-colors hover:text-[#F5A623]"
                                            >
                                                Forgot Password?
                                            </TextLink>
                                        )}

                                    </div>

                                    {/* LOGIN BUTTON */}
                                    <Button
                                        type="submit"
                                        disabled={processing}
                                        tabIndex={4}
                                        data-test="login-button"
                                        className="mt-2 w-full rounded-lg bg-[#1B1F5C] py-2.5 font-medium text-white shadow-md transition-all hover:bg-[#131644] hover:border-b-2 hover:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:ring-offset-2"
                                    >

                                        {processing && (
                                            <Spinner className="mr-2" />
                                        )}

                                        Log In

                                    </Button>

                                    {/* REGISTER */}
                                    <div className="mt-3 text-center text-xs text-gray-500">

                                        Don't have an account?{' '}

                                        <TextLink
                                            href={register()}
                                            tabIndex={6}
                                            data-test="register-link"
                                            className="font-bold text-[#1B1F5C] transition-colors hover:text-[#F5A623]"
                                        >
                                            Register here
                                        </TextLink>

                                    </div>

                                </>
                            )}
                        </Form>

                        {/* STATUS */}
                        {status && (
                            <div className="mt-4 rounded-lg border border-emerald-200 bg-emerald-50 px-3 py-2 text-center text-xs font-medium text-emerald-600">
                                {status}
                            </div>
                        )}

                        {/* HOME */}
                        <div className="mt-6 text-center">

                            <Link
                                href="/"
                                className="text-xs text-gray-400 transition-colors hover:text-[#1B1F5C]"
                            >
                                ← Back to Home
                            </Link>

                        </div>

                    </div>
                </div>
            </div>
        </div>
    );
}

Login.layout = {
    title: 'Log in to CCIS Attendance System',
    description: 'Enter your credentials below to log in',
};