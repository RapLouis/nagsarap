import { Link, usePage } from '@inertiajs/react';
import AppLogoIcon from '@/components/app-logo-icon';
import { home } from '@/routes';
import type { AuthLayoutProps } from '@/types';
import logoImage from '../logo.jpeg';

export default function AuthSplitLayout({
    children,
    title,
    description,
}: AuthLayoutProps) {
    const { name } = usePage().props;

    return (
        <div className="min-h-screen w-full bg-[#F5F6FA] font-sans text-gray-900 antialiased">
            {/* MAIN 2-COLUMN SPLIT LAYOUT WRAPPER 
                - Pinned non-scrollable left sidebar on desktop (lg:)
                - Independent scrolling right panel
            */}
            <div className="flex min-h-screen flex-col lg:h-screen lg:flex-row lg:overflow-hidden">
                
                {/* LEFT BRANDING PANEL */}
                <aside className="relative flex flex-col items-center justify-center overflow-hidden bg-[#1B1F5C] p-8 text-center text-white shrink-0 lg:w-5/12 lg:h-screen lg:p-16">
                    {/* Background Pattern */}
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
                        <Link
                            href={home()}
                            className="group mb-6 flex flex-col items-center focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-full p-1"
                        >
                            <div className="mx-auto flex h-24 w-24 items-center justify-center overflow-hidden rounded-full border-4 border-[#F5A623] bg-white p-2 shadow-xl ring-4 ring-white/10 transition-transform group-hover:scale-105">
                                <img
                                    src={logoImage}
                                    alt="4ttnd System Logo"
                                    className="h-full w-full scale-125 object-contain"
                                />
                            </div>
                        </Link>

                        <h1 className="text-4xl font-black tracking-tight text-[#F5A623] sm:text-5xl">
                            4ttnd
                        </h1>
                        <h2 className="mt-1 text-xl font-bold tracking-wide text-white/95 sm:text-2xl">
                            Attendance System
                        </h2>
                        <p className="mx-auto mt-4 max-w-sm text-sm leading-relaxed text-white/80">
                            Smart Biometric Attendance & Event Verification System.
                        </p>
                        <div className="mx-auto mt-8 h-1 w-16 rounded-full bg-[#F5A623]" />
                    </div>

                    <div className="mt-8 text-xs text-white/50">
                        &copy; {new Date().getFullYear()} Mariano Marcos State University
                    </div>
                </aside>

                {/* RIGHT FORM CONTENT PANEL */}
                <div className="flex flex-1 items-center justify-center bg-[#F5F6FA] p-4 sm:p-8 lg:w-7/12 lg:h-screen lg:overflow-y-auto lg:p-12">
                    <main className="w-full max-w-md rounded-2xl border border-gray-200/80 bg-white p-6 shadow-xl sm:p-10 my-auto">
                        <div className="mb-6 flex flex-col items-center justify-center text-center lg:hidden">
                            <Link href={home()} className="mb-2">
                                <AppLogoIcon className="h-10 text-[#1B1F5C]" />
                            </Link>
                        </div>

                        {(title || description) && (
                            <header className="mb-6 text-center">
                                {title && (
                                    <h2 className="text-2xl font-black tracking-tight text-[#1B1F5C] sm:text-3xl">
                                        {title}
                                    </h2>
                                )}
                                {description && (
                                    <p className="mt-1.5 text-xs sm:text-sm font-medium text-gray-500 leading-relaxed">
                                        {description}
                                    </p>
                                )}
                            </header>
                        )}

                        {children}
                    </main>
                </div>
            </div>
        </div>
    );
}