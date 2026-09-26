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
        <AppShell variant="sidebar">
            {/* Render AdminSidebar for admins, fallback to standard AppSidebar */}
            {isAdmin ? <AdminSidebar /> : <AppSidebar />}

            <AppContent variant="sidebar" className="min-w-0 overflow-x-clip">
                <AppSidebarHeader breadcrumbs={breadcrumbs} />
                {children}
            </AppContent>
        </AppShell>
    );
}