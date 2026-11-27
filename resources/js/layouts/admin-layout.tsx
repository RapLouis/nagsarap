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
        <div className="flex min-h-screen bg-[#F5F6FA] font-sans text-gray-900 antialiased">
            {/* Sticky Desktop Sidebar + Accessible Mobile Drawer */}
            <div className="lg:sticky lg:top-0 lg:h-screen lg:shrink-0">
                <AdminSidebar isOpen={isSidebarOpen} onClose={() => setIsSidebarOpen(false)} />
            </div>

            {/* Main Content Pane */}
            <div className="flex flex-1 flex-col min-w-0">
                <AdminHeader
                    title={title}
                    onOpenSidebar={() => setIsSidebarOpen(true)}
                />

                <main className="flex-1 p-4 pt-4 sm:p-6 lg:p-8">
                    {children}
                </main>
            </div>
        </div>
    );
}