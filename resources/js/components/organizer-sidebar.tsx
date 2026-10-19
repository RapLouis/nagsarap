import React, { useState, useMemo } from 'react';
import { Link, usePage } from '@inertiajs/react';
import {
    House,
    Calendar,
    Camera,
    LogOut,
    X,
} from 'lucide-react';
import { LogoutModal } from '@/components/logout-modal';
import logoImage from '../pages/logo.jpeg';

type OrganizerSidebarProps = {
    isOpen?: boolean;
    onClose?: () => void;
};

export function OrganizerSidebar({ isOpen = false, onClose }: OrganizerSidebarProps) {
    const [showLogoutModal, setShowLogoutModal] = useState(false);
    const { url } = usePage();

    const navItems = useMemo(
        () => [
            { title: 'Dashboard', href: '/organizer/dashboard', icon: House },
            { title: 'Events', href: '/organizer/events', icon: Calendar },
            { title: 'Kiosk Mode', href: '/organizer/kiosk', icon: Camera },
        ],
        []
    );

    const sidebarContent = (
        <aside className="w-64 h-full bg-[#03045E] text-white flex flex-col justify-between p-6 shrink-0">
            <div className="flex flex-col min-h-0">
                <div className="flex items-center justify-between mb-8 pl-2 shrink-0">
                    <div className="flex items-center gap-3">
                        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-white overflow-hidden shadow-md p-0.5">
                            <img src={logoImage} alt="4ttnd Logo" className="h-full w-full object-contain scale-125" />
                        </div>
                        <div className="flex items-baseline tracking-wider">
                            <span className="text-2xl font-black text-[#FFD600]">4</span>
                            <span className="text-lg font-bold text-white">ttnd</span>
                        </div>
                    </div>
                    {onClose && (
                        <button
                            type="button"
                            onClick={onClose}
                            className="lg:hidden text-white/80 hover:text-white p-1"
                            aria-label="Close Sidebar"
                        >
                            <X className="w-6 h-6" />
                        </button>
                    )}
                </div>

                <nav className="space-y-2 overflow-y-auto">
                    {navItems.map((item) => {
                        const Icon = item.icon;
                        const isActive = item.href === '/organizer/dashboard' 
                            ? url === item.href 
                            : url.startsWith(item.href);

                        return (
                            <Link
                                key={item.href}
                                href={item.href}
                                onClick={onClose}
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
    );

    return (
        <>
            <div className="hidden lg:block h-screen sticky top-0 shrink-0">
                {sidebarContent}
            </div>

            {isOpen && (
                <div className="fixed inset-0 z-50 lg:hidden flex">
                    <div 
                        className="fixed inset-0 bg-black/50 backdrop-blur-xs transition-opacity" 
                        onClick={onClose} 
                    />
                    <div className="relative flex-1 flex flex-col max-w-xs w-full bg-[#03045E] h-full shadow-xl z-10">
                        {sidebarContent}
                    </div>
                </div>
            )}

            <LogoutModal
                isOpen={showLogoutModal}
                onClose={() => setShowLogoutModal(false)}
            />
        </>
    );
}