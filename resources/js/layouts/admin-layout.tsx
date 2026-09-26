import React from 'react';
import { AdminSidebar } from '@/components/admin-sidebar';
import { AdminHeader } from '@/components/admin-header';

interface AdminLayoutProps {
    children: React.ReactNode;
    title?: string;
}

export default function AdminLayout({ children, title = 'Dashboard' }: AdminLayoutProps) {
    return (
        <div className="flex h-screen bg-[#F4F5FA] overflow-hidden font-sans">
            {/* Dedicated Admin Sidebar */}
            <AdminSidebar />

            {/* Main Content Area */}
            <div className="flex-1 flex flex-col min-w-0 h-screen overflow-y-auto">
                {/* Dedicated Admin Header */}
                <AdminHeader title={title} />

                {/* Dashboard Page View Content */}
                <main className="p-8 pt-4 flex-1">
                    {children}
                </main>
            </div>
        </div>
    );
}