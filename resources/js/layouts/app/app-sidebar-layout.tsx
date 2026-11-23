import { usePage } from '@inertiajs/react';
import { AdminSidebar } from '@/components/admin-sidebar';
import { AppContent } from '@/components/app-content';
import { AppShell } from '@/components/app-shell';
import { AppSidebar } from '@/components/app-sidebar';
import { AppSidebarHeader } from '@/components/app-sidebar-header';
import type { AppLayoutProps } from '@/types';

interface SharedProps {
    auth: {
        user: {
            id: number;
            name: string;
            email: string;
            role: 'student' | 'organizer' | 'admin';
        };
    };
    [key: string]: unknown;
}

export default function AppSidebarLayout({
    children,
    breadcrumbs = [],
}: AppLayoutProps) {
    const { auth } = usePage<SharedProps>().props;
    const isAdmin = auth.user?.role === 'admin';

    return (
        <div className="min-h-screen bg-[#F5F6FA] font-sans text-gray-900 antialiased">
            <AppShell variant="sidebar">
                {/* Render AdminSidebar for admins, fallback to standard AppSidebar */}
                {isAdmin ? <AdminSidebar /> : <AppSidebar />}

                <AppContent variant="sidebar" className="flex-1 min-w-0 overflow-x-clip bg-[#F5F6FA]">
                    <AppSidebarHeader breadcrumbs={breadcrumbs} />
                    <main className="p-4 sm:p-6 lg:p-8 w-full max-w-7xl mx-auto">
                        {children}
                    </main>
                </AppContent>
            </AppShell>
        </div>
    );
}