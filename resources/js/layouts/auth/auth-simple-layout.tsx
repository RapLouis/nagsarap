import { Link } from '@inertiajs/react';
import AppLogoIcon from '@/components/app-logo-icon';
import { home } from '@/routes';
import type { AuthLayoutProps } from '@/types';

export default function AuthSimpleLayout({
    children,
    title,
    description,
}: AuthLayoutProps) {
    return (
        <div className="flex min-h-screen flex-col items-center justify-center bg-[#F5F6FA] p-4 sm:p-6 lg:p-10 font-sans text-gray-900 antialiased">
            <main className="w-full max-w-md rounded-2xl border border-gray-200/80 bg-white p-6 shadow-xl sm:p-10 my-auto">
                <div className="flex flex-col gap-6">
                    <header className="flex flex-col items-center gap-3 text-center">
                        <Link
                            href={home()}
                            className="flex flex-col items-center gap-2 font-bold focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-xl p-1 transition-transform hover:scale-105"
                        >
                            <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-[#1B1F5C] p-2.5 shadow-md ring-2 ring-[#F5A623]">
                                <AppLogoIcon className="h-full w-full fill-current text-[#F5A623]" />
                            </div>
                            <span className="sr-only">{title}</span>
                        </Link>

                        <div className="space-y-1.5">
                            {title && (
                                <h1 className="text-2xl font-black tracking-tight text-[#1B1F5C]">
                                    {title}
                                </h1>
                            )}
                            {description && (
                                <p className="text-xs sm:text-sm font-medium text-gray-500 leading-relaxed">
                                    {description}
                                </p>
                            )}
                        </div>
                    </header>
                    {children}
                </div>
            </main>
        </div>
    );
}