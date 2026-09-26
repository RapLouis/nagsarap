import { Link, usePage } from '@inertiajs/react';
import { Bell } from 'lucide-react';

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

interface AdminHeaderProps {
    title?: string;
}

export function AdminHeader({ title = 'Dashboard' }: AdminHeaderProps) {
    const { auth } = usePage<SharedProps>().props;
    const adminName = auth.user?.name || 'Raphael Gabion';

    return (
        <header className="flex justify-between items-center p-8 pb-4 shrink-0">
            {/* Page Title */}
            <h1 className="text-3xl font-bold text-gray-900">{title}</h1>

            {/* Notifications & Admin Profile */}
            <div className="flex items-center gap-6">
                {/* Notification Bell */}
                <button 
                    type="button" 
                    className="relative text-gray-600 hover:text-gray-900 transition"
                    aria-label="Notifications"
                >
                    <Bell className="w-6 h-6" />
                </button>

                {/* Clickable Profile Link */}
                <Link 
                    href="/settings/profile" // Update this path to match your profile route
                    className="flex items-center gap-3 p-1.5 rounded-lg hover:bg-gray-200/60 transition group"
                >
                    <div className="w-10 h-10 rounded-full bg-gray-300 border border-gray-400 flex items-center justify-center font-bold text-gray-700 group-hover:border-gray-500">
                        {adminName.charAt(0).toUpperCase()}
                    </div>
                    <div>
                        <p className="text-xs font-bold text-gray-800 uppercase leading-none">Admin</p>
                        <p className="text-sm text-gray-600 leading-tight group-hover:text-gray-900">{adminName}</p>
                    </div>
                </Link>
            </div>
        </header>
    );
}