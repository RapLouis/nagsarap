import React, { useState } from 'react';
import { OrganizerSidebar } from '@/components/organizer-sidebar';
import { OrganizerHeader } from '@/components/organizer-header';

interface OrganizerLayoutProps {
    children: React.ReactNode;
    title?: string;
}

export default function OrganizerLayout({ children, title = 'Dashboard' }: OrganizerLayoutProps) {
    const [isSidebarOpen, setIsSidebarOpen] = useState(false);

    return (
        <div className="flex h-screen bg-[#F4F5FA] overflow-hidden font-sans">
            {/* Single Organizer Sidebar */}
            <OrganizerSidebar isOpen={isSidebarOpen} onClose={() => setIsSidebarOpen(false)} />

            {/* Main Content Area */}
            <div className="flex-1 flex flex-col min-w-0 h-screen overflow-y-auto">
                <OrganizerHeader 
                    title={title} 
                    onOpenSidebar={() => setIsSidebarOpen(true)} 
                />

                <main className="p-4 sm:p-6 lg:p-8 pt-4 flex-1">
                    {children}
                </main>
            </div>
        </div>
    );
}