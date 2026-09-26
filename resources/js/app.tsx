import { createInertiaApp } from '@inertiajs/react';
import { Toaster } from '@/components/ui/sonner';
import { TooltipProvider } from '@/components/ui/tooltip';
import { initializeTheme } from '@/hooks/use-appearance';
import AppLayout from '@/layouts/app-layout';
import SettingsLayout from '@/layouts/settings/layout';

const appName = import.meta.env.VITE_APP_NAME || 'Laravel';

createInertiaApp({
    title: (title) => (title ? `${title} - ${appName}` : appName),

    layout: (name) => {
        switch (true) {
            // Public landing page
            case name === 'welcome':
                return null;

            // Authentication pages
            // These pages have their own full-screen designs
            case name.startsWith('auth/'):
                return null;

            // Settings pages
            case name.startsWith('settings/'):
                return [AppLayout, SettingsLayout];

            // Team pages
            case name.startsWith('teams/'):
                return AppLayout;

            // Default application pages
            default:
                return AppLayout;
        }
    },

    strictMode: true,

    withApp(app) {
        return (
            <TooltipProvider delayDuration={0}>
                {app}
                <Toaster />
            </TooltipProvider>
        );
    },

    progress: {
        color: '#4B5563',
    },
});

// This will set light / dark mode on load...
initializeTheme();