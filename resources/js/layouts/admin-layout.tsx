import React, { useState } from 'react';
import { AdminSidebar } from '@/components/admin-sidebar';
import { AdminHeader } from '@/components/admin-header';

interface AdminLayoutProps {
    children: React.ReactNode;
    title?: string;
}

export default function AdminLayout({ children, title = 'Dashboard' }: AdminLayoutProps) {
    const [isSidebarOpen, setIsSidebarOpen] = useState(false);

    return (
        <div className="flex h-screen bg-[#F4F5FA] overflow-hidden font-sans">
            {/* Dedicated Admin Sidebar with mobile drawer state */}
            <AdminSidebar isOpen={isSidebarOpen} onClose={() => setIsSidebarOpen(false)} />

            {/* Main Content Area */}
            <div className="flex-1 flex flex-col min-w-0 h-screen overflow-y-auto">
                {/* Dedicated Admin Header with mobile toggle handler */}
                <AdminHeader 
                    title={title} 
                    onOpenSidebar={() => setIsSidebarOpen(true)} 
                />

                {/* Dashboard Page View Content */}
                <main className="p-4 sm:p-6 lg:p-8 pt-4 flex-1">
                    {children}
                </main>
            </div>
        </div>
    );
}