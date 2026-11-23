import { Link } from '@inertiajs/react';
import type { PropsWithChildren } from 'react';
import AppLogoIcon from '@/components/app-logo-icon';
import {
    Card,
    CardContent,
    CardDescription,
    CardHeader,
    CardTitle,
} from '@/components/ui/card';
import { home } from '@/routes';

export default function AuthCardLayout({
    children,
    title,
    description,
}: PropsWithChildren<{
    name?: string;
    title?: string;
    description?: string;
}>) {
    return (
        <div className="flex min-h-screen flex-col items-center justify-center bg-[#F5F6FA] p-4 sm:p-6 lg:p-10 font-sans text-gray-900 antialiased">
            <div className="flex w-full max-w-md flex-col gap-6 my-auto">
                {/* Brand Logo Header */}
                <Link
                    href={home()}
                    className="flex items-center gap-2 self-center font-bold text-[#1B1F5C] transition-transform hover:scale-105 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-xl p-1"
                >
                    <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-[#1B1F5C] p-2 shadow-md ring-2 ring-[#F5A623]">
                        <AppLogoIcon className="h-full w-full fill-current text-[#F5A623]" />
                    </div>
                </Link>

                {/* Card Container */}
                <Card className="rounded-2xl border border-gray-200/80 bg-white shadow-xl overflow-hidden">
                    <CardHeader className="px-6 pt-8 pb-2 text-center sm:px-8">
                        {title && (
                            <CardTitle className="text-2xl font-black tracking-tight text-[#1B1F5C]">
                                {title}
                            </CardTitle>
                        )}
                        {description && (
                            <CardDescription className="text-xs sm:text-sm font-medium text-gray-500 leading-relaxed mt-1">
                                {description}
                            </CardDescription>
                        )}
                    </CardHeader>
                    <CardContent className="px-6 py-6 sm:px-8 sm:pb-8">
                        {children}
                    </CardContent>
                </Card>
            </div>
        </div>
    );
}