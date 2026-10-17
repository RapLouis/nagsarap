import { Link, usePage } from '@inertiajs/react';
import { Bell, Menu } from 'lucide-react';

interface User {
    id: number;
    name: string;
    email: string;
    role: string;
}

interface SharedProps {
    auth: {
        user: User;
    };
    [key: string]: unknown;
}

interface OrganizerHeaderProps {
    title?: string;
    onOpenSidebar?: () => void;
}

export function OrganizerHeader({ title = 'Dashboard', onOpenSidebar }: OrganizerHeaderProps) {
    const { auth } = usePage<SharedProps>().props;
    const organizerName = auth.user?.name || 'Organizer';

    return (
        <header className="flex justify-between items-center px-4 sm:px-8 py-4 sm:py-6 pb-4 shrink-0 bg-white/50 backdrop-blur-xs border-b border-gray-100 lg:border-none">
            <div className="flex items-center gap-3">
                {onOpenSidebar && (
                    <button
                        type="button"
                        onClick={onOpenSidebar}
                        className="lg:hidden p-2 rounded-xl text-gray-600 hover:bg-gray-200/60 transition"
                        aria-label="Open Sidebar Menu"
                    >
                        <Menu className="w-6 h-6" />
                    </button>
                )}
                <h1 className="text-xl sm:text-3xl font-bold text-gray-900 tracking-tight">{title}</h1>
            </div>

            <div className="flex items-center gap-4 sm:gap-6">
                <button 
                    type="button" 
                    className="relative text-gray-600 hover:text-gray-900 transition p-1"
                    aria-label="Notifications"
                >
                    <Bell className="w-6 h-6" />
                </button>

                <Link 
                    href="/settings/profile"
                    className="flex items-center gap-3 p-1.5 rounded-lg hover:bg-gray-200/60 transition group"
                >
                    <div className="w-10 h-10 rounded-full bg-gray-300 border border-gray-400 flex items-center justify-center font-bold text-gray-700 group-hover:border-gray-500 shrink-0">
                        {organizerName.charAt(0).toUpperCase()}
                    </div>
                    <div className="hidden sm:block">
                        <p className="text-xs font-bold text-gray-800 uppercase leading-none">Organizer</p>
                        <p className="text-sm text-gray-600 leading-tight group-hover:text-gray-900">{organizerName}</p>
                    </div>
                </Link>
            </div>
        </header>
    );
}