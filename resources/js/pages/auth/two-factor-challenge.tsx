import { Form, Head, setLayoutProps } from '@inertiajs/react';
import { REGEXP_ONLY_DIGITS } from 'input-otp';
import { useMemo, useState } from 'react';
import InputError from '@/components/input-error';
import TextLink from '@/components/text-link';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
    InputOTP,
    InputOTPGroup,
    InputOTPSlot,
} from '@/components/ui/input-otp';
import { Spinner } from '@/components/ui/spinner';
import { OTP_MAX_LENGTH } from '@/hooks/use-two-factor-auth';
import { store } from '@/routes/two-factor/login';
import { ArrowLeft, Key, ShieldAlert } from 'lucide-react';
import logoImage from '../logo.jpeg';

// Flat Design Input Base Styling
const inputClass =
    'w-full min-h-[44px] rounded-lg border border-gray-300 bg-white text-gray-900 placeholder:text-gray-400 caret-[#1B1F5C] shadow-sm transition-all focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none text-sm disabled:cursor-not-allowed disabled:bg-gray-100 disabled:opacity-75';

export default function TwoFactorChallenge() {
    const [showRecoveryInput, setShowRecoveryInput] = useState<boolean>(false);
    const [code, setCode] = useState<string>('');

    const authConfigContent = useMemo<{
        title: string;
        description: string;
        toggleText: string;
    }>(() => {
        if (showRecoveryInput) {
            return {
                title: 'Emergency Recovery Code',
                description:
                    'Please confirm access to your account by entering one of your emergency recovery codes.',
                toggleText: 'Login using an authenticator code',
            };
        }

        return {
            title: 'Two-Factor Authentication',
            description:
                'Enter the 6-digit verification code provided by your authenticator app.',
            toggleText: 'Login using an emergency recovery code',
        };
    }, [showRecoveryInput]);

    setLayoutProps({
        title: authConfigContent.title,
        description: authConfigContent.description,
    });

    const toggleRecoveryMode = (clearErrors: () => void): void => {
        setShowRecoveryInput(!showRecoveryInput);
        clearErrors();
        setCode('');
    };

    return (
        <div className="min-h-screen w-full bg-[#F5F6FA] font-sans text-gray-900 antialiased">
            <Head title="Two-Factor Verification | 4ttnd Attendance System" />

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
                            Two-Factor Security Verification.
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
                                {showRecoveryInput ? (
                                    <Key className="h-6 w-6 text-[#1B1F5C]" aria-hidden="true" />
                                ) : (
                                    <ShieldAlert className="h-6 w-6 text-[#1B1F5C]" aria-hidden="true" />
                                )}
                            </div>
                            <h3 className="text-2xl font-black tracking-tight text-[#1B1F5C] sm:text-3xl">
                                {authConfigContent.title}
                            </h3>
                            <p className="mt-1.5 text-xs sm:text-sm font-medium text-gray-500 leading-relaxed">
                                {authConfigContent.description}
                            </p>
                        </header>

                        <Form
                            {...store.form()}
                            noValidate
                            resetOnError
                            resetOnSuccess={!showRecoveryInput}
                            className="flex flex-col gap-5"
                        >
                            {({ errors, processing, clearErrors }) => (
                                <>
                                    {showRecoveryInput ? (
                                        <div className="grid gap-1.5">
                                            <Input
                                                name="recovery_code"
                                                type="text"
                                                placeholder="Enter 8-character recovery code"
                                                autoFocus={showRecoveryInput}
                                                required
                                                aria-required="true"
                                                aria-invalid={!!errors.recovery_code}
                                                className={inputClass}
                                            />
                                            <InputError message={errors.recovery_code} />
                                        </div>
                                    ) : (
                                        <div className="flex flex-col items-center justify-center gap-2 text-center">
                                            <div className="flex w-full items-center justify-center">
                                                <InputOTP
                                                    name="code"
                                                    maxLength={OTP_MAX_LENGTH}
                                                    value={code}
                                                    onChange={(value) => setCode(value)}
                                                    disabled={processing}
                                                    pattern={REGEXP_ONLY_DIGITS}
                                                    autoFocus
                                                >
                                                    <InputOTPGroup>
                                                        {Array.from(
                                                            { length: OTP_MAX_LENGTH },
                                                            (_, index) => (
                                                                <InputOTPSlot
                                                                    key={index}
                                                                    index={index}
                                                                    className="h-12 w-10 sm:w-12 text-base font-bold border-gray-300 focus-visible:ring-[#F5A623]"
                                                                />
                                                            ),
                                                        )}
                                                    </InputOTPGroup>
                                                </InputOTP>
                                            </div>
                                            <InputError message={errors.code} />
                                        </div>
                                    )}

                                    <Button
                                        type="submit"
                                        disabled={processing}
                                        className="mt-2 w-full min-h-[48px] bg-[#1B1F5C] py-3 text-sm font-bold text-white shadow-lg hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                                    >
                                        {processing ? (
                                            <>
                                                <Spinner className="mr-2 h-4 w-4" /> Verifying Code...
                                            </>
                                        ) : (
                                            'Verify & Continue →'
                                        )}
                                    </Button>

                                    <div className="mt-2 text-center text-xs text-gray-600">
                                        Need a different method?{' '}
                                        <button
                                            type="button"
                                            onClick={() => toggleRecoveryMode(clearErrors)}
                                            className="font-bold text-[#1B1F5C] underline hover:text-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-sm px-1 cursor-pointer transition-colors"
                                        >
                                            {authConfigContent.toggleText}
                                        </button>
                                    </div>
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