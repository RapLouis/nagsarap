import React from 'react';
import { Link, usePage } from '@inertiajs/react';
import {
    LayoutGrid,
    Camera,
    Calendar,
    History,
    User,
    LogOut,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { dashboard } from '@/routes';

const NAVY_DARK = '#141843';

const navItems = [
    { title: 'Dashboard', href: dashboard(), icon: LayoutGrid },
    { title: 'Check-in', href: '/check-in', icon: Camera },
    { title: 'My events', href: '/events', icon: Calendar },
    { title: 'Attendance history', href: '/attendance/history', icon: History },
    { title: 'Profile', href: '/profile', icon: User },
];

export function AppSidebar({ children }: { children: React.ReactNode }) {
    const { url } = usePage();

    return (
        <div className="flex min-h-screen bg-gray-50">
            {/* LEFT FIXED SIDEBAR */}
            <aside
                className="fixed inset-y-0 left-0 z-30 flex w-64 flex-col justify-between p-6 text-white"
                style={{ backgroundColor: NAVY_DARK }}
            >
                <div className="space-y-8">
                    {/* BRAND HEADER */}
                    <div className="flex items-center gap-3 px-2">
                        <div className="h-9 w-9 rounded-full bg-white/20" />
                        <span className="text-xl font-bold tracking-wide">Brand</span>
                    </div>

                    {/* NAVIGATION LINKS */}
                    <nav className="space-y-1.5">
                        {navItems.map((item) => {
                            const isActive = url === item.href || url.startsWith(item.href + '/');
                            const Icon = item.icon;

                            return (
                                <Link
                                    key={item.title}
                                    href={item.href}
                                    className={cn(
                                        'flex items-center gap-3.5 rounded-xl px-4 py-3 text-sm font-medium transition-all',
                                        isActive
                                            ? 'bg-white/10 text-white font-semibold border-l-4 border-amber-400'
                                            : 'text-gray-300 hover:bg-white/5 hover:text-white'
                                    )}
                                >
                                    <Icon className="h-5 w-5 shrink-0" />
                                    <span>{item.title}</span>
                                </Link>
                            );
                        })}
                    </nav>
                </div>

                {/* FOOTER LOGOUT */}
                <div className="border-t border-white/10 pt-4">
                    <Link
                        href="/logout"
                        method="post"
                        as="button"
                        className="flex w-full items-center gap-3.5 rounded-xl px-4 py-3 text-sm font-medium text-gray-300 transition-all hover:bg-white/5 hover:text-white"
                    >
                        <LogOut className="h-5 w-5 shrink-0" />
                        <span>Log out</span>
                    </Link>
                </div>
            </aside>

            {/* MAIN CONTENT AREA */}
            <div className="flex-1 pl-64">
                {/* TOP USER BAR */}
                <header className="flex h-16 items-center justify-between border-b border-gray-100 bg-white px-8">
                    <h1 className="text-lg font-bold text-gray-900">Dashboard</h1>
                    <div className="flex items-center gap-4">
                        <button className="rounded-full p-2 text-gray-400 hover:bg-gray-100 hover:text-gray-600">
                            <span className="sr-only">Notifications</span>
                            <div className="h-2 w-2 rounded-full bg-amber-500 absolute top-4 right-20" />
                            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
                            </svg>
                        </button>
                        <div className="flex items-center gap-2">
                            <div className="flex h-8 w-8 items-center justify-center rounded-full bg-indigo-100 text-xs font-bold text-indigo-900">
                                LC
                            </div>
                            <span className="text-sm font-semibold text-gray-700">Lowell Cabie</span>
                        </div>
                    </div>
                </header>

                <main>{children}</main>
            </div>
        </div>
    );
}