import { AppContent } from '@/components/app-content';
import { AppShell } from '@/components/app-shell';
import type { AppLayoutProps } from '@/types';

export default function AppHeaderLayout({ children }: AppLayoutProps) {
    return (
        <div className="min-h-screen bg-[#F5F6FA] font-sans text-gray-900 antialiased">
            <AppShell variant="header">
                <AppContent variant="header" className="min-w-0 max-w-7xl mx-auto w-full p-4 sm:p-6 lg:p-8">
                    {children}
                </AppContent>
            </AppShell>
        </div>
    );
}