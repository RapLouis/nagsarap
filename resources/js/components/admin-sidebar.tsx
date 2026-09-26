import React, { useState } from 'react';
import { Link, usePage } from '@inertiajs/react';
import {
    House,
    Users,
    Calendar,
    BarChart3,
    BookOpen,
    LogOut,
} from 'lucide-react';
import { LogoutModal } from '@/components/logout-modal';

export function AdminSidebar() {
    const [showLogoutModal, setShowLogoutModal] = useState(false);
    const { url } = usePage();

    const navItems = [
        {
            title: 'Dashboard',
            href: '/admin/dashboard',
            icon: House,
        },
        {
            title: 'Student Management',
            href: '/admin/students',
            icon: Users,
        },
        {
            title: 'Events',
            href: '/admin/events',
            icon: Calendar,
        },
        {
            title: 'Analysis',
            href: '/admin/analytics',
            icon: BarChart3,
        },
        {
            title: 'Student Clearance',
            href: '/admin/clearance',
            icon: BookOpen,
        },
    ];

    return (
        <>
            <aside className="w-64 h-screen bg-[#03045E] text-white flex flex-col justify-between p-6 shrink-0 sticky top-0">
                {/* Top Navigation Content */}
                <div className="flex flex-col min-h-0">
                    {/* Brand Header */}
                    <div className="flex items-center gap-3 mb-8 pl-2 shrink-0">
                        <div className="w-10 h-10 bg-white rounded-full" />
                        <span className="text-2xl font-bold tracking-wide">Brand</span>
                    </div>

                    {/* Navigation Items */}
                    <nav className="space-y-2 overflow-y-auto">
                        {navItems.map((item) => {
                            const Icon = item.icon;
                            const isActive = url.startsWith(item.href);

                            return (
                                <Link
                                    key={item.href}
                                    href={item.href}
                                    className={`flex items-center gap-4 px-4 py-3 font-medium transition ${
                                        isActive
                                            ? 'bg-[#1D217D] text-[#FFD600] border-l-4 border-[#FFD600]'
                                            : 'text-white/80 hover:bg-white/10 hover:text-white rounded-lg'
                                    }`}
                                >
                                    <Icon className="w-5 h-5 shrink-0" />
                                    <span className="text-sm font-semibold">{item.title}</span>
                                </Link>
                            );
                        })}
                    </nav>
                </div>

                {/* Logout Button */}
                <div className="pt-4 border-t border-white/10 shrink-0">
                    <button
                        type="button"
                        onClick={() => setShowLogoutModal(true)}
                        className="flex items-center gap-3 text-white/80 hover:text-white px-2 py-2 transition w-full text-left rounded-lg hover:bg-white/10"
                    >
                        <LogOut className="w-6 h-6 shrink-0" />
                        <span className="font-semibold text-lg">Log out</span>
                    </button>
                </div>
            </aside>

            {/* Reusable Confirmation Modal */}
            <LogoutModal
                isOpen={showLogoutModal}
                onClose={() => setShowLogoutModal(false)}
            />
        </>
    );
}