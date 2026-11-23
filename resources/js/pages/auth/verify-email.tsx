import { Form, Head } from '@inertiajs/react';
import TextLink from '@/components/text-link';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/spinner';
import { logout } from '@/routes';
import { send } from '@/routes/verification';
import { ArrowLeft, CheckCircle2, LogOut, MailCheck } from 'lucide-react';
import logoImage from '../logo.jpeg';

export default function VerifyEmail({ status }: { status?: string }) {
    return (
        <div className="min-h-screen w-full bg-[#F5F6FA] font-sans text-gray-900 antialiased">
            <Head title="Verify Email | 4ttnd Attendance System" />

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
                            Verify your registered student email address.
                        </p>
                        <div className="mx-auto mt-8 h-1 w-16 rounded-full bg-[#F5A623]" />
                    </div>

                    <div className="mt-8 text-xs text-white/50">
                        &copy; {new Date().getFullYear()} Mariano Marcos State University
                    </div>
                </aside>

                {/* RIGHT FORM PANEL */}
                <div className="flex flex-1 items-center justify-center bg-[#F5F6FA] p-4 sm:p-8 lg:w-7/12 lg:h-screen lg:overflow-y-auto lg:p-12">
                    <main className="w-full max-w-md rounded-2xl border border-gray-200/80 bg-white p-6 shadow-xl sm:p-10 my-auto text-center">
                        <header className="mb-6 text-center">
                            <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-xl bg-emerald-50 text-emerald-600">
                                <MailCheck className="h-6 w-6 text-emerald-600" aria-hidden="true" />
                            </div>
                            <h3 className="text-2xl font-black tracking-tight text-[#1B1F5C] sm:text-3xl">
                                Verify Email Address
                            </h3>
                            <p className="mt-2 text-xs sm:text-sm font-medium text-gray-500 leading-relaxed">
                                Thanks for signing up! Before getting started, please verify your email address by clicking on the link we just sent to your inbox.
                            </p>
                        </header>

                        {/* STATUS MESSAGE */}
                        {status === 'verification-link-sent' && (
                            <div
                                role="status"
                                aria-live="polite"
                                className="mb-6 flex items-start gap-2.5 rounded-xl border border-emerald-200 bg-emerald-50/80 p-3.5 text-xs font-semibold text-emerald-700 shadow-sm text-left"
                            >
                                <CheckCircle2 className="h-4 w-4 shrink-0 text-emerald-600 mt-0.5" aria-hidden="true" />
                                <span className="leading-normal">
                                    A new verification link has been sent to the email address provided during registration.
                                </span>
                            </div>
                        )}

                        <Form {...send.form()} className="flex flex-col gap-4">
                            {({ processing }) => (
                                <>
                                    <Button
                                        type="submit"
                                        disabled={processing}
                                        className="w-full min-h-[48px] bg-[#1B1F5C] py-3 text-sm font-bold text-white shadow-lg hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                                    >
                                        {processing ? (
                                            <>
                                                <Spinner className="mr-2 h-4 w-4" /> Resending Link...
                                            </>
                                        ) : (
                                            'Resend Verification Email →'
                                        )}
                                    </Button>

                                    <div className="pt-2">
                                        <TextLink
                                            href={logout()}
                                            className="inline-flex items-center gap-1.5 text-xs font-semibold text-gray-500 transition-colors hover:text-red-600 focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-sm px-2 py-1"
                                        >
                                            <LogOut className="h-3.5 w-3.5" /> Log out of account
                                        </TextLink>
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

VerifyEmail.layout = {
    title: 'Email verification | 4ttnd Attendance System',
    description: 'Please verify your email address by clicking on the link we just emailed to you.',
};