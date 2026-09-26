import { Head, Link } from '@inertiajs/react';
import { Button } from '@/components/ui/button';
import { login, register } from '@/routes';
import { Cpu, MapPin, ShieldCheck, ScanFace } from 'lucide-react';

export default function Welcome() {
    return (
        <>
            <Head title="CCIS Attendance System" />

            <div className="min-h-screen w-full bg-[#F5F6FA] font-sans">
                {/* HERO SECTION */}
                <section className="relative min-h-screen overflow-hidden bg-[#1B1F5C] text-white">
                    {/* Circuit Background */}
                    <div
                        className="absolute inset-0 opacity-15 pointer-events-none"
                        style={{
                            backgroundImage: `
                                radial-gradient(#F5A623 1.5px, transparent 1.5px),
                                linear-gradient(to right, rgba(255,255,255,0.08) 1px, transparent 1px),
                                linear-gradient(to bottom, rgba(255,255,255,0.08) 1px, transparent 1px)
                            `,
                            backgroundSize:
                                '28px 28px, 28px 28px, 28px 28px',
                        }}
                    />

                    {/* Decorative Circles */}
                    <div className="absolute -right-32 -top-32 h-96 w-96 rounded-full border border-[#F5A623]/20" />
                    <div className="absolute -right-20 -top-20 h-72 w-72 rounded-full border border-[#F5A623]/10" />
                    <div className="absolute -bottom-40 -left-40 h-96 w-96 rounded-full border border-white/10" />

                    {/* Navigation */}
                    <nav className="relative z-20 flex items-center justify-between px-6 py-6 lg:px-16">
                        <div className="flex items-center gap-3">
                            <div className="flex h-10 w-10 items-center justify-center rounded-full bg-white">
                                <Cpu className="h-5 w-5 text-[#1B1F5C]" />
                            </div>

                            <div>
                                <div className="text-lg font-extrabold tracking-wider text-[#F5A623]">
                                    CCIS
                                </div>
                                <div className="text-[10px] font-medium tracking-wider text-white/70">
                                    ATTENDANCE SYSTEM
                                </div>
                            </div>
                        </div>

                        <div className="flex items-center gap-3">
                            <Button
                                asChild
                                variant="ghost"
                                className="text-white hover:bg-white/10 hover:text-[#F5A623]"
                            >
                                <Link href={login()}>
                                    Log In
                                </Link>
                            </Button>

                            <Button
                                asChild
                                className="bg-[#F5A623] text-[#1B1F5C] font-semibold hover:bg-[#e69a17]"
                            >
                                <Link href={register()}>
                                    Register
                                </Link>
                            </Button>
                        </div>
                    </nav>

                    {/* Main Hero */}
                    <div className="relative z-10 flex min-h-[calc(100vh-88px)] items-center justify-center px-6 py-12 lg:px-16">
                        <div className="grid w-full max-w-6xl items-center gap-16 lg:grid-cols-2">
                            {/* Left Content */}
                            <div className="text-center lg:text-left">
                                <div className="mb-6 inline-flex items-center gap-2 rounded-full border border-[#F5A623]/30 bg-[#F5A623]/10 px-4 py-2 text-xs font-medium text-[#F5A623]">
                                    <span className="h-2 w-2 rounded-full bg-[#F5A623]" />
                                    SMART ATTENDANCE TECHNOLOGY
                                </div>

                                <h1 className="text-4xl font-extrabold leading-tight sm:text-5xl lg:text-6xl">
                                    Attendance Made
                                    <span className="block text-[#F5A623]">
                                        Smart & Secure
                                    </span>
                                </h1>

                                <p className="mx-auto mt-6 max-w-xl text-base leading-relaxed text-white/70 lg:mx-0 lg:text-lg">
                                    A modern attendance verification system
                                    designed to make event attendance faster,
                                    more secure, and easier to manage.
                                </p>

                                <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row lg:justify-start">
                                    <Button
                                        asChild
                                        size="lg"
                                        className="bg-[#F5A623] px-8 font-semibold text-[#1B1F5C] hover:bg-[#e69a17]"
                                    >
                                        <Link href={login()}>
                                            Get Started
                                        </Link>
                                    </Button>

                                    <Button
                                        asChild
                                        size="lg"
                                        variant="outline"
                                        className="border-white/30 bg-transparent px-8 text-white hover:bg-white/10 hover:text-white"
                                    >
                                        <Link href={register()}>
                                            Create Account
                                        </Link>
                                    </Button>
                                </div>
                            </div>

                            {/* Right Visual */}
                            <div className="flex justify-center lg:justify-end">
                                <div className="relative">
                                    {/* Glow */}
                                    <div className="absolute inset-0 scale-75 rounded-full bg-[#F5A623]/20 blur-3xl" />

                                    {/* Main Circle */}
                                    <div className="relative flex h-72 w-72 items-center justify-center rounded-full border-2 border-[#F5A623]/40 bg-white/5 backdrop-blur-sm sm:h-80 sm:w-80">
                                        <div className="flex h-56 w-56 items-center justify-center rounded-full border border-white/10 bg-white/5">
                                            <div className="flex h-36 w-36 items-center justify-center rounded-full bg-white shadow-[0_0_40px_rgba(245,166,35,0.25)]">
                                                <Cpu className="h-20 w-20 text-[#1B1F5C]" />
                                            </div>
                                        </div>

                                        {/* Orbit Icons */}
                                        <div className="absolute -top-5 flex h-12 w-12 items-center justify-center rounded-full border border-[#F5A623]/40 bg-[#1B1F5C]">
                                            <ScanFace className="h-6 w-6 text-[#F5A623]" />
                                        </div>

                                        <div className="absolute -bottom-5 flex h-12 w-12 items-center justify-center rounded-full border border-[#F5A623]/40 bg-[#1B1F5C]">
                                            <ShieldCheck className="h-6 w-6 text-[#F5A623]" />
                                        </div>

                                        <div className="absolute -right-5 flex h-12 w-12 items-center justify-center rounded-full border border-[#F5A623]/40 bg-[#1B1F5C]">
                                            <MapPin className="h-6 w-6 text-[#F5A623]" />
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>

                    {/* Bottom Text */}
                    <div className="absolute bottom-5 left-0 right-0 z-10 text-center text-xs text-white/40">
                        CCIS Attendance System
                    </div>
                </section>
            </div>
        </>
    );
}

Welcome.layout = {
    title: 'CCIS Attendance System',
    description: 'Smart. Simple. Secure Attendance Tracking.',
};